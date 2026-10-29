#!/usr/bin/env bash
# Shared by the hypervisor scripts, per ADR-0200.
# shellcheck source=../../scripts/lib/bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/bootstrap.sh"
# shellcheck source=hypervisor.env
source "$(dirname "${BASH_SOURCE[0]}")/hypervisor.env"

INVENTORY="infra/talos/inventory/${ENVIRONMENT}/nodes.yml"

remote() {
  local opts=(-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new)
  if [ -n "${SSH_KEY:-}" ]; then opts+=(-i "$SSH_KEY"); fi
  ssh "${opts[@]}" "$HYPERVISOR_SSH" "$@"
}

# The VM id and the MAC follow from the private address, so a rebuilt VM gets the same address from DHCP.
# `10.0.10.11` is VM 111 with MAC `0e:00:00:00:10:11`. The last two octets are each below 100.
vm_id() { # <address>
  echo $((100 + 10#${1##*.}))
}
vm_mac() { # <address>
  local rest="${1#*.*.}"
  printf '0e:00:00:00:%02d:%02d' "$((10#${rest%.*}))" "$((10#${rest#*.}))"
}

# One `name address` line for each node of the inventory.
nodes() {
  [ -f "$INVENTORY" ] || fail "no inventory at ${INVENTORY}"
  yq -r '.nodes | to_entries | .[] | .key + " " + .value.address' "$INVENTORY"
}
