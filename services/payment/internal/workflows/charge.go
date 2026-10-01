// Package workflows holds the Charge workflow: an idempotent activity sequence with compensation on failure. A mock
// processor settles it, per ADR-0302.
package workflows

import (
	"fmt"
	"time"

	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"

	"github.com/tabmadi/sovereign-platform-template/libs/go/money"
)

// statusFailed is the terminal status of a charge that the workflow could not complete.
const statusFailed = "failed"

type ChargeInput struct {
	ChargeID string
	OrderID  string
	Amount   money.Amount
}

type ChargeResult struct {
	Status string // `settled` or `failed`
}

// Charge is the workflow body. Activities are looked up by name string, so this
// file compiles without the activities package.
func Charge(ctx workflow.Context, in ChargeInput) (ChargeResult, error) {
	ao := workflow.ActivityOptions{
		StartToCloseTimeout: 15 * time.Second,
		RetryPolicy:         &temporal.RetryPolicy{InitialInterval: time.Second, MaximumAttempts: 3},
	}
	ctx = workflow.WithActivityOptions(ctx, ao)

	// The tuple that makes the charge readable comes first, before anything that can fail. `charge#read` resolves
	// through the order, so the buyer can see a charge that did not settle. The handler inserts the row, because
	// payment's deduplication key is a client header that a unique constraint enforces.
	err := workflow.ExecuteActivity(ctx, "GrantChargeAccessActivity", in.ChargeID, in.OrderID).Get(ctx, nil)
	if err != nil {
		return ChargeResult{Status: statusFailed}, fmt.Errorf("charge: grant charge access: %w", err)
	}

	err = workflow.ExecuteActivity(ctx, "SettleActivity", in).Get(ctx, nil)
	if err != nil {
		_ = workflow.ExecuteActivity(ctx, "MarkChargeStatusActivity", in.ChargeID, statusFailed).Get(ctx, nil)
		return ChargeResult{Status: statusFailed}, fmt.Errorf("charge: settle: %w", err)
	}
	err = workflow.ExecuteActivity(ctx, "MarkChargeStatusActivity", in.ChargeID, "settled").Get(ctx, nil)
	if err != nil {
		return ChargeResult{Status: "settled"}, fmt.Errorf("charge: mark settled: %w", err)
	}
	return ChargeResult{Status: "settled"}, nil
}
