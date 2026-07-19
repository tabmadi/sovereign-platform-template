package observability

import (
	"context"
	"testing"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
)

// TestInitSetsGlobalPropagator guards the end-to-end tracing regression: otelhttp
// (the server handler in httpmw and the client transport on outbound calls) reads
// the GLOBAL propagator, which defaults to a no-op. If Init forgets to install a
// TraceContext propagator, cross-service traces silently stop stitching. Run in the
// exporter-disabled path so no OTel Collector is needed.
func TestInitSetsGlobalPropagator(t *testing.T) {
	t.Setenv("OTEL_SDK_DISABLED", "true")

	shutdown, err := Init(context.Background(), Config{ServiceName: "test", AdminAddr: ":0"})
	if err != nil {
		t.Fatalf("Init: %v", err)
	}
	t.Cleanup(func() { _ = shutdown(context.Background()) })

	prop := otel.GetTextMapPropagator()
	var hasTraceparent, hasBaggage bool
	for _, f := range prop.Fields() {
		switch f {
		case "traceparent":
			hasTraceparent = true
		case "baggage":
			hasBaggage = true
		}
	}
	if !hasTraceparent {
		t.Errorf("global propagator missing 'traceparent'; fields=%v", prop.Fields())
	}
	if !hasBaggage {
		t.Errorf("global propagator missing 'baggage'; fields=%v", prop.Fields())
	}

	// Round-trip: a span context injected on the way out must be extractable on the
	// way in — the exact behavior a downstream service's otelhttp handler relies on.
	carrier := propagation.MapCarrier{
		"traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
	}
	ctx := prop.Extract(context.Background(), carrier)
	out := propagation.MapCarrier{}
	prop.Inject(ctx, out)
	if out["traceparent"] == "" {
		t.Errorf("propagator did not round-trip traceparent; got %v", out)
	}
}
