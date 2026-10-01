# orders

The checkout saga, per ADR-0302. The `Checkout` workflow lives here because orders owns the *business process*. It calls `catalog` for prices and `payment` to charge, but the process-owner rule puts the workflow here.

`POST /orders` returns a 202 with a workflow handle. The `WorkflowHandle` schema in `openapi.yaml` defines the handle. `GET /orders/{id}` shows the status.
