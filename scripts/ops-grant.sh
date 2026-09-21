#!/usr/bin/env bash
# Grant a human the ops tier by adding them to group:operator in OpenFGA, resolving the Kratos identity by email (ADR-0304, ADR-0306). Idempotent.
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

# Cleanup must be armed before backgrounding anything, or a failure in between
# (e.g. the secret read) would orphan a port-forward.
kpf=""
opf=""
trap 'kill "$kpf" "$opf" 2>/dev/null || true' EXIT

# A prior run whose cleanup trap did not fire leaves port-forwards holding 4434/18080.
reap_stale_port_forwards() {
  pkill -f 'kubectl.*port-forward svc/(ory-kratos-admin|openfga)' 2>/dev/null || true
}

# Local 18080, not 8080: the local edge maps host 8080, so binding 8080 would collide with it.
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

# The coarse ops gate is a claim check on the `operator` trait, not an OpenFGA call, and is always enforced
# (ADR-0306). group:operator without the trait grants nothing, and the gate additionally requires AAL2.
set_operator_trait() {
  curl -fsS -X PATCH "http://localhost:4434/admin/identities/${1}" \
    -H 'Content-Type: application/json' \
    -d "[{\"op\":\"add\",\"path\":\"/traits/operator\",\"value\":${2}}]" >/dev/null
}

# By name, the same discovery the services do.
platform_store_id() {
  fga store list --api-url "$API" --api-token "$sk" |
    jq -r '.stores[] | select(.name=="platform") | .id' | head -n1
}

# Idempotent: writing an existing tuple or deleting an absent one is a no-op. OpenFGA errors on both, so those
# two messages are tolerated and nothing else is.
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
  echo "no Kratos identity for ${email} — they must register first" >&2
  exit 1
fi

op_val=true
[ "$action" = "delete" ] && op_val=false
set_operator_trait "$id" "$op_val"

sid="$(platform_store_id)"
if [ -z "$sid" ]; then
  echo "no OpenFGA store 'platform' — has the seed Job run?" >&2
  exit 1
fi
apply_membership "$sid" "$id"

verb="granted"
[ "$action" = "delete" ] && verb="revoked"
ok "${verb} operator trait + group:operator for ${email} (user:${id})"
[ "$action" = "write" ] && detail "→ they must have AAL2 (a second factor) enrolled; re-login if already signed in."
