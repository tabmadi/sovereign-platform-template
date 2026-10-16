# orgs requirements

- **Prefix:** ORG
- **Contract:** [openapi.yaml](openapi.yaml)

What this service must do, per [ADR-0602](../../docs/adr/0602-behaviour-requirements.md). The contract holds the shape of each request, and the README holds the purpose.

## Reading organisations

| ID | Requirement |
| --- | --- |
| ORG-001 | If a caller with no session reads an organisation, the service returns 401, even when the caller holds its identifier. |
| ORG-002 | If a signed-in caller who is not a member and not an operator reads an organisation, the service returns 403. |
| ORG-003 | When a member reads their organisation, the service returns it. |
| ORG-004 | When an operator reads any organisation, the service returns it. |

## Writing organisations

| ID | Requirement |
| --- | --- |
| ORG-005 | If the caller is not a confirmed operator, the service refuses to update or delete an organisation: 401 with no session, 403 for a non-operator, and 500 when the check fails. |
| ORG-006 | If an operator updates an organisation with an empty name, the service returns 400. |

## Registration

| ID | Requirement |
| --- | --- |
| ORG-007 | When Kratos reports an identity, the `RegisterUser` workflow creates its personal organisation, grants it `admin`, and records the organisation on the identity. |
| ORG-008 | If the personal organisation cannot be created, the `RegisterUser` workflow fails and grants no `admin` tuple. |
| ORG-009 | If the organisation cannot be recorded on the identity, the `RegisterUser` workflow fails. |
| ORG-010 | If the `admin` grant fails after the organisation exists, the `RegisterUser` workflow fails. |
