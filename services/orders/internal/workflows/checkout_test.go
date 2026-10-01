package workflows

import (
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/testsuite"

	"github.com/tabmadi/sovereign-platform-template/libs/go/money"
)

var testCheckout = CheckoutInput{
	OrderID:   "order_01kztnj6c8e0jt7vzw0cn1wxvd",
	ProductID: "product_01kztmx9e0fq1r13w5d1aerqw6",
	Quantity:  2,
	OwnerID:   "identity-1",
	OrgID:     "org_01kztn9tsrea7b1597q3yjdeav",
}

// checkoutEnv registers a stub for each activity that Checkout runs, under the names
// that it uses. The test env then resolves them without the real store, the real
// OpenFGA, or the two services that the saga calls.
func checkoutEnv(ts *testsuite.WorkflowTestSuite) *testsuite.TestWorkflowEnvironment {
	env := ts.NewTestWorkflowEnvironment()
	env.RegisterActivityWithOptions(
		func(context.Context, CheckoutInput) error { return nil },
		activity.RegisterOptions{Name: "CreateOrderActivity"},
	)
	env.RegisterActivityWithOptions(
		func(context.Context, string, string, string) error { return nil },
		activity.RegisterOptions{Name: "GrantOrderAccessActivity"},
	)
	env.RegisterActivityWithOptions(
		func(context.Context, string) (money.Amount, error) { return money.Amount{}, nil },
		activity.RegisterOptions{Name: "LookupProductActivity"},
	)
	env.RegisterActivityWithOptions(
		func(context.Context, string, money.Amount) error { return nil },
		activity.RegisterOptions{Name: "SetOrderTotalActivity"},
	)
	env.RegisterActivityWithOptions(
		func(context.Context, string, money.Amount) (string, error) { return "", nil },
		activity.RegisterOptions{Name: "ChargeActivity"},
	)
	env.RegisterActivityWithOptions(
		func(context.Context, string, string) error { return nil },
		activity.RegisterOptions{Name: "MarkOrderStatusActivity"},
	)
	return env
}

func TestCheckoutWorkflow(t *testing.T) {
	t.Parallel()

	t.Run(
		"writes the row and its access tuples before charging",
		func(t *testing.T) {
			t.Parallel()
			var ts testsuite.WorkflowTestSuite
			env := checkoutEnv(&ts)
			env.OnActivity("CreateOrderActivity", mock.Anything, testCheckout).Return(nil).Once()
			env.OnActivity(
				"GrantOrderAccessActivity",
				mock.Anything,
				testCheckout.OrderID,
				testCheckout.OwnerID,
				testCheckout.OrgID,
			).Return(nil).Once()
			unitPrice := money.MustParse("15.00", "EUR")
			orderTotal := money.MustParse("30.00", "EUR")
			env.OnActivity(
				"LookupProductActivity",
				mock.Anything,
				testCheckout.ProductID,
			).Return(unitPrice, nil).Once()
			env.OnActivity(
				"SetOrderTotalActivity",
				mock.Anything,
				testCheckout.OrderID,
				orderTotal,
			).Return(nil).Once()
			env.OnActivity(
				"ChargeActivity",
				mock.Anything,
				testCheckout.OrderID,
				orderTotal,
			).Return("charge_01kztnyqr0f13shqqnx8028xx5", nil).Once()
			env.OnActivity(
				"MarkOrderStatusActivity",
				mock.Anything,
				testCheckout.OrderID,
				"confirmed",
			).Return(nil).Once()

			env.ExecuteWorkflow(Checkout, testCheckout)

			require.True(t, env.IsWorkflowCompleted())
			require.NoError(t, env.GetWorkflowError())
			var res CheckoutResult
			require.NoError(t, env.GetWorkflowResult(&res))
			require.Equal(t, "confirmed", res.Status)
			// The saga multiplied the unit price by the quantity with the shared
			// money type, so the total carries its currency and not only a scale.
			require.Equal(t, "30", res.Total.String())
			require.Equal(t, "EUR", res.Total.Currency())
			env.AssertExpectations(t)
		},
	)

	// The DB write and the OpenFGA write are the two legs of one dual write, per
	// ADR-0304. So a failed insert must not leave tuples that point at a row that
	// does not exist.
	t.Run(
		"a failed insert never grants access",
		func(t *testing.T) {
			t.Parallel()
			var ts testsuite.WorkflowTestSuite
			env := checkoutEnv(&ts)
			env.OnActivity("CreateOrderActivity", mock.Anything, mock.Anything).
				Return(errors.New("db down"))

			env.ExecuteWorkflow(Checkout, testCheckout)

			require.True(t, env.IsWorkflowCompleted())
			require.Error(t, env.GetWorkflowError())
			env.AssertNotCalled(
				t,
				"GrantOrderAccessActivity",
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
			)
		},
	)

	// The dual write exists to prevent an order that nobody can read. So the saga
	// stops and does not charge for something that the buyer cannot see.
	t.Run(
		"a failed grant stops the saga before it charges",
		func(t *testing.T) {
			t.Parallel()
			var ts testsuite.WorkflowTestSuite
			env := checkoutEnv(&ts)
			env.OnActivity("CreateOrderActivity", mock.Anything, mock.Anything).Return(nil).Once()
			env.OnActivity(
				"GrantOrderAccessActivity",
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
			).Return(errors.New("openfga down"))

			env.ExecuteWorkflow(Checkout, testCheckout)

			require.True(t, env.IsWorkflowCompleted())
			require.Error(t, env.GetWorkflowError())
			env.AssertNotCalled(t, "ChargeActivity", mock.Anything, mock.Anything, mock.Anything)
		},
	)
}
