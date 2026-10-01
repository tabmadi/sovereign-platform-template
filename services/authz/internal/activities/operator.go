// Package activities holds the two legs of the operator dual write, per ADR-0302 and ADR-0304.
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

// SetOperatorFlagActivity is leg 1: metadata_public.operator, the coarse ops-tier claim, per ADR-0306. It is
// idempotent.
func (a *Activities) SetOperatorFlagActivity(ctx context.Context, identityID string, op bool) error {
	err := a.identities.SetOperatorFlag(ctx, identityID, op)
	if err != nil {
		return fmt.Errorf("set operator flag: %w", err)
	}
	return nil
}

// SetOperatorGrantActivity is leg 2: `group:operator#member`, which the fine per-tool gate and the admin console read,
// per ADR-0401. The workflow exists to prevent a silent failure of this leg. It is idempotent in both directions.
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
