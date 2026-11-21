//go:build tools

// Package tools keeps the ruleguard DSL in go.mod, because golangci-lint type-checks the rules through this module.
package tools

import _ "github.com/quasilyte/go-ruleguard/dsl"
