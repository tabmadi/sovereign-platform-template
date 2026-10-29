# Setup modes

A setup mode is where a project stands today: which forge runs its pipelines, and how its nodes come to exist. The template carries the files of every mode. A project keeps only the files of the modes it chose, per [ADR-0106](../adr/0106-dependency-updates.md).

Each mode is a Copier answer. The `_exclude` list of `copier.yml` holds one line for each path, and `project:init` reads the same lines. The answers are in the project's `.copier-answers.yml`.

## The modes

| Answer | Value | Decided by | Keeps | Leave it when |
| --- | --- | --- | --- | --- |
| `forge` | `github`, the default | [ADR-0102](../adr/0102-source-control-and-ci.md) | the provider-hosted workflows, with their `permissions` blocks | the platform cluster serves its first environment, which is the trigger of ADR-0102 |
| `forge` | `forgejo` | [ADR-0102](../adr/0102-source-control-and-ci.md) | `infra/forge-host/` and `infra/runner/`. The workflows lose their `permissions` blocks, which Forgejo ignores with a warning | the project leaves its own forge |
| `provisioning` | `terraform`, the default | [ADR-0200](../adr/0200-cluster-topology.md) | `infra/terraform/` | the provider stops being the place that the nodes come from |
| `provisioning` | `provided` | [ADR-0200](../adr/0200-cluster-topology.md) | none. Someone else gives the machines, and `infra/talos/` starts at the machine config | the project starts to create its own machines |
| `provisioning` | `hypervisor` | [ADR-0200](../adr/0200-cluster-topology.md) | `infra/hypervisor/` | the project stops running its own hardware |

## Changing a mode

Run `copier update --data <answer>=<value>`. The update stops rendering the old mode's files and starts rendering the new mode's files. It deletes only files that came from the template and that the project did not change. A file the project wrote itself stays, so the old mode's local files are the project's to remove.

A project that came from a template release with no mode answers gets the defaults at its first update. A project that already runs its own forge or hypervisor passes its answers on that update.
