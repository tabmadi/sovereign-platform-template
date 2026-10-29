# The hypervisor

The machine that the nodes run on, where the project runs its own hardware. This is the third provisioning mode of [ADR-0200](../../docs/adr/0200-cluster-topology.md). No provider API sits between the repository and the metal, so the node lifecycle is a script against one Proxmox VE host.

This directory exists in a project whose `provisioning` answer is `hypervisor`, per [modes.md](../../docs/reference/modes.md).

**No file here holds a secret.** Addresses and bridges are facts about a machine. A reader still needs the host's root key to reach it.

## Where each fact lives

| Fact | File |
| --- | --- |
| the host, its storage, its bridges, its public addresses, and the VM sizes | `hypervisor.env` |
| the node names and private addresses | `infra/talos/inventory/<env>/nodes.yml` |
| the forge and runner addresses | `infra/forge-host/forge.env` and `infra/runner/runner.env` |

The scripts derive the rest. A VM's id and MAC follow from its private address: `10.0.10.11` is VM 111 with MAC `0e:00:00:00:10:11`. So DHCP gives a rebuilt VM the address that the inventory names. The last two octets of each address are below 100.

## Files

| Script | Does |
| --- | --- |
| `host.sh render <dir>` | writes the two bridges, the DHCP reservations, and the NAT rules into a directory for review |
| `host.sh install` | installs those files on the host, and tests the NAT rules before it loads them |
| `nodes.sh create`, `reimage`, `destroy` | defines the node VMs, writes the Talos image over their disks, or removes them |
| `vm.sh create`, `resize` with `forge` or `runner` | writes Debian onto a VM beside the nodes, or applies the sizes in `hypervisor.env` |

## Building the host

The Proxmox VE install itself is not scripted. It is done once in each host's lifetime, through the provider's rescue system.

1. Install Proxmox VE, `dnsmasq`, and `iptables-persistent` on the host.
2. Put the raw Talos image that `infra/talos/` targets at `/root/talos-<version>.raw`.
3. Set the values in `hypervisor.env`, and private addresses in the inventory.
4. Run `bash infra/hypervisor/host.sh render /tmp/host`, and review the files.
5. Run `bash infra/hypervisor/host.sh install`.
6. Run `bash infra/hypervisor/nodes.sh create`, then `bash infra/hypervisor/nodes.sh reimage`.
7. Apply each node's machine config and bootstrap the cluster, per [ADR-0200](../../docs/adr/0200-cluster-topology.md).
8. With the `forgejo` forge, build the forge and the runner, per `infra/forge-host/` and `infra/runner/`.

The scripts read the inventory with `yq`, so run them as `mise exec -- bash infra/hypervisor/<script>`.

## What the NAT does

| Rule | Why |
| --- | --- |
| DNAT of `PUBLIC_EDGE` to Traefik's node ports | the cluster edge, per [ADR-0305](../../docs/adr/0305-edge-auth-and-traffic-policy.md) |
| DNAT of `PUBLIC_FORGE` on 80, 443, and 2222 | the forge, whose SSH transport stays off the host's own 22 |
| MASQUERADE toward each DNAT target | the hairpin: a VM that reaches a public address of this network arrives with a private source, and the reply would skip the host |
| SNAT of port 25 to `PUBLIC_MAIL` | mail leaves on one address whose PTR matches the HELO name, per [ADR-0307](../../docs/adr/0307-outbound-email.md) |
| MASQUERADE of everything else | the private network reaches the internet as the host |

A pod that calls the public host of the edge reaches it only through the hairpin. Where that fails, the service chart's `hostAliases` maps the host to the Traefik Service.
