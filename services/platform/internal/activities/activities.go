// Package activities holds the platform worker's activities (ADR-0302).
package activities

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"time"
)

type Activities struct {
	log *slog.Logger
	// forgeAPI is where tracking issues are opened. Empty until a forge exists,
	// which is the honest state: ADR-0207 says the drill "opens a tracking issue",
	// and there is nowhere to open one yet.
	forgeAPI string
	// The analytics service, east-west. Unlike the forge it exists, so an activity that needs it fails rather than
	// logging: a rollup that silently did not run is a panel showing stale numbers.
	analyticsAPI string
	// One client, reused: a client per call leaks a connection pool per call. The timeout stops an activity hanging
	// until Temporal's StartToClose fires.
	http *http.Client
}

func New(log *slog.Logger) *Activities {
	if log == nil {
		log = slog.Default()
	}
	return &Activities{
		log:          log,
		forgeAPI:     os.Getenv("FORGE_API_URL"),
		analyticsAPI: os.Getenv("ANALYTICS_API_URL"),
		http:         &http.Client{Timeout: 2 * time.Minute},
	}
}

// OpenTrackingIssueActivity: With no forge configured it logs the issue at warn and succeeds: failing would make
// every scheduled run red for a reason nobody can fix from here, and silence would make the schedule a decoration.
func (a *Activities) OpenTrackingIssueActivity(ctx context.Context, title, body string) error {
	if a.forgeAPI == "" {
		a.log.WarnContext(
			ctx,
			"no forge configured — tracking issue not filed",
			slog.String("title", title),
			slog.String("body", body),
		)
		return nil
	}
	return a.openIssue(ctx, title, body)
}

// AuditCardinalityActivity: A report rather than a threshold: `ActiveSeriesNearCeiling` already alerts on the total,
// and which labels are growing is a ranking (ADR-0500).
func (a *Activities) AuditCardinalityActivity(ctx context.Context) error {
	a.log.InfoContext(ctx, "cardinality audit: not yet reading Prometheus")
	return nil
}

// EraseServiceDataActivity: Per service rather than one query across every database (ADR-0301): each service owns its
// schema, and the delete-versus-anonymise decision is per data class.
func (a *Activities) EraseServiceDataActivity(ctx context.Context, service, identityID string) error {
	a.log.InfoContext(ctx, "erase service data", "service", service, "identity", identityID)
	return nil
}

func (a *Activities) EraseIdentityActivity(ctx context.Context, identityID string) error {
	a.log.InfoContext(ctx, "erase identity", "identity", identityID)
	return nil
}

// EraseAuthzTuplesActivity: Last in the workflow: while the tuples exist the services can still answer questions
// about the subject, which is what makes a failed run safe to retry.
func (a *Activities) EraseAuthzTuplesActivity(ctx context.Context, identityID string) error {
	a.log.InfoContext(ctx, "erase authz tuples", "identity", identityID)
	return nil
}

// ExportSubjectDataActivity assembles a subject-access export and returns where it
// was written.
func (a *Activities) ExportSubjectDataActivity(ctx context.Context, identityID string) (string, error) {
	a.log.InfoContext(ctx, "export subject data", "identity", identityID)
	return "", nil
}

func (a *Activities) ApplyRetentionActivity(ctx context.Context) error {
	a.log.InfoContext(ctx, "retention pass: not yet pruning")
	return nil
}

// ComputeFunnelRollupActivity calls the service, not the database: the events are analytics' store, and a worker
// holding a second connection to someone else's schema is the coupling the ownership rule prevents (ADR-0700).
// Unlike the stubs above this has a real body, because the endpoint is east-west and reachable from this pod.
func (a *Activities) ComputeFunnelRollupActivity(
	ctx context.Context, funnel string, from, to time.Time,
) error {
	if a.analyticsAPI == "" {
		return errors.New("ANALYTICS_API_URL is not set")
	}

	window := map[string]string{
		"from": from.UTC().Format(time.RFC3339),
		"to":   to.UTC().Format(time.RFC3339),
	}
	body, err := json.Marshal(window)
	if err != nil {
		return fmt.Errorf("marshal window: %w", err)
	}

	endpoint := fmt.Sprintf(
		"%s/api/analytics/funnels/%s/rollup",
		a.analyticsAPI,
		url.PathEscape(funnel),
	)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := a.http.Do(req)
	if err != nil {
		return fmt.Errorf("call analytics: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	// The response body is read on the error path and discarded otherwise. A
	// rollup's result is a count this activity has nothing to do with — the record
	// that it ran is the workflow's event history.
	if resp.StatusCode != http.StatusOK {
		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return fmt.Errorf("analytics rollup %s: %s: %s", funnel, resp.Status, bytes.TrimSpace(detail))
	}
	a.log.InfoContext(ctx, "funnel rollup computed", "funnel", funnel, "from", from, "to", to)
	return nil
}

// RestoreToScratchActivity: Stubbed, and the stub fails rather than succeeding quietly: a restore verification that
// reports success without restoring anything converts "we do not know" into "we believe" (ADR-0207).
func (a *Activities) RestoreToScratchActivity(ctx context.Context) (string, error) {
	a.log.ErrorContext(ctx, "restore verification is scheduled but not implemented")
	return "", errors.New(
		"RestoreToScratchActivity is not implemented: it must create a CNPG Cluster " +
			"with a recovery bootstrap from the backup object store (ADR-0207)",
	)
}

// AssertRestoredRowCountsActivity checks the restored database is not merely
// present but populated (ADR-0207).
func (a *Activities) AssertRestoredRowCountsActivity(ctx context.Context, namespace string) error {
	a.log.ErrorContext(ctx, "restore assertion is scheduled but not implemented", "namespace", namespace)
	return errors.New("AssertRestoredRowCountsActivity is not implemented")
}

// TeardownScratchRestoreActivity: A scratch namespace left behind holds a full copy of production data, so this
// activity's failure is worth logging loudly even when the run otherwise succeeded.
func (a *Activities) TeardownScratchRestoreActivity(ctx context.Context, namespace string) error {
	a.log.ErrorContext(ctx, "scratch teardown is scheduled but not implemented", "namespace", namespace)
	return errors.New("TeardownScratchRestoreActivity is not implemented")
}

// openIssue posts to the forge's issue API. Shared by every periodic obligation
// that produces a task for a person rather than a change to the platform.
func (a *Activities) openIssue(ctx context.Context, title, body string) error {
	a.log.InfoContext(
		ctx,
		"filing tracking issue",
		slog.String("title", title),
		slog.String("body", body),
		slog.String("forge", a.forgeAPI),
	)
	// Not implemented against a specific forge: ADR-0102 is mid-migration, and GitHub and Forgejo differ in exactly this
	// endpoint.
	return fmt.Errorf("forge issue API not implemented for %s", a.forgeAPI)
}
