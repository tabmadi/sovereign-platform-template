// Package workflows holds the authz Temporal workflows: creating an operator, a dual write across two systems that
// share no transaction (ADR-0302, ADR-0304).
package workflows

import (
	"fmt"
	"time"

	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"
)

// RegisterOperatorInput is the createOperator request body, forwarded by the
// handler that accepted it.
type RegisterOperatorInput struct {
	Email    string
	Password string
}

// RegisterOperator runs the operator dual write: mint the Kratos identity, then grant `group:operator#member`.
// The grant is retried, and a run that exhausts its attempts is a failed workflow someone can find.
// The identity is minted first because the grant needs its id.
func RegisterOperator(ctx workflow.Context, in RegisterOperatorInput) error {
	ctx = workflow.WithActivityOptions(
		ctx,
		workflow.ActivityOptions{
			StartToCloseTimeout: 30 * time.Second,
			RetryPolicy:         &temporal.RetryPolicy{InitialInterval: time.Second, MaximumAttempts: 5},
		},
	)

	var identityID string
	err := workflow.ExecuteActivity(ctx, "CreateOperatorIdentityActivity", in.Email, in.Password).Get(ctx, &identityID)
	if err != nil {
		return fmt.Errorf("register operator: create identity: %w", err)
	}
	err = workflow.ExecuteActivity(ctx, "GrantOperatorRoleActivity", identityID).Get(ctx, nil)
	if err != nil {
		return fmt.Errorf("register operator: grant operator role: %w", err)
	}
	return nil
}
