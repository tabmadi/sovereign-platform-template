// Package apierr defines the platform-wide HTTP error format, per ADR-0303.
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

// TypeBlank is the default problem type. RFC 9457 defines it to mean that the status
// code carries all of the machine-readable meaning.
const TypeBlank = "about:blank"

// ValidationError is one field-level failure, as the errors extension carries it.
type ValidationError struct {
	// Pointer is an RFC 6901 JSON Pointer to the member that failed.
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

// WithType sets a problem-type URN. Use it when two errors share a status code
// and a client handles them differently.
func (e *Error) WithType(urn string) *Error {
	e.Type = urn
	return e
}

// WithValidation attaches field-level failures. The generated validator fills them.
// A handler does not build them by hand.
func (e *Error) WithValidation(errs ...ValidationError) *Error {
	e.Errors = append(e.Errors, errs...)
	return e
}

// WithTrace adds the trace-id of the active span. Outside a recording span it does nothing.
// It is here because a handler that forgets it produces an error that nobody can find, and nothing shows the omission.
func (e *Error) WithTrace(ctx context.Context) *Error {
	sc := trace.SpanContextFromContext(ctx)
	if sc.HasTraceID() {
		e.TraceID = sc.TraceID().String()
	}
	return e
}

// Write serialises the error to w. Inside a request, use WriteContext instead,
// because it adds the trace-id.
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

// Service code calls these helpers and does not build the struct by hand. Then `title`
// is the same for a given status in every service, so a client can switch on it.

func BadRequest(detail string) *Error { return New(http.StatusBadRequest, detail) }

func Unauthorized() *Error {
	return New(http.StatusUnauthorized, "missing or invalid credentials")
}

func Forbidden(detail string) *Error { return New(http.StatusForbidden, detail) }

func NotFound(resource string) *Error {
	return New(http.StatusNotFound, resource+" not found")
}

func Conflict(detail string) *Error { return New(http.StatusConflict, detail) }

// Internal is the one helper whose detail is not safe to pass through. A driver message often carries a query,
// a hostname, or a credential. The cause goes to the log and never reaches the body.
func Internal(cause string) *Error {
	slog.Error("apierr: internal", "cause", cause)
	return New(http.StatusInternalServerError, "an internal error occurred")
}

// Resolved returns err as an *Error with the active trace-id. It uses Internal for any error the handlers did not
// raise. The trace-id is added here and not in each handler. A handler that forgets it produces an error that
// nobody can correlate, and nothing shows the omission.
func Resolved(ctx context.Context, err error) *Error {
	e, ok := As(err)
	if !ok {
		e = Internal(err.Error())
	}
	return e.WithTrace(ctx)
}

// ServeError is the ogen server's ErrorHandler. It answers a request that the generated server rejected before any
// handler ran. Without it, ogen writes a bare 500, and a client sees a server fault for its own mistake.
func ServeError(ctx context.Context, w http.ResponseWriter, _ *http.Request, err error) {
	e, ok := As(err)
	if !ok {
		e = Internal(err.Error())
	}
	e.WriteContext(ctx, w)
}

// As unwraps err to an *Error. It also recognises the errors that the generated server produces before a handler
// runs. Those are the client's mistake and belong in the 4xx range. Without this, they get a 500.
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
