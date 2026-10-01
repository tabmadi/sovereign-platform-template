#!/usr/bin/env bash
# Lint every OpenAPI spec under services/, per ADR-0303. Each spec is self-contained.
# Its shared shapes are declared in its own components, not in cross-file $refs.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

shopt -s nullglob globstar

specs=()
for f in services/*/openapi.yaml; do
  [[ -f "$f" ]] && specs+=("$f")
done

if [[ ${#specs[@]} -eq 0 ]]; then
  ok "no OpenAPI specs yet"
  exit 0
fi

step "linting ${#specs[@]} OpenAPI spec(s) with vacuum"
vacuum lint --ruleset tools/codegen/openapi-ruleset.yaml --fail-severity error "${specs[@]}"

# Resource-prefix ownership is the one rule vacuum cannot express, per ADR-0303.
# It is a property of the set of specs, and vacuum lints one document at a time.
step "checking resource-prefix ownership across the /api namespace"
go run ./tools/lint-api-prefixes

# The shared components are copied into each spec, not $ref'd across files, so each document stays self-contained for ogen and vacuum, per ADR-0303.
# This check makes `identical across specs` a fact and not a habit.
step "checking the shared components have not diverged"
go run ./tools/shared-components -check
