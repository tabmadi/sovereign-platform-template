// Package workflows holds the checkout saga, per ADR-0302. orders owns it by the process-owner rule, but the data
// lives in catalog and payment.
package workflows

import (
	"fmt"
	"time"

	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"

	"github.com/tabmadi/sovereign-platform-template/libs/go/money"
)

// statusFailed is the terminal status of an order that the saga could not complete.
const statusFailed = "failed"

type CheckoutInput struct {
	OrderID   string
	ProductID string
	Quantity  int32
	// OwnerID is the buyer's Kratos identity. OrgID is the org they act through, per
	// ADR-0304. The order's OpenFGA tuples are written from both.
	OwnerID string
	OrgID   string
	// IdempotencyKey comes from the client. It goes into the row, so a retried
	// checkout finds the order that the first one created, per ADR-0003.
	IdempotencyKey string
}

type CheckoutResult struct {
	Status   string // `confirmed` or `failed`
	Total    money.Amount
	ChargeID string
}

func Checkout(ctx workflow.Context, in CheckoutInput) (CheckoutResult, error) {
	ao := workflow.ActivityOptions{
		StartToCloseTimeout: 30 * time.Second,
		RetryPolicy:         &temporal.RetryPolicy{InitialInterval: time.Second, MaximumAttempts: 3},
	}
	ctx = workflow.WithActivityOptions(ctx, ao)

	err := workflow.ExecuteActivity(ctx, "CreateOrderActivity", in).Get(ctx, nil)
	if err != nil {
		return CheckoutResult{Status: statusFailed}, fmt.Errorf("checkout: create order: %w", err)
	}
	// This runs before any step that can fail the order. A later activity can mark
	// the row `failed`, and its buyer must still be able to read it.
	err = workflow.ExecuteActivity(ctx, "GrantOrderAccessActivity", in.OrderID, in.OwnerID, in.OrgID).Get(ctx, nil)
	if err != nil {
		return CheckoutResult{Status: statusFailed}, fmt.Errorf("checkout: grant order access: %w", err)
	}

	var price money.Amount
	err = workflow.ExecuteActivity(ctx, "LookupProductActivity", in.ProductID).Get(ctx, &price)
	if err != nil {
		_ = workflow.ExecuteActivity(ctx, "MarkOrderStatusActivity", in.OrderID, statusFailed).Get(ctx, nil)
		return CheckoutResult{Status: statusFailed}, fmt.Errorf("checkout: lookup product: %w", err)
	}
	// Money multiplication, not a bare integer product: the shared type carries the currency and scale, per ADR-0300.
	// It is deterministic: integer arithmetic with no clock and no rounding mode.
	total := price.Mul(int64(in.Quantity))

	err = workflow.ExecuteActivity(ctx, "SetOrderTotalActivity", in.OrderID, total).Get(ctx, nil)
	if err != nil {
		_ = workflow.ExecuteActivity(ctx, "MarkOrderStatusActivity", in.OrderID, statusFailed).Get(ctx, nil)
		return CheckoutResult{Status: statusFailed, Total: total}, fmt.Errorf("checkout: set order total: %w", err)
	}

	var chargeID string
	err = workflow.ExecuteActivity(ctx, "ChargeActivity", in.OrderID, total).Get(ctx, &chargeID)
	if err != nil {
		_ = workflow.ExecuteActivity(ctx, "MarkOrderStatusActivity", in.OrderID, statusFailed).Get(ctx, nil)
		return CheckoutResult{Status: statusFailed, Total: total}, fmt.Errorf("checkout: charge: %w", err)
	}

	err = workflow.ExecuteActivity(ctx, "MarkOrderStatusActivity", in.OrderID, "confirmed").Get(ctx, nil)
	if err != nil {
		return CheckoutResult{
			Status:   "confirmed",
			Total:    total,
			ChargeID: chargeID,
		}, fmt.Errorf("checkout: mark order confirmed: %w", err)
	}
	return CheckoutResult{Status: "confirmed", Total: total, ChargeID: chargeID}, nil
}
