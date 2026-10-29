#!/usr/bin/env bash
# Create or refresh the `ci` machine user that pushes promotion commits, per ADR-0102 and ADR-0201.
# It gives `ci` write access to the repository, stores a new token of `ci` as the PROMOTE_TOKEN secret, and applies branch protection.
# A rerun rotates the token. FORGE_TOKEN is an admin token. The new token goes only to the secret and is never printed.
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

step "creating a token for ${user}"
name="promote-$(date -u +%Y%m%d%H%M%S)"
new="$(curl -sS -u "${user}:${password}" -H "Content-Type: application/json" \
  --data "$(jq -n --arg n "$name" '{name: $n, scopes: ["write:repository"]}')" \
  "${url}/api/v1/users/${user}/tokens" | jq -r '.sha1 // empty')"
[[ -n "$new" ]] || fail "the forge did not return a token for ${user}"

step "giving ${user} write access to ${repo}"
code="$(api PUT "repos/${repo}/collaborators/${user}" '{"permission": "write"}')"
[[ "$code" =~ ^2 ]] || fail "the forge refused the collaborator, HTTP ${code}"

step "storing the token as the PROMOTE_TOKEN secret"
code="$(api PUT "repos/${repo}/actions/secrets/PROMOTE_TOKEN" "$(jq -n --arg d "$new" '{data: $d}')")"
[[ "$code" =~ ^2 ]] || fail "the forge refused the secret, HTTP ${code}"
detail "token ${name}. Older tokens of ${user} stay valid until you delete them in its settings"

bash "$(dirname "${BASH_SOURCE[0]}")/forge-apply.sh"
ok "${user} pushes the promotion commits of ${repo}"
