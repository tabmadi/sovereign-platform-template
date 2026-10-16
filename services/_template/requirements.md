# `_template` requirements

- **Prefix:** TPL
- **Contract:** [openapi.yaml](openapi.yaml)

What this service must do, per [ADR-0602](../../docs/adr/0602-behaviour-requirements.md). The contract holds the shape of each request, and the README holds the purpose.

<!--
Written to ADR-0602. Before merging, check:
  - The prefix is two to four capital letters that no other requirements file uses. `TPL` fails lint:requirements outside services/_template/.
  - Each row is one EARS sentence in the present tense. It opens with The, When, While, If, or Where.
  - A row states observable behaviour: a status, a state change, an order of effects, or what a failure leaves behind. It never restates a field, a type, or a format from openapi.yaml.
  - A test cites each ID in its name: t.Run("TPL-001 a nameless item is a bad request", ...). Run it alone with go test -run '/TPL-001'.
  - A changed meaning gets a new ID. A retired ID is never used again.
  - Group the rows under one heading for each resource or workflow. A heading with no rows is deleted.
-->

## Items

| ID | Requirement |
| --- | --- |
| TPL-001 | When a caller creates an item with an empty name, the service returns 400 and stores nothing. |
