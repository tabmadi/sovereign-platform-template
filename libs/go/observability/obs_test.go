package observability

import (
	"context"
	"testing"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
)

// otelhttp reads the global propagator, which defaults to a no-op. A missing TraceContext propagator breaks
// cross-service traces with no error. The test runs with exporters disabled, so it needs no collector.
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
		t.Errorf("global propagator missing `traceparent`: fields=%v", prop.Fields())
	}
	if !hasBaggage {
		t.Errorf("global propagator missing `baggage`: fields=%v", prop.Fields())
	}

	// Round-trip: a span context injected on the way out must be extractable on the
	// way in. A downstream service's otelhttp handler depends on this behaviour.
	carrier := propagation.MapCarrier{
		"traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
	}
	ctx := prop.Extract(context.Background(), carrier)
	out := propagation.MapCarrier{}
	prop.Inject(ctx, out)
	if out["traceparent"] == "" {
		t.Errorf("propagator did not round-trip traceparent: got %v", out)
	}
}
