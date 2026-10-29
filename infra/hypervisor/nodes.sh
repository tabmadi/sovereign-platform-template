#!/usr/bin/env bash
# The node lifecycle on the hypervisor, per ADR-0200. `create` skips a VM that exists. `reimage` writes the Talos image
# over every node's disk, so the next boot is a new node and not a rejoin.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() { fail "usage: nodes.sh <create|reimage|destroy>"; }
[ "$#" -eq 1 ] || usage

mapfile -t entries < <(nodes)
[ "${#entries[@]}" -gt 0 ] || fail "${INVENTORY} names no node"

case "$1" in
create)
  step "defining ${#entries[@]} nodes on ${HYPERVISOR_SSH}"
  for entry in "${entries[@]}"; do
    read -r name address <<<"$entry"
    id="$(vm_id "$address")"
    if remote "qm status ${id}" >/dev/null 2>&1; then
      detail "${name}, VM ${id}, exists"
      continue
    fi
    remote "qm create ${id} --name ${name} --cores ${NODE_CORES} --memory ${NODE_MEMORY} --cpu host \
      --net0 virtio=$(vm_mac "$address"),bridge=${PRIVATE_BRIDGE} --scsihw virtio-scsi-single \
      --scsi0 ${STORAGE}:${NODE_DISK} --boot order=scsi0 --ostype l26 --agent enabled=1 --onboot 1"
    detail "${name}, VM ${id}, created"
  done
  ok "nodes defined. Run 'reimage' to write the Talos image"
  ;;

reimage)
  ids=()
  for entry in "${entries[@]}"; do
    read -r _ address <<<"$entry"
    ids+=("$(vm_id "$address")")
  done
  step "writing the Talos image over ${#ids[@]} node disks"
  # The image is the raw Talos release that infra/talos/ targets, placed on the host once per Talos version.
  remote "set -e
    TALOS_RAW=\$(ls /root/talos-*.raw 2>/dev/null | sort -V | tail -1)
    [ -n \"\$TALOS_RAW\" ] || { echo 'no Talos raw image in /root on the host' >&2; exit 1; }
    for id in ${ids[*]}; do qm stop \"\$id\" >/dev/null 2>&1 || true; done
    for id in ${ids[*]}; do while qm status \"\$id\" | grep -q running; do sleep 2; done; done
    for id in ${ids[*]}; do
      dd if=\"\$TALOS_RAW\" of=/dev/${VOLUME_GROUP}/vm-\${id}-disk-0 bs=4M conv=fsync status=none
      echo \"  vm \${id} reimaged\"
    done
    for id in ${ids[*]}; do qm start \"\$id\" >/dev/null 2>&1 || true; done"
  ok "nodes reimaged and starting. Each waits on the Talos API for its machine config, per ADR-0200"
  ;;

destroy)
  warn "this destroys the ${ENVIRONMENT} nodes and every volume on them"
  for entry in "${entries[@]}"; do
    read -r name address <<<"$entry"
    id="$(vm_id "$address")"
    remote "qm stop ${id} >/dev/null 2>&1 || true; qm destroy ${id} --purge" || true
    detail "${name}, VM ${id}, destroyed"
  done
  ok "nodes destroyed"
  ;;

*) usage ;;
esac
