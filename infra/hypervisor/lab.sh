#!/usr/bin/env bash
# The QEMU copy of the hypervisor on a workstation, per ADR-0208. It installs the host with nixos-anywhere, and it
# bootstraps the Talos nodes from the patches of infra/talos/. It proves that a deploy that closes SSH rolls back by
# itself, and that a deploy for the next boot takes effect on reboot. It needs KVM and 16 GB of free memory.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
mode=online
case "$*" in
install) ;;
"install --offline") mode=offline ;;
*)
  echo "usage: just hypervisor-test install [--offline]" >&2
  exit 2
  ;;
esac

# The cap holds QEMU and every tool of the run, so a leak stops the lab and not the workstation.
if [ -z "${LAB_IN_SCOPE:-}" ]; then
  exec systemd-run --user --scope --quiet --collect -p MemoryMax="${LAB_MEMORY_MAX:-18G}" -p MemorySwapMax=0 \
    env LAB_IN_SCOPE=1 bash "$0" "$@"
fi

work="${LAB_DIR:-$HOME/.cache/hypervisor-lab}"
port="${LAB_PORT:-2222}"
mkdir -p "$work"
exec 9>"$work/lock"
flock -n 9 || {
  echo "FAIL: another lab run holds ${work}/lock" >&2
  exit 1
}
schematic="$(nix eval --raw --file infra/hypervisor/settings.nix talos.url | cut -d/ -f5)"
version="$(nix eval --raw --file infra/hypervisor/settings.nix talos.url | cut -d/ -f6)"
# shellcheck source=infra/hypervisor/lab-cache.sh
source infra/hypervisor/lab-cache.sh
key="$work/id_ed25519"

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
step_name=""
step_start=0
timings=()
end_step() {
  [ -n "$step_name" ] || return 0
  timings+=("$(printf '%6ss  %s' "$((SECONDS - step_start))" "$step_name")")
  printf 'TIME: %ss\n' "$((SECONDS - step_start))"
  step_name=""
}
step() {
  end_step
  step_name="$*"
  step_start=$SECONDS
  printf '\n== %s\n' "$*"
}
pass() { printf 'PASS: %s\n' "$*"; }
cleanup() {
  local status=$?
  end_step
  [ -z "${guard:-}" ] || kill "$guard" 2>/dev/null || true
  if [ -f "$work/qemu.pid" ]; then
    local pid
    pid="$(cat "$work/qemu.pid")"
    kill "$pid" 2>/dev/null || true
    # The next run reuses the port and the disk path, so this run ends only after QEMU has gone.
    for _ in $(seq 50); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.2
    done
  fi
  rm -f "$work/qemu.pid"
  # Each run starts from an empty disk, so the old one only holds space. LAB_KEEP_DISK keeps it to debug a failure.
  [ -n "${LAB_KEEP_DISK:-}" ] || rm -f "$work/disk.qcow2"
  registry_stop
  [ "${#timings[@]}" -eq 0 ] || printf '\nStep times:\n%s\n%6ss  total\n' "$(printf '%s\n' "${timings[@]}")" "$SECONDS"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 143' INT TERM
deploy_opts=(--skip-checks --fast-connection true
  --ssh-opts "-p $port -i $key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null")
nodes=(10.0.10.11 10.0.10.12 10.0.10.13)

rm -f "$work/disk.qcow2"
check_resources
memory_guard "$$" 9>&- &
guard=$!

registry_start
if [ "$mode" = online ]; then
  step "filling the local cache"
  prepare_cache
else
  # Nix reads only the local store, so a pass proves that the cache is enough.
  export NIX_CONFIG="${NIX_CONFIG:-}"$'\nsubstitute = false\n'
fi
step "checking the local cache"
verify_cache
install -m 0600 "$(nix build --no-link --print-out-paths .#hypervisor-lab-key)" "$key"
iso="$(echo "$(nix build --no-link --print-out-paths .#hypervisor-lab-installer)"/iso/*.iso)"
system="$(nix build --no-link --print-out-paths .#nixosConfigurations.hypervisor-lab.config.system.build.toplevel)"
disko="$(nix build --no-link --print-out-paths .#nixosConfigurations.hypervisor-lab.config.system.build.diskoScript)"

step "booting the installer with an empty disk"
rm -f "$work/disk.qcow2"
qemu-img create -q -f qcow2 "$work/disk.qcow2" 80G
# Each connection of a node to the mirror starts its own socat. A chardev target would serve only one.
netdev="user,id=n0,hostfwd=tcp:127.0.0.1:$port-:22,guestfwd=tcp:${registry_guest}-cmd:socat - TCP:127.0.0.1:${registry_port}"
[ "$mode" = online ] || netdev+=",restrict=on"
qemu-system-x86_64 -enable-kvm -cpu host -smp 8 -m "${LAB_VM_MEMORY_MB:-14336}" -display none -daemonize \
  -pidfile "$work/qemu.pid" -serial "file:$work/serial.log" \
  -drive "file=$work/disk.qcow2,if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap" -cdrom "$iso" -boot once=d \
  -netdev "$netdev" -device virtio-net-pci,netdev=n0 9>&-
retry 120 remote true

step "installing the host with nixos-anywhere and disko"
nixos-anywhere --store-paths "$disko" "$system" --no-substitute-on-destination \
  --target-host root@127.0.0.1 -p "$port" -i "$key" \
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
  infra/talos/patches/controlplane.yaml root@127.0.0.1:/root/talos/
write_mirror_patch "$work/mirrors.yaml"
# The nodes take their time from the host, so the lab needs no public time server.
yq '.machine.time.servers = ["10.0.10.1"]' infra/talos/patches/common.yaml >"$work/common.yaml"
scp -P "$port" -i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  "$work/mirrors.yaml" "$work/common.yaml" root@127.0.0.1:/root/talos/
remote "cd /root/talos && printf 'machine:\n  install:\n    image: factory.talos.dev/metal-installer/%s:%s\n' $schematic $version > install.yaml &&
  talosctl gen config lab https://10.0.10.11:6443 --talos-version v1.13 --force \
    --config-patch @common.yaml --config-patch @install.yaml --config-patch @mirrors.yaml \
    --config-patch-control-plane @controlplane.yaml >/dev/null"
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
