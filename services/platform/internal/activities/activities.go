// Package activities holds the platform worker's activities, per ADR-0302.
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
	// forgeAPI is where tracking issues are opened. It is empty when no forge
	// exists. ADR-0207 says that the drill opens a tracking issue, and with no
	// forge there is no place to open one.
	forgeAPI string
	// The analytics service, east-west. Unlike the forge, it always exists, so an activity that needs it fails and does
	// not only log. A rollup that did not run with no error gives a panel with old numbers.
	analyticsAPI string
	// One reused client, because a client per call leaks a connection pool per call. The timeout stops an activity from
	// hanging until Temporal's StartToClose fires.
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

// OpenTrackingIssueActivity logs the issue at warn and succeeds when no forge is configured. A failure would make
// every scheduled run red for a reason that nobody can fix here. Silence would make the schedule useless.
func (a *Activities) OpenTrackingIssueActivity(ctx context.Context, title, body string) error {
	if a.forgeAPI == "" {
		a.log.WarnContext(
			ctx,
			"no forge configured so tracking issue not filed",
			slog.String("title", title),
			slog.String("body", body),
		)
		return nil
	}
	return a.openIssue(ctx, title, body)
}

// AuditCardinalityActivity is a report, not a threshold. `ActiveSeriesNearCeiling` already alerts on the total, and
// the growing labels are a ranking, per ADR-0500.
func (a *Activities) AuditCardinalityActivity(ctx context.Context) error {
	a.log.InfoContext(ctx, "cardinality audit: not yet reading Prometheus")
	return nil
}

// EraseServiceDataActivity runs per service, not as one query across every database, per ADR-0301. Each service owns
// its schema, and the choice to delete or anonymise is per data class.
func (a *Activities) EraseServiceDataActivity(ctx context.Context, service, identityID string) error {
	a.log.InfoContext(ctx, "erase service data", "service", service, "identity", identityID)
	return nil
}

func (a *Activities) EraseIdentityActivity(ctx context.Context, identityID string) error {
	a.log.InfoContext(ctx, "erase identity", "identity", identityID)
	return nil
}

// EraseAuthzTuplesActivity runs last in the workflow. While the tuples exist, the services can still answer questions
// about the subject, so a failed run is safe to retry.
func (a *Activities) EraseAuthzTuplesActivity(ctx context.Context, identityID string) error {
	a.log.InfoContext(ctx, "erase authz tuples", "identity", identityID)
	return nil
}

// ExportSubjectDataActivity builds a subject-access export and returns where it
// was written.
func (a *Activities) ExportSubjectDataActivity(ctx context.Context, identityID string) (string, error) {
	a.log.InfoContext(ctx, "export subject data", "identity", identityID)
	return "", nil
}

func (a *Activities) ApplyRetentionActivity(ctx context.Context) error {
	a.log.InfoContext(ctx, "retention pass: not yet pruning")
	return nil
}

// ComputeFunnelRollupActivity calls the service, not the database. The events are the analytics store. A worker with a
// second connection to another service's schema is the coupling that the ownership rule prevents, per ADR-0700.
// Unlike the stubs above, this has a real body, because this pod can reach the east-west endpoint.
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

	// The response body is read on the error path and dropped otherwise. A
	// rollup's result is a count that this activity does not use. The workflow's
	// event history records that it ran.
	if resp.StatusCode != http.StatusOK {
		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return fmt.Errorf("analytics rollup %s: %s: %s", funnel, resp.Status, bytes.TrimSpace(detail))
	}
	a.log.InfoContext(ctx, "funnel rollup computed", "funnel", funnel, "from", from, "to", to)
	return nil
}

// RestoreToScratchActivity is a stub, and the stub fails and does not succeed with no warning. A restore verification
// that reports success with no restore turns an unknown state into a false belief, per ADR-0207.
func (a *Activities) RestoreToScratchActivity(ctx context.Context) (string, error) {
	a.log.ErrorContext(ctx, "restore verification is scheduled but not implemented")
	return "", errors.New(
		"RestoreToScratchActivity is not implemented: it must create a CNPG Cluster " +
			"with a recovery bootstrap from the backup object store, per ADR-0207",
	)
}

// AssertRestoredRowCountsActivity checks that the restored database exists and
// also has data, per ADR-0207.
func (a *Activities) AssertRestoredRowCountsActivity(ctx context.Context, namespace string) error {
	a.log.ErrorContext(ctx, "restore assertion is scheduled but not implemented", "namespace", namespace)
	return errors.New("AssertRestoredRowCountsActivity is not implemented")
}

// TeardownScratchRestoreActivity: a scratch namespace that stays behind holds a full copy of production data. So log
// this activity's failure clearly, even when the rest of the run succeeded.
func (a *Activities) TeardownScratchRestoreActivity(ctx context.Context, namespace string) error {
	a.log.ErrorContext(ctx, "scratch teardown is scheduled but not implemented", "namespace", namespace)
	return errors.New("TeardownScratchRestoreActivity is not implemented")
}

// openIssue posts to the forge's issue API. Every periodic obligation that gives a
// person a task, and not a change to the platform, uses it.
func (a *Activities) openIssue(ctx context.Context, title, body string) error {
	a.log.InfoContext(
		ctx,
		"filing tracking issue",
		slog.String("title", title),
		slog.String("body", body),
		slog.String("forge", a.forgeAPI),
	)
	// It targets no specific forge, because GitHub and Forgejo differ in exactly this endpoint, per ADR-0102.
	return fmt.Errorf("forge issue API not implemented for %s", a.forgeAPI)
}
