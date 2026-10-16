# platform requirements

- **Prefix:** PLT
- **Contract:** none. This worker answers no requests.

What this worker must do, per [ADR-0602](../../docs/adr/0602-behaviour-requirements.md). The README holds the purpose and the store table.

## Erasure

| ID | Requirement |
| --- | --- |
| PLT-001 | The `EraseSubject` workflow erases the data of every service first, then the Kratos identity, and the OpenFGA tuples last. |
| PLT-002 | The `EraseSubject` workflow gives every store of one run the same pseudonym, which starts with `erased-`. |
| PLT-003 | If a store fails, the `EraseSubject` workflow fails and does not erase the tuples. |
| PLT-004 | The erasure calls only the stores that tag an identifier column, so payment and catalog get no call. |
| PLT-005 | If the URL of a store that holds personal data is not set, the erasure fails. |
| PLT-006 | If the Kratos identity is already gone, erasing it succeeds. |
| PLT-007 | The tuple erasure reads every object type and every page, then deletes every tuple whose user is the subject in one write. |

## Export

| ID | Requirement |
| --- | --- |
| PLT-008 | The export holds the identity, the data of each store, and the subject's tuples, and an identity that is gone exports as `null`. |

## Retention

| ID | Requirement |
| --- | --- |
| PLT-009 | When the daily retention pass runs, the worker asks analytics to apply retention, then erases each subject that Kratos no longer has. |
| PLT-010 | If Kratos still has an identity, or the subject is a service account, the retention pass erases nothing for it. |

## Audits and restore verification

| ID | Requirement |
| --- | --- |
| PLT-011 | If the forge refuses the tracking issue that an audit opens, the audit fails. |
| PLT-012 | The restore cluster recovers from the source's archive with the source's image and storage size, and does not copy the source's backup settings. |
| PLT-013 | If a source table with rows is empty or missing in the restore, restore verification reports a failure. |
