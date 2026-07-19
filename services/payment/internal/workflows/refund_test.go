package workflows

import (
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/testsuite"
)

// refundEnv registers stub activities under the names Refund executes, so the
// test env resolves and mocks them without the real PSP/DB implementations.
func refundEnv(ts *testsuite.WorkflowTestSuite) *testsuite.TestWorkflowEnvironment {
	env := ts.NewTestWorkflowEnvironment()
	env.RegisterActivityWithOptions(
		func(context.Context, RefundInput) error { return nil },
		activity.RegisterOptions{Name: "RefundActivity"},
	)
	env.RegisterActivityWithOptions(
		func(context.Context, string, string) error { return nil },
		activity.RegisterOptions{Name: "MarkChargeStatusActivity"},
	)
	return env
}

func TestRefundWorkflow(t *testing.T) {
	t.Parallel()

	t.Run(
		"reverses the charge then marks it refunded",
		func(t *testing.T) {
			t.Parallel()
			var ts testsuite.WorkflowTestSuite
			env := refundEnv(&ts)
			env.OnActivity("RefundActivity", mock.Anything, mock.Anything).Return(nil).Once()
			env.OnActivity("MarkChargeStatusActivity", mock.Anything, "chg_1", "refunded").Return(nil).Once()

			env.ExecuteWorkflow(Refund, RefundInput{ChargeID: "chg_1", Reason: "duplicate"})

			require.True(t, env.IsWorkflowCompleted())
			require.NoError(t, env.GetWorkflowError())
			var res RefundResult
			require.NoError(t, env.GetWorkflowResult(&res))
			require.Equal(t, "refunded", res.Status)
			env.AssertExpectations(t)
		},
	)

	t.Run(
		"PSP failure fails the workflow and never marks refunded",
		func(t *testing.T) {
			t.Parallel()
			var ts testsuite.WorkflowTestSuite
			env := refundEnv(&ts)
			env.OnActivity("RefundActivity", mock.Anything, mock.Anything).Return(errors.New("psp down"))

			env.ExecuteWorkflow(Refund, RefundInput{ChargeID: "chg_1"})

			require.True(t, env.IsWorkflowCompleted())
			require.Error(t, env.GetWorkflowError())
			env.AssertNotCalled(t, "MarkChargeStatusActivity", mock.Anything, mock.Anything, mock.Anything)
		},
	)
}
