#!/usr/bin/env bash
# The etcd metric addresses of each environment match the private addresses of its inventory, per ADR-0500.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

is_private() {
  [[ "$1" =~ ^10\.[0-9]+\.[0-9]+\.[0-9]+$ || "$1" =~ ^192\.168\.[0-9]+\.[0-9]+$ || "$1" =~ ^172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+$ ]]
}

failed=0
for inventory in infra/talos/inventory/*/nodes.yml; do
  env="$(basename "$(dirname "$inventory")")"
  values="infra/gitops/platform/${env}/values.yaml"
  [ -f "$values" ] || continue
  missing="$(yq -r '.nodes | to_entries | map(select(.value.role == "controlplane" and (.value.privateAddress // "") == "")) | .[].key' "$inventory")"
  if [ -n "$missing" ]; then
    warn "${inventory}: no privateAddress on: ${missing//$'\n'/ }"
    failed=1
  fi
  want="$(yq -r '.nodes | to_entries | map(select(.value.role == "controlplane" and (.value.privateAddress // "") != "")) | .[].value.privateAddress' "$inventory" | sort)"
  got="$(yq -r '.etcdMetrics.addresses // [] | .[]' "$values" | sort)"
  while read -r address; do
    [ -z "$address" ] || is_private "$address" || {
      warn "${inventory}: ${address} is not a private address"
      failed=1
    }
  done <<<"$want"
  if [ "$want" != "$got" ]; then
    warn "${values}: etcdMetrics.addresses differs from ${inventory}"
    failed=1
  fi
done
[ "$failed" -eq 0 ] || fail "the etcd metric addresses do not match the inventory"
ok "the etcd metric addresses match the inventory"
