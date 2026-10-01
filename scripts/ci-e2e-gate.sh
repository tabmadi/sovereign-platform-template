#!/usr/bin/env bash
# Decide whether a pull request runs the smoke suite, as a forge step-output assignment, per ADR-0102 and ADR-0601.
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

[[ "${LABELED:-false}" != true ]] || decide true "→ the \`e2e-smoke\` label is set. Running the suite."

manifest="$(mise run ci:affected -- --base "origin/${BASE_REF:-master}")"

# A global change reaches every service, so it is the widest multi-service case.
# Examples are a shared library, the toolchain, and the platform charts.
[[ "$(jq -r '.global' <<<"$manifest")" != true ]] ||
  decide true "→ a global change. Running the suite."

services="$(jq -r '.services | length' <<<"$manifest")"
[[ "$services" -le 1 ]] ||
  decide true "→ ${services} services affected. Only an e2e test sees a cross-service change."

decide false "✓ ${services} service(s) affected and no label. The smoke suite is skipped."
