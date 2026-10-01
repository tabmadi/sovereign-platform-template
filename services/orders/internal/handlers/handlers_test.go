package handlers

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"go.temporal.io/sdk/client"

	"go.opentelemetry.io/otel/metric"

	"github.com/tabmadi/sovereign-platform-template/libs/go/apierr"
	"github.com/tabmadi/sovereign-platform-template/libs/go/authmw"

	"github.com/tabmadi/sovereign-platform-template/libs/go/authz"
	"github.com/tabmadi/sovereign-platform-template/libs/go/observability"
	orders "github.com/tabmadi/sovereign-platform-template/libs/go/sdks/orders"
	"github.com/tabmadi/sovereign-platform-template/services/orders/internal/store"
)

const statusPending = "pending"

// testCurrency is the currency of every fixture here. The currency itself does not
// matter. It only needs to travel with the amount.
const testCurrency = "EUR"

// pendingOrder is a row that can be rendered: the total is a valid numeric with
// a currency. The zero pgtype.Numeric is not, and a handler that renders money
// needs a row with money in it.
func pendingOrder() store.GetOrderRow {
	var total pgtype.Numeric
	err := total.Scan("30.00")
	if err != nil {
		panic(err)
	}
	return store.GetOrderRow{Status: statusPending, Total: total, Currency: testCurrency}
}

// testUser is the principal of every authenticated case.
const testUser = "alice"

// A well-formed wire identifier, per ADR-0003. The cases below then test the
// handler's logic and not its identifier decoding, which has its own case.
const testOrderID = orders.OrderId("order_01kztnj6c8e0jt7vzw0cn1wxvd")

// fakeQ embeds store.Querier, so only the methods that a test uses need stubs.
// Any other call panics on nil, and that is the wanted signal for an unexpected query.
type fakeQ struct {
	store.Querier

	order   store.GetOrderRow
	getErr  error
	list    []store.ListOrdersRow
	listErr error
	byKey   store.GetOrderByIdempotencyKeyRow
}

func (f fakeQ) GetOrder(context.Context, pgtype.UUID) (store.GetOrderRow, error) {
	return f.order, f.getErr
}

// An unset byKey means that no order carries this key, which is the first-attempt
// path. Otherwise the zero value would count as a hit in every test.
func (f fakeQ) GetOrderByIdempotencyKey(
	context.Context, pgtype.Text,
) (store.GetOrderByIdempotencyKeyRow, error) {
	if f.byKey.Status == "" {
		return store.GetOrderByIdempotencyKeyRow{}, pgx.ErrNoRows
	}
	return f.byKey, nil
}

func (f fakeQ) ListOrders(context.Context) ([]store.ListOrdersRow, error) {
	return f.list, f.listErr
}

// fakeTemporal embeds client.Client. The handler calls only ExecuteWorkflow and
// ignores the returned run, so a nil run works.
type fakeTemporal struct {
	client.Client

	err error
}

func (f fakeTemporal) ExecuteWorkflow(
	context.Context, client.StartWorkflowOptions, any, ...any,
) (client.WorkflowRun, error) {
	return nil, f.err
}

// fakeChecker stands in for the OpenFGA Checker, so a test can run the operator
// gate without a cluster, per ADR-0304.
type fakeChecker struct {
	allowed bool
	err     error
}

func (f fakeChecker) Allowed(context.Context, string, string, string) (bool, error) {
	return f.allowed, f.err
}

// opCtx is an authenticated-operator request context. It passes the
// requireOperator gate, so the business-logic cases below reach the store.
func opCtx() context.Context {
	return authmw.NewContext(context.Background(), &authmw.Principal{UserID: testUser})
}

func okChecker() authz.Checker { return fakeChecker{allowed: true} }

// noopCounter is the metric that a handler increments on the happy path. The global
// meter is a no-op until observability.Init runs. So this is a real counter with no
// export target, not a stub.
func noopCounter() metric.Int64Counter { return observability.Counter("test.checkouts_started") }

// resourceChecker answers per resource, as the read gate needs. A buyer holds
// `order#read` on their own order and nothing on `group:operator`. An operator is
// the reverse. A single bool cannot express either.
type resourceChecker map[string]bool

func (c resourceChecker) Allowed(_ context.Context, _, _, resource string) (bool, error) {
	return c[resource], nil
}

// buyerCtx is an authenticated buyer who acts through their personal org. Every
// checkout needs this principal, per ADR-0304.
func buyerCtx() context.Context {
	return authmw.NewContext(
		context.Background(),
		&authmw.Principal{UserID: testUser, OrgID: "org_01kztn9tsrea7b1597q3yjdeav"},
	)
}

// orderObject is the OpenFGA object that the read gate checks.
var orderObject = "order:" + string(testOrderID)

func TestGetOrderAuthz(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		ctx     func() context.Context
		checker authz.Checker
		want    int
	}{
		{
			"holding the identifier is not enough",
			context.Background,
			resourceChecker{orderObject: true},
			401,
		},
		{
			"another buyer is forbidden",
			buyerCtx,
			resourceChecker{},
			403,
		},
		{
			"the order's own buyer reads it",
			buyerCtx,
			resourceChecker{orderObject: true},
			0,
		},
		{
			"an operator reads any order",
			buyerCtx,
			resourceChecker{"group:operator": true},
			0,
		},
	}
	for _, tc := range tests {
		t.Run(
			tc.name,
			func(t *testing.T) {
				t.Parallel()
				h := &Handlers{q: fakeQ{order: pendingOrder()}, checker: tc.checker}
				_, err := h.GetOrder(tc.ctx(), orders.GetOrderParams{ID: testOrderID})
				if tc.want == 0 {
					if err != nil {
						t.Fatalf("unexpected error: %v", err)
					}
					return
				}
				assertStatus(t, err, tc.want)
			},
		)
	}
}

// Checkout writes the tuples that decide who may read the order. So it cannot run
// without a principal to write them for, per ADR-0304.
func TestCheckoutRequiresAnOwner(t *testing.T) {
	t.Parallel()

	req := &orders.CheckoutInput{ProductID: "product_01kztmx9e0fq1r13w5d1aerqw6", Quantity: 1}
	// The header that the client sends to make a retry safe, per ADR-0003.
	params := orders.CheckoutParams{IdempotencyKey: "checkout-" + t.Name()}

	t.Run(
		"anonymous is unauthorized",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{q: fakeQ{}, tc: fakeTemporal{}, checker: okChecker()}
			_, err := h.Checkout(context.Background(), req, params)
			assertStatus(t, err, 401)
		},
	)

	// The edge builds the header from the Kratos identity, per ADR-0304. An identity
	// whose org never reached the edge would produce an order that belongs to nobody.
	t.Run(
		"an identity with no org is forbidden",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{q: fakeQ{}, tc: fakeTemporal{}, checker: okChecker()}
			_, err := h.Checkout(opCtx(), req, params)
			assertStatus(t, err, 403)
		},
	)

	// Without the header, a retry cannot be recognised. So the request is refused and
	// does not place a second order with no warning.
	t.Run(
		"a missing Idempotency-Key is a bad request",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{q: fakeQ{}, tc: fakeTemporal{}, checker: okChecker()}
			_, err := h.Checkout(buyerCtx(), req, orders.CheckoutParams{})
			assertStatus(t, err, 400)
		},
	)

	// The replay path. An order with this key means that the first attempt
	// succeeded, so the same handle comes back and no second workflow starts.
	t.Run(
		"a repeated key replays the first order",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{
				q:       fakeQ{byKey: store.GetOrderByIdempotencyKeyRow{Status: statusPending}},
				tc:      fakeTemporal{err: errors.New("must not be reached")},
				checker: okChecker(),
			}
			handle, err := h.Checkout(buyerCtx(), req, params)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if handle.Status != orders.WorkflowHandleStatusRunning {
				t.Fatalf("status = %v, want running", handle.Status)
			}
		},
	)

	t.Run(
		"a buyer with an org starts the checkout workflow",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{
				q:                fakeQ{},
				tc:               fakeTemporal{},
				checker:          okChecker(),
				checkoutsStarted: noopCounter(),
			}
			handle, err := h.Checkout(buyerCtx(), req, params)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if handle.Status != orders.WorkflowHandleStatusRunning {
				t.Fatalf("status = %v, want running", handle.Status)
			}
		},
	)
}

// CancelOrder is operator-gated, per ADR-0304. The gate rejects before any DB
// access, so a nil store works for these cases.
func TestCancelOrderAuthz(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		authed  bool
		checker authz.Checker
		want    int
	}{
		{"anonymous is unauthorized", false, fakeChecker{}, 401},
		{"non-operator is forbidden", true, fakeChecker{allowed: false}, 403},
		{"checker failure is internal", true, fakeChecker{err: errors.New("openfga down")}, 500},
	}
	for _, tc := range tests {
		t.Run(
			tc.name,
			func(t *testing.T) {
				t.Parallel()
				ctx := context.Background()
				if tc.authed {
					ctx = authmw.NewContext(ctx, &authmw.Principal{UserID: testUser})
				}
				h := &Handlers{checker: tc.checker}
				_, err := h.CancelOrder(ctx, orders.CancelOrderParams{})
				assertStatus(t, err, tc.want)
			},
		)
	}
}

func TestCancelOrder(t *testing.T) {
	t.Parallel()

	t.Run(
		"missing order is not found",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{q: fakeQ{getErr: pgx.ErrNoRows}, tc: fakeTemporal{}, checker: okChecker()}
			_, err := h.CancelOrder(opCtx(), orders.CancelOrderParams{ID: testOrderID})
			assertStatus(t, err, 404)
		},
	)

	for _, status := range []string{"cancelled", "failed"} {
		t.Run(
			status+" order is a conflict",
			func(t *testing.T) {
				t.Parallel()
				h := &Handlers{q: fakeQ{order: store.GetOrderRow{Status: status}}, tc: fakeTemporal{}, checker: okChecker()}
				_, err := h.CancelOrder(opCtx(), orders.CancelOrderParams{ID: testOrderID})
				assertStatus(t, err, 409)
			},
		)
	}

	t.Run(
		"a workflow start failure is internal",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{
				q:       fakeQ{order: store.GetOrderRow{Status: statusPending}},
				tc:      fakeTemporal{err: errors.New("temporal down")},
				checker: okChecker(),
			}
			_, err := h.CancelOrder(opCtx(), orders.CancelOrderParams{ID: testOrderID})
			assertStatus(t, err, 500)
		},
	)

	// The generated validator rejects a malformed id before the handler sees it. So
	// this reaches the handler only if a spec edit makes the two disagree.
	t.Run(
		"a malformed order id is a bad request",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{q: fakeQ{order: store.GetOrderRow{Status: statusPending}}, tc: fakeTemporal{}, checker: okChecker()}
			_, err := h.CancelOrder(opCtx(), orders.CancelOrderParams{ID: "order_not-base32"})
			assertStatus(t, err, 400)
		},
	)

	t.Run(
		"a cancellable order starts the cancel workflow",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{q: fakeQ{order: store.GetOrderRow{Status: statusPending}}, tc: fakeTemporal{}, checker: okChecker()}
			handle, err := h.CancelOrder(opCtx(), orders.CancelOrderParams{ID: testOrderID})
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if handle.Status != orders.WorkflowHandleStatusRunning {
				t.Fatalf("status = %v, want running", handle.Status)
			}
		},
	)
}

func TestListOrders(t *testing.T) {
	t.Parallel()

	// Listing every order is the back-office view with `x-audience: internal`, per
	// ADR-0303. So it is operator-gated, and an anonymous caller is refused before the
	// store is reached.
	t.Run(
		"an anonymous caller is unauthorized",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{q: fakeQ{}, checker: okChecker()}
			_, err := h.ListOrders(context.Background())
			assertStatus(t, err, 401)
		},
	)

	t.Run(
		"a non-operator is forbidden",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{q: fakeQ{}, checker: fakeChecker{allowed: false}}
			_, err := h.ListOrders(opCtx())
			assertStatus(t, err, 403)
		},
	)

	t.Run(
		"a store error is internal",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{q: fakeQ{listErr: errors.New("db down")}, checker: okChecker()}
			_, err := h.ListOrders(opCtx())
			assertStatus(t, err, 500)
		},
	)

	t.Run(
		"rows map to the API schema",
		func(t *testing.T) {
			t.Parallel()
			var total pgtype.Numeric
			err := total.Scan("5.00")
			if err != nil {
				t.Fatalf("scan total: %v", err)
			}
			h := &Handlers{q: fakeQ{list: []store.ListOrdersRow{
				{Quantity: 2, Total: total, Currency: testCurrency, Status: statusPending},
			}}, checker: okChecker()}
			got, err := h.ListOrders(opCtx())
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			// The stored numeric reaches the wire as a decimal string with its
			// currency, never as a number and never as minor units, per ADR-0300.
			if len(got) != 1 || got[0].Quantity != 2 || got[0].Total.Amount != "5" ||
				got[0].Total.Currency != testCurrency || got[0].Status != orders.OrderStatusPending {
				t.Fatalf("mapping = %+v", got)
			}
		},
	)
}

func assertStatus(t *testing.T, err error, want int) {
	t.Helper()
	e, ok := apierr.As(err)
	if !ok {
		t.Fatalf("want *apierr.Error, got %v", err)
	}
	if e.Status != want {
		t.Fatalf("status = %d, want %d", e.Status, want)
	}
}
