#!/usr/bin/env bash
# Node-confinement lint (ADR-0100 §runtime, ADR-0601 §Node escape hatch).
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

fail=0

# 1. No npm lockfile outside test/e2e/. (Bun lockfiles are fine — that is the app runtime.)
stray=$(find . \
  -path ./test/e2e -prune -o \
  -path '*/node_modules' -prune -o \
  -name package-lock.json -print 2>/dev/null || true)
if [ -n "$stray" ]; then
  echo "✗ npm lockfile(s) outside test/e2e/ — Node is e2e-only (ADR-0100/0601):" >&2
  echo "$stray" >&2
  fail=1
fi

# 2. test/e2e/ must NOT be a Bun workspace member (it is an npm/Node island).
if grep -qE '"test/e2e' package.json 2>/dev/null; then
  echo "✗ test/e2e/ is listed in the root Bun workspace; it must stay a Node island." >&2
  fail=1
fi

# 3. The e2e workspace must actually exist and be npm-managed.
if [ ! -f test/e2e/package.json ]; then
  echo "✗ missing test/e2e/package.json — the sanctioned Node workspace." >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "✓ node-scope: npm confined to test/e2e/"
fi
exit "$fail"
