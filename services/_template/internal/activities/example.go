//go:build _template

// Activities are idempotent and short, with one per file, per ADR-0302.
package activities

import "context"

func DoStuff(_ context.Context, input string) (string, error) { return "ok:" + input, nil }
