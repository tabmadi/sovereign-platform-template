# Setup modes

A setup mode is where a project stands today: which forge runs its pipelines, and how its nodes come to exist. A project keeps only the files of the modes it chose, per [ADR-0117](../adr/0117-updates-and-setup-modes.md).

Each mode is an answer to a question of `just init`. `just init` removes the paths of every mode that the project did not choose. It writes the answers into `infra/project.yaml`.

## The modes

| Answer | Value | Decided by | Keeps | Leave it when |
| --- | --- | --- | --- | --- |
| `forge` | `github`, the default | [ADR-0116](../adr/0116-forge-and-pipelines.md) | the provider-hosted workflows, with their `permissions` blocks | the platform cluster serves its first environment, which is the trigger of ADR-0116 |
| `forge` | `forgejo` | [ADR-0116](../adr/0116-forge-and-pipelines.md) | `infra/forge-host/` and `infra/runner/`. The workflows move to `.forgejo/workflows/` and lose their `permissions` blocks, which Forgejo ignores with a warning. `.forgejo/default_merge_message/SQUASH_TEMPLATE.md` sets the squash message. The design-preview generator reads the forge, per [ADR-0701](../adr/0701-product-design-and-discovery.md) | the project leaves its own forge |
| `provisioning` | `tofu`, the default | [ADR-0200](../adr/0200-cluster-topology.md) | `infra/opentofu/` | the provider stops being the place that the nodes come from |
| `provisioning` | `provided` | [ADR-0200](../adr/0200-cluster-topology.md) | none. Someone else gives the machines, and `infra/talos/` starts at the machine config | the project starts to create its own machines |
| `provisioning` | `hypervisor` | [ADR-0200](../adr/0200-cluster-topology.md) | `infra/hypervisor/` | the project stops running its own hardware |

## Changing a mode

`just init` runs once, so a change of mode later is a change by hand, in one pull request:

1. Set the new value in `infra/project.yaml`.
2. For a new `provisioning` mode, take its folder from the release of `.template-version`, and remove the folder of the old mode.
3. For `forgejo`, take `infra/forge-host/` and `infra/runner/` from the same release. Move `.github/workflows/` to `.forgejo/workflows/`, and remove each `permissions` block. Write `${PullRequestTitle} (${PullRequestReference})` to `.forgejo/default_merge_message/SQUASH_TEMPLATE.md`.
4. For `github`, move the workflows back, add the `permissions` blocks of the release again, and remove `.forgejo/`.
5. Run `just gen` and `just check`.
