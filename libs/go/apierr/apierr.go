// Package apierr defines the platform-wide HTTP error format (ADR-0303).
package apierr

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"github.com/ogen-go/ogen/ogenerrors"
	"go.opentelemetry.io/otel/trace"
)

// TypeBlank is the default problem type. RFC 9457 gives it the meaning "the status
// code is the whole of the machine-readable semantics".
const TypeBlank = "about:blank"

// ValidationError is one field-level failure, as the errors extension carries it.
type ValidationError struct {
	// Pointer is an RFC 6901 JSON Pointer to the offending member.
	Pointer string `json:"pointer"`
	Message string `json:"message"`
}

// Error is the canonical platform error response.
type Error struct {
	// Status is duplicated into the body as `status`, per RFC 9457.
	Status  int               `json:"status"`
	Type    string            `json:"type"`
	Title   string            `json:"title"`
	Detail  string            `json:"detail,omitempty"`
	TraceID string            `json:"trace_id,omitempty"`
	Errors  []ValidationError `json:"errors,omitempty"`
}

func (e *Error) Error() string {
	if e.Detail == "" {
		return e.Title
	}
	return e.Title + ": " + e.Detail
}

// WithType sets a problem-type URN, for the case where two errors share a status
// code and a client handles them differently.
func (e *Error) WithType(urn string) *Error {
	e.Type = urn
	return e
}

// WithValidation attaches field-level failures. Populated from the generated
// validator rather than assembled by hand in a handler.
func (e *Error) WithValidation(errs ...ValidationError) *Error {
	e.Errors = append(e.Errors, errs...)
	return e
}

// WithTrace stamps the trace-id of the active span, and is a no-op outside a recording span.
// It lives here because a handler that forgets it produces an error nobody can find, with no signal it was forgotten.
func (e *Error) WithTrace(ctx context.Context) *Error {
	sc := trace.SpanContextFromContext(ctx)
	if sc.HasTraceID() {
		e.TraceID = sc.TraceID().String()
	}
	return e
}

// Write serialises the error to w. Callers inside a request should prefer
// WriteContext, which stamps the trace-id.
func (e *Error) Write(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/problem+json")
	w.WriteHeader(e.Status)
	err := json.NewEncoder(w).Encode(e)
	if err != nil {
		slog.Error("apierr: encode response", "error", err)
	}
}

func (e *Error) WriteContext(ctx context.Context, w http.ResponseWriter) {
	e.WithTrace(ctx).Write(w)
}

// New builds an error with the status's reason phrase as its stable title.
func New(status int, detail string) *Error {
	return &Error{
		Status: status,
		Type:   TypeBlank,
		Title:  http.StatusText(status),
		Detail: detail,
	}
}

// Helpers for the common cases. Service code calls these rather than building the
// struct by hand, so `title` stays identical for a given status across services —
// which is the property that makes it switchable.

func BadRequest(detail string) *Error { return New(http.StatusBadRequest, detail) }

func Unauthorized() *Error {
	return New(http.StatusUnauthorized, "missing or invalid credentials")
}

func Forbidden(detail string) *Error { return New(http.StatusForbidden, detail) }

func NotFound(resource string) *Error {
	return New(http.StatusNotFound, resource+" not found")
}

func Conflict(detail string) *Error { return New(http.StatusConflict, detail) }

// Internal is the one helper whose detail is not safe to pass through: a driver message routinely carries a query,
// a hostname, or a credential. The cause is logged and never reaches the body.
func Internal(cause string) *Error {
	slog.Error("apierr: internal", "cause", cause)
	return New(http.StatusInternalServerError, "an internal error occurred")
}

// Resolved returns err as an *Error carrying the active trace-id, falling back to Internal for anything the
// handlers did not raise. The trace-id is stamped here rather than in each handler: a handler that forgets it
// produces an error nobody can correlate, and nothing signals the omission.
func Resolved(ctx context.Context, err error) *Error {
	e, ok := As(err)
	if !ok {
		e = Internal(err.Error())
	}
	return e.WithTrace(ctx)
}

// ServeError is the ogen server's ErrorHandler, answering a request the generated server rejected before any
// handler ran. Without it ogen writes a bare 500, so a client sees a server fault for its own mistake.
func ServeError(ctx context.Context, w http.ResponseWriter, _ *http.Request, err error) {
	e, ok := As(err)
	if !ok {
		e = Internal(err.Error())
	}
	e.WriteContext(ctx, w)
}

// As unwraps err to an *Error, and recognises the errors the generated server produces before a handler is
// reached. Those are the client's mistake and belong in the 4xx range; unrecognised, they would be answered 500.
func As(err error) (*Error, bool) {
	var e *Error
	if errors.As(err, &e) {
		return e, true
	}
	var decodeParams *ogenerrors.DecodeParamsError
	if errors.As(err, &decodeParams) {
		return BadRequest(decodeParams.Error()), true
	}
	var decodeRequest *ogenerrors.DecodeRequestError
	if errors.As(err, &decodeRequest) {
		return BadRequest(decodeRequest.Error()), true
	}
	return nil, false
}
