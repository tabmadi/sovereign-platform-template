// Package workflows holds the platform's periodic obligations (ADR-0302).
package workflows

import (
	"fmt"
	"time"

	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"
)

// How far back each funnel pass recomputes. Events arrive late, so a bucket is not final when its day ends; three
// days is longer than any plausible delivery delay.
const rollupTrailingDays = 3

// Periodic work is not latency sensitive and its dependencies are occasionally slow, so the timeout is generous and
// the retry count high.
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

// DisasterRecoveryDrill: It opens an issue rather than performing a restore (ADR-0207): the drill is a rehearsal
// people carry out, and a workflow claiming to have tested a restore would be worse than none.
func DisasterRecoveryDrill(ctx workflow.Context) error {
	ctx = activityOptions(ctx)
	title := "Quarterly restore rehearsal (ADR-0200, ADR-0207)"
	body := "The backup restore is rehearsed quarterly, and the rehearsal is what " +
		"makes the recovery objectives measurements rather than intentions. " +
		"Restore the most recent base backup into a scratch namespace, confirm it " +
		"is byte-exact, and record the elapsed time against the stated RTO."
	err := workflow.ExecuteActivity(ctx, "OpenTrackingIssueActivity", title, body).Get(ctx, nil)
	if err != nil {
		return fmt.Errorf("dr drill: open issue: %w", err)
	}
	return nil
}

// TriggerReview: Covers the deferral register's `query` rows and the ASVS cadence (ADR-0000). Both decay silently —
// nothing breaks when a review is skipped — which is why the reminder is mechanical.
func TriggerReview(ctx workflow.Context) error {
	ctx = activityOptions(ctx)
	title := "Quarterly deferral and verification review (ADR-0000, ADR-0203)"
	body := "Walk the `query` rows in docs/reference/deferral-register.md and the " +
		"cadence rows in docs/reference/asvs-verification.md. A query row walked " +
		"without its answer being recorded has not been walked."
	err := workflow.ExecuteActivity(ctx, "OpenTrackingIssueActivity", title, body).Get(ctx, nil)
	if err != nil {
		return fmt.Errorf("trigger review: open issue: %w", err)
	}
	return nil
}

// CardinalityAudit: A query rather than a rule: the interesting answer is which labels are growing, and an alert can
// only say a total crossed a line. `ActiveSeriesNearCeiling` covers the line (ADR-0500).
func CardinalityAudit(ctx workflow.Context) error {
	ctx = activityOptions(ctx)
	err := workflow.ExecuteActivity(ctx, "AuditCardinalityActivity").Get(ctx, nil)
	if err != nil {
		return fmt.Errorf("cardinality audit: %w", err)
	}
	return nil
}

// FunnelRollup: A trailing window rather than "since the last run" (ADR-0700): events arrive late, and recomputing
// the recent past costs nothing because a bucket is replaced rather than added to. One activity per funnel, so a
// funnel naming an event nothing emits does not stop the others.
func FunnelRollup(ctx workflow.Context, funnels []string) error {
	ctx = activityOptions(ctx)

	// `workflow.Now`, never `time.Now`: a workflow must be deterministic, and a
	// replay that read the wall clock would compute a different window than the
	// original run and write different buckets.
	end := workflow.Now(ctx).UTC().Truncate(24 * time.Hour).Add(24 * time.Hour)
	start := end.AddDate(0, 0, -rollupTrailingDays)

	var failed []string
	for _, funnel := range funnels {
		err := workflow.ExecuteActivity(ctx, "ComputeFunnelRollupActivity", funnel, start, end).Get(ctx, nil)
		if err != nil {
			// Recorded and carried on. Returning here would leave the funnels after
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

// RestoreVerification runs weekly, because quarterly is the detection latency for an unrestorable backup: one
// that stopped being valid in January is found in April (ADR-0207). It asserts row counts, not "the restore
// succeeded" — a restore producing an empty database succeeds. It does not page.
func RestoreVerification(ctx workflow.Context) error {
	ctx = activityOptions(ctx)

	var restored string
	err := workflow.ExecuteActivity(ctx, "RestoreToScratchActivity").Get(ctx, &restored)
	if err != nil {
		return fmt.Errorf("restore verification: restore: %w", err)
	}

	// Teardown runs whether or not the assertion passes, and its failure does not
	// mask the assertion's. A scratch namespace left behind holds a full copy of
	// production data, which is a worse outcome than a failed check.
	assertErr := workflow.ExecuteActivity(ctx, "AssertRestoredRowCountsActivity", restored).Get(ctx, nil)

	teardownErr := workflow.ExecuteActivity(ctx, "TeardownScratchRestoreActivity", restored).Get(ctx, nil)
	if teardownErr != nil {
		workflow.GetLogger(ctx).Error(
			"scratch restore not torn down — it holds a copy of production data",
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
