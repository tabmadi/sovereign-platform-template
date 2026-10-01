package apierr_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"go.opentelemetry.io/otel/trace"

	"github.com/tabmadi/sovereign-platform-template/libs/go/apierr"
)

// The test asserts the marshalled JSON and not the struct. A struct-level assertion cannot see a renamed tag, and a
// renamed tag breaks every consumer, per ADR-0303.
func TestProblemWireShape(t *testing.T) {
	t.Parallel()

	body := marshal(t, apierr.NotFound("product"))

	want := map[string]any{
		"status": float64(http.StatusNotFound),
		"type":   "about:blank",
		"title":  "Not Found",
		"detail": "product not found",
	}
	for k, v := range want {
		if body[k] != v {
			t.Errorf("%s = %v, want %v", k, body[k], v)
		}
	}

	// instance is left out on purpose: trace_id identifies the occurrence.
	if _, present := body["instance"]; present {
		t.Error("instance is present, but ADR-0303 omits it")
	}
	// No member from before RFC 9457 may remain.
	for _, gone := range []string{"code", "message", "details"} {
		if _, present := body[gone]; present {
			t.Errorf("%q is present, but it is not an RFC 9457 member", gone)
		}
	}
	// An absent extension stays absent. It does not serialise as null.
	for _, k := range []string{"trace_id", "errors"} {
		if _, present := body[k]; present {
			t.Errorf("%q serialised while empty, but it must be omitted", k)
		}
	}
}

// title is stable per status, and detail is not. A client that switches on title
// does not need to know which resource was missing.
func TestTitleIsStableAcrossInstances(t *testing.T) {
	t.Parallel()

	product := marshal(t, apierr.NotFound("product"))
	order := marshal(t, apierr.NotFound("order"))

	if product["title"] != order["title"] {
		t.Errorf("title varies with the instance: %v vs %v", product["title"], order["title"])
	}
	if product["detail"] == order["detail"] {
		t.Error("detail does not vary with the instance, but it must")
	}
}

// This rule is the easiest to break. A driver or client error often carries a query,
// a hostname, or a credential. Passing it through puts that value in a response body,
// per ADR-0303 and ADR-0503.
func TestInternalDoesNotLeakItsCause(t *testing.T) {
	t.Parallel()

	const cause = `pq: password authentication failed for user "orders" on host db.internal`
	body := marshal(t, apierr.Internal(cause))

	detail, _ := body["detail"].(string)
	if strings.Contains(detail, "password") || strings.Contains(detail, "db.internal") {
		t.Fatalf("detail leaked the cause: %q", detail)
	}
	if body["status"] != float64(http.StatusInternalServerError) {
		t.Errorf("status = %v, want 500", body["status"])
	}
}

func TestWithTraceStampsTheActiveSpan(t *testing.T) {
	t.Parallel()

	traceID := trace.TraceID{
		0x4b, 0xf9, 0x2f, 0x35, 0x77, 0xb3, 0x4d, 0xa6,
		0xa3, 0xce, 0x92, 0x9d, 0x0e, 0x0e, 0x47, 0x36,
	}
	config := trace.SpanContextConfig{
		TraceID: traceID,
		SpanID:  trace.SpanID{1, 2, 3, 4, 5, 6, 7, 8},
	}
	ctx := trace.ContextWithSpanContext(context.Background(), trace.NewSpanContext(config))

	e := apierr.BadRequest("bad").WithTrace(ctx)
	if e.TraceID != traceID.String() {
		t.Errorf("trace_id = %q, want %q", e.TraceID, traceID.String())
	}
}

// Building an error outside a request must not need a tracer. Otherwise every unit
// test has to build one.
func TestWithTraceOutsideASpanIsANoOp(t *testing.T) {
	t.Parallel()

	e := apierr.BadRequest("bad").WithTrace(context.Background())
	if e.TraceID != "" {
		t.Errorf("trace_id = %q, want empty outside a span", e.TraceID)
	}
}

func TestValidationErrorsSerialise(t *testing.T) {
	t.Parallel()

	e := apierr.BadRequest("validation failed").WithValidation(
		apierr.ValidationError{Pointer: "/price_cents", Message: "must be >= 0"},
	)
	body := marshal(t, e)

	errs, ok := body["errors"].([]any)
	if !ok || len(errs) != 1 {
		t.Fatalf("errors = %v, want one entry", body["errors"])
	}
	first, _ := errs[0].(map[string]any)
	if first["pointer"] != "/price_cents" {
		t.Errorf("pointer = %v", first["pointer"])
	}
}

func TestWriteSetsTheProblemMediaType(t *testing.T) {
	t.Parallel()

	rec := httptest.NewRecorder()
	apierr.Conflict("already exists").Write(rec)

	if got := rec.Header().Get("Content-Type"); got != "application/problem+json" {
		t.Errorf("Content-Type = %q", got)
	}
	if rec.Code != http.StatusConflict {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusConflict)
	}
}

// marshal renders the error the way a client receives it.
func marshal(t *testing.T, e *apierr.Error) map[string]any {
	t.Helper()
	rec := httptest.NewRecorder()
	e.Write(rec)

	var body map[string]any
	err := json.Unmarshal(rec.Body.Bytes(), &body)
	if err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	return body
}
