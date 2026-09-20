// Package httpmw provides the default HTTP middleware: a tracing span, RED metrics, and a structured access log
// (ADR-0500).
package httpmw

import (
	"log/slog"
	"net/http"
	"os"
	"strconv"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

	"github.com/tabmadi/sovereign-platform-template/libs/go/buildinfo"
)

// Chain wraps h with tracing, RED metrics, and access logging. RED is owned by otelhttp's stable
// http.server.request.duration histogram, which the dashboards and the availability alert read.
// otelhttp must wrap access, not the reverse: it creates the server span the access log reads to stamp trace_id.
func Chain(h http.Handler, serviceName string) http.Handler {
	traced := otelhttp.NewHandler(access(h), "http", otelhttp.WithServerName(serviceName))
	return version(traced)
}

// version stamps the running binary's identity on every response (ADR-0103), so a
// client — the frontend, a curl, DevOps — can confirm which build answered without
// trusting the deploy pipeline. Set outermost so the headers land before any write.
func version(next http.Handler) http.Handler {
	return http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("X-App-Version", buildinfo.Version)
			w.Header().Set("X-App-Revision", buildinfo.SHA)
			next.ServeHTTP(w, r)
		},
	)
}

type statusWriter struct {
	http.ResponseWriter

	status int
}

func (s *statusWriter) WriteHeader(c int) { s.status = c; s.ResponseWriter.WriteHeader(c) }

func access(next http.Handler) http.Handler {
	return http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
			start := time.Now()
			next.ServeHTTP(sw, r)
			slog.LogAttrs(
				r.Context(),
				slog.LevelInfo,
				"http",
				slog.String("method", r.Method),
				slog.String("path", r.URL.Path),
				slog.Int("status", sw.status),
				slog.String("duration", strconv.FormatFloat(time.Since(start).Seconds(), 'f', 6, 64)),
			)
		},
	)
}

// ListenAddr is ":8080" in-cluster — the chart's containerPort, the edge IngressRoute and the NetworkPolicies
// all assume it. PORT overrides it for host-native runs, where each service binds its registered port
// (scripts/lib/ports.sh, ADR-0205) so more than one can run at a time.
func ListenAddr() string {
	p := os.Getenv("PORT")
	if p != "" {
		return ":" + p
	}
	return ":8080"
}
