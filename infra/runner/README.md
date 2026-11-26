# The CI runner

The machine that runs Forgejo Actions jobs, per [ADR-0116](../../docs/adr/0116-forge-and-pipelines.md). It is a dedicated NixOS machine. It is never the forge and never a cluster node, because a job controls this machine's Docker, and that is root on it.

This directory exists in a project whose `forge` answer is `forgejo`, per [modes.md](../../docs/reference/modes.md).

## What `runner.nix` sets up

| Part | Why |
| --- | --- |
| Docker, Nix, Node, git, and the build tools | what a provider-hosted `ubuntu-24.04` image carries and a job assumes |
| higher inotify limits | each kind node runs a kubelet, and the default runs out |
| one home, temp directory, and Actions cache for each instance | one job's cache restore or registry logout otherwise lands in another running job |
| the `ubuntu-24.04:host` label, with `ubuntu-latest:host` beside it | a job runs on the machine, so kind can publish on loopback and bind-mount the checkout |
| an hourly `runner-gc` timer | a job that dies early leaves BuildKit builders, kind clusters, and images that nothing else removes |
| the blackbox exporter, when `probe.enable` is set | the registry probe of [ADR-0500](../../docs/adr/0500-observability.md) |

`instances` in `settings.nix` is 1 by default. A machine has one registry port and one set of edge ports, so a second job that starts a cluster waits for the first one.

## Building the runner

1. Start the VM. On the project's own hypervisor, the host boots it from its disk image, per `infra/hypervisor/`. Elsewhere, run `just runner-image` and start a VM from `runner.img`.
2. Set `address` and `jump` in `settings.nix`, then run `just runner-deploy`.
3. Run `just runner-token`. It mints a registration token on the forge, writes it on the runner, and starts every instance.

Where the forge is not reachable over SSH, `runner-token` reads `RUNNER_TOKEN` instead.
