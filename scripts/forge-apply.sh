#!/usr/bin/env bash
# Reconcile infra/forge/branch-protection.yaml and infra/forge/teams.yaml into the forge, per ADR-0102.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

CONFIG="$(dirname "${BASH_SOURCE[0]}")/../infra/forge/branch-protection.yaml"
TEAMS="$(dirname "${BASH_SOURCE[0]}")/../infra/forge/teams.yaml"

url="${FORGE_URL:-}"
repo="${FORGE_REPO:-}"
token="${FORGE_TOKEN:-}"

if [[ -z "$url" || -z "$repo" || -z "$token" ]]; then
  warn "FORGE_URL, FORGE_REPO, or FORGE_TOKEN unset. Branch protection is not applied"
  detail "the committed rules are in ${CONFIG}"
  exit 0
fi

branch="$(yq -r '.branch' "$CONFIG")"
# The protection block is the API body. The file's field names are Forgejo's, so the payload is the block and its branch.
# A mapping table here would be a second place where a field name can be wrong.
body="$(yq -o=json '.protection + {"rule_name": .branch}' "$CONFIG")"

api() { # <method> <path> [body]
  local method="$1" path="$2" data="${3:-}"
  curl -sS -o /dev/null -w '%{http_code}' -X "$method" \
    -H "Authorization: token ${token}" \
    -H "Content-Type: application/json" \
    ${data:+--data "$data"} \
    "${url}/api/v1/repos/${repo}${path:+/${path}}"
}

step "applying branch protection to ${repo}@${branch}"
code="$(api PATCH "branch_protections/${branch}" "$body")"
if [[ "$code" == "404" ]]; then
  code="$(api POST "branch_protections" "$body")"
fi
[[ "$code" =~ ^2 ]] || fail "forge refused the branch protection, HTTP ${code}"
detail "$(yq -r '.protection.status_check_contexts | join(", ")' "$CONFIG") required"

step "applying the merge styles to ${repo}"
code="$(api PATCH "" "$(yq -o=json '.repository' "$CONFIG")")"
[[ "$code" =~ ^2 ]] || fail "forge refused the merge styles, HTTP ${code}"
detail "default merge style: $(yq -r '.repository.default_merge_style' "$CONFIG")"

if [[ "$(yq -r '.actions.approval_for_outside_collaborators' "$CONFIG")" == "true" ]]; then
  # Forgejo has no switch for this. It holds a run from an outside collaborator's fork until a maintainer approves it.
  detail "runs from an outside collaborator's fork wait for a maintainer's approval, which Forgejo does by itself"
fi

ok "branch protection applied to ${repo}@${branch}"

[[ -f "$TEAMS" ]] || exit 0
org="${repo%%/*}"
step "applying team access to ${org}"
existing="$(curl -sS -H "Authorization: token ${token}" "${url}/api/v1/orgs/${org}/teams?limit=50")"
while IFS= read -r team; do
  name="$(jq -r '.name' <<<"$team")"
  id="$(jq -r --arg n "$name" '.[] | select(.name == $n) | .id' <<<"$existing")"
  [[ -n "$id" ]] || fail "the forge has no team ${name} in ${org}"
  code="$(curl -sS -o /dev/null -w '%{http_code}' -X PATCH -H "Authorization: token ${token}" \
    -H "Content-Type: application/json" --data "$team" "${url}/api/v1/teams/${id}")"
  [[ "$code" =~ ^2 ]] || fail "forge refused the team ${name}, HTTP ${code}"
  detail "${name}: code $(jq -r '.units_map["repo.code"]' <<<"$team")"
done < <(yq -o=json -I=0 '.teams[]' "$TEAMS")
ok "team access applied to ${org}"
