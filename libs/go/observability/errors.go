package observability

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"reflect"
	"runtime"
	"strings"
	"sync"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/trace"
)

// The error signal, per ADR-0503: errors are OpenTelemetry data grouped by a computed fingerprint.
// error.fingerprint has high cardinality. It is only a span attribute and log metadata, never a stream or metric
// label, per ADR-0500. Alerts read the bounded metric errors_total{service, kind}.

// Kind is the closed enumeration that labels `errors_total`. An open string here is an unbounded metric label,
// per ADR-0500.
type Kind string

const (
	// KindInternal is a fault in this service. It is the default when no more
	// specific kind is true.
	KindInternal Kind = "internal"
	// KindDependency is a failure to reach a dependency of this service: a
	// database, a sibling service, or an external API.
	KindDependency Kind = "dependency"
	// KindValidation is a request that this service refused as malformed. It is
	// counted, because a spike of it shows a broken caller.
	KindValidation Kind = "validation"
	// KindConflict is a request refused because the state changed: a version clash,
	// a duplicate, or a state that no longer permits the operation.
	KindConflict Kind = "conflict"
	// KindTimeout is a deadline that this service ran out of. The deadline is its
	// own or one inherited from its caller.
	KindTimeout Kind = "timeout"
)

// An unknown kind becomes `internal` and does not pass through. A metric label is the one place where a typo is
// permanent.
var valid = map[Kind]bool{
	KindInternal:   true,
	KindDependency: true,
	KindValidation: true,
	KindConflict:   true,
	KindTimeout:    true,
}

var (
	errorsOnce  sync.Once
	errorsTotal metric.Int64Counter
)

// initErrorsTotal creates the counter on first use, not at package init. A meter
// created before obs.Init has no provider behind it, so it records nothing.
func initErrorsTotal() {
	errorsTotal = Counter(
		"errors_total",
		metric.WithDescription("Errors by kind, per ADR-0503."),
	)
}

// RecordError counts the error and attaches its fingerprint to the active span. One call does both. A count with
// no fingerprint says that something broke but not what. A fingerprint with no count cannot trigger an alert.
func RecordError(ctx context.Context, err error, kind Kind) {
	if err == nil {
		return
	}
	if !valid[kind] {
		kind = KindInternal
	}
	errorsOnce.Do(initErrorsTotal)
	errorsTotal.Add(
		ctx,
		1,
		metric.WithAttributes(attribute.String("kind", string(kind))),
	)

	span := trace.SpanFromContext(ctx)
	if !span.IsRecording() {
		return
	}
	// RecordError puts the exception on the span as an event. The fingerprint goes
	// beside it as an attribute, so a trace search can group by fault.
	span.RecordError(err)
	span.SetAttributes(
		attribute.String("error.fingerprint", Fingerprint(err)),
		attribute.String("error.kind", string(kind)),
	)
}

// Fingerprint identifies the fault, not the occurrence: the error's type, the application frames, and the message
// without its varying part, per normalise. Line numbers and vendor frames are left out. Go's errors carry no stack,
// so frames alone cannot separate two faults in one handler, and the message is needed.
func Fingerprint(err error) string {
	if err == nil {
		return ""
	}
	sum := sha256.New()
	_, _ = sum.Write([]byte(errorType(err)))
	_, _ = sum.Write([]byte{0})
	_, _ = sum.Write([]byte(normalise(err.Error())))
	for _, frame := range appFrames() {
		_, _ = sum.Write([]byte{0})
		_, _ = sum.Write([]byte(frame))
	}
	// 16 hex characters, not 64. A human reads it from a dashboard and types it into
	// a query. For the number of faults a platform has, collisions are not the limit.
	// Legibility is.
	return hex.EncodeToString(sum.Sum(nil))[:16]
}

// normalise removes the parts of a message that vary per occurrence. A run of digits becomes <n>, and a run of
// four or more letters and digits becomes <x>. It is not a hex rule. An id's wire form is Crockford base32, and a
// hex rule breaks it into fragments that still differ between occurrences.
func normalise(msg string) string {
	var b strings.Builder
	b.Grow(len(msg))
	for i := 0; i < len(msg); {
		if !isAlnum(msg[i]) {
			_ = b.WriteByte(msg[i])
			i++
			continue
		}
		j := i
		digits, letters := 0, 0
		for j < len(msg) && isAlnum(msg[j]) {
			if msg[j] >= '0' && msg[j] <= '9' {
				digits++
			} else {
				letters++
			}
			j++
		}
		run := msg[i:j]
		switch {
		case letters == 0:
			_, _ = b.WriteString("<n>")
		case digits > 0 && len(run) >= 4:
			_, _ = b.WriteString("<x>")
		default:
			_, _ = b.WriteString(run)
		}
		i = j
	}
	return b.String()
}

func isAlnum(c byte) bool {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

// The root, not the wrapper. Every layer wraps with fmt.Errorf, so the outermost type is `*fmt.wrapError` for
// almost every error.
func errorType(err error) string {
	for {
		unwrapped, ok := err.(interface{ Unwrap() error })
		if !ok {
			break
		}
		next := unwrapped.Unwrap()
		if next == nil {
			break
		}
		err = next
	}
	return strings.TrimPrefix(typeName(err), "*")
}

// The skip count starts above this package. `runtime` and this package's own frames are the same for every error on
// the platform.
func appFrames() []string {
	const (
		skip      = 3
		maxFrames = 8
	)
	pcs := make([]uintptr, maxFrames+skip)
	n := runtime.Callers(skip, pcs)
	if n == 0 {
		return nil
	}
	frames := runtime.CallersFrames(pcs[:n])
	var out []string
	for {
		frame, more := frames.Next()
		if frame.Function != "" && isFirstParty(frame.Function) {
			out = append(out, frame.Function)
		}
		if !more || len(out) == maxFrames {
			break
		}
	}
	return out
}

// modulePrefix is this platform's module path. A frame outside it is a vendor
// frame. It is the same code for every caller, so it identifies a library and not
// a fault.
const modulePrefix = "github.com/tabmadi/sovereign-platform-template/"

func isFirstParty(fn string) bool {
	if !strings.HasPrefix(fn, modulePrefix) {
		return false
	}
	// This package's own frames are first-party but are not the fault. They are
	// the same in every error that the platform records.
	return !strings.HasPrefix(fn, modulePrefix+"libs/go/observability")
}

// The type, not the message. A message carries an id or a count, so hashing it makes one fault per occurrence.
// All sentinel errors from errors.New share one unexported type, so the call frames tell them apart.
func typeName(err error) string {
	return reflect.TypeOf(err).String()
}

// NormaliseForTest exposes the message normaliser. Its rules decide which messages merge, so tests pin them
// directly.
func NormaliseForTest(msg string) string { return normalise(msg) }
