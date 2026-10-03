# platform

The worker that owns work that belongs to the platform and not to any one service, per [ADR-0302](../../docs/adr/0302-temporal.md) and [ADR-0301](../../docs/adr/0301-data-lifecycle-privacy.md).

```sh
cd services/platform
mise run worker
```

## Why this exists

Each of these tasks comes from an ADR that names no owner:

- a quarterly DR drill, per [ADR-0207](../../docs/adr/0207-cluster-storage.md)
- a retention pass, per [ADR-0301](../../docs/adr/0301-data-lifecycle-privacy.md)
- a cardinality audit, per [ADR-0500](../../docs/adr/0500-observability.md)
- a quarterly trigger review, per [ADR-0000](../../docs/adr/0000-platform-foundations.md)

None belongs to catalog, orders, orgs, payment, or authz.

If one of those services owned them, it would be in charge of work outside its domain. The process-owner rule exists to prevent that. A Kubernetes `CronJob` is forbidden for business-meaningful work, per [ADR-0302](../../docs/adr/0302-temporal.md), and three of the four tasks are business-meaningful. So they get a worker.

It is **worker-only**, with no HTTP surface, because it answers no requests. The shared chart's `server.enabled` setting exists for this case. It runs on the full local tier and in every deployed environment.

## What it does not do

[ADR-0301](../../docs/adr/0301-data-lifecycle-privacy.md) rejects a dedicated erasure service that calls each owning service's API. This worker is not that. ADR-0301 objects to a service that builds its own retries, timers, and state, when Temporal is already Core. Everything here gets all three from Temporal. This process holds the workflow, not a second orchestrator.

## Starting an erasure or an export

Nothing in the product starts them. An operator does, from a workstation with the environment's kubeconfig:

```sh
mise run privacy:export -- <identity-id> > export.json   # GDPR Art. 15 and 20
mise run privacy:erase -- <identity-id>                  # GDPR Art. 17
```

Both run the Temporal CLI in the cluster's admin-tools pod. The export is the workflow's result, as JSON. It fails, and says so, when it would pass Temporal's payload limit of about 2 MB.

## What each store does

| Store | Erasure | Export |
| --- | --- | --- |
| orders | `owner_id` becomes the pseudonym. The order stays, because it carries a bookkeeping obligation | the subject's orders |
| orgs | `user_id` becomes the pseudonym. The membership stays | the memberships, with org name and role |
| analytics | every session of the subject gets its own replacement id. `properties` and `device_class` are emptied | the events and consent records of those sessions |
| Kratos | the identity is deleted, with its sessions | the identity |
| OpenFGA | every tuple whose user is the subject is deleted | those tuples |

One pseudonym, `erased-<uuid>`, replaces the identity in every store of one erasure. payment and catalog tag no identifier column, so an erasure has nothing to change there.

## Retention and the sweep

The daily `RetentionPass` asks analytics to create next month's event partition and to drop months past 90 days, the period of its `device` column. Then it reads each store's list of subjects and erases every identifier whose Kratos identity is gone. Only a 404 from Kratos counts as gone, so a Kratos outage stops the pass and does not erase anything.

## Restore verification

The weekly `RestoreVerification` restores the source cluster's latest backup into the `restore-verification` namespace. It reads the backup settings from the live cluster, so it tests what production writes. It then compares the row counts of each service database: every table with rows in the source must have rows in the restore. Last, it deletes the scratch cluster and waits until its volumes are gone. The worker's Role allows these calls and nothing more.

## Erasure ordering

`EraseSubject` removes application data per service, then the Kratos identity, then the OpenFGA tuples. This order is on purpose. While the tuples exist, the services can still answer questions about the subject, so a failed run is safe to retry. If the tuples went first, the remaining rows would be unreachable. They would be erased in effect, and the retry that must erase them could not see them.
