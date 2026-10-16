# authz requirements

- **Prefix:** AUZ
- **Contract:** [openapi.yaml](openapi.yaml)

What this service must do, per [ADR-0602](../../docs/adr/0602-behaviour-requirements.md). The contract holds the shape of each request, and the README holds the purpose.

## The edge gate

| ID | Requirement |
| --- | --- |
| AUZ-001 | When an operator with an AAL2 session asks for an ops tool, the gate admits the request. |
| AUZ-002 | If the session is AAL1, the gate refuses with 403, even for an operator. |
| AUZ-003 | If the identity's operator flag is false or absent, the gate refuses with 403. |
| AUZ-004 | If the request names no subject, the gate refuses with 403. |
| AUZ-005 | The coarse gate decides from the session's claims alone and makes no OpenFGA call. |
| AUZ-006 | Where the fine-grained layer is on, the gate admits an operator only to a tool that the operator holds a `view` grant on. |

## Identities

| ID | Requirement |
| --- | --- |
| AUZ-007 | When the service lists identities, an identity with no operator flag reports `operator` as false. |
| AUZ-008 | When an identity update changes only its name, the service keeps the schema, state, email, and public metadata, and writes no operator trait. |
| AUZ-009 | When an identity update changes `operator`, the `SetOperator` workflow writes the Kratos flag, then the OpenFGA grant, and then the service returns the identity. |
| AUZ-010 | If the flag write fails, the `SetOperator` workflow fails and does not change the grant. |
| AUZ-011 | If the grant write fails, the `SetOperator` workflow fails, so the flag and the grant cannot silently disagree. |
