#!/usr/bin/env bash
# Break-glass operator grant, per ADR-0304: the first operator, or any operator while the admin console is down.
# It writes the claim and group:operator together, and finds the Kratos identity by email. Idempotent.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

NS="${NS:-platform}"
KCTX="${KUBE_CONTEXT:-}"
ctx_args=()
[ -n "$KCTX" ] && ctx_args=(--context "$KCTX")

email="${1:-}"
action="write"
[ "${2:-}" = "--revoke" ] && action="delete"
if [ -z "$email" ]; then
  echo "usage: mise run ops:grant -- <email> [--revoke]" >&2
  exit 2
fi

k() { kubectl "${ctx_args[@]}" -n "$NS" "$@"; }

# Arm the cleanup before anything runs in the background. Otherwise a failure in between, such as the secret read, leaves a port-forward behind.
kpf=""
opf=""
trap 'kill "$kpf" "$opf" 2>/dev/null || true' EXIT

# A previous run whose cleanup trap did not fire leaves port-forwards on 4434 and 18080.
reap_stale_port_forwards() {
  pkill -f 'kubectl.*port-forward svc/(ory-kratos-admin|openfga)' 2>/dev/null || true
}

# Local 18080, not 8080: the local edge maps host 8080, so a bind on 8080 would collide with it.
open_admin_apis() {
  k port-forward svc/ory-kratos-admin 4434:80 >/dev/null &
  kpf=$!
  sk="$(k get secret openfga-creds -o jsonpath='{.data.preshared_key}' | base64 -d)"
  k port-forward svc/openfga 18080:8080 >/dev/null &
  opf=$!
  sleep 4
}

identity_id_for() {
  curl -fsS "http://localhost:4434/admin/identities?credentials_identifier=${1}" |
    jq -r '.[0].id // ""'
}

# The coarse ops gate checks the metadata_public.operator claim, not OpenFGA, and it is always enforced, per ADR-0306.
# group:operator without the flag grants nothing, and the gate also requires AAL2. The whole object is written back,
# because the edge reads the org and roles from the same metadata.
set_operator_flag() {
  local meta
  meta="$(curl -fsS "http://localhost:4434/admin/identities/${1}" | jq -c --argjson v "${2}" '(.metadata_public // {}) + {operator: $v}')"
  curl -fsS -X PATCH "http://localhost:4434/admin/identities/${1}" \
    -H 'Content-Type: application/json' \
    -d "[{\"op\":\"add\",\"path\":\"/metadata_public\",\"value\":${meta}}]" >/dev/null
}

# By name, the same discovery that the services use.
platform_store_id() {
  fga store list --api-url "$API" --api-token "$sk" |
    jq -r '.stores[] | select(.name=="platform") | .id' | head -n1
}

# Idempotent: a write of an existing tuple or a delete of an absent one is a no-op. OpenFGA returns an error for both,
# so only those two messages are accepted.
apply_membership() {
  local out rc
  set +e
  out="$(fga tuple "$action" --store-id "$1" --api-url "$API" --api-token "$sk" \
    "user:${2}" member group:operator 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    return 0
  fi
  if echo "$out" | grep -qE 'already existed|did not exist'; then
    return 0
  fi
  echo "$out" >&2
  return 1
}

API="http://localhost:18080"
reap_stale_port_forwards
open_admin_apis

id="$(identity_id_for "$email")"
if [ -z "$id" ]; then
  echo "no Kratos identity for ${email}. They must register first" >&2
  exit 1
fi

op_val=true
[ "$action" = "delete" ] && op_val=false
set_operator_flag "$id" "$op_val"

sid="$(platform_store_id)"
if [ -z "$sid" ]; then
  echo "no OpenFGA store 'platform'. Check that the seed Job has run" >&2
  exit 1
fi
apply_membership "$sid" "$id"

verb="granted"
[ "$action" = "delete" ] && verb="revoked"
ok "${verb} operator flag and group:operator for ${email}, user:${id}"
[ "$action" = "write" ] && detail "→ they must have AAL2, a second factor, enrolled. Log in again if already signed in."
