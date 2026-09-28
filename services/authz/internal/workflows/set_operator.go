// Package workflows holds the authz Temporal workflows: promoting or demoting an operator, a dual write across two
// systems that share no transaction (ADR-0302, ADR-0304).
package workflows

import (
	"fmt"
	"time"

	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"
)

type SetOperatorInput struct {
	IdentityID string
	Operator   bool
}

// SetOperator runs the operator dual write: the metadata flag, then the OpenFGA grant. Both legs are retried, and a
// run that exhausts its attempts is a failed workflow someone can find. The flag goes first so a demotion closes the
// coarse gate before the grant is revoked.
func SetOperator(ctx workflow.Context, in SetOperatorInput) error {
	ctx = workflow.WithActivityOptions(
		ctx,
		workflow.ActivityOptions{
			StartToCloseTimeout: 30 * time.Second,
			RetryPolicy:         &temporal.RetryPolicy{InitialInterval: time.Second, MaximumAttempts: 5},
		},
	)

	err := workflow.ExecuteActivity(ctx, "SetOperatorFlagActivity", in.IdentityID, in.Operator).Get(ctx, nil)
	if err != nil {
		return fmt.Errorf("set operator: flag: %w", err)
	}
	err = workflow.ExecuteActivity(ctx, "SetOperatorGrantActivity", in.IdentityID, in.Operator).Get(ctx, nil)
	if err != nil {
		return fmt.Errorf("set operator: grant: %w", err)
	}
	return nil
}
