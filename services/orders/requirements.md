# orders requirements

- **Prefix:** ORD
- **Contract:** [openapi.yaml](openapi.yaml)

What this service must do, per [ADR-0602](../../docs/adr/0602-behaviour-requirements.md). The contract holds the shape of each request, and the README holds the purpose.

## Checkout

| ID | Requirement |
| --- | --- |
| ORD-001 | If a caller with no session starts a checkout, the service returns 401. |
| ORD-002 | If the caller's identity carries no organisation, the service refuses the checkout with 403. |
| ORD-003 | If a checkout has no `Idempotency-Key` header, the service returns 400 and starts no workflow. |
| ORD-004 | When a checkout repeats an `Idempotency-Key`, the service returns the handle of the first order and starts no second workflow. |
| ORD-005 | When a buyer with an organisation starts a checkout, the service starts the `Checkout` workflow and returns a running handle. |

## The checkout saga

| ID | Requirement |
| --- | --- |
| ORD-006 | When the lookup and the charge succeed, the `Checkout` workflow sets the total to price times quantity and marks the order `confirmed`. |
| ORD-007 | If the order insert fails, the `Checkout` workflow fails and grants no access to the order. |
| ORD-008 | If the access grant fails, the `Checkout` workflow fails before it charges. |

## Reading orders

| ID | Requirement |
| --- | --- |
| ORD-009 | If a caller with no session reads an order, the service returns 401, even when the caller holds the order's identifier. |
| ORD-010 | If a signed-in caller who holds no `read` relation on an order and is not an operator reads it, the service returns 403. |
| ORD-011 | When the buyer of an order reads it, the service returns the order. |
| ORD-012 | When an operator reads any order, the service returns it. |
| ORD-013 | If a caller with no session lists every order, the service returns 401. |
| ORD-014 | If a signed-in caller who is not an operator lists every order, the service returns 403. |

## Cancelling an order

| ID | Requirement |
| --- | --- |
| ORD-015 | If the caller is not a confirmed operator, the service refuses a cancel: 401 with no session, 403 for a non-operator, and 500 when the check fails. |
| ORD-016 | If the order to cancel does not exist, the service returns 404. |
| ORD-017 | If the order is already `cancelled` or `failed`, the service refuses the cancel with 409. |
| ORD-018 | When an operator cancels an order in any other status, the service starts the `CancelOrder` workflow and returns a running handle. |
| ORD-019 | The `CancelOrder` workflow marks the order `cancelled`. |
| ORD-020 | If the status write fails, the `CancelOrder` workflow fails. |
