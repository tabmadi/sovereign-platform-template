package handlers

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"go.temporal.io/sdk/client"

	"github.com/tabmadi/sovereign-platform-template/libs/go/apierr"
	"github.com/tabmadi/sovereign-platform-template/libs/go/authmw"
	"github.com/tabmadi/sovereign-platform-template/libs/go/authz"
	payment "github.com/tabmadi/sovereign-platform-template/libs/go/sdks/payment"
	"github.com/tabmadi/sovereign-platform-template/services/payment/internal/store"
)

const statusSettled = "settled"

// A well-formed wire identifier, per ADR-0003. The cases below then test the
// handler's logic and not its identifier decoding, which has its own case.
const testChargeID = payment.ChargeId("charge_01kztnyqr0f13shqqnx8028xx5")

const testOrderID = payment.OrderId("order_01kztnj6c8e0jt7vzw0cn1wxvd")

// fakeQ embeds store.Querier, so only the methods that a test uses need stubs.
// Any other call panics on nil, and that is the wanted signal for an unexpected query.
type fakeQ struct {
	store.Querier

	charge  store.GetChargeRow
	getErr  error
	list    []store.ListChargesRow
	listErr error
}

func (f fakeQ) GetCharge(context.Context, pgtype.UUID) (store.GetChargeRow, error) {
	return f.charge, f.getErr
}

func (f fakeQ) ListCharges(context.Context) ([]store.ListChargesRow, error) {
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
	return authmw.NewContext(context.Background(), &authmw.Principal{UserID: "alice"})
}

func okChecker() authz.Checker { return fakeChecker{allowed: true} }

// RefundCharge is operator-gated, per ADR-0304. The gate rejects before any DB
// access, so a nil store works for these cases.
func TestRefundChargeAuthz(t *testing.T) {
	t.Parallel()
	req := &payment.RefundInput{Reason: "duplicate"}

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
					ctx = authmw.NewContext(ctx, &authmw.Principal{UserID: "alice"})
				}
				h := &Handlers{checker: tc.checker}
				_, err := h.RefundCharge(ctx, req, payment.RefundChargeParams{})
				assertStatus(t, err, tc.want)
			},
		)
	}
}

func TestRefundCharge(t *testing.T) {
	t.Parallel()
	req := &payment.RefundInput{Reason: "duplicate"}

	t.Run(
		"missing charge is not found",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{q: fakeQ{getErr: pgx.ErrNoRows}, tc: fakeTemporal{}, checker: okChecker()}
			_, err := h.RefundCharge(opCtx(), req, payment.RefundChargeParams{ID: testChargeID})
			assertStatus(t, err, 404)
		},
	)

	t.Run(
		"an unsettled charge is a conflict",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{q: fakeQ{charge: store.GetChargeRow{Status: "pending"}}, tc: fakeTemporal{}, checker: okChecker()}
			_, err := h.RefundCharge(opCtx(), req, payment.RefundChargeParams{ID: testChargeID})
			assertStatus(t, err, 409)
		},
	)

	t.Run(
		"a workflow start failure is internal",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{
				q:       fakeQ{charge: store.GetChargeRow{Status: statusSettled}},
				tc:      fakeTemporal{err: errors.New("temporal down")},
				checker: okChecker(),
			}
			_, err := h.RefundCharge(opCtx(), req, payment.RefundChargeParams{ID: testChargeID})
			assertStatus(t, err, 500)
		},
	)

	// The generated validator rejects a malformed id before the handler sees it. So
	// this reaches the handler only if a spec edit makes the two disagree.
	t.Run(
		"a malformed charge id is a bad request",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{q: fakeQ{charge: store.GetChargeRow{Status: statusSettled}}, tc: fakeTemporal{}, checker: okChecker()}
			_, err := h.RefundCharge(opCtx(), req, payment.RefundChargeParams{ID: "charge_not-base32"})
			assertStatus(t, err, 400)
		},
	)

	t.Run(
		"a settled charge starts the refund workflow",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{q: fakeQ{charge: store.GetChargeRow{Status: statusSettled}}, tc: fakeTemporal{}, checker: okChecker()}
			handle, err := h.RefundCharge(opCtx(), req, payment.RefundChargeParams{ID: testChargeID})
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if handle.Status != payment.WorkflowHandleStatusRunning {
				t.Fatalf("status = %v, want running", handle.Status)
			}
		},
	)
}

// It answers per resource. A buyer holds `charge#read` on their own order's charge and nothing on `group:operator`.
// An operator is the reverse.
type resourceChecker map[string]bool

func (c resourceChecker) Allowed(_ context.Context, _, _, resource string) (bool, error) {
	return c[resource], nil
}

// testCurrency is the currency of every fixture here. The currency itself does not
// matter. It only needs to travel with the amount.
const testCurrency = "EUR"

// numeric is a stored `numeric(19,4)`. The zero pgtype.Numeric is not, and a
// handler that renders money needs a row with money in it.
func numeric(t *testing.T, v string) pgtype.Numeric {
	t.Helper()
	var n pgtype.Numeric
	err := n.Scan(v)
	if err != nil {
		t.Fatalf("scan %q: %v", v, err)
	}
	return n
}

// chargeObject is the OpenFGA object that the read gate checks.
var chargeObject = "charge:" + string(testChargeID)

func TestGetChargeAuthz(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		ctx     func() context.Context
		checker authz.Checker
		want    int
	}{
		{"holding the identifier is not enough", context.Background, resourceChecker{chargeObject: true}, 401},
		{"another buyer is forbidden", opCtx, resourceChecker{}, 403},
		{"the order's buyer reads its charge", opCtx, resourceChecker{chargeObject: true}, 0},
		{"an operator reads any charge", opCtx, resourceChecker{"group:operator": true}, 0},
	}
	for _, tc := range tests {
		t.Run(
			tc.name,
			func(t *testing.T) {
				t.Parallel()
				row := store.GetChargeRow{
					Status:   statusSettled,
					Amount:   numeric(t, "25.98"),
					Currency: testCurrency,
				}
				h := &Handlers{q: fakeQ{charge: row}, checker: tc.checker}
				_, err := h.GetCharge(tc.ctx(), payment.GetChargeParams{ID: testChargeID})
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

// The shared money type validates the amount, and a value that it refuses is the
// client's mistake, not a 500. A generated validator cannot catch these shapes,
// because the wire form of an amount is only a string.
func TestCreateChargeAmount(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name   string
		amount payment.Money
	}{
		{"a non-decimal amount", payment.Money{Amount: "12,00", Currency: testCurrency}},
		{"an unknown currency form", payment.Money{Amount: "12.00", Currency: "eur"}},
		{"zero is not a charge", payment.Money{Amount: "0.00", Currency: testCurrency}},
		{"a negative amount is a refund, not a charge", payment.Money{Amount: "-1.00", Currency: testCurrency}},
	}
	for _, tc := range tests {
		t.Run(
			tc.name,
			func(t *testing.T) {
				t.Parallel()
				h := &Handlers{q: fakeQ{}, tc: fakeTemporal{}, checker: okChecker()}
				req := &payment.ChargeInput{OrderID: testOrderID, Amount: tc.amount}
				_, err := h.CreateCharge(
					opCtx(),
					req,
					payment.CreateChargeParams{IdempotencyKey: "key-1"},
				)
				assertStatus(t, err, 400)
			},
		)
	}
}

func TestListCharges(t *testing.T) {
	t.Parallel()

	// Listing every charge is the back-office view with `x-audience: internal`, per
	// ADR-0303. So it is operator-gated, and an anonymous caller is refused before the
	// store is reached.
	t.Run(
		"an anonymous caller is unauthorized",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{q: fakeQ{}, checker: okChecker()}
			_, err := h.ListCharges(context.Background())
			assertStatus(t, err, 401)
		},
	)

	t.Run(
		"a non-operator is forbidden",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{q: fakeQ{}, checker: fakeChecker{allowed: false}}
			_, err := h.ListCharges(opCtx())
			assertStatus(t, err, 403)
		},
	)

	t.Run(
		"a store error is internal",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{q: fakeQ{listErr: errors.New("db down")}, checker: okChecker()}
			_, err := h.ListCharges(opCtx())
			assertStatus(t, err, 500)
		},
	)

	t.Run(
		"rows map to the API schema",
		func(t *testing.T) {
			t.Parallel()
			h := &Handlers{q: fakeQ{list: []store.ListChargesRow{
				{Amount: numeric(t, "9.99"), Currency: testCurrency, Status: statusSettled},
			}}, checker: okChecker()}
			got, err := h.ListCharges(opCtx())
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			// The stored numeric reaches the wire as a decimal string with its
			// currency, never as a number and never as minor units, per ADR-0300.
			if len(got) != 1 || got[0].Amount.Amount != "9.99" ||
				got[0].Amount.Currency != testCurrency || got[0].Status != payment.ChargeStatusSettled {
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
