#!/usr/bin/env bash
# The vocabulary gate for human output, per ADR-0001. Scripts use → ✓ ✗ ⚠ from scripts/lib/log.sh, not bare status text.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

step "checking that scripts use the log vocabulary of ADR-0001"

# The glyphs are alternatives, not a bracket class: a bracket class compares single bytes under a C locale.
# A GitHub Actions annotation starts with `::`, so the pattern skips it. `lib/log.sh` defines the vocabulary and is excluded below.
pattern='(echo|printf)([[:space:]]+-[a-zA-Z]+)*[[:space:]]+["'\'']([[:space:]]*(✓|✗|⚠|→)|(WARN(ING)?|ERROR|FAIL(ED)?|OK)\b)'

hits=$(grep -rnE "$pattern" scripts --include='*.sh' | grep -v 'scripts/lib/log.sh' || true)

if [[ -n "$hits" ]]; then
  warn "bare status output found. Use step, ok, warn, fail, or detail from scripts/lib/log.sh:"
  printf '%s\n' "$hits" | sed 's/^/  /'
  fail "log-vocabulary lint failed"
fi

ok "all scripts use the log vocabulary"
