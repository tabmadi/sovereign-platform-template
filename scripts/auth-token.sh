#!/usr/bin/env bash
# Mint a Kratos session token for a registered identity, for hitting authenticated endpoints locally (ADR-0305, ADR-0304). Requires the full tier.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

CLUSTER="${CLUSTER:-platform}"
source "$(dirname "${BASH_SOURCE[0]}")/lib/cluster.sh"
NS="platform"
k() { kubectl --context "$(cluster_ctx)" -n "$NS" "$@"; }

email="${1:?usage: mise run auth:token -- <email>}"
password="${KRATOS_PASSWORD:-}"
if [ -z "$password" ]; then
  read -rsp "password for ${email}: " password
  echo
fi

k port-forward svc/ory-kratos-public 4433:80 >/dev/null &
pf=$!
trap 'kill "$pf" 2>/dev/null || true' EXIT
sleep 3

base="http://localhost:4433"
flow="$(curl -fsS -H 'Accept: application/json' "${base}/self-service/login/api")"
action="$(printf '%s' "$flow" | jq -r '.ui.action')"
resp="$(curl -fsS -H 'Accept: application/json' -H 'Content-Type: application/json' \
  -X POST "$action" \
  -d "$(jq -n --arg id "$email" --arg pw "$password" \
    '{method:"password", identifier:$id, password:$pw}')")"

token="$(printf '%s' "$resp" | jq -r '.session_token // empty')"
if [ -z "$token" ]; then
  warn "login failed:"
  printf '%s\n' "$resp" | jq -r '.ui.messages[]?.text // .error.message // .' >&2 || true
  fail "no session token for ${email}"
fi
echo "$token"
