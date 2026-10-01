# Long-running workflows registry

[ADR-0302](../adr/0302-temporal.md) requires this registry. A workflow can have a wall-clock longer than one prod deploy cycle, which is about 1 week. Such a workflow is permitted only if it is listed here with a versioning plan and replay tests.

## Why this registry exists

A workflow that lives longer than a deploy cycle runs across code changes. So it must use `workflow.GetVersion` patching. It must also have replay tests with `workflow.NewReplayer`, which prove that old event histories still replay. A row here makes this duty explicit, and a reviewer can check it.

## Registered workflows

No workflow is registered. Use workflows freely for operations that have many steps, that need compensation, or that cross systems. Use long wall-clocks with care.

| Workflow | Owning service | Expected wall-clock | Versioning plan | Replay tests |
| --- | --- | --- | --- | --- |
| none | none | none | none | none |

## Adding an entry

1. Add a row above with the workflow, its owning service, and its expected wall-clock.
2. Link the `workflow.GetVersion` plan. It names the change points that are versioned.
3. Link the replay test in CI that covers typical historical event histories.
