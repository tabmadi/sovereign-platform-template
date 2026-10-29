# The forge host

The machine that runs Forgejo, per [ADR-0102](../../docs/adr/0102-source-control-and-ci.md). It is a Debian machine beside the workload cluster, never a chart inside it. Argo CD reconciles the cluster from this forge, so a forge in the cluster could not recover a lost cluster.

This directory exists in a project whose `forge` answer is `forgejo`, per [modes.md](../../docs/reference/modes.md).

## Files

| File | Holds |
| --- | --- |
| `forge.env` | how a workstation reaches the machine, the forge's public name, and the Forgejo version |
| `forge.sh` | the steps `install`, `configure`, and `seed`, run from a workstation over SSH |
| `lib.sh` | the SSH helper that `infra/runner/` also uses |

## Building the forge

Each step is safe to run again. `configure` keeps the secrets of an existing `app.ini`, so a second run does not end sessions or break tokens.

1. Create a Debian machine. On the project's own hypervisor, run `bash infra/hypervisor/vm.sh create forge`.
2. Point `FORGE_DOMAIN` at the machine's public address in DNS, per [ADR-0206](../../docs/adr/0206-cluster-networking.md).
3. Run `bash infra/forge-host/forge.sh install`.
4. Run `bash infra/forge-host/forge.sh configure`. Forgejo then gets its certificate from ACME.
5. Run `bash infra/forge-host/forge.sh seed`.
6. Register the tokens that `seed` leaves in `/root/.forgejo-*-token`, per the [credential register](../../docs/reference/credential-register.md).

`seed` creates the break-glass admin, the `ci` and `argocd` machine users, the repository under `FORGE_ORG`, and the `PROMOTE_TOKEN` secret. With `MIRROR_URL` set, it also creates a push mirror and prints the deploy key that the mirror's host needs.

A mirror is a copy. The forge pushes on every commit and overwrites the mirror, so a commit pushed to the mirror directly is lost at the next sync.
