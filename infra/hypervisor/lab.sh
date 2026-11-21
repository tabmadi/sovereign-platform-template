#!/usr/bin/env bash
# The QEMU copy of the hypervisor on a workstation, per ADR-0208. It installs the host with nixos-anywhere, and it
# bootstraps the Talos nodes from the patches of infra/talos/. It proves that a deploy that closes SSH rolls back by
# itself, and that a deploy for the next boot takes effect on reboot. It needs KVM, the internet, and 14 GB of memory.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

work="${LAB_DIR:-$HOME/.cache/hypervisor-lab}"
port="${LAB_PORT:-2222}"
mkdir -p "$work"
key="$work/id_ed25519"
install -m 0600 "$(nix build --no-link --print-out-paths .#hypervisor-lab-key)" "$key"

ssh_opts=(-p "$port" -i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR)
remote() { ssh "${ssh_opts[@]}" root@127.0.0.1 "$@"; }
guest() { # <address> <command>
  ssh -i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR \
    -o ProxyCommand="ssh ${ssh_opts[*]} -W %h:%p root@127.0.0.1" "root@$1" "$2"
}
retry() { # <tries> <command...>
  local tries="$1"
  shift
  for _ in $(seq "$tries"); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 5
  done
  "$@"
}
step() { printf '\n== %s\n' "$*"; }
pass() { printf 'PASS: %s\n' "$*"; }
deploy_opts=(--skip-checks --ssh-opts "-p $port -i $key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null")
nodes=(10.0.10.11 10.0.10.12 10.0.10.13)

step "building the installer and the host"
iso="$(echo "$(nix build --no-link --print-out-paths .#hypervisor-lab-installer)"/iso/*.iso)"
nix build --no-link .#nixosConfigurations.hypervisor-lab.config.system.build.toplevel

step "booting the installer with an empty disk"
rm -f "$work/disk.qcow2"
qemu-img create -q -f qcow2 "$work/disk.qcow2" 80G
qemu-system-x86_64 -enable-kvm -cpu host -smp 8 -m 14336 -display none -daemonize \
  -pidfile "$work/qemu.pid" -serial "file:$work/serial.log" \
  -drive "file=$work/disk.qcow2,if=virtio,format=qcow2" -cdrom "$iso" -boot once=d \
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$port-:22" -device virtio-net-pci,netdev=n0
trap 'kill "$(cat "$work/qemu.pid")" 2>/dev/null || true' EXIT
retry 120 remote true

step "installing the host with nixos-anywhere and disko"
nixos-anywhere --flake .#hypervisor-lab --target-host root@127.0.0.1 -p "$port" -i "$key" \
  --ssh-option StrictHostKeyChecking=no --ssh-option UserKnownHostsFile=/dev/null
sleep 30
retry 120 remote true
[ "$(remote hostname)" = hypervisor-lab ]
pass "nixos-anywhere installed the host, and it booted from its own disk"

step "checking the VMs at the addresses of the inventory"
for a in "${nodes[@]}"; do retry 120 remote talosctl -n "$a" -e "$a" get disks --insecure; done
retry 120 guest 10.0.10.30 true
retry 120 guest 10.0.10.40 true
pass "the host runs three Talos nodes, the forge, and the runner at their addresses"

step "bootstrapping the cluster from the patches of infra/talos/"
remote mkdir -p /root/talos
scp -P "$port" -i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  infra/talos/patches/common.yaml infra/talos/patches/controlplane.yaml root@127.0.0.1:/root/talos/
schematic="$(nix eval --raw --file infra/hypervisor/settings.nix talos.url | cut -d/ -f5)"
version="$(nix eval --raw --file infra/hypervisor/settings.nix talos.url | cut -d/ -f6)"
remote "cd /root/talos && printf 'machine:\n  install:\n    image: factory.talos.dev/metal-installer/%s:%s\n' $schematic $version > install.yaml &&
  talosctl gen config lab https://10.0.10.11:6443 --talos-version v1.13 --force \
    --config-patch @common.yaml --config-patch @install.yaml --config-patch-control-plane @controlplane.yaml >/dev/null"
for a in "${nodes[@]}"; do
  remote "cd /root/talos && talosctl apply-config --insecure -n $a -e $a -f controlplane.yaml --config-patch '{\"cluster\":{\"etcd\":{\"extraArgs\":{\"listen-metrics-urls\":\"http://$a:2381\"}}}}'"
done
retry 120 remote "cd /root/talos && talosctl --talosconfig talosconfig -n 10.0.10.11 -e 10.0.10.11 bootstrap"
retry 240 remote "cd /root/talos && talosctl --talosconfig talosconfig -n 10.0.10.11 -e 10.0.10.11 etcd members | grep -c lab-cp | grep -qx 3"
pass "the nodes took the machine config of ADR-0200 and formed one etcd cluster of three"

step "deploying the installed config once, so that a rollback has a generation of deploy-rs to return to"
deploy "${deploy_opts[@]}" .#hypervisor-lab
pass "the first deploy changed nothing"

step "deploying a config that closes SSH"
before="$(remote readlink /run/current-system)"
# deploy-rs can report the deploy as confirmed after the host has rolled back. The host's generation is the proof.
deploy "${deploy_opts[@]}" .#hypervisor-lab-broken >"$work/broken.log" 2>&1 || true
grep -q "Activation succeeded" "$work/broken.log" || {
  echo "FAIL: the broken config never activated" >&2
  exit 1
}
grep -q "re-activate the last generation" "$work/broken.log" || {
  echo "FAIL: the host did not roll back" >&2
  exit 1
}
retry 60 remote true
[ "$(remote readlink /run/current-system)" = "$before" ]
pass "a deploy that closed SSH rolled back by itself, and SSH came back with no action"

step "deploying a change for the next boot"
deploy "${deploy_opts[@]}" --boot .#hypervisor-lab-next
remote test ! -e /etc/lab-generation
remote systemctl reboot || true
sleep 30
retry 120 remote true
[ "$(remote cat /etc/lab-generation)" = next ]
pass "a deploy for the next boot took effect after the reboot"

step "checking the cluster after the reboot of the host"
retry 240 remote "cd /root/talos && talosctl --talosconfig talosconfig -n 10.0.10.11 -e 10.0.10.11 etcd members | grep -c lab-cp | grep -qx 3"
pass "the nodes kept their config and their data, and the cluster came back"
