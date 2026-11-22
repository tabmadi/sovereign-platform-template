# Hypervisor lab

This guide shows which test to run for a change. It also shows how to use the cache and offline mode of the lab, per [ADR-0208](../adr/0208-hypervisor-host.md).

## Choose the test

Run the cheapest test that can prove the change.

| Change | Command | Needs |
| --- | --- | --- |
| Code, docs, charts, or an alert rule | `just check` | no cluster |
| The host, a VM, an image, a reboot path, or the etcd members | `just hypervisor-test install` | KVM and the local cache |
| The same change, on a slow or missing network | `just hypervisor-test install --offline` | one earlier pass with the same pins |

`just check` runs `just test-alerts`. It proves each alert with simulated time, so an alert change needs no cluster.

## Fill the cache

`just hypervisor-test install` fills the cache first, then runs the test. To fill it:

1. Stop other local clusters.
2. Run `just hypervisor-test install`.
3. Read the step times at the end of the output.

The cache is in `~/.cache/hypervisor-lab`. Set `LAB_DIR` to move it.

| Item | Where | Kept by |
| --- | --- | --- |
| Nix packages, VM images, and flake inputs | the Nix store | the GC roots in `roots/` |
| Talos and Kubernetes images | the private zot data in `registry/` | the lab, which never deletes them |

The step skips each item that the cache holds. After a network failure, run the command again and it continues.

To free the space, delete the cache folder. The next run downloads everything again.

## Run offline

1. Pass `just hypervisor-test install` once with the current pins.
2. Run `just hypervisor-test install --offline`.

The offline run skips the fill step and blocks the internet of the lab VM. The nodes reach only the private zot. A missing package or image stops the run before the VM starts, and the error names it. A change to a pin needs a new run with the internet.

## Limits

| Limit | Default | Setting |
| --- | --- | --- |
| Free disk that a run needs | 20 GB | `LAB_MIN_FREE_GB` |
| Free memory that a run needs | 16 GiB | `LAB_MIN_MEMORY_MB` |
| Memory cap of the run | 18 GiB | `LAB_MEMORY_MAX` |
| Free memory at which the lab stops | 2 GiB | `LAB_MEMORY_FLOOR_MB` |

The lab VM needs about 14 GB. On a workstation with 32 GB of memory, stop `platform-full` before a run.
