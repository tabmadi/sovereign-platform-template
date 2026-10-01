// Package activities holds the two legs of the register-user dual write, per ADR-0302 and ADR-0304.
package activities

import (
	"context"
	"fmt"
	"net/http"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tabmadi/sovereign-platform-template/libs/go/authz"
	"github.com/tabmadi/sovereign-platform-template/libs/go/id"
	"github.com/tabmadi/sovereign-platform-template/services/orgs/internal/store"
)

type Activities struct {
	db          *pgxpool.Pool
	q           *store.Queries
	granter     authz.Granter
	HTTP        *http.Client
	KratosAdmin string
}

func New(db *pgxpool.Pool, granter authz.Granter) *Activities {
	return &Activities{
		db:          db,
		q:           store.New(db),
		granter:     granter,
		HTTP:        http.DefaultClient,
		KratosAdmin: kratosAdminURL(),
	}
}

// Generic on purpose, not the user's email. An org can later hold a team, every member sees its `name`, per
// ADR-0301, and an email can change.
const personalOrgName = "Personal workspace"

// CreatePersonalOrgActivity is dual-write leg 1, per ADR-0304: the org and its admin membership in one transaction.
// It returns the org id in the wire form, per ADR-0003, because the id leaves this process.
func (a *Activities) CreatePersonalOrgActivity(ctx context.Context, identityID string) (string, error) {
	tx, err := a.db.Begin(ctx)
	if err != nil {
		return "", fmt.Errorf("create personal org: begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// Minted here, not by a column default and not in the workflow. `id.New` reads the clock and the entropy pool, and
	// a workflow function must not, per ADR-0003.
	key, err := id.New("org")
	if err != nil {
		return "", fmt.Errorf("create personal org: mint id: %w", err)
	}

	qtx := a.q.WithTx(tx)
	org, err := qtx.CreateOrg(
		ctx,
		store.CreateOrgParams{
			ID:   pgtype.UUID{Bytes: key.UUID(), Valid: true},
			Name: personalOrgName,
		},
	)
	if err != nil {
		return "", fmt.Errorf("create personal org: insert org: %w", err)
	}
	err = qtx.AddMember(ctx, store.AddMemberParams{OrgID: org.ID, UserID: identityID, Role: "admin"})
	if err != nil {
		return "", fmt.Errorf("create personal org: add member: %w", err)
	}
	err = tx.Commit(ctx)
	if err != nil {
		return "", fmt.Errorf("create personal org: commit: %w", err)
	}
	return key.String(), nil
}

// GrantOrgAdminActivity is dual-write leg 2, per ADR-0304: the OpenFGA write. It grants
// the identity the `admin` relation on their personal org, `org:<id>#admin@user:<id>` in
// model.fga. So ReBAC ownership matches the app-DB membership.
func (a *Activities) GrantOrgAdminActivity(ctx context.Context, orgID, identityID string) error {
	err := a.granter.Grant(ctx, "user:"+identityID, "admin", "org:"+orgID)
	if err != nil {
		return fmt.Errorf("grant org admin: %w", err)
	}
	return nil
}
