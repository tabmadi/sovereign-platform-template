// The platform worker, per ADR-0302 and ADR-0301.
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

// No database and no OpenFGA client. This worker owns no schema. Every store it
// uses belongs to another service, and it reaches them through activities.
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

	schedules, err := temporalmw.ParseSchedules(workflows.ScheduleFile)
	if err != nil {
		return fmt.Errorf("schedules: %w", err)
	}
	err = temporalmw.ReconcileSchedules(ctx, tc.ScheduleClient(), serviceName, schedules)
	if err != nil {
		return fmt.Errorf("schedules: %w", err)
	}

	w := temporalmw.NewWorker(tc, serviceName+"-queue")
	for _, wf := range workflows.All() {
		w.RegisterWorkflow(wf)
	}

	acts := activities.New(slog.Default(), activities.ConfigFromEnv())
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
