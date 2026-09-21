// Package lint is the terminal report every gate under tools/ prints (ADR-0001).
package lint

import (
	"fmt"
	"os"
	"slices"
)

type Report struct {
	findings []string
	ok       string
	hint     string
}

// Add takes findings the caller has already formatted. One is enough to fail the gate.
func (r *Report) Add(findings ...string) {
	r.findings = append(r.findings, findings...)
}

func (r *Report) Addf(format string, args ...any) {
	r.findings = append(r.findings, fmt.Sprintf(format, args...))
}

// Okf sets the success line, printed only when no finding was recorded.
func (r *Report) Okf(format string, args ...any) {
	r.ok = fmt.Sprintf(format, args...)
}

// Hintf sets the remedy printed under the findings; it never appears on a passing run.
func (r *Report) Hintf(format string, args ...any) {
	r.hint = fmt.Sprintf(format, args...)
}

// Main runs fn and owns the exit code. An error from fn prints "✗ <err>"; findings print under a
// "✗ <problem>:" header, sorted and indented two spaces. Either exits 1; otherwise the success line
// goes to stdout. Never returns.
func Main(problem string, fn func(*Report) error) {
	var r Report
	err := fn(&r)
	if err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "✗ %v\n", err)
		os.Exit(1)
	}
	if len(r.findings) > 0 {
		_, _ = fmt.Fprintf(os.Stderr, "✗ %s:\n", problem)
		slices.Sort(r.findings)
		for _, f := range r.findings {
			_, _ = fmt.Fprintln(os.Stderr, "  "+f)
		}
		if r.hint != "" {
			_, _ = fmt.Fprintf(os.Stderr, "\n  %s\n", r.hint)
		}
		os.Exit(1)
	}
	_, _ = fmt.Fprintln(os.Stdout, "✓ "+r.ok)
}
