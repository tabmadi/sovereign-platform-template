#!/usr/bin/env bash
# Decide whether a pull request pays for the smoke suite, as a forge step-output assignment (ADR-0102, ADR-0601).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

summary() {
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$*" >>"$GITHUB_STEP_SUMMARY"
  :
}
decide() {
  summary "$2"
  printf 'run=%s\n' "$1"
  exit 0
}

[[ "${LABELED:-false}" != true ]] || decide true "→ the \`e2e-smoke\` label is set; running the suite."

manifest="$(mise run ci:affected -- --base "origin/${BASE_REF:-master}")"

# A global change (a shared library, the toolchain, the platform charts) reaches
# every service by definition, so it is the multi-service case at its widest.
[[ "$(jq -r '.global' <<<"$manifest")" != true ]] ||
  decide true "→ a global change; running the suite."

services="$(jq -r '.services | length' <<<"$manifest")"
[[ "$services" -le 1 ]] ||
  decide true "→ ${services} services affected; a cross-service change is what only an e2e can see."

decide false "✓ ${services} service(s) affected and no label — the smoke suite is skipped."
