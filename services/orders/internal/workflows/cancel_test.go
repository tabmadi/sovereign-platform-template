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

// cancelEnv registers a stub MarkOrderStatusActivity under the name CancelOrder
// executes, so the test env resolves and mocks it without the real store.
func cancelEnv(ts *testsuite.WorkflowTestSuite) *testsuite.TestWorkflowEnvironment {
	env := ts.NewTestWorkflowEnvironment()
	env.RegisterActivityWithOptions(
		func(context.Context, string, string) error { return nil },
		activity.RegisterOptions{Name: "MarkOrderStatusActivity"},
	)
	return env
}

func TestCancelOrderWorkflow(t *testing.T) {
	t.Parallel()

	t.Run(
		"marks the order cancelled",
		func(t *testing.T) {
			t.Parallel()
			var ts testsuite.WorkflowTestSuite
			env := cancelEnv(&ts)
			env.OnActivity("MarkOrderStatusActivity", mock.Anything, "ord_1", "cancelled").Return(nil).Once()

			env.ExecuteWorkflow(CancelOrder, CancelInput{OrderID: "ord_1"})

			require.True(t, env.IsWorkflowCompleted())
			require.NoError(t, env.GetWorkflowError())
			var res CancelResult
			require.NoError(t, env.GetWorkflowResult(&res))
			require.Equal(t, "cancelled", res.Status)
			env.AssertExpectations(t)
		},
	)

	t.Run(
		"activity failure fails the workflow",
		func(t *testing.T) {
			t.Parallel()
			var ts testsuite.WorkflowTestSuite
			env := cancelEnv(&ts)
			env.OnActivity("MarkOrderStatusActivity", mock.Anything, mock.Anything, mock.Anything).
				Return(errors.New("db down"))

			env.ExecuteWorkflow(CancelOrder, CancelInput{OrderID: "ord_1"})

			require.True(t, env.IsWorkflowCompleted())
			require.Error(t, env.GetWorkflowError())
		},
	)
}
