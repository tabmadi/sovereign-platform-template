// Package workflows holds the orgs Temporal workflows. orgs owns the create-personal-org process by the process-owner
// rule, but the OpenFGA write goes to the authz store, per ADR-0302.
package workflows

import (
	"fmt"
	"time"

	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"
)

// RegisterInput is the Kratos post-registration payload. The /identity-created
// webhook handler forwards it.
type RegisterInput struct {
	IdentityID string
}

// RegisterUser is the dual write for a new identity, per ADR-0304: the personal org and membership, then the
// matching OpenFGA owner tuple. Both are activities, so the pair cannot half-apply. The third activity records
// the org on the Kratos identity, and the edge builds X-Org-Id from it.
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
