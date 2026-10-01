#!/usr/bin/env bash
# Node-confinement lint, per ADR-0100 and ADR-0601.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

# `rc`, not `fail`: the accumulator must not shadow the log.sh verb, which the verdict below calls after all three checks.
rc=0

# A Bun lockfile is fine anywhere, because Bun is the app runtime.
no_npm_lockfile_outside_e2e() {
  local stray
  stray=$(find . \
    -path ./test/e2e -prune -o \
    -path '*/node_modules' -prune -o \
    -name package-lock.json -print 2>/dev/null || true)
  [ -z "$stray" ] && return 0
  warn "npm lockfile(s) outside test/e2e/. Node is only for e2e, per ADR-0100 and ADR-0601:"
  echo "$stray" >&2
  return 1
}

e2e_is_not_a_bun_workspace_member() {
  grep -qE '"test/e2e' package.json 2>/dev/null || return 0
  warn "test/e2e/ is listed in the root Bun workspace. It must stay a Node island."
  return 1
}

e2e_workspace_exists() {
  [ -f test/e2e/package.json ] && return 0
  warn "missing test/e2e/package.json, the approved Node workspace."
  return 1
}

no_npm_lockfile_outside_e2e || rc=1
e2e_is_not_a_bun_workspace_member || rc=1
e2e_workspace_exists || rc=1

[ "$rc" -eq 0 ] || fail "node-scope: npm is not confined to test/e2e/"
ok "node-scope: npm confined to test/e2e/"
