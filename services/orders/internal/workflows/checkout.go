// Package workflows holds the checkout saga (ADR-0302). orders owns it by the process-owner rule, though the data
// lives in catalog and payment.
package workflows

import (
	"fmt"
	"time"

	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"

	"github.com/tabmadi/sovereign-platform-template/libs/go/money"
)

// statusFailed is the terminal status of an order the saga could not complete.
const statusFailed = "failed"

type CheckoutInput struct {
	OrderID   string
	ProductID string
	Quantity  int32
	// OwnerID is the buyer's Kratos identity; OrgID is the org they act through
	// (ADR-0304). Both are what the order's OpenFGA tuples are written from.
	OwnerID string
	OrgID   string
	// IdempotencyKey is the client's, carried into the row so a retried checkout
	// finds the order the first one created (ADR-0003).
	IdempotencyKey string
}

type CheckoutResult struct {
	Status   string // "confirmed" | "failed"
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
	// Before any step that can fail the order: a row whose status a later activity
	// marks `failed` still has to be readable by the buyer it belongs to.
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
	// Money multiplication, not a bare integer product: the shared type carries the currency and scale (ADR-0300).
	// Deterministic — integer arithmetic with no clock and no rounding mode.
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
