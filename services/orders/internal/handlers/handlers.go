// Package handlers implement the ogen-generated orders.Handler interface, per ADR-0303.
package handlers

import (
	"context"
	"errors"
	"math"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
	"go.temporal.io/sdk/client"

	"github.com/tabmadi/sovereign-platform-template/libs/go/apierr"
	"github.com/tabmadi/sovereign-platform-template/libs/go/authmw"
	"github.com/tabmadi/sovereign-platform-template/libs/go/authz"
	"github.com/tabmadi/sovereign-platform-template/libs/go/id"
	"github.com/tabmadi/sovereign-platform-template/libs/go/money"
	"github.com/tabmadi/sovereign-platform-template/libs/go/observability"
	orders "github.com/tabmadi/sovereign-platform-template/libs/go/sdks/orders"
	"github.com/tabmadi/sovereign-platform-template/services/orders/internal/store"
	"github.com/tabmadi/sovereign-platform-template/services/orders/internal/workflows"
)

const serviceName = "orders"

type Handlers struct {
	q                store.Querier
	tc               client.Client
	checker          authz.Checker
	checkoutsStarted metric.Int64Counter
}

func New(db *pgxpool.Pool, tc client.Client, checker authz.Checker) *Handlers {
	return &Handlers{
		q:                store.New(db),
		tc:               tc,
		checker:          checker,
		checkoutsStarted: observability.Counter("orders.checkouts_started"),
	}
}

var _ orders.Handler = (*Handlers)(nil)

// These three are the transport boundary, per ADR-0003. catalog mints a product id, and this service only carries it.
// So it is encoded under catalog's prefix, and the checkout saga decodes it. They return an error and do not panic,
// because one spec edit can make the generated validator and these calls disagree.
func orderID(u pgtype.UUID) orders.OrderId {
	return orders.OrderId(id.MustFrom("order", uuid.UUID(u.Bytes)).String())
}

func productID(u pgtype.UUID) orders.ProductId {
	return orders.ProductId(id.MustFrom("product", uuid.UUID(u.Bytes)).String())
}

// mintOrderID is where an identifier enters the system, per ADR-0003. The service holds it before the insert, so a
// failed write still has an identifier to name in the failure.
func mintOrderID() (pgtype.UUID, error) {
	v, err := id.New("order")
	if err != nil {
		return pgtype.UUID{}, apierr.Internal(err.Error())
	}
	return pgtype.UUID{Bytes: v.UUID(), Valid: true}, nil
}

// wireTotal renders the stored total for the wire, per ADR-0300. The column is
// `numeric`, and the wire is a decimal string with its currency. It goes through
// money.Amount, so the value matches what the shared type produces everywhere else.
func wireTotal(total pgtype.Numeric, currency string) (orders.Money, error) {
	raw, err := total.Value()
	if err != nil {
		return orders.Money{}, apierr.Internal(err.Error())
	}
	text, ok := raw.(string)
	if !ok {
		return orders.Money{}, apierr.Internal("total is not a numeric")
	}
	amount, err := money.Parse(text, currency)
	if err != nil {
		return orders.Money{}, apierr.Internal(err.Error())
	}
	return orders.Money{Amount: amount.String(), Currency: amount.Currency()}, nil
}

func storedOrderID(v orders.OrderId) (pgtype.UUID, error) {
	parsed, err := id.Parse("order", string(v))
	if err != nil {
		return pgtype.UUID{}, apierr.BadRequest("malformed order id")
	}
	return pgtype.UUID{Bytes: parsed.UUID(), Valid: true}, nil
}

// requireBuyerWithOrg exists because an order belongs to a buyer and to the org they act through, per ADR-0304. So
// checkout has no anonymous form. Without both, nobody gets the order's read tuples, and only operators could read
// the row.
func requireBuyerWithOrg(ctx context.Context) (*authmw.Principal, error) {
	principal, _ := authmw.FromContext(ctx)
	if !principal.Authenticated() {
		return nil, apierr.Unauthorized()
	}
	if principal.OrgID == "" {
		return nil, apierr.Forbidden("this identity carries no organization")
	}
	return principal, nil
}

func (h *Handlers) Checkout(
	ctx context.Context,
	req *orders.CheckoutInput,
	params orders.CheckoutParams,
) (*orders.WorkflowHandle, error) {
	ctx, span := observability.StartSpan(ctx, "orders.Checkout")
	defer span.End()

	if req.Quantity <= 0 || req.Quantity > math.MaxInt32 {
		return nil, apierr.BadRequest("product_id and quantity required")
	}
	principal, err := requireBuyerWithOrg(ctx)
	if err != nil {
		return nil, err
	}
	if params.IdempotencyKey == "" {
		return nil, apierr.BadRequest("Idempotency-Key required")
	}

	replayed, found, err := h.replayedCheckout(ctx, params.IdempotencyKey)
	if err != nil {
		return nil, err
	}
	if found {
		return replayed, nil
	}

	key, err := mintOrderID()
	if err != nil {
		return nil, err
	}
	oid := string(orderID(key))
	// Tag the root span, so TraceQL can find a checkout in Tempo. A reader has the wire form, so the attribute
	// carries the wire form.
	span.SetAttributes(attribute.String("order.id", oid))
	_, err = h.tc.ExecuteWorkflow(
		ctx,
		client.StartWorkflowOptions{
			ID:        "checkout-" + oid,
			TaskQueue: serviceName + "-queue",
		},
		workflows.Checkout,
		workflows.CheckoutInput{
			OrderID:        oid,
			ProductID:      string(req.ProductID),
			Quantity:       int32(req.Quantity),
			OwnerID:        principal.UserID,
			OrgID:          principal.OrgID,
			IdempotencyKey: params.IdempotencyKey,
		},
	)
	if err != nil {
		return nil, apierr.Internal(err.Error())
	}
	h.checkoutsStarted.Add(ctx, 1)
	return checkoutHandle(oid), nil
}

// checkoutHandle is the 202 body. It is built the same way for a new checkout and
// for a replay of an earlier one.
func checkoutHandle(oid string) *orders.WorkflowHandle {
	return &orders.WorkflowHandle{
		ID:        "checkout-" + oid,
		RunID:     oid,
		Status:    orders.WorkflowHandleStatusRunning,
		ResultURL: orders.NewOptString("/api/orders/" + oid),
	}
}

func (h *Handlers) GetOrder(ctx context.Context, params orders.GetOrderParams) (*orders.Order, error) {
	key, err := storedOrderID(params.ID)
	if err != nil {
		return nil, err
	}
	err = h.requireReader(ctx, "order:"+string(params.ID))
	if err != nil {
		return nil, err
	}
	row, err := h.q.GetOrder(ctx, key)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, apierr.NotFound("order")
	}
	if err != nil {
		return nil, apierr.Internal(err.Error())
	}
	total, err := wireTotal(row.Total, row.Currency)
	if err != nil {
		return nil, err
	}
	return &orders.Order{
		ID:        orderID(row.ID),
		ProductID: productID(row.ProductID),
		Quantity:  int(row.Quantity),
		Total:     total,
		Status:    orders.OrderStatus(row.Status),
	}, nil
}

func (h *Handlers) ListOrders(ctx context.Context) ([]orders.Order, error) {
	// Every order, not only the caller's. It is a back-office view with
	// `x-audience: internal`, so it is operator-gated and not scoped.
	err := h.requireOperator(ctx, "listing every order")
	if err != nil {
		return nil, err
	}
	rows, err := h.q.ListOrders(ctx)
	if err != nil {
		return nil, apierr.Internal(err.Error())
	}
	out := make([]orders.Order, 0, len(rows))
	for _, r := range rows {
		total, err := wireTotal(r.Total, r.Currency)
		if err != nil {
			return nil, err
		}
		out = append(
			out,
			orders.Order{
				ID:        orderID(r.ID),
				ProductID: productID(r.ProductID),
				Quantity:  int(r.Quantity),
				Total:     total,
				Status:    orders.OrderStatus(r.Status),
			},
		)
	}
	return out, nil
}

func (h *Handlers) CancelOrder(ctx context.Context, params orders.CancelOrderParams) (*orders.WorkflowHandle, error) {
	ctx, span := observability.StartSpan(ctx, "orders.CancelOrder")
	defer span.End()

	err := h.requireOperator(ctx, "cancelling orders")
	if err != nil {
		return nil, err
	}
	key, err := storedOrderID(params.ID)
	if err != nil {
		return nil, err
	}
	row, err := h.q.GetOrder(ctx, key)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, apierr.NotFound("order")
	}
	if err != nil {
		return nil, apierr.Internal(err.Error())
	}
	if row.Status == "cancelled" || row.Status == "failed" {
		return nil, apierr.Conflict("order is not cancellable")
	}

	oid := string(params.ID)
	_, err = h.tc.ExecuteWorkflow(
		ctx,
		client.StartWorkflowOptions{
			ID:        "cancel-order-" + oid,
			TaskQueue: serviceName + "-queue",
		},
		workflows.CancelOrder,
		workflows.CancelInput{OrderID: oid},
	)
	if err != nil {
		return nil, apierr.Internal(err.Error())
	}
	return &orders.WorkflowHandle{
		ID:        "cancel-order-" + oid,
		RunID:     oid,
		Status:    orders.WorkflowHandleStatusRunning,
		ResultURL: orders.NewOptString("/api/orders/" + oid),
	}, nil
}

// NewError maps a handler error onto the generated RFC 9457 response, per ADR-0303.
func (h *Handlers) NewError(ctx context.Context, err error) *orders.ErrorStatusCode {
	e := apierr.Resolved(ctx, err)

	problem := orders.Problem{Type: e.Type, Title: e.Title, Status: e.Status}
	if e.Detail != "" {
		problem.Detail = orders.NewOptString(e.Detail)
	}
	if e.TraceID != "" {
		problem.TraceID = orders.NewOptString(e.TraceID)
	}
	for _, v := range e.Errors {
		problem.Errors = append(problem.Errors, orders.ProblemErrorsItem{Pointer: v.Pointer, Message: v.Message})
	}
	return &orders.ErrorStatusCode{StatusCode: e.Status, Response: problem}
}

// replayedCheckout makes a retry return the order that the first attempt created, and not place a second one, per
// ADR-0003. This read is the fast path. The unique index on the column is the real guarantee, because two
// concurrent retries both miss this read.
func (h *Handlers) replayedCheckout(
	ctx context.Context, key string,
) (*orders.WorkflowHandle, bool, error) {
	existing, err := h.q.GetOrderByIdempotencyKey(ctx, pgtype.Text{String: key, Valid: true})
	switch {
	case err == nil:
		return checkoutHandle(string(orderID(existing.ID))), true, nil
	case errors.Is(err, pgx.ErrNoRows):
		return nil, false, nil
	default:
		return nil, false, apierr.Internal(err.Error())
	}
}

// An unguessable identifier is not an access control, so holding one grants nothing, per ADR-0003. `order#read`
// resolves the buyer and the owning org's admins. Both are Checker calls, and neither reads a role from a header.
func (h *Handlers) requireReader(ctx context.Context, object string) error {
	principal, _ := authmw.FromContext(ctx)
	if !principal.Authenticated() {
		return apierr.Unauthorized()
	}
	allowed, err := h.checker.Allowed(ctx, principal.Subject(), "read", object)
	if err != nil {
		return apierr.Internal(err.Error())
	}
	if allowed {
		return nil
	}
	return h.requireOperator(ctx, "reading an order placed by someone else")
}

// requireOperator gates a write on the shared Checker, per ADR-0304. Reads and starting a checkout stay open. Only the
// destructive cancel is gated.
func (h *Handlers) requireOperator(ctx context.Context, action string) error {
	principal, _ := authmw.FromContext(ctx)
	if !principal.Authenticated() {
		return apierr.Unauthorized()
	}
	allowed, err := h.checker.Allowed(ctx, principal.Subject(), "member", "group:operator")
	if err != nil {
		return apierr.Internal(err.Error())
	}
	if !allowed {
		return apierr.Forbidden(action + " requires operator")
	}
	return nil
}
