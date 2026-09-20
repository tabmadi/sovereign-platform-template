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

// The error signal (ADR-0503): errors are OpenTelemetry data grouped by a computed fingerprint.
// error.fingerprint is high cardinality — a span attribute and log metadata only, never a stream or metric
// label (ADR-0500). errors_total{service, kind} is the bounded metric alerts read.

// Kind is the closed enumeration `errors_total` is labelled by. An open string here is an unbounded metric label
// (ADR-0500).
type Kind string

const (
	// KindInternal is a fault in this service — the default when nothing more
	// specific is true.
	KindInternal Kind = "internal"
	// KindDependency is a failure reaching something this service depends on: a
	// database, a sibling service, an external API.
	KindDependency Kind = "dependency"
	// KindValidation is a request this service refused as malformed. It is counted
	// because a spike of it is a caller that has broken, which is worth seeing.
	KindValidation Kind = "validation"
	// KindConflict is a request refused because the world moved: a version clash,
	// a duplicate, a state that no longer permits the operation.
	KindConflict Kind = "conflict"
	// KindTimeout is a deadline this service ran out of, whether its own or one
	// inherited from its caller.
	KindTimeout Kind = "timeout"
)

// An unknown kind becomes `internal` rather than passing through: a metric label is the one place a typo is
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

// initErrorsTotal creates the counter on first use rather than at package init,
// because a meter created before obs.Init has no provider behind it and records
// into nothing.
func initErrorsTotal() {
	errorsTotal = Counter(
		"errors_total",
		metric.WithDescription("Errors by kind (ADR-0503)."),
	)
}

// RecordError counts the error and attaches its fingerprint to the active span. One call does both: a count with
// no fingerprint says something broke and not what, and a fingerprint with no count cannot be alerted on.
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
	// RecordError puts the exception on the span as an event; the fingerprint rides
	// beside it as an attribute so a trace search can group by fault.
	span.RecordError(err)
	span.SetAttributes(
		attribute.String("error.fingerprint", Fingerprint(err)),
		attribute.String("error.kind", string(kind)),
	)
}

// Fingerprint identifies the fault, not the occurrence. It hashes the error's type with the application call
// frames, excluding line numbers, vendor frames, and the varying part of the message (see normalise).
// The message is needed because Go's errors carry no stack: frames alone cannot tell two faults in one handler apart.
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
	// 16 hex characters, not 64. It is an identifier a human reads off a dashboard
	// and types into a query; the collision probability over the number of distinct
	// faults a platform has is not the binding constraint, legibility is.
	return hex.EncodeToString(sum.Sum(nil))[:16]
}

// normalise removes the parts of a message that vary per occurrence: a run of digits becomes <n>, and a run of
// letters and digits four or longer becomes <x>. Not a hex rule — the wire form of an id is Crockford base32,
// whose alphabet a hex run shreds into fragments that still differ between occurrences.
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

// The root rather than the wrapper: every layer wraps with fmt.Errorf, so the outermost type is `*fmt.wrapError` for
// almost everything.
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

// The skip count starts above this package: `runtime` and this package's own frames are identical for every error on
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
// frame: the same code for every caller, so it identifies a library rather than a
// fault.
const modulePrefix = "github.com/tabmadi/sovereign-platform-template/"

func isFirstParty(fn string) bool {
	if !strings.HasPrefix(fn, modulePrefix) {
		return false
	}
	// This package's own frames are first-party and are still not the fault: they
	// appear identically in every error the platform records.
	return !strings.HasPrefix(fn, modulePrefix+"libs/go/observability")
}

// The type, not the message: a message carries an id or a count, so hashing it mints a fault per occurrence.
// Sentinel errors from errors.New all share one unexported type, so the call frames do the discriminating.
func typeName(err error) string {
	return reflect.TypeOf(err).String()
}

// NormaliseForTest exposes the message normaliser: its rules decide what merges with what, so they are pinned
// directly.
func NormaliseForTest(msg string) string { return normalise(msg) }
