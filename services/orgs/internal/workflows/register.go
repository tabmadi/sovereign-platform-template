// Package workflows holds the orgs Temporal workflows. orgs owns the create-personal-org process by the process-owner
// rule, though the OpenFGA write targets the authz store (ADR-0302).
package workflows

import (
	"fmt"
	"time"

	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"
)

// RegisterInput is the Kratos post-registration payload, forwarded by the
// /identity-created webhook handler.
type RegisterInput struct {
	IdentityID string
}

// RegisterUser is the dual write for a new identity (ADR-0304): the personal org and membership, then the
// matching OpenFGA owner tuple. Both are activities, so the pair cannot half-apply.
// The third records the org on the Kratos identity, which is what the edge builds X-Org-Id out of.
func RegisterUser(ctx workflow.Context, in RegisterInput) error {
	ctx = workflow.WithActivityOptions(
		ctx,
		workflow.ActivityOptions{
			StartToCloseTimeout: 30 * time.Second,
			RetryPolicy:         &temporal.RetryPolicy{InitialInterval: time.Second, MaximumAttempts: 5},
		},
	)

	var orgID string
	err := workflow.ExecuteActivity(ctx, "CreatePersonalOrgActivity", in.IdentityID).Get(ctx, &orgID)
	if err != nil {
		return fmt.Errorf("register user: create personal org: %w", err)
	}
	err = workflow.ExecuteActivity(ctx, "GrantOrgAdminActivity", orgID, in.IdentityID).Get(ctx, nil)
	if err != nil {
		return fmt.Errorf("register user: grant org admin: %w", err)
	}
	err = workflow.ExecuteActivity(ctx, "SetIdentityOrgActivity", in.IdentityID, orgID).Get(ctx, nil)
	if err != nil {
		return fmt.Errorf("register user: set identity org: %w", err)
	}
	return nil
}
