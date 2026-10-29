# The CI runner

The machine that runs Forgejo Actions jobs, per [ADR-0102](../../docs/adr/0102-source-control-and-ci.md). It is a dedicated Debian machine. It is never the forge and never a cluster node, because a job controls this machine's Docker, and that is root on it.

This directory exists in a project whose `forge` answer is `forgejo`, per [modes.md](../../docs/reference/modes.md).

## What `runner.sh install` sets up

| Part | Why |
| --- | --- |
| Docker, buildx, Node, pipx, chromium, and the build tools | what a provider-hosted `ubuntu-24.04` image carries and a job assumes |
| higher inotify limits | each kind node runs a kubelet, and the Debian default runs out |
| one user, home, and temp directory for each instance | one job's cache restore or registry logout otherwise lands in another running job |
| the `ubuntu-24.04:host` label, with `ubuntu-latest:host` beside it | a job runs on the machine, so kind can publish on loopback and bind-mount the checkout |
| one Actions cache, served by instance 1 | separate caches would each warm the registry mirror against one Docker Hub limit |
| an hourly `runner-gc` timer | a job that dies early leaves BuildKit builders, kind clusters, and images that nothing else removes |

`INSTANCES` is 1 by default. A machine has one registry port and one set of edge ports, so a second job that starts a cluster waits for the first one.

## Building the runner

1. Create a Debian machine. On the project's own hypervisor, run `bash infra/hypervisor/vm.sh create runner`.
2. Set `RUNNER_SSH`, `RUNNER_JUMP`, and `RUNNER_ADDRESS` in `runner.env`.
3. Export `MISE_GITHUB_TOKEN`, so jobs do not hit the anonymous limit of the GitHub API.
4. Run `bash infra/runner/runner.sh install`.

The script mints a registration token on the forge over `FORGE_SSH`. Where the forge is not reachable that way, it reads `RUNNER_TOKEN` instead.
