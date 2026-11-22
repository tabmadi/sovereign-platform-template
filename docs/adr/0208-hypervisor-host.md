# ADR-0208: Hypervisor host

- **Status:** Accepted
- **Decides:** In the hypervisor mode, the host runs NixOS, and its VMs, network, install, and deploy are one NixOS configuration in `infra/hypervisor/`.

## Context

In the hypervisor mode of [ADR-0200](0200-cluster-topology.md), the project runs its own machine, and the Talos nodes, the forge, and the runner are VMs on it. The host ran Proxmox VE, which a person installed by hand from the rescue system of the provider. Bash scripts then wrote the bridges, the DHCP reservations, the NAT rules, and the VMs over SSH.

The rest of this repo is pinned by `flake.lock` and checked by `just ci`, per [ADR-0100](0100-toolchain.md). The host was the one machine outside it.

The decision drivers:

1. **Reproducible host.** A rebuilt host is the same host, from files in git.
2. **Safe change.** A change to the host that cuts the network rolls back with no action from a person, who may have no console.
3. **Scripted install.** The install from the rescue system is a command, not a list of steps.
4. **Talos nodes.** The host runs the Talos image of [ADR-0200](0200-cluster-topology.md) as VMs, with the address of the inventory.
5. **Testable on a laptop.** A copy of the host runs on a workstation, with the same install and the same deploy.
6. **Small surface.** Few parts that a person must learn and patch.

## Considered options

| Option | 1 Reproducible | 2 Safe change | 3 Scripted install | 4 Talos nodes | 5 Testable on a laptop | 6 Small surface | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Proxmox VE with bash scripts | No. The packages of the host change with each `apt` run | No. A broken NAT rule needs the console | No. A person installs Proxmox | Yes | No. Proxmox in a VM is a second install by hand | No. A web UI, a cluster file system, and its own API, for one machine | Rejected on drivers 1, 2, 3, and 5 |
| Incus on Debian | Partly. The VMs are declared, the host is not | No | No | Yes | Partly | Yes | Rejected on drivers 1 and 2 |
| NixOS with libvirt | Yes | Yes, with deploy-rs | Yes, with nixos-anywhere | Yes | Yes | No. libvirt is a daemon with its own XML and its own state beside NixOS | Rejected on driver 6. It is the next candidate when a VM needs live migration |
| NixOS with microvm.nix | Yes | Yes | Yes | No. microvm.nix builds NixOS guests, and a Talos node is not one | Yes | Yes | Rejected on driver 4 |
| **NixOS, with each VM a QEMU unit of systemd** | **Yes. `flake.lock` pins the host, its QEMU, and its images** | **Yes. deploy-rs rolls back a deploy that cuts SSH** | **Yes. nixos-anywhere with disko installs from the rescue system** | **Yes. Each node boots the image of the Image Factory schematic** | **Yes. `just hypervisor-test install` runs the copy** | **Yes. QEMU, dnsmasq, and nftables, as NixOS options** | **Chosen** |

Sources:

- nixos-anywhere installs NixOS over SSH and partitions the disk with disko: [nixos-anywhere README](https://github.com/nix-community/nixos-anywhere).
- deploy-rs rolls back a deploy that loses the SSH connection: [deploy-rs README](https://github.com/serokell/deploy-rs).
- microvm.nix builds NixOS guests: [microvm.nix README](https://github.com/microvm-nix/microvm.nix).
- Talos boots from the raw image of the Image Factory and takes its machine config over its API: [Talos, Image Factory](https://docs.siderolabs.com/talos/latest/learn-more/image-factory).

### The result of the spike

The spike ran the QEMU copy of `just hypervisor-test install` on a laptop with nested KVM. No run on real hardware exists.

| Criterion | Result |
| --- | --- |
| nixos-anywhere installs the host, and the host boots three Talos nodes from the machine config of ADR-0200 | Pass. The nodes took the patches of `infra/talos/` and formed one etcd cluster of three |
| The node VMs get the addresses of the inventory | Pass. dnsmasq gives each MAC its address |
| A deploy rolls back by itself | Pass, after a first deploy that changes nothing. Without it the rollback fails, and the host stays on the broken config |
| A release upgrade is a deploy for the next boot and a reboot | Pass. NixOS 26.05 moved to 26.11, and the nodes came back |
| A QEMU copy of the host runs the same test on a laptop | Pass |

The four questions of the spike:

| Question | Answer |
| --- | --- |
| Can a NixOS host run the Talos nodes as VMs | Yes, as QEMU units with KVM. libvirt is not needed |
| Can nixos-anywhere with disko install the host | Yes, from any system that accepts the admin key over SSH |
| Can the forge host and the runner host move to NixOS too | They run as Debian VMs on the NixOS host, with cloud-init. Their own kits set them up over SSH, as before |
| Which parts become NixOS modules in tabnix | The server base and the deploy, which the host imports. The VM units stay here, because only this repo runs Talos |

## Decision

### The host

`infra/hypervisor/host.nix` is the host. It imports the tabnix module `server`, so SSH takes keys only. The flake deploys it through the tabnix module `deploy`, so a deploy rolls back by itself. `infra/hypervisor/settings.nix` holds every fact of the machine: its address, its disk, its uplink, the public addresses, the private network, the sizes, and the images.

`infra/hypervisor/vms.nix` runs each VM as a systemd unit of QEMU:

| VM | Image | Address from |
| --- | --- | --- |
| Each Talos node | The raw Talos image of the Image Factory schematic of `infra/talos/` | `infra/talos/inventory/<environment>/nodes.yml` |
| The forge, where `infra/forge-host/` exists | The Debian cloud image, with the admin keys from cloud-init | `FORGE_SSH` in `infra/forge-host/forge.env` |
| The runner, where `infra/runner/` exists | The Debian cloud image | `RUNNER_ADDRESS` in `infra/runner/runner.env` |

A VM writes its disk from its image on its first start only. A later start, and a deploy of the host, keep the disk. The MAC of a VM holds its address in hex, so dnsmasq gives a rebuilt VM the same address.

### The network

| Rule | Why |
| --- | --- |
| DNAT of the public edge to the Traefik node ports of the first node | The cluster edge, per [ADR-0305](0305-edge-auth-and-traffic-policy.md) |
| DNAT of the public forge on 80, 443, and 2222 | The forge, whose SSH stays off the host's own 22 |
| A masquerade toward each DNAT target | The hairpin: a VM that reaches a public address arrives with a private source |
| SNAT of port 25 to the public mail address | Mail leaves on one address whose PTR matches the HELO name, per [ADR-0307](0307-outbound-email.md) |
| A masquerade of the private network to the uplink | The VMs reach the internet as the host |

### The install and the deploy

1. `just hypervisor-install` installs the host from the rescue system with nixos-anywhere. It erases the disk of `settings.nix`.
2. `just hypervisor-deploy` runs once, and changes nothing. A rollback of deploy-rs returns only to a generation that deploy-rs made.
3. Each later change is `just hypervisor-deploy`. The host waits for a new SSH connection, and rolls back without one.
4. A NixOS release upgrade is `just hypervisor-deploy-boot`: a deploy for the next boot, then a reboot.

deploy-rs can report a deploy as confirmed after the host has rolled back, once SSH is back. The generation of the host is the proof of a rollback, not the exit code.

### The Talos config

`talosctl` 1.14 writes the new config documents, and the v1alpha1 patches of `infra/talos/` conflict with them. So `talosctl gen config` takes `--talos-version v1.13`, per `infra/talos/README.md`. The nodes of the QEMU copy run Talos 1.14.6 and accept that form.

**The host can report its own pressure.** With `hostMetrics.enable`, a Prometheus node exporter binds the private bridge address and serves CPU, memory, and I/O pressure, and disk latency. It beats `Alloy host metrics` and `the OTel hostmetrics receiver` because it adds one small service to the host and no collector pipeline.

## Consequences

The host runs no web UI. A person reads its state with SSH, `systemctl`, and the console log of each VM in `/var/lib/vms/`.

A VM cannot move to another host while it runs.

The lab is the QEMU copy of the host. `just hypervisor-test install` tests it from an empty disk, and needs KVM and about 14 GB of memory. It is not a step of `just ci`.

The lab reads a local cache: the Nix store of the workstation under GC roots, and a private zot that mirrors the node images. Only the lab nodes use this mirror, so a real cluster does not change. After one pass, `just hypervisor-test install --offline` runs with no internet and the same pins, per the [lab guide](../guide/hypervisor-lab.md).

The `disko` input is in `flake.nix` in every mode. A project in another mode never fetches it.

## Rules

- The hypervisor host is the NixOS configuration `hypervisor` of `infra/hypervisor/`. No step on the host is by hand.
- Every VM of the host is an entry of `hypervisor.vms`, and its address comes from the inventory or from the kit of its role.
- The first deploy after `just hypervisor-install` changes nothing.
- A NixOS release upgrade of the host is `just hypervisor-deploy-boot`, never a live switch.
- `just hypervisor-test install` passes before a deploy that changes `vms.nix`, `host.nix`, or the images.
- Each lab run stays inside a memory cap, and stops before the workstation runs short of memory.
