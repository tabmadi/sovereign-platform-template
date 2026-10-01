// Package activities holds the Charge workflow's activities.
package activities

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tabmadi/sovereign-platform-template/libs/go/authz"
	"github.com/tabmadi/sovereign-platform-template/libs/go/id"
	"github.com/tabmadi/sovereign-platform-template/services/payment/internal/workflows"
)

type Activities struct {
	DB      *pgxpool.Pool
	Granter authz.Granter
}

func New(db *pgxpool.Pool, granter authz.Granter) *Activities {
	return &Activities{DB: db, Granter: granter}
}

// GrantChargeAccessActivity is the OpenFGA leg of the charge write, per ADR-0304. It writes one tuple. `charge#read`
// is `read from order`, so a change to who may read an order also applies to the charge.
func (a *Activities) GrantChargeAccessActivity(ctx context.Context, chargeID, orderID string) error {
	err := a.Granter.Grant(ctx, "order:"+orderID, "order", "charge:"+chargeID)
	if err != nil {
		return fmt.Errorf("grant charge access: %w", err)
	}
	return nil
}

func (a *Activities) SettleActivity(_ context.Context, _ workflows.ChargeInput) error { return nil }

func (a *Activities) RefundActivity(_ context.Context, _ workflows.RefundInput) error { return nil }

// MarkChargeStatusActivity writes the terminal status of a charge. The workflow
// carries the wire form, and the column holds the bare uuid, per ADR-0003. This is
// where the two meet.
func (a *Activities) MarkChargeStatusActivity(ctx context.Context, chargeID, status string) error {
	parsed, err := id.Parse("charge", chargeID)
	if err != nil {
		return fmt.Errorf("mark charge status: parse charge id: %w", err)
	}
	_, err = a.DB.Exec(ctx, `update charges set status = $2 where id = $1`, parsed.UUID(), status)
	if err != nil {
		return fmt.Errorf("mark charge status: update: %w", err)
	}
	return nil
}
