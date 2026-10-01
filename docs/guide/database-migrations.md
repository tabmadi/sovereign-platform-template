# Database migrations

This guide shows how to write and apply schema migrations. [ADR-0300](../adr/0300-data.md) holds the decision: dbmate, sqlc, CNPG, and one database per service. This guide is the operational procedure.

## Write a migration

1. Create the file under `services/<service>/migrations/`. Give it a timestamp and use the dbmate format with `-- migrate:up` and `-- migrate:down` sections.
2. **Write the `down` section for yourself, not for production.** It lets you run the migration again locally. Never plan to run it in production. A production rollback is a forward fix: a new migration that reverses the change, per [ADR-0300](../adr/0300-data.md).
3. Regenerate the typed data layer after any schema or query change: `mise run gen:sqlc`. Commit its output. CI checks it for drift against your SQL.
4. Run `mise run lint:sql` before you push. It rejects a `timestamp` where `timestamptz` belongs. It also rejects a column that holds personal data without a tag, per [ADR-0301](../adr/0301-data-lifecycle-privacy.md).

## Apply migrations locally

```sh
mise run db:migrate            # applies each service's migrations to the local Postgres
```

The inner loop runs against the disposable local Postgres. The full tier and deployed environments run CNPG, per [ADR-0205](../adr/0205-environment-parity.md).

## Apply migrations in a deployed environment

Migrations run as an **init container** before the service container. Nobody runs them by hand. An advisory lock stops two replicas from running them at the same time. A schema change ships with the service image that depends on it. So the deploy sets the order, and no separate run is needed.

A change that can break running code follows three phases: expand, migrate, contract. At least one deploy separates the expand phase from the code switch, per [ADR-0300](../adr/0300-data.md).

## Authz-relevant migrations

A migration can add or change an authz-relevant table. It then lands with the OpenFGA schema and the dual-write path, per [ADR-0304](../adr/0304-identity-and-authorization.md). Never change authz-relevant rows outside the workflow dual-write.

## Backups and recovery

The recovery path is a CNPG `ScheduledBackup` plus WAL archiving to the off-cluster bucket, per [ADR-0207](../adr/0207-cluster-storage.md). The restore is rehearsed every quarter. The procedure is in [disaster-recovery](disaster-recovery.md).
