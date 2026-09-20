#!/usr/bin/env bash
# Human-output vocabulary gate (ADR-0001): scripts speak → ✓ ✗ ⚠ from scripts/lib/log.sh, not bare status prose.
set -euo pipefail
source "$(dirname "$0")/lib/log.sh"
cd "$(cd "$(dirname "$0")/.." && pwd)"

step "checking scripts use the log vocabulary (ADR-0001)"

# echo/printf whose message starts with a bare status word. `lib/log.sh` defines
# the vocabulary, so it is exempt.
pattern='(echo|printf)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)?["'\''](WARN(ING)?|ERROR|FAIL(ED)?|OK)\b'

hits=$(grep -rnE "$pattern" scripts --include='*.sh' | grep -v 'scripts/lib/log.sh' || true)

if [[ -n "$hits" ]]; then
  warn "bare status prose found — use warn/fail/ok from scripts/lib/log.sh:"
  printf '%s\n' "$hits" | sed 's/^/  /'
  fail "log-vocabulary lint failed"
fi

ok "all scripts use the log vocabulary"
