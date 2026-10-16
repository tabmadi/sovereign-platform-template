# analytics requirements

- **Prefix:** ANL
- **Contract:** [openapi.yaml](openapi.yaml)

What this service must do, per [ADR-0602](../../docs/adr/0602-behaviour-requirements.md). The contract holds the shape of each request, and the README holds the purpose.

## Ingest and consent

| ID | Requirement |
| --- | --- |
| ANL-001 | If a batch's session has no consent decision, the service stores no event and reports every event as dropped, with no error. |
| ANL-002 | If a batch's session has a decision other than `granted`, the service stores no event and reports every event as dropped, with no error. |
| ANL-003 | While a batch's session has a `granted` decision, the service stores every event of the batch and reports them as stored. |
| ANL-004 | If the consent decision cannot be read, the service returns 500 and stores no event. |
| ANL-005 | When the collector delivers browser logs, the service keeps only `marketing.*` events, groups them by session, and reduces the browser to a device class. |

## Funnels

| ID | Requirement |
| --- | --- |
| ANL-006 | The funnel rollup counts a session at a step only when the session reached every earlier step first, in the funnel's order. |
| ANL-007 | The funnel rollup counts two steps first seen at the same instant as reached in the funnel's order. |
| ANL-008 | The funnel rollup returns one count per step, zero where nothing reached it, and no count above the step before. |
| ANL-009 | The funnel rollup splits a window into contiguous days that start at midnight UTC, and an empty or reversed window has no days. |
| ANL-010 | If the definitions are missing, empty, or hold a funnel with one step, a repeated step, or a duplicate ID, the service does not start. |
| ANL-011 | The committed funnel definitions in `infra/analytics/funnels.yaml` load. |

## Retention

| ID | Requirement |
| --- | --- |
| ANL-012 | When the retention pass runs, the service makes sure the event partitions of the current and the next UTC month exist. |
| ANL-013 | When the retention pass runs, the service drops each monthly partition that ended before the retention period, and never the default partition. |
| ANL-014 | The retention period of events equals the period of the `device` class in the data-class registry. |
