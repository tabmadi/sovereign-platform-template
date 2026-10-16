# payment requirements

- **Prefix:** PAY
- **Contract:** [openapi.yaml](openapi.yaml)

What this service must do, per [ADR-0602](../../docs/adr/0602-behaviour-requirements.md). The contract holds the shape of each request, and the README holds the purpose.

## Creating a charge

| ID | Requirement |
| --- | --- |
| PAY-001 | If a charge amount does not parse as a decimal amount in a known currency, the service returns 400 and records nothing. |
| PAY-002 | If a charge amount is zero or negative, the service returns 400 and records nothing. |

## Reading charges

| ID | Requirement |
| --- | --- |
| PAY-003 | If a caller with no session reads a charge, the service returns 401, even when the caller holds the charge's identifier. |
| PAY-004 | If a signed-in caller who holds no `read` relation on a charge and is not an operator reads it, the service returns 403. |
| PAY-005 | When the buyer of the charged order reads the charge, the service returns it. |
| PAY-006 | When an operator reads any charge, the service returns it. |
| PAY-007 | If a caller with no session lists every charge, the service returns 401. |
| PAY-008 | If a signed-in caller who is not an operator lists every charge, the service returns 403. |

## Refunding a charge

| ID | Requirement |
| --- | --- |
| PAY-009 | If the caller is not a confirmed operator, the service refuses a refund: 401 with no session, 403 for a non-operator, and 500 when the check fails. |
| PAY-010 | If the charge to refund does not exist, the service returns 404. |
| PAY-011 | If the charge is not `settled`, the service refuses the refund with 409. |
| PAY-012 | When an operator refunds a settled charge, the service starts the `Refund` workflow and returns a running handle. |
| PAY-013 | The `Refund` workflow reverses the charge at the payment processor, then marks it `refunded`. |
| PAY-014 | If the processor reversal fails, the `Refund` workflow fails and the charge is not marked `refunded`. |
