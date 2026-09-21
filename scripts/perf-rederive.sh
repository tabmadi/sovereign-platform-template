#!/usr/bin/env bash
# Re-derive the measured numbers the ADR set asserts (ADR-0001, ADR-0204).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

step "re-deriving the measured numbers"

detail "committed values, as the ADR set states them:"
grep -rn '(measured)' docs/adr/*.md | sed 's/^/    /' | head -20 || true

echo
detail "resource governance, computed from the charts as they stand now:"
mise run lint:resource-governance 2>&1 | grep -E 'requests|containers' | sed 's/^/    /' || true

echo
detail "load suite — this needs a running cluster (ADR-0601):"
if mise run perf:smoke 2>&1 | tail -20 | sed 's/^/    /'; then
  ok "load suite ran"
else
  warn "load suite did not run — a cluster is required, and its absence is not drift"
fi

echo
warn "compare the two by hand, and change the ADR only when the platform changed"
warn "a number measured on different hardware is a different measurement, not a regression"
