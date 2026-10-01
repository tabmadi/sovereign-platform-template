#!/usr/bin/env bash
# Structural parity gate, per ADR-0205: a deployed values key must exist in the local overlay, unless the allowlist gives the reason it cannot.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

OVERLAY="infra/gitops/platform"
LOCAL="${OVERLAY}/local/values.yaml"
ALLOWLIST="infra/gitops/parity-allowlist.txt"

[ -f "$LOCAL" ] || fail "no ${LOCAL}"
[ -f "$ALLOWLIST" ] || fail "no ${ALLOWLIST}"

# Every entry has a reason. The gate exists to show a divergence that nobody argued for.
while IFS= read -r line; do
  case "$line" in
  '' | '#'*) continue ;;
  *'#'*) ;;
  *) fail "${ALLOWLIST}: '${line}' carries no reason" ;;
  esac
done <"$ALLOWLIST"

# Flattened leaf paths, so a section in one overlay and not in another shows as the paths it holds. A prefix entry covers its children.
paths() { yq -o=json '.' "$1" | jq -r '[paths(scalars) | join(".")] | .[]'; }
allowed() {
  awk -v p="$1" '!/^[[:space:]]*#/ && NF { if (p == $1 || index(p, $1 ".") == 1) { found = 1 } } END { exit(found ? 0 : 1) }' "$ALLOWLIST"
}

step "checking that deployed values keys exist in the local overlay"
local_paths="$(paths "$LOCAL")"

problems=()
# Every deployed environment that the project keeps. A project can run fewer than the template ships.
for file in "$OVERLAY"/*/values.yaml; do
  env="$(basename "$(dirname "$file")")"
  [ "$env" != local ] || continue
  while IFS= read -r path; do
    grep -qxF "$path" <<<"$local_paths" && continue
    allowed "$path" ||
      problems+=("${env}: '${path}' is absent from the local overlay and unlisted in ${ALLOWLIST}")
  done < <(paths "$file")
done

if [ "${#problems[@]}" -gt 0 ]; then
  warn "the deployed overlays carry keys the local tier does not:"
  printf '  · %s\n' "${problems[@]}" >&2
  fail "cover the key locally, or add its prefix to ${ALLOWLIST} with the approved reason"
fi
ok "every deployed values key is local, or allowlisted with a reason"
