package workflows

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/testsuite"
)

const testID = "019a3f8c-6d21-7c4b-8e55-0f27f7f0b001"

// setOperatorEnv registers stub activities under the names SetOperator executes,
// so the test env resolves and mocks them without a real Kratos or OpenFGA.
func setOperatorEnv(ts *testsuite.WorkflowTestSuite) *testsuite.TestWorkflowEnvironment {
	env := ts.NewTestWorkflowEnvironment()
	env.RegisterActivityWithOptions(
		func(context.Context, string, bool) error { return nil },
		activity.RegisterOptions{Name: "SetOperatorFlagActivity"},
	)
	env.RegisterActivityWithOptions(
		func(context.Context, string, bool) error { return nil },
		activity.RegisterOptions{Name: "SetOperatorGrantActivity"},
	)
	return env
}

func TestSetOperatorWorkflow(t *testing.T) {
	t.Parallel()

	for _, op := range []bool{true, false} {
		t.Run(
			fmt.Sprintf("operator=%t writes the flag then the grant", op),
			func(t *testing.T) {
				t.Parallel()
				var ts testsuite.WorkflowTestSuite
				env := setOperatorEnv(&ts)
				env.OnActivity("SetOperatorFlagActivity", mock.Anything, testID, op).Return(nil).Once()
				env.OnActivity("SetOperatorGrantActivity", mock.Anything, testID, op).Return(nil).Once()

				env.ExecuteWorkflow(SetOperator, SetOperatorInput{IdentityID: testID, Operator: op})

				require.True(t, env.IsWorkflowCompleted())
				require.NoError(t, env.GetWorkflowError())
				env.AssertExpectations(t)
			},
		)
	}

	t.Run(
		"a flag failure fails the run and never touches the grant",
		func(t *testing.T) {
			t.Parallel()
			var ts testsuite.WorkflowTestSuite
			env := setOperatorEnv(&ts)
			env.OnActivity("SetOperatorFlagActivity", mock.Anything, mock.Anything, mock.Anything).
				Return(errors.New("kratos down"))

			env.ExecuteWorkflow(SetOperator, SetOperatorInput{IdentityID: testID, Operator: true})

			require.True(t, env.IsWorkflowCompleted())
			require.Error(t, env.GetWorkflowError())
			env.AssertNotCalled(t, "SetOperatorGrantActivity", mock.Anything, mock.Anything, mock.Anything)
		},
	)

	t.Run(
		// The state the workflow exists to prevent: a flag and a grant that disagree. A grant failure must fail the run
		// so it is visible, rather than returning success with half the write done.
		"a grant failure fails the run rather than leaving the legs disagreeing",
		func(t *testing.T) {
			t.Parallel()
			var ts testsuite.WorkflowTestSuite
			env := setOperatorEnv(&ts)
			env.OnActivity("SetOperatorFlagActivity", mock.Anything, testID, true).Return(nil).Once()
			env.OnActivity("SetOperatorGrantActivity", mock.Anything, testID, true).
				Return(errors.New("openfga down"))

			env.ExecuteWorkflow(SetOperator, SetOperatorInput{IdentityID: testID, Operator: true})

			require.True(t, env.IsWorkflowCompleted())
			require.Error(t, env.GetWorkflowError())
		},
	)
}
