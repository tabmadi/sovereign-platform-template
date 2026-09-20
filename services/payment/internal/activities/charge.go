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

// GrantChargeAccessActivity: The OpenFGA leg of the charge write (ADR-0304). One tuple: `charge#read` is `read from
// order`, so a change to who may read an order cannot leave the charge behind.
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
// carries the wire form, and the column holds the bare uuid (ADR-0003), so this is
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
