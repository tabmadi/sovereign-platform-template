// Package activities holds the two legs of the operator dual write (ADR-0302, ADR-0304).
package activities

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/tabmadi/sovereign-platform-template/libs/go/authz"
	"github.com/tabmadi/sovereign-platform-template/services/authz/internal/kratos"
)

type Activities struct {
	identities *kratos.Admin
	granter    authz.Granter
}

func New(granter authz.Granter, log *slog.Logger) *Activities {
	return &Activities{identities: kratos.New(log), granter: granter}
}

// SetOperatorFlagActivity: leg 1, metadata_public.operator, the coarse ops-tier claim (ADR-0306). Idempotent.
func (a *Activities) SetOperatorFlagActivity(ctx context.Context, identityID string, op bool) error {
	err := a.identities.SetOperatorFlag(ctx, identityID, op)
	if err != nil {
		return fmt.Errorf("set operator flag: %w", err)
	}
	return nil
}

// SetOperatorGrantActivity: leg 2, `group:operator#member`, which the fine per-tool gate and the admin console read
// (ADR-0401). This is the leg whose silent failure the workflow exists to prevent. Idempotent either way.
func (a *Activities) SetOperatorGrantActivity(ctx context.Context, identityID string, op bool) error {
	subject := "user:" + identityID
	var err error
	if op {
		err = a.granter.Grant(ctx, subject, "member", "group:operator")
	} else {
		err = a.granter.Revoke(ctx, subject, "member", "group:operator")
	}
	if err != nil {
		return fmt.Errorf("set operator grant: %w", err)
	}
	return nil
}
