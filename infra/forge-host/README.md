# The forge host

Follow the [proxy guide](../../docs/guide/http-proxy.md#forgejo-runner-and-hypervisor) for a restricted network.

The machine that runs Forgejo, per [ADR-0116](../../docs/adr/0116-forge-and-pipelines.md). It is a NixOS machine beside the workload cluster, never a chart inside it. Argo CD reconciles the cluster from this forge, so a forge in the cluster could not recover a lost cluster.

This directory exists in a project whose `forge` answer is `forgejo`, per [modes.md](../../docs/reference/modes.md).

## Files

| File | Holds |
| --- | --- |
| `settings.nix` | the facts of the machine: its address, its jump host, the public name, and the public facts of the signing key |
| `forge.nix` | the NixOS configuration: Forgejo with its own ACME client, and its Postgres |
| `forge.sh` | the data steps `signing` and `seed`, run from a workstation over SSH |
| `machine.nix` | the base of the forge and the runner: the server base of tabkit, the disk image, and DHCP |
| `guest.nix` | builds the forge and the runner, for this kit and for the hypervisor |
| `flake-module.nix` | the `forge` and `runner` configurations, their deploy, their disk images, and the `forge-runner` check |
| `test.nix` | the `forge-runner` check: both machines boot, and the runner registers with the forge |
| `lib.sh` | the SSH helper that `infra/runner/` also uses |

`flake.lock` pins Forgejo and every other package of the machine. A release is a flake update, not a value here.

## Building the forge

Each step is safe to run again.

1. Start the VM. On the project's own hypervisor, the host boots it from its disk image, per `infra/hypervisor/`. Elsewhere, run `just forge-image` and start a VM from `forge.img`.
2. Point `domain` at the machine's public address in DNS, per [ADR-0206](../../docs/adr/0206-cluster-networking.md). Forgejo then gets its certificate from ACME.
3. Run `just secrets-gpg` once. It makes the signing keys of the forge and of `ci`, per [ADR-0116](../../docs/adr/0116-forge-and-pipelines.md). Then run `just forge-signing` to import the forge key.
4. Set `signing` in `settings.nix` to the values that `forge-signing` printed. Then run `just forge-deploy`.
5. Run `just forge-seed`.
6. Run `just forge-ci-user`. It uploads the public key of `ci`. Branch protection then requires signed commits.
7. Register the tokens that `seed` leaves in `/root/.forgejo-*-token`, per the [credential register](../../docs/reference/credential-register.md).

`seed` creates the break-glass admin, the `ci` and `argocd` machine users, the repository under `org`, and the `PROMOTE_TOKEN` secret. With `mirrorUrl` set, it also creates a push mirror and prints the deploy key that the mirror's host needs.

A mirror is a copy. The forge pushes on every commit and overwrites the mirror, so a commit pushed to the mirror directly is lost at the next sync.
