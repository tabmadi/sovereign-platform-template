# analytics

The marketing event store and the consent record, per [ADR-0700](../../docs/adr/0700-analytics.md).

It is an ordinary first-party service, and that is a decision, not a convenience. A platform component pays the full cost of resources, supply chain, network policy, and backup. A service gets all of these from the template. As a service, it is also reachable by an erasure workflow, which could not reach rows inside a vendored product.

```sh
cd services/analytics
mise run server     # http://localhost:8086
```

## Who calls it

No browser calls it. The browser emits `marketing.*` events through Faro, the only browser agent. The collector's routing connector splits them out of the logs pipeline and delivers them here. This indirection keeps marketing events out of Loki, and it lets you replace this store without a frontend release.

The consent control writes decisions to `/analytics/consent`. The panel reads funnels through queries over `events`.

## Consent is enforced twice

The browser wrapper emits no `marketing.*` event without a recorded grant. `RecordEvents` drops any batch whose session has no grant. The second check exists because the first runs on a client that the platform does not control. Either check alone is a policy, and both together are a control.

A dropped batch is not an error. The caller is the collector, which cannot fix a missing grant and must not retry. So the response reports `stored` and `dropped`, and a non-zero `dropped` shows a client to investigate.

## PII

Every column has a class from the first migration, per [ADR-0301](../../docs/adr/0301-data-lifecycle-privacy.md). The table always carries a session id, and it carries an identity id when the visitor is authenticated. So it is a PII store by definition. Raw IP addresses are never stored, and ingest reduces the user agent to a device class.

`events` is partitioned by month on `occurred_at`. So retention drops a partition and does not delete rows. A retention job that rewrites a table gets postponed.
