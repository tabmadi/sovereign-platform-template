#!/usr/bin/env bash
# Human-output vocabulary gate (ADR-0001): scripts speak → ✓ ✗ ⚠ from scripts/lib/log.sh, not bare status prose.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

step "checking scripts use the log vocabulary (ADR-0001)"

# The glyphs are alternated rather than bracketed: a bracket class compares single
# bytes under a C locale. A GitHub Actions annotation opens with `::` and so falls
# outside the pattern; `lib/log.sh` defines the vocabulary and is excluded below.
pattern='(echo|printf)([[:space:]]+-[a-zA-Z]+)*[[:space:]]+["'\'']([[:space:]]*(✓|✗|⚠|→)|(WARN(ING)?|ERROR|FAIL(ED)?|OK)\b)'

hits=$(grep -rnE "$pattern" scripts --include='*.sh' | grep -v 'scripts/lib/log.sh' || true)

if [[ -n "$hits" ]]; then
  warn "bare status output found — use step/ok/warn/fail/detail from scripts/lib/log.sh:"
  printf '%s\n' "$hits" | sed 's/^/  /'
  fail "log-vocabulary lint failed"
fi

ok "all scripts use the log vocabulary"
