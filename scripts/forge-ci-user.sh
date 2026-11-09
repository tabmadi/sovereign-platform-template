#!/usr/bin/env bash
# Create or refresh the `ci` machine user that pushes promotion commits and runs Renovate, per ADR-0102, ADR-0201, and ADR-0106.
# It gives `ci` write access to the repository, stores new tokens of `ci` as the PROMOTE_TOKEN and RENOVATE_TOKEN secrets, and applies branch protection.
# A rerun rotates the tokens. FORGE_TOKEN is an admin token. The new token goes only to the secret and is never printed.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

url="${FORGE_URL:-}"
repo="${FORGE_REPO:-}"
token="${FORGE_TOKEN:-}"
[[ -n "$url" && -n "$repo" && -n "$token" ]] || fail "set FORGE_URL, FORGE_REPO, and FORGE_TOKEN, an admin token"
user=ci
host="${url#*://}"

api() { # <method> <path> [body]
  local method="$1" path="$2" data="${3:-}"
  curl -sS -o /dev/null -w '%{http_code}' -X "$method" \
    -H "Authorization: token ${token}" -H "Content-Type: application/json" \
    ${data:+--data "$data"} "${url}/api/v1/${path}"
}

# A token is created with the user's own password, so each run sets a new random one. Nobody signs in as `ci`.
# `write:issue` lets it comment on a pull request, as the design-preview workflow does, because Forgejo serves pull request comments through its issue API.
password="$(openssl rand -base64 36 | tr -d '\n')"
if [[ "$(api GET "users/${user}")" == 200 ]]; then
  step "resetting the password of ${user}"
  code="$(api PATCH "admin/users/${user}" "$(jq -n --arg p "$password" --arg l "$user" \
    '{login_name: $l, source_id: 0, password: $p, must_change_password: false}')")"
else
  step "creating the ${user} user"
  code="$(api POST admin/users "$(jq -n --arg p "$password" --arg u "$user" --arg e "${user}@noreply.${host}" \
    '{username: $u, email: $e, password: $p, must_change_password: false, visibility: "private"}')")"
fi
[[ "$code" =~ ^2 ]] || fail "the forge refused the ${user} user, HTTP ${code}"

stamp="$(date -u +%Y%m%d%H%M%S)"
token_for() { # <name> <scopes as a JSON array>
  local new
  new="$(curl -sS -u "${user}:${password}" -H "Content-Type: application/json" \
    --data "$(jq -n --arg n "$1-${stamp}" --argjson s "$2" '{name: $n, scopes: $s}')" \
    "${url}/api/v1/users/${user}/tokens" | jq -r '.sha1 // empty')"
  [[ -n "$new" ]] || fail "the forge did not return the $1 token for ${user}"
  printf '%s' "$new"
}
step "creating the promote and renovate tokens for ${user}"
promote="$(token_for promote '["write:repository", "write:issue"]')"
# Renovate's Forgejo platform reads the bot's own user and the organisation of the repository as well.
renovate="$(token_for renovate '["write:repository", "write:issue", "read:user", "read:organization"]')"

step "giving ${user} write access to ${repo}"
code="$(api PUT "repos/${repo}/collaborators/${user}" '{"permission": "write"}')"
[[ "$code" =~ ^2 ]] || fail "the forge refused the collaborator, HTTP ${code}"

for pair in "PROMOTE_TOKEN:${promote}" "RENOVATE_TOKEN:${renovate}"; do
  step "storing the ${pair%%:*} secret"
  code="$(api PUT "repos/${repo}/actions/secrets/${pair%%:*}" "$(jq -n --arg d "${pair#*:}" '{data: $d}')")"
  [[ "$code" =~ ^2 ]] || fail "the forge refused the ${pair%%:*} secret, HTTP ${code}"
done
detail "tokens of ${stamp}. Older tokens of ${user} stay valid until you delete them in its settings"

bash "$(dirname "${BASH_SOURCE[0]}")/forge-apply.sh"
ok "${user} pushes the promotion commits of ${repo} and runs its Renovate"
