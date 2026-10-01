# payment

A service that runs its writes through a workflow, per ADR-0302. `POST /charges` is idempotent on `Idempotency-Key` and returns a workflow handle. The `Charge` workflow:

1. Records the charge as `pending`.
2. Runs `SettleActivity`, the PSP integration, which is a mock here.
3. Marks the charge `settled`, or `failed` if `SettleActivity` returns an error.

It shows idempotency, compensation, and the shape of the cross-service workflow handle, per ADR-0302.
