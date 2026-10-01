// Package workflows holds the platform's periodic obligations, per ADR-0302.
package workflows

import (
	"fmt"
	"time"

	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"
)

// How far back each funnel pass recomputes. Events arrive late, so a bucket is not final when its day ends. Three
// days is longer than any likely delivery delay.
const rollupTrailingDays = 3

// Periodic work is not latency sensitive, and its dependencies are sometimes slow. So the timeout is long and the
// retry count is high.
func activityOptions(ctx workflow.Context) workflow.Context {
	return workflow.WithActivityOptions(
		ctx,
		workflow.ActivityOptions{
			StartToCloseTimeout: 10 * time.Minute,
			RetryPolicy: &temporal.RetryPolicy{
				InitialInterval: 30 * time.Second,
				MaximumAttempts: 10,
			},
		},
	)
}

// DisasterRecoveryDrill opens an issue and does not do a restore, per ADR-0207. People do the drill as a rehearsal.
// A workflow that claims to have tested a restore would be worse than no workflow.
func DisasterRecoveryDrill(ctx workflow.Context) error {
	ctx = activityOptions(ctx)
	title := "Quarterly restore rehearsal, per ADR-0200 and ADR-0207"
	body := "The backup restore is rehearsed quarterly. The rehearsal makes the " +
		"recovery objectives measurements and not intentions. " +
		"Restore the most recent base backup into a scratch namespace, confirm that it " +
		"is byte-exact, and record the time it took against the stated RTO."
	err := workflow.ExecuteActivity(ctx, "OpenTrackingIssueActivity", title, body).Get(ctx, nil)
	if err != nil {
		return fmt.Errorf("dr drill: open issue: %w", err)
	}
	return nil
}

// TriggerReview covers the deferral register's `query` rows and the ASVS cadence, per ADR-0000. Both go stale with no
// signal, because nothing breaks when a review is skipped. So the reminder is mechanical.
func TriggerReview(ctx workflow.Context) error {
	ctx = activityOptions(ctx)
	title := "Quarterly deferral and verification review, per ADR-0000 and ADR-0203"
	body := "Review the `query` rows in docs/reference/deferral-register.md and the " +
		"cadence rows in docs/reference/asvs-verification.md. A query row counts as " +
		"reviewed only when its answer is recorded."
	err := workflow.ExecuteActivity(ctx, "OpenTrackingIssueActivity", title, body).Get(ctx, nil)
	if err != nil {
		return fmt.Errorf("trigger review: open issue: %w", err)
	}
	return nil
}

// CardinalityAudit is a query, not a rule. The useful answer is which labels grow, and an alert can only say that a
// total crossed a line. `ActiveSeriesNearCeiling` covers the line, per ADR-0500.
func CardinalityAudit(ctx workflow.Context) error {
	ctx = activityOptions(ctx)
	err := workflow.ExecuteActivity(ctx, "AuditCardinalityActivity").Get(ctx, nil)
	if err != nil {
		return fmt.Errorf("cardinality audit: %w", err)
	}
	return nil
}

// FunnelRollup uses a trailing window, not the time since the last run, per ADR-0700. Events arrive late, and a
// recompute of the recent past is cheap, because a bucket is replaced and not added to. One activity per funnel, so
// a funnel that names an event nothing emits does not stop the others.
func FunnelRollup(ctx workflow.Context, funnels []string) error {
	ctx = activityOptions(ctx)

	// `workflow.Now`, never `time.Now`. A workflow must be deterministic. A replay
	// that read the wall clock would compute a different window than the original
	// run and write different buckets.
	end := workflow.Now(ctx).UTC().Truncate(24 * time.Hour).Add(24 * time.Hour)
	start := end.AddDate(0, 0, -rollupTrailingDays)

	var failed []string
	for _, funnel := range funnels {
		err := workflow.ExecuteActivity(ctx, "ComputeFunnelRollupActivity", funnel, start, end).Get(ctx, nil)
		if err != nil {
			// Record the error and continue. A return here would leave the funnels after
			// this one uncomputed because of a problem with this one.
			workflow.GetLogger(ctx).Error("funnel rollup failed", "funnel", funnel, "err", err)
			failed = append(failed, funnel)
		}
	}
	if len(failed) > 0 {
		return fmt.Errorf("funnel rollup: %d of %d funnels failed: %v", len(failed), len(funnels), failed)
	}
	return nil
}

// RestoreVerification runs weekly. A quarterly run would find a bad backup from January only in April, per ADR-0207.
// It asserts row counts and not only restore success, because a restore that gives an empty database succeeds.
// It does not page.
func RestoreVerification(ctx workflow.Context) error {
	ctx = activityOptions(ctx)

	var restored string
	err := workflow.ExecuteActivity(ctx, "RestoreToScratchActivity").Get(ctx, &restored)
	if err != nil {
		return fmt.Errorf("restore verification: restore: %w", err)
	}

	// Teardown runs whether or not the assertion passes, and its failure does not
	// hide the assertion's. A scratch namespace that stays behind holds a full copy
	// of production data, which is worse than a failed check.
	assertErr := workflow.ExecuteActivity(ctx, "AssertRestoredRowCountsActivity", restored).Get(ctx, nil)

	teardownErr := workflow.ExecuteActivity(ctx, "TeardownScratchRestoreActivity", restored).Get(ctx, nil)
	if teardownErr != nil {
		workflow.GetLogger(ctx).Error(
			"scratch restore not torn down and holds a copy of production data",
			"namespace",
			restored,
			"err",
			teardownErr,
		)
	}

	if assertErr != nil {
		return fmt.Errorf("restore verification: assert: %w", assertErr)
	}
	if teardownErr != nil {
		return fmt.Errorf("restore verification: teardown: %w", teardownErr)
	}
	return nil
}
