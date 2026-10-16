# catalog requirements

- **Prefix:** CAT
- **Contract:** [openapi.yaml](openapi.yaml)

What this service must do, per [ADR-0602](../../docs/adr/0602-behaviour-requirements.md). The contract holds the shape of each request, and the README holds the purpose.

## Writing products

| ID | Requirement |
| --- | --- |
| CAT-001 | If the caller is not a confirmed operator, the service refuses to create a product: 401 with no session, 403 for a non-operator, and 500 when the check fails. |
| CAT-002 | If the caller is not a confirmed operator, the service refuses to update or delete a product, with the same statuses as CAT-001. |
| CAT-003 | When an operator creates a product, the product list includes it. |
| CAT-004 | When an operator renames a product, a read and the list return the new name, and the old name is gone. |
| CAT-005 | When an operator deletes a product, the list no longer includes it. |
