#!/usr/bin/env bash
# Node-confinement lint (ADR-0100 §runtime, ADR-0601 §Node escape hatch).
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

fail=0

# A Bun lockfile is fine anywhere — that is the app runtime.
no_npm_lockfile_outside_e2e() {
  local stray
  stray=$(find . \
    -path ./test/e2e -prune -o \
    -path '*/node_modules' -prune -o \
    -name package-lock.json -print 2>/dev/null || true)
  [ -z "$stray" ] && return 0
  echo "✗ npm lockfile(s) outside test/e2e/ — Node is e2e-only (ADR-0100/0601):" >&2
  echo "$stray" >&2
  return 1
}

e2e_is_not_a_bun_workspace_member() {
  grep -qE '"test/e2e' package.json 2>/dev/null || return 0
  echo "✗ test/e2e/ is listed in the root Bun workspace; it must stay a Node island." >&2
  return 1
}

e2e_workspace_exists() {
  [ -f test/e2e/package.json ] && return 0
  echo "✗ missing test/e2e/package.json — the sanctioned Node workspace." >&2
  return 1
}

no_npm_lockfile_outside_e2e || fail=1
e2e_is_not_a_bun_workspace_member || fail=1
e2e_workspace_exists || fail=1

if [ "$fail" -eq 0 ]; then
  echo "✓ node-scope: npm confined to test/e2e/"
fi
exit "$fail"
