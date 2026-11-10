#!/usr/bin/env bash
# Decide whether a pull request runs Lighthouse, as a forge step-output assignment, per ADR-0400.
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

base="origin/${BASE_REF:-master}"
manifest="$(mise run ci:affected -- --base "$base" --runtime)"

[[ "$(jq -r '.global' <<<"$manifest")" != true ]] ||
  decide true "→ a global change. Measuring the frontend."
[[ "$(jq -r '.apps | index("frontend") != null' <<<"$manifest")" != true ]] ||
  decide true "→ apps/frontend changed. Measuring the frontend."
# The frontend bundles the TypeScript libs. The manifest names a lib without its language, so the path decides.
changed="$(git diff --name-only "${base}...HEAD")"
! grep -q '^libs/ts/' <<<"$changed" ||
  decide true "→ a TypeScript lib changed. Measuring the frontend."

decide false "✓ nothing that the frontend serves changed. Lighthouse is skipped."
