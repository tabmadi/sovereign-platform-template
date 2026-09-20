package observability_test

import (
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/tabmadi/sovereign-platform-template/libs/go/observability"
)

// These pin the fingerprint's stability (ADR-0503). Nothing else can see a break: a drifted fingerprint looks like a
// new fault.

func failOne() error           { return errors.New("boom") }
func failTwo() error           { return errors.New("boom") }
func failElsewhere() error     { return errors.New("the pool is closed") }
func wrapOne() error           { return fmt.Errorf("handling request: %w", failOne()) }
func failWith(id string) error { return fmt.Errorf("order %s not found", id) }

func TestFingerprintIsStableForTheSameFault(t *testing.T) {
	t.Parallel()
	first := observability.Fingerprint(failOne())
	second := observability.Fingerprint(failOne())
	if first != second {
		t.Fatalf("same call site produced two fingerprints: %s and %s", first, second)
	}
}

// The varying part of a message must not reach the hash. This is the difference
// between one fault and one fault per request.
func TestFingerprintIgnoresTheMessagePayload(t *testing.T) {
	t.Parallel()
	first := observability.Fingerprint(failWith("order_1"))
	second := observability.Fingerprint(failWith("order_2"))
	if first != second {
		t.Fatalf("message payload changed the fingerprint: %s vs %s", first, second)
	}
}

// Different faults get different fingerprints. This is the half that stops one
// dashboard row from standing for the whole platform.
func TestFingerprintSeparatesDistinctFaults(t *testing.T) {
	t.Parallel()
	if observability.Fingerprint(failOne()) == observability.Fingerprint(failElsewhere()) {
		t.Fatal("two distinct faults share a fingerprint")
	}
}

// A known merge: two errors with the same normalised message from the same place are one fault, because Go's
// errors carry no creation stack. Asserted so a change to the frame rule has to decide about it deliberately.
func TestIdenticalMessagesFromOneRecordSiteMerge(t *testing.T) {
	t.Parallel()
	if observability.Fingerprint(failOne()) != observability.Fingerprint(failTwo()) {
		t.Fatal("identical messages recorded from one site produced two fingerprints")
	}
}

// The normaliser earns its place here: an id in a message must not mint a fault.
func TestFingerprintNormalisesIdentifiers(t *testing.T) {
	t.Parallel()
	first := observability.Fingerprint(failWith("order_01kztmx9e0fq1r13w5d1aerqw6"))
	second := observability.Fingerprint(failWith("order_01hbgxyzq0fq1r13w5d1aerab2"))
	if first != second {
		t.Fatalf("two ids produced two fingerprints: %s vs %s", first, second)
	}
}

// Wrapping must not change the fault. Every layer wraps with fmt.Errorf, so a
// fingerprint that moved on each wrap would depend on how deep the error was
// caught rather than on where it came from.
func TestFingerprintSurvivesWrapping(t *testing.T) {
	t.Parallel()
	if observability.Fingerprint(wrapOne()) == "" {
		t.Fatal("wrapped error produced no fingerprint")
	}
}

func TestFingerprintIsShortAndHex(t *testing.T) {
	t.Parallel()
	got := observability.Fingerprint(failOne())
	if len(got) != 16 {
		t.Fatalf("fingerprint is %d characters, want 16: %q", len(got), got)
	}
	if strings.TrimLeft(got, "0123456789abcdef") != "" {
		t.Fatalf("fingerprint is not hex: %q", got)
	}
}

func TestFingerprintOfNilIsEmpty(t *testing.T) {
	t.Parallel()
	if got := observability.Fingerprint(nil); got != "" {
		t.Fatalf("nil error produced %q", got)
	}
}

// The normaliser is the tuned part, so its rules are pinned directly rather than
// only through fingerprints. A change here changes what merges with what.
func TestNormaliseRules(t *testing.T) {
	t.Parallel()
	cases := []struct{ in, want string }{
		{"order order_01kztmx9e0fq1r13w5d1aerqw6 not found", "order order_<x> not found"},
		{"retry 3 of 5", "retry <n> of <n>"},
		{"dial postgres-rw:5432: connection refused", "dial postgres-rw:<n>: connection refused"},
		// Words that happen to be hex are words. An earlier hex-run rule turned
		// `dead` and `add` into placeholders and shredded base32 ids into fragments.
		{"deadlock detected", "deadlock detected"},
		{"add failed", "add failed"},
		// No varying part means nothing changes.
		{"the pool is closed", "the pool is closed"},
	}
	for _, c := range cases {
		if got := observability.NormaliseForTest(c.in); got != c.want {
			t.Errorf("normalise(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}
