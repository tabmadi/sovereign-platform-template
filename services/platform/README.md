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

It is **worker-only**, with no HTTP surface, because it answers no requests. The shared chart's `server.enabled` setting exists for this case.

## What it does not do

[ADR-0301](../../docs/adr/0301-data-lifecycle-privacy.md) rejects a dedicated erasure service that calls each owning service's API. This worker is not that. ADR-0301 objects to a service that builds its own retries, timers, and state, when Temporal is already Core. Everything here gets all three from Temporal. This process holds the workflow, not a second orchestrator.

## Erasure ordering

`EraseSubject` removes application data per service, then the Kratos identity, then the OpenFGA tuples. This order is on purpose. While the tuples exist, the services can still answer questions about the subject, so a failed run is safe to retry. If the tuples went first, the remaining rows would be unreachable. They would be erased in effect, and the retry that must erase them could not see them.
