// Package observability is the single entry point for logs, metrics, traces, and continuous profiles, per ADR-0500.
package observability

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/pprof"
	"os"
	"strconv"
	"time"

	"go.opentelemetry.io/contrib/bridges/otelslog"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
	sdklog "go.opentelemetry.io/otel/sdk/log"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"

	"github.com/tabmadi/sovereign-platform-template/libs/go/buildinfo"
)

// Config reads an omitted field from environment variables. Service code gives only the service name, and every
// other field has a default.
type Config struct {
	ServiceName  string
	OTLPEndpoint string // default: $OTEL_EXPORTER_OTLP_ENDPOINT
	AdminAddr    string // default: :9090
}

// Init wires up tracing, metrics, logs, pprof, and slog. main must call the returned shutdown function to flush all
// signals.
//
//nolint:funlen // ADR-0500: the single documented wiring point; kept linear on purpose.
func Init(ctx context.Context, cfg Config) (func(context.Context) error, error) {
	if cfg.ServiceName == "" {
		return nil, errors.New("observability.Init: ServiceName is required")
	}
	if cfg.AdminAddr == "" {
		cfg.AdminAddr = ":9090"
	}

	// otelhttp reads the global propagator, which defaults to a no-op. Then every service starts a new root span per
	// hop. It is always set, so context passes through HTTP even with exporters disabled.
	otel.SetTextMapPropagator(
		propagation.NewCompositeTextMapPropagator(propagation.TraceContext{}, propagation.Baggage{}),
	)

	// OTEL_SDK_DISABLED=true, from the OTel spec, makes Init a no-op for exporters.
	// It opens no OTLP connections, so a service can run locally without the
	// Collector stack. Logs still go to stdout, and pprof is still served.
	disabled, _ := strconv.ParseBool(os.Getenv("OTEL_SDK_DISABLED"))
	if disabled {
		slog.SetDefault(slog.New(slog.NewTextHandler(os.Stdout, nil)))
		go serveAdmin(cfg.AdminAddr)
		return func(context.Context) error { return nil }, nil
	}

	// In local dev, the OTel Collector uses plaintext with no TLS. So the OTLP
	// exporters must turn off their default HTTPS and TLS behaviour.
	var local bool
	switch os.Getenv("DEPLOY_ENV") {
	case "", "dev", "local":
		local = true
	}

	// service.version and service.build.sha come from the build identity in the binary, per ADR-0103. So every
	// signal reports which binary emitted it.
	res, err := resource.New(
		ctx,
		resource.WithAttributes(
			semconv.ServiceName(cfg.ServiceName),
			semconv.ServiceVersion(buildinfo.Version),
			attribute.String("service.build.sha", buildinfo.SHA),
		),
		resource.WithFromEnv(),
		resource.WithProcessRuntimeName(),
	)
	if err != nil {
		return nil, fmt.Errorf("resource: %w", err)
	}

	// All three signals share one OTLP gRPC endpoint. Logs use otlploggrpc, not otlploghttp. otlploghttp POSTs to the
	// gRPC port, and every export fails with `malformed HTTP response`.
	var traceOpts []otlptracegrpc.Option
	var metricOpts []otlpmetricgrpc.Option
	var logOpts []otlploggrpc.Option
	if local {
		traceOpts = append(traceOpts, otlptracegrpc.WithInsecure())
		metricOpts = append(metricOpts, otlpmetricgrpc.WithInsecure())
		logOpts = append(logOpts, otlploggrpc.WithInsecure())
	}

	traceExp, err := otlptracegrpc.New(ctx, traceOpts...)
	if err != nil {
		return nil, fmt.Errorf("trace exporter: %w", err)
	}
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExp),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)

	metricExp, err := otlpmetricgrpc.New(ctx, metricOpts...)
	if err != nil {
		return nil, fmt.Errorf("metric exporter: %w", err)
	}
	mp := sdkmetric.NewMeterProvider(
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExp)),
		sdkmetric.WithResource(res),
	)
	otel.SetMeterProvider(mp)

	logExp, err := otlploggrpc.New(ctx, logOpts...)
	if err != nil {
		return nil, fmt.Errorf("log exporter: %w", err)
	}
	lp := sdklog.NewLoggerProvider(
		sdklog.WithProcessor(sdklog.NewBatchProcessor(logExp)),
		sdklog.WithResource(res),
	)
	handlers := fanout{otelslog.NewHandler(cfg.ServiceName, otelslog.WithLoggerProvider(lp))}
	if local {
		handlers = append(fanout{slog.NewTextHandler(os.Stdout, nil)}, handlers...)
	}
	slog.SetDefault(slog.New(handlers))

	go serveAdmin(cfg.AdminAddr)

	shutdown := func(ctx context.Context) error {
		_ = tp.Shutdown(ctx)
		_ = mp.Shutdown(ctx)
		_ = lp.Shutdown(ctx)
		return nil
	}
	return shutdown, nil
}

// fanout is a slog.Handler that sends every record to all wrapped handlers. So
// logs reach stdout, which local runs show, and the OTLP pipeline.
type fanout []slog.Handler

func (f fanout) Enabled(ctx context.Context, level slog.Level) bool {
	for _, h := range f {
		if h.Enabled(ctx, level) {
			return true
		}
	}
	return false
}

func (f fanout) Handle(ctx context.Context, r slog.Record) error {
	var err error
	for _, h := range f {
		if h.Enabled(ctx, r.Level) {
			e := h.Handle(ctx, r.Clone())
			if e != nil {
				err = e
			}
		}
	}
	return err
}

func (f fanout) WithAttrs(attrs []slog.Attr) slog.Handler {
	next := make(fanout, len(f))
	for i, h := range f {
		next[i] = h.WithAttrs(attrs)
	}
	return next
}

func (f fanout) WithGroup(name string) slog.Handler {
	next := make(fanout, len(f))
	for i, h := range f {
		next[i] = h.WithGroup(name)
	}
	return next
}

// StartSpan wraps otel.Tracer().Start so service code never imports otel directly.
//
//nolint:spancheck // thin passthrough; the caller owns the returned span and its End().
func StartSpan(ctx context.Context, name string) (context.Context, trace.Span) {
	return otel.Tracer("service").Start(ctx, name)
}

func Counter(name string, opts ...metric.Int64CounterOption) metric.Int64Counter {
	c, err := otel.Meter("service").Int64Counter(name, opts...)
	if err != nil {
		// A failed counter creation is a programmer error. Panic, so it shows during dev.
		panic("observability.Counter(" + name + "): " + err.Error())
	}
	return c
}

// ObservableGauge registers a gauge that is read on each export, not pushed. This fits a quantity that already
// exists and costs a lot to compute. The callback runs on the exporter's goroutine with the export context. It
// must not block, because a slow callback delays every metric in the batch.
func ObservableGauge(
	name string,
	observe func(context.Context) (int64, error),
	opts ...metric.Int64ObservableGaugeOption,
) {
	meter := otel.Meter("service")
	g, err := meter.Int64ObservableGauge(name, opts...)
	if err != nil {
		panic("observability.ObservableGauge(" + name + "): " + err.Error())
	}
	_, err = meter.RegisterCallback(
		func(ctx context.Context, o metric.Observer) error {
			v, err := observe(ctx)
			if err != nil {
				// Reported, not returned. An error returned from a callback
				// stops the whole export batch, so one unreadable gauge would
				// lose every other metric in the process.
				RecordError(ctx, err, KindDependency)
				return nil
			}
			o.ObserveInt64(g, v)
			return nil
		},
		g,
	)
	if err != nil {
		panic("observability.ObservableGauge(" + name + ") callback: " + err.Error())
	}
}

func serveAdmin(addr string) {
	mux := http.NewServeMux()
	// Liveness is SHALLOW: it checks that the process runs, never a dependency.
	// A liveness check on a dependency turns a short dependency fault into a restart.
	mux.HandleFunc("/livez", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	// Readiness is DEEP: it returns 200 only if every registered dependency check
	// passes. On failure, the pod leaves Service rotation WITHOUT a restart. It
	// rejoins when the dependency recovers, per readiness.go.
	mux.HandleFunc(
		"/readyz",
		func(w http.ResponseWriter, r *http.Request) {
			name, err := checkReadiness(r.Context())
			if err != nil {
				http.Error(w, "not ready: "+name+": "+err.Error(), http.StatusServiceUnavailable)
				return
			}
			w.WriteHeader(http.StatusOK)
		},
	)
	// Build identity of the running binary, per ADR-0103. A script or curl can read
	// it per pod, so it shows directly if a pod runs the released version.
	mux.HandleFunc(
		"/version",
		func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(buildinfo.Get())
		},
	)
	mux.HandleFunc("/debug/pprof/", pprof.Index)
	mux.HandleFunc("/debug/pprof/cmdline", pprof.Cmdline)
	mux.HandleFunc("/debug/pprof/profile", pprof.Profile)
	mux.HandleFunc("/debug/pprof/symbol", pprof.Symbol)
	mux.HandleFunc("/debug/pprof/trace", pprof.Trace)
	srv := &http.Server{Addr: addr, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	err := srv.ListenAndServe()
	if err != nil && !errors.Is(err, http.ErrServerClosed) {
		// This runs in a goroutine, so it cannot return the error.
		slog.Error("admin server failed", "error", err)
	}
}
