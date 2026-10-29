#!/usr/bin/env bash
# A Debian VM beside the nodes on the hypervisor, per ADR-0200: the forge or the CI runner of ADR-0102.
# `create` writes Debian over the VM's disk and boots it with cloud-init. `resize` applies the sizes in hypervisor.env.
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
source "$here/lib.sh"

usage() { fail "usage: vm.sh <create|resize> <forge|runner>"; }
[ "$#" -eq 2 ] || usage
verb="$1" role="$2"

slug="$(awk '$1 == "project_slug:" {print $2; exit}' .copier-answers.yml 2>/dev/null)"
[ -n "$slug" ] || fail "no project_slug in .copier-answers.yml"
# The address comes from the file of the machine's own kit, so the VM and its setup cannot name two addresses.
case "$role" in
forge)
  # shellcheck source=../forge-host/forge.env
  source "$here/../forge-host/forge.env"
  address="${FORGE_SSH#*@}" cores="$FORGE_CORES" memory="$FORGE_MEMORY" disk="$FORGE_DISK"
  ;;
runner)
  # shellcheck source=../runner/runner.env
  source "$here/../runner/runner.env"
  address="$RUNNER_ADDRESS" cores="$RUNNER_CORES" memory="$RUNNER_MEMORY" disk="$RUNNER_DISK"
  ;;
*) usage ;;
esac
id="$(vm_id "$address")"
name="${slug}-${ENVIRONMENT}-${role}"
image="/root/$(basename "$DEBIAN_IMAGE_URL")"

wait_ssh() {
  remote "for _ in \$(seq 1 60); do nc -z -w2 ${address} 22 2>/dev/null && exit 0; sleep 5; done; exit 1" ||
    fail "no SSH on ${address}. Inspect it with 'qm terminal ${id}' on the host"
}

case "$verb" in
create)
  step "defining ${name}, VM ${id}, and writing Debian onto it"
  # Written over the disk the VM already boots from. `qm importdisk` would leave a second disk attached to nothing.
  # cloud-init runs on the first boot only, so its drive is attached before the VM starts.
  remote "set -e
    [ -f ${image} ] || curl -fsSL -o ${image} '${DEBIAN_IMAGE_URL}'
    qm status ${id} >/dev/null 2>&1 || qm create ${id} --name ${name} --cores ${cores} --memory ${memory} \
      --cpu host --net0 virtio=$(vm_mac "$address"),bridge=${PRIVATE_BRIDGE} --scsihw virtio-scsi-single \
      --scsi0 ${STORAGE}:${disk} --boot order=scsi0 --ostype l26 --agent enabled=1 --onboot 1
    qm stop ${id} 2>/dev/null || true
    while qm status ${id} | grep -q running; do sleep 2; done
    qemu-img convert -f qcow2 -O raw ${image} /dev/${VOLUME_GROUP}/vm-${id}-disk-0
    qm set ${id} --ide2 ${STORAGE}:cloudinit >/dev/null 2>&1 || true
    qm set ${id} --ciuser root --sshkeys /root/.ssh/authorized_keys --ipconfig0 ip=dhcp \
      --nameserver ${PRIVATE_GATEWAY} --serial0 socket --vga serial0 >/dev/null
    qm start ${id}"
  wait_ssh
  ok "${name} is up at ${address}"
  ;;

resize)
  step "applying ${cores} cores, ${memory}MB, and ${disk}GB to ${name}, and rebooting it"
  # A disk only grows. The guest's growroot extends its filesystem at the next boot.
  remote "qm resize ${id} scsi0 ${disk}G 2>/dev/null; qm set ${id} --cores ${cores} --memory ${memory} >/dev/null && qm reboot ${id}"
  wait_ssh
  ok "${name} is back"
  ;;

*) usage ;;
esac
