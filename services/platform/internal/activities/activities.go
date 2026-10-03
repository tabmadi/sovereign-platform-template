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
	"maps"
	"net/http"
	"net/url"
	"os"
	"time"
)

// Config is where each dependency is. An empty value means that the dependency does not exist in this environment, and
// the activity that needs it fails and says so.
type Config struct {
	// ForgeAPI is the forge's repository API, such as `https://api.github.com/repos/<owner>/<repo>`. It is empty when
	// no forge exists. ADR-0207 says that the drill opens a tracking issue, and with no forge there is no place for it.
	ForgeAPI   string
	ForgeToken string
	// Each service that holds personal data, east-west, per ADR-0303 and ADR-0301.
	AnalyticsAPI string
	OrdersAPI    string
	OrgsAPI      string
	// The Kratos admin API and OpenFGA, for the identity and the tuples of an erasure.
	KratosAdmin  string
	OpenFGAAPI   string
	OpenFGAKey   string
	OpenFGAStore string
	// Prometheus, for the cardinality audit.
	PrometheusAPI string
	Restore       RestoreConfig
}

func ConfigFromEnv() Config {
	return Config{
		ForgeAPI:     os.Getenv("FORGE_API_URL"),
		ForgeToken:   os.Getenv("FORGE_TOKEN"),
		AnalyticsAPI: os.Getenv("ANALYTICS_API_URL"),
		OrdersAPI:    os.Getenv("ORDERS_API_URL"),
		OrgsAPI:      os.Getenv("ORGS_API_URL"),
		KratosAdmin:  os.Getenv("KRATOS_ADMIN_URL"),
		OpenFGAAPI:   os.Getenv("OPENFGA_API_URL"),
		// The SOPS secret's own key name is the fallback, the same as libs/go/authz, per ADR-0202.
		OpenFGAKey:    envOr("OPENFGA_PRESHARED_KEY", os.Getenv("preshared_key")),
		OpenFGAStore:  envOr("OPENFGA_STORE_NAME", "platform"),
		PrometheusAPI: os.Getenv("PROMETHEUS_URL"),
		Restore:       restoreConfigFromEnv(),
	}
}

type Activities struct {
	log *slog.Logger
	cfg Config
	// One reused client, because a client per call leaks a connection pool per call. The timeout stops an activity from
	// hanging until Temporal's StartToClose fires.
	http *http.Client
	// kube is the Kubernetes API, for restore verification. It is nil outside a cluster.
	kube *kubeClient
}

func New(log *slog.Logger, cfg Config) *Activities {
	if log == nil {
		log = slog.Default()
	}
	kube, err := inClusterKube()
	if err != nil {
		log.Info("no Kubernetes API: restore verification is not available here", "err", err)
	}
	return &Activities{
		log:  log,
		cfg:  cfg,
		http: &http.Client{Timeout: 2 * time.Minute},
		kube: kube,
	}
}

// OpenTrackingIssueActivity logs the issue at warn and succeeds when no forge is configured. A failure would make
// every scheduled run red for a reason that nobody can fix here. Silence would make the schedule useless.
func (a *Activities) OpenTrackingIssueActivity(ctx context.Context, title, body string) error {
	if a.cfg.ForgeAPI == "" {
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

// ComputeFunnelRollupActivity calls the service, not the database. The events are the analytics store. A worker with a
// second connection to another service's schema is the coupling that the ownership rule prevents, per ADR-0700.
func (a *Activities) ComputeFunnelRollupActivity(
	ctx context.Context, funnel string, from, to time.Time,
) error {
	if a.cfg.AnalyticsAPI == "" {
		return errors.New("ANALYTICS_API_URL is not set")
	}
	window := map[string]string{
		"from": from.UTC().Format(time.RFC3339),
		"to":   to.UTC().Format(time.RFC3339),
	}
	endpoint := fmt.Sprintf("%s/analytics/funnels/%s/rollup", a.cfg.AnalyticsAPI, url.PathEscape(funnel))
	// A rollup's result is a count that this activity does not use. The workflow's event history records that it ran.
	err := a.do(ctx, http.MethodPost, endpoint, nil, window, nil, http.StatusOK)
	if err != nil {
		return fmt.Errorf("analytics rollup %s: %w", funnel, err)
	}
	a.log.InfoContext(ctx, "funnel rollup computed", "funnel", funnel, "from", from, "to", to)
	return nil
}

// openIssue posts to the forge's issue API. GitHub and Forgejo share this endpoint and its two fields, per ADR-0102.
func (a *Activities) openIssue(ctx context.Context, title, body string) error {
	var created struct {
		Number  int    `json:"number"`
		HTMLURL string `json:"html_url"`
	}
	header := http.Header{}
	if a.cfg.ForgeToken != "" {
		header.Set("Authorization", "token "+a.cfg.ForgeToken)
	}
	err := a.do(
		ctx,
		http.MethodPost,
		a.cfg.ForgeAPI+"/issues",
		header,
		map[string]string{"title": title, "body": body},
		&created,
		http.StatusCreated,
	)
	if err != nil {
		return fmt.Errorf("open tracking issue: %w", err)
	}
	a.log.InfoContext(ctx, "tracking issue filed", "title", title, "number", created.Number, "url", created.HTMLURL)
	return nil
}

// statusError is a response with a status that the caller did not expect. Callers that accept a 404 check for it.
type statusError struct {
	status int
	detail string
}

func (e *statusError) Error() string {
	return fmt.Sprintf("HTTP %d: %s", e.status, e.detail)
}

func isStatus(err error, status int) bool {
	var se *statusError
	return errors.As(err, &se) && se.status == status
}

// do sends one JSON request and decodes the JSON response into out, when out is not nil. Any status outside want is
// an error, and its body, cut short, is the error's detail.
func (a *Activities) do(
	ctx context.Context, method, endpoint string, header http.Header, in, out any, want ...int,
) error {
	var body io.Reader
	if in != nil {
		raw, err := json.Marshal(in)
		if err != nil {
			return fmt.Errorf("marshal: %w", err)
		}
		body = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, endpoint, body)
	if err != nil {
		return fmt.Errorf("build request: %w", err)
	}
	maps.Copy(req.Header, header)
	if in != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	req.Header.Set("Accept", "application/json")

	resp, err := a.http.Do(req)
	if err != nil {
		return fmt.Errorf("%s %s: %w", method, endpoint, err)
	}
	defer func() { _ = resp.Body.Close() }()

	ok := false
	for _, w := range want {
		ok = ok || resp.StatusCode == w
	}
	if !ok {
		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return &statusError{status: resp.StatusCode, detail: string(bytes.TrimSpace(detail))}
	}
	if out == nil {
		return nil
	}
	err = json.NewDecoder(resp.Body).Decode(out)
	if err != nil {
		return fmt.Errorf("decode %s %s: %w", method, endpoint, err)
	}
	return nil
}

func envOr(key, fallback string) string {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	return v
}
