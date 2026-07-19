# Database migrations

How-to for writing and applying schema migrations. The decision (dbmate, sqlc, CNPG, per-service
databases) is [ADR-0007](../adr/0007-data.md); this is the operational procedure.

## Write a migration

- Migrations live under `services/<service>/migrations/` as timestamped SQL files (dbmate format,
  `-- migrate:up` / `-- migrate:down`).
- Every migration is reversible; a `down` that cannot restore state is a review-blocker.
- After changing schema or queries, regenerate the typed data layer: `mise run gen:sqlc` (sqlc). Generated
  code is committed and drift-checked in CI ([ADR-0007](../adr/0007-data.md)).
- SQL is linted by sqruff: `mise run lint:sql`.

## Apply migrations locally

```sh
mise run db:migrate            # applies each service's migrations to the local Postgres
```

The inner loop runs against the throwaway local Postgres; the full tier and deployed environments run
CNPG ([ADR-0003](../adr/0003-cluster-topology.md), [ADR-0016](../adr/0016-environment-parity.md)).

## Apply migrations in a deployed environment

Migrations run as an init/pre-sync step of the service deploy, not by hand. A schema change ships with
the service image that depends on it, so the ordering is deploy-time, not a separate manual run.

## Authz-relevant migrations

A migration that adds or changes an authz-relevant table must land together with the OpenFGA schema and
the dual-write path ([ADR-0010](../adr/0010-auth.md), [docs/auth/authorization-levels.md](../auth/authorization-levels.md)).
Never mutate authz-relevant rows outside the workflow dual-write.

## Backups & recovery

CNPG `ScheduledBackup` + WAL archiving to the off-cluster bucket is the recovery path; restore is
rehearsed quarterly ([ADR-0003](../adr/0003-cluster-topology.md), [docs/cluster/dr-runbook.md](../cluster/dr-runbook.md)).
