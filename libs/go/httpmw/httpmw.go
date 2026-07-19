// Package httpmw provides default HTTP middleware (ADR-0011): a tracing span,
// RED metrics, and a structured access log. Services compose them via Chain.
package httpmw

import (
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"

	"github.com/tabmadi/microservices-monorepo-template/libs/go/buildinfo"
)

// Chain wraps h with tracing, RED metrics, and access logging. The metric
// instruments are created here (not in init) so they bind to the MeterProvider
// that obs.Init installs before any service calls Chain.
func Chain(h http.Handler, serviceName string) http.Handler {
	meter := otel.Meter("http.server")
	requestCount, err := meter.Int64Counter("http.server.requests")
	if err != nil {
		panic(err)
	}
	requestDur, err := meter.Float64Histogram("http.server.duration_seconds")
	if err != nil {
		panic(err)
	}
	// otelhttp must wrap red+access, not the other way round: it creates the server
	// span and injects it into the request context it passes inward. The access log
	// reads that context, so keeping it INSIDE the span is what stamps trace_id/
	// span_id onto every access log line (→ Loki structured metadata), giving
	// logs↔traces correlation. With access outside otelhttp the log had no span and
	// every line landed in Loki untraceable.
	traced := otelhttp.NewHandler(red(requestCount, requestDur, access(h)), "http", otelhttp.WithServerName(serviceName))
	return version(traced)
}

// version stamps the running binary's identity on every response (ADR-0013), so a
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

func red(requestCount metric.Int64Counter, requestDur metric.Float64Histogram, next http.Handler) http.Handler {
	return http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
			start := time.Now()
			next.ServeHTTP(sw, r)
			dur := time.Since(start).Seconds()
			attrs := metric.WithAttributes(
				attribute.String("http.method", r.Method),
				attribute.String("http.route", r.URL.Path),
				attribute.Int("http.status_code", sw.status),
			)
			requestCount.Add(r.Context(), 1, attrs)
			requestDur.Record(r.Context(), dur, attrs)
		},
	)
}

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
