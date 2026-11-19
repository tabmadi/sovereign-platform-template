# The hypervisor

The machine that the nodes run on, where the project runs its own hardware. This is the third provisioning mode of [ADR-0200](../../docs/adr/0200-cluster-topology.md). The host runs NixOS, and this directory is its whole configuration, per [ADR-0208](../../docs/adr/0208-hypervisor-host.md).

This directory exists in a project whose `provisioning` answer is `hypervisor`, per [modes.md](../../docs/reference/modes.md).

**No file here holds a secret.** Addresses and disks are facts about a machine. A reader still needs an admin key to reach it.

## Where each fact lives

| Fact | File |
| --- | --- |
| the host, its disk, its uplink, its public addresses, the private network, the VM sizes, and the images | `settings.nix` |
| the node names and private addresses | `infra/talos/inventory/<env>/nodes.yml` |
| the forge and runner addresses | `infra/forge-host/forge.env` and `infra/runner/runner.env` |

## Files

| File | Holds |
| --- | --- |
| `host.nix` | The host: the server base of tabnix, the uplink, and the VMs from the inventory and the kits |
| `vms.nix` | The VMs as QEMU units, the private bridge, DHCP, and the NAT rules |
| `disk.nix` | The disk layout that disko writes at the install |
| `flake-module.nix` | The host, its deploy, and the QEMU copy, as outputs of `flake.nix` |
| `lab.sh` | The QEMU copy of the host, which `just hypervisor-lab` runs |

## Building the host

1. Set the values in `settings.nix`, and the private addresses of the nodes in the inventory.
2. Run `just hypervisor-lab` on a workstation with KVM. It installs a QEMU copy of the host and tests it.
3. Boot the machine into a rescue system that accepts your SSH key as root.
4. Run `just hypervisor-install`. It erases the disk of `settings.nix` and installs the host.
5. Run `just hypervisor-deploy` once. It changes nothing, but a later rollback needs a generation that deploy-rs made.
6. Apply each node's machine config and bootstrap the cluster, per [ADR-0200](../../docs/adr/0200-cluster-topology.md).
7. With the `forgejo` forge, set up the forge and the runner, per `infra/forge-host/` and `infra/runner/`.

## Changing the host

| Change | Command |
| --- | --- |
| Any change to `settings.nix`, `host.nix`, or `vms.nix` | `just hypervisor-deploy`. A deploy that cuts SSH rolls back by itself |
| A NixOS release upgrade | `just hypervisor-deploy-boot`. It deploys for the next boot, then reboots the host |
| A new node | Add it to the inventory, then `just hypervisor-deploy` |
| A node from a clean disk | `systemctl stop vm-<name>`, remove `/var/lib/vms/<name>.raw` on the host, then `systemctl start vm-<name>` |

Each VM writes its console to `/var/lib/vms/<name>.console` on the host.
