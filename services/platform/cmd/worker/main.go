// The platform worker (ADR-0302, ADR-0301).
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/tabmadi/sovereign-platform-template/libs/go/observability"
	"github.com/tabmadi/sovereign-platform-template/libs/go/temporalmw"
	"github.com/tabmadi/sovereign-platform-template/services/platform/internal/activities"
	"github.com/tabmadi/sovereign-platform-template/services/platform/internal/workflows"
)

const serviceName = "platform"

func main() {
	err := run()
	if err != nil {
		slog.Error("fatal", "err", err)
		os.Exit(1)
	}
}

// No database and no OpenFGA client. This worker owns no schema — every store it
// touches belongs to someone else, and it reaches them through activities.
func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	shutdown, err := observability.Init(ctx, observability.Config{ServiceName: serviceName + "-worker"})
	if err != nil {
		return fmt.Errorf("obs init: %w", err)
	}
	defer func() { _ = shutdown(context.Background()) }()

	tc, err := temporalmw.NewClient(serviceName + "-worker")
	if err != nil {
		return fmt.Errorf("temporal: %w", err)
	}
	defer tc.Close()

	w := temporalmw.NewWorker(tc, serviceName+"-queue")
	w.RegisterWorkflow(workflows.DisasterRecoveryDrill)
	w.RegisterWorkflow(workflows.TriggerReview)
	w.RegisterWorkflow(workflows.CardinalityAudit)
	w.RegisterWorkflow(workflows.EraseSubject)
	w.RegisterWorkflow(workflows.ExportSubject)
	w.RegisterWorkflow(workflows.RetentionPass)
	w.RegisterWorkflow(workflows.FunnelRollup)
	w.RegisterWorkflow(workflows.RestoreVerification)

	acts := activities.New(slog.Default())
	w.RegisterActivity(acts.OpenTrackingIssueActivity)
	w.RegisterActivity(acts.AuditCardinalityActivity)
	w.RegisterActivity(acts.EraseServiceDataActivity)
	w.RegisterActivity(acts.EraseIdentityActivity)
	w.RegisterActivity(acts.EraseAuthzTuplesActivity)
	w.RegisterActivity(acts.ExportSubjectDataActivity)
	w.RegisterActivity(acts.ApplyRetentionActivity)
	w.RegisterActivity(acts.ComputeFunnelRollupActivity)
	w.RegisterActivity(acts.RestoreToScratchActivity)
	w.RegisterActivity(acts.AssertRestoredRowCountsActivity)
	w.RegisterActivity(acts.TeardownScratchRestoreActivity)

	interrupt := make(chan any, 1)
	go func() { <-ctx.Done(); interrupt <- nil }()
	err = w.Run(interrupt)
	if err != nil {
		return fmt.Errorf("worker: %w", err)
	}
	return nil
}
