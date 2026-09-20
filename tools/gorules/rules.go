//go:build ruleguard

// Package gorules holds custom gocritic/ruleguard lint rules for this repo.
package gorules

import "github.com/quasilyte/go-ruleguard/dsl"

// noIfInitAssign forbids the init-statement form of `if`. The three else-shapes are spelled out because
// gogrep has no wildcard for an else clause.
func noIfInitAssign(m dsl.Matcher) {
	m.Match(
		`if $*_ := $*_; $_ { $*_ }`,
		`if $*_ := $*_; $_ { $*_ } else { $*_ }`,
		`if $*_ := $*_; $_ { $*_ } else if $_ { $*_ }`,
		`if $*_ = $*_; $_ { $*_ }`,
		`if $*_ = $*_; $_ { $*_ } else { $*_ }`,
		`if $*_ = $*_; $_ { $*_ } else if $_ { $*_ }`,
	).Report(`no assignment in if-init: declare the variable on its own line`)
}

// errCompare forbids == / != on errors outside nil checks, which see only the outermost error once it is
// wrapped with %w. It exists because errorlint misses the single-value short-declaration form.
func errCompare(m dsl.Matcher) {
	m.Match(
		`$x == $y`,
		`$x != $y`,
	).Where(
		m["x"].Type.Is(`error`) && m["y"].Type.Is(`error`) &&
			!m["x"].Text.Matches(`^nil$`) && !m["y"].Text.Matches(`^nil$`),
	).Report(`error compared with ==/!=; fails on wrapped errors, use errors.Is (or errors.As)`)

	m.Match(`switch $x { $*_ }`).
		Where(m["x"].Type.Is(`error`)).
		Report(`switch on an error; fails on wrapped errors, use errors.Is in if/else if`)
}
