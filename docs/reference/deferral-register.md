# Deferral Register

This table holds every deferral in the ADR set. The Trigger, Seam, and Cost triad makes *later* falsifiable for each decision. This document makes the deferrals enumerable. A trigger that nobody watches is only a comment. Twenty triggers in twenty documents are twenty things that nobody watches.

The reasoning stays in the owning ADR. This document adds the column that no ADR can answer for itself: **whether a machine can see the trigger fire.**

| Watched by | Meaning |
| --- | --- |
| **alert** | a rule already evaluates the condition, or could with no new signal |
| **query** | the data exists and nobody asks for it. A scheduled query would see it |
| **event** | a person notices it happen: a contract, an incident, or a decision elsewhere |
| **uncollected** | the condition is measurable in principle, and no collector gathers the series that it needs |

An **event** row is not a weaker deferral. Some triggers are commercial or organisational, and no metric will ever carry them. What matters is that no row has the wrong label. A condition that could have an alert and has none is a gap. A condition that only a human can see needs a human who knows to look.

**`uncollected` exists because `alert` claimed too much.** Three rows said *alert, already measurable*, but nothing gathered the series behind them. This is the worst of the four states. It looks covered, so nobody writes the rule and nobody adds the collector. A row is `alert` only when a rule names it.

## The register

| Deferred | Trigger | Watched by | Owner |
| --- | --- | --- | --- |
| Mimir, replacing Prometheus | active series cross the paging threshold and more memory is no longer the cheap answer, or retention exceeds one local TSDB | **alert**: `ActiveSeriesNearCeiling`. The series arrives through the cluster collector, which scrapes Prometheus and exports again over OTLP. So the store's only way in is still a push | [ADR-0500](../adr/0500-observability.md) |
| Tail sampling, through a collector gateway | a latency investigation fails twice because head sampling dropped the slow traces | **event** | [ADR-0500](../adr/0500-observability.md) |
| PgBouncer in session mode | a service needs `LISTEN/NOTIFY` across statements, an advisory lock, or a session-scoped `SET` | **event** | [ADR-0300](../adr/0300-data.md) |
| Postgres row-level security | a service's tables start to hold rows that belong to more than one organisation | **query**: a schema walk can see the tenant column arrive | [ADR-0300](../adr/0300-data.md) |
| Temporal Worker Controller | a workflow's wall-clock must be longer than a deploy cycle, or a non-determinism failure reaches production twice | **alert** for the second half. **query** over `docs/reference/long-running-workflows.md` for the first | [ADR-0302](../adr/0302-temporal.md) |
| A publish-subscribe bus | one event has three or more independent consumers that the producer should not know, or a consumer needs to replay a stream | **event**. Labelled a **bet**: adoption rewrites the producers | [ADR-0302](../adr/0302-temporal.md) |
| A cluster segment in the slug grammar | a second cluster is provisioned inside one environment | **query**: the inventory of clusters is committed | [ADR-0003](../adr/0003-naming-and-identifiers.md) |
| Per-consumer rate limiting | a project bills for API access, so a caller's quota depends on the contract and not on the route | **event** | [ADR-0305](../adr/0305-edge-auth-and-traffic-policy.md) |
| Directory provisioning with SCIM | the first contract that makes directory-driven provisioning a condition of purchase | **event** | [ADR-0304](../adr/0304-identity-and-authorization.md) |
| An OpenFGA consistency token | a read-after-write staleness bug seen in production: a user completes a mutation and is then denied what it granted | **alert**, when a rule counts authorization denials that follow a mutation on the same resource | [ADR-0304](../adr/0304-identity-and-authorization.md) |
| Ops-tier token isolation | an origin under the apex that is not first-party, or the product showing user-supplied content to other users | **query** over the ingress set for the first. **event** for the second | [ADR-0306](../adr/0306-trust-tiers-and-urls.md) |
| A partner credential tier | a party outside the organisation gets credentials for the API | **event** | [ADR-0306](../adr/0306-trust-tiers-and-urls.md) |
| The forge migration to Forgejo | the platform cluster serves its first environment | **event** | [ADR-0102](../adr/0102-source-control-and-ci.md) |
| SemVer for a published artifact | an artifact is published for a consumer outside this repository to pin | **event** | [ADR-0103](../adr/0103-release-and-versioning.md) |
| Escalation and paging | a response-time obligation outside working hours: an availability target with consequences, or a contract that names one | **event**. This is the largest row here: it is the trigger that bounds [`detection-latency.md`](detection-latency.md) | [ADR-0502](../adr/0502-alerting-and-on-call.md) |
| Keyless signing | a first-party image is published for an external party to verify | **event** | [ADR-0104](../adr/0104-supply-chain-security.md) |
| GlitchTip | fingerprint triage becomes routine work and not incident work, or the novelty window misses a fault that reached a customer | **event** for the first. **query** for the second, which compares faults the window detected against reported ones | [ADR-0503](../adr/0503-error-tracking.md) |
| The `(admin)` route group, replacing Lowdefy | upstream releases stop for two quarters, or a security advisory gets no answer for one quarter | **query**: a scheduled check of the upstream release feed | [ADR-0401](../adr/0401-internal-admin.md) |
| Session replay | three distinct incidents in one quarter where a reported bug could not be reproduced from traces plus RUM logs | **event**. It needs an incident record to count against, per [`incident-management`](../guide/incident-management.md) | [ADR-0700](../adr/0700-analytics.md) |
| ClickHouse | funnel-query p95 above 2s against the declared rollup window, or the events table holding more than about 10M rows per month over time | **alert** for the volume half: `AnalyticsStorageGrowthTrigger`, on the row-count gauge that the analytics service emits for the current month's partition. The latency half is **query**. The panel reads a precomputed rollup, so a slow funnel is a question about the rollup pass and not a live p95 | [ADR-0700](../adr/0700-analytics.md) |
| The CNPG Barman Cloud plugin | a CloudNativePG upgrade to 1.30, which removes the in-tree `barmanObjectStore` | **query** over Renovate's CloudNativePG pull requests: the version is in the title | [ADR-0207](../adr/0207-cluster-storage.md) |
| A second GitOps repository | promotion commits outnumber code commits on `master`, or someone opens a review against a diff that is more than half values bumps | **query** over merge history | [ADR-0201](../adr/0201-gitops.md) |
| Registry mirroring | ~~an upstream registry rate-limits or removes a pinned digest that the cluster depends on~~ | **adopted**: zot mirrors the four upstreams as a pull-through cache, per [ADR-0105](../adr/0105-image-registry.md). It was adopted early because the egress surface forced it, not the rate limit. `ImagePullsFailing` still watches the pull path | [ADR-0105](../adr/0105-image-registry.md) |
| A transactional mail provider | a lasting delivery-failure or complaint rate that DMARC alignment and warmup do not fix, or a blocklist listing that does not clear | **query** over DMARC aggregate reports, which are reviewed on a cadence in both cases | [ADR-0307](../adr/0307-outbound-email.md) |
| Storybook | someone who does not run the app edits a component, or a visual regression reaches `master` twice | **event**. Labelled a **bet**: the stories to enable do not exist | [ADR-0400](../adr/0400-frontend.md) |
| Longhorn | a Postgres restore rehearsal takes more than half the RTO | **query** over the rehearsal table in `docs/guide/disaster-recovery.md` | [ADR-0207](../adr/0207-cluster-storage.md) |
| Per-workload certificate identity | a service that performs a monetary mutation, a second team that owns a service, or an auditor who requires a CA chain | **event** | [ADR-0305](../adr/0305-edge-auth-and-traffic-policy.md) |

## What the column shows

**The alerted rows** are the ones that these alerts name:

- `LoadGeneratorDroppingIterations`, `ImagePullsFailing`, and `AnalyticsStorageGrowthTrigger` in `infra/observability/alerts/deferral-triggers.yaml`
- `ActiveSeriesNearCeiling` in `cardinality.yaml`

A deferral whose trigger could have an alert and has none looks the same as a deferral with no trigger. So a row reaches this state only when a rule names the condition that the ADR wrote down.

**No row is `uncollected`.** The last one was the ClickHouse row. It left the state in the same way as the registry row: first something collected its signal, then a rule named it. The analytics service emits the current month's row count as a gauge, and `AnalyticsStorageGrowthTrigger` reads it. A rule added before the series would never fire. That is the same blindness with a green tick on it.

**Query rows**: the data exists, and something has to ask. They use the quarterly `Schedule` that [`upstream-status.md`](upstream-status.md) describes. It opens one tracking issue that covers these rows, the upstream facts in that document, and the concerns in [`asvs-verification.md`](asvs-verification.md). A row's owner is the owner of its owning ADR. A query row is not walked until its answer is recorded.

**The other rows are events**, and each one is commercial, organisational, or an incident. Whoever reads this register watches them. This is why the register is one document and not twenty.

**Two rows are bets, not deferrals**: the publish-subscribe bus and Storybook. They are bets because no seam exists. They are in this table so that people see them, and they follow a different rule. A bet is adopted before its trigger, or paid for with a rewrite, per [ADR-0000](../adr/0000-platform-foundations.md).
