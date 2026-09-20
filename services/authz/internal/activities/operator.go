// Package activities holds the two legs of the operator-registration dual write (ADR-0302, ADR-0304).
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

// CreateOperatorIdentityActivity: Dual-write leg 1: the Kratos identity carrying the `operator` trait, the coarse
// ops-tier claim gate (ADR-0306). Not idempotent, and it need not be: Kratos refuses a second identity with the same
// email address.
func (a *Activities) CreateOperatorIdentityActivity(ctx context.Context, email, password string) (string, error) {
	id, err := a.identities.CreateOperatorIdentity(ctx, email, password)
	if err != nil {
		return "", fmt.Errorf("create operator identity: %w", err)
	}
	return id, nil
}

// GrantOperatorRoleActivity: Dual-write leg 2: `group:operator#member`, seeding the optional fine per-tool layer
// (ADR-0401). This is the leg whose silent failure the workflow exists to prevent. A tuple write is idempotent.
func (a *Activities) GrantOperatorRoleActivity(ctx context.Context, identityID string) error {
	err := a.granter.Grant(ctx, "user:"+identityID, "member", "group:operator")
	if err != nil {
		return fmt.Errorf("grant operator role: %w", err)
	}
	return nil
}
