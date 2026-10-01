# ADR-0700: Marketing and Product Analytics

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0104](0104-supply-chain-security.md), [ADR-0200](0200-cluster-topology.md), [ADR-0204](0204-resource-management.md), [ADR-0301](0301-data-lifecycle-privacy.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0304](0304-identity-and-authorization.md), [ADR-0306](0306-trust-tiers-and-urls.md), [ADR-0400](0400-frontend.md), [ADR-0500](0500-observability.md)
- **Decides:** One browser agent emits marketing events under a reserved namespace, and the collector splits them from operational telemetry.

## Context

The platform has no instrument for the people who bring in its users. Marketing needs three things. People often mix them up, and they do not cost the same:

| Need | Question |
| --- | --- |
| Acquisition and journey | where a visitor came from, which page they entered on, and which pages they moved through |
| Engagement and conversion | time on page, clicks, custom events, and the funnel and retention questions built on them |
| Session replay | watching a recorded session to see why someone left |

One requirement comes before all three: **an error must be connectable to the journey that produced it.**

The platform already collects browser signals. Faro POSTs to the edge, and the data goes through the collector into Loki and Tempo, next to service telemetry. [ADR-0400](0400-frontend.md) and [ADR-0500](0500-observability.md) set this path.

That path answers whether something is broken or slow. It was never built to answer whether a campaign converted. Loki does counts well enough, but it does funnels badly. It has no step joins, and its distinct-over-window support is weak. Marketing also wants months of retention, and ops logs want days.

**The correlation requirement removes most of the market before any feature comparison.** Every standalone analytics product creates its own session identity, in its own store, with its own retention. Faro creates another. Without a join key, the question `show me the journey of this user who hit an error` becomes a match on timestamp and IP. [ADR-0301](0301-data-lifecycle-privacy.md) makes that match worse, not better.

So the decision is not which analytics tool to use. It is **which store holds Faro's events**.

## Decision drivers

1. **An error is connectable to the journey that produced it**, without a match on timestamp and IP.
2. **A platform component costs more than a service here.** A component pays the full cost of resources, supply chain, network policy, and backups. A service inherits all of it from the template.
3. **PII discipline is already decided.** An analytics store meets [ADR-0301](0301-data-lifecycle-privacy.md) on day one, not through a later retrofit.
4. **Marketing serves itself without ops-tier access.** Marketing staff are not operators, and Grafana is not their tool, per [ADR-0306](0306-trust-tiers-and-urls.md).
5. **Collection stays vendor-neutral.** The backend is the replaceable part.

## Considered options

| Option | Session identity | Components added | Verdict |
| --- | --- | --- | --- |
| **Faro events into a first-party service on the existing Postgres** | **shared with ops telemetry** | **none** | **Chosen** *(reasoned)* |
| Umami | **its own, separate from Faro's** | **none. It runs on PostgreSQL**, which the platform already has | The cheapest self-hosted product here by component weight. It still fails the correlation requirement: its session identity is its own, so a funnel step cannot join to a trace or an error. It gives privacy-first page and event analytics, but not the product-analytics answers this ADR needs |
| Plausible CE | its own | **ClickHouse in addition to PostgreSQL** | The same as Umami on correlation. It also brings the datastore that Umami does not |
| Matomo | its own | MariaDB | The same as above, plus a second SQL engine to operate. Its funnel, cohort, and heatmap features are paid Marketplace plugins, not free core. Those features are most of the reason to choose it |
| Rybbit, OpenPanel | its own | ClickHouse | Newer products of the same shape: a ClickHouse-backed product-analytics server with its own identity. They lose the same way, with less operating history |
| PostHog self-hosted | its own | a fleet of mostly-stateful systems, about the size of the whole Core floor in [`operational-surface.md`](../operational-surface.md). It also needs a chart that this team writes and maintains forever | Upstream has sunset the Kubernetes self-host. What remains is an unversioned image that ships continuously from master. That conflicts with the digest-pin and signature admission of [ADR-0104](0104-supply-chain-security.md), which exists to forbid floating dependencies |
| PostHog Cloud | native OpenTelemetry ingest, ids attached automatically, and a direct jump from exception to replay | none | **The closest product fit.** Rejected as the default, because the data leaves the estate and one frontend runs two RUM agents. **Kept as the documented escape hatch** |
| OpenReplay self-hosted | its own | a floor of 2 vCPU, 8 GB memory, and 50 GB storage, plus bundled Postgres, Redis, and ClickHouse | Maintained charts, versioned releases, and the best replay in the category. Correlation to our traces is integration work, not a native join. It comes back into scope only if the replay trigger fires |
| Loki as the analytics store | shared | none | Works for a first week, but not as an endpoint. It has no funnel step joins. Routing identity-bearing events into the log store also breaks the PII rule of [ADR-0500](0500-observability.md) |

## Decision

### One browser agent, one session identity

Faro stays the **only** browser agent. Marketing events go through its event API under a reserved `marketing.*` namespace. No second SDK is added.

So this ADR does not build correlation. Correlation follows from refusing a second agent. An exception in Tempo, a RUM log in Loki, and a funnel step in the analytics store share one session id. They also share one trace context.

### The split happens at the collector

A `routing` connector in the existing DaemonSet collector checks a condition on the event name. It moves `marketing.*` events out of the logs pipeline and into an exporter aimed at the analytics service. Ops signals do not change.

This placement does three things:

- Marketing events **never reach Loki**, so the PII rule of [ADR-0500](0500-observability.md) holds for the log store.
- Marketing data gets its own retention class and does not inherit the ops-log class.
- The browser does not know the topology, so the backend can change without a frontend release.

It is added configuration on a component that already runs. There is no gateway tier and no new component.

### The store is a service, not a platform component

`services/analytics/` is an ordinary first-party service built from the template. It has these parts:

- a partitioned events table on the existing cluster
- generated queries
- migrations
- a spec at `x-audience: internal`
- a deployment through the shared chart

Funnels, retention, and cohorts are SQL window functions over that table. A Temporal `Schedule` refreshes pre-aggregated rollups.

**Zero platform components are added.** Backups, HA, network policy, resource governance, signing, and admission already work for this shape of workload. That is the whole reason to put the capability here and not in a vendored chart.

### The panel is a route group on the product origin

The panel is served under the product origin and is `noindex`. It uses the dev-portal pattern without change: a route group, not a separate app, behind the app session. It is **page-gated by `Checker`, not by a bare session check**.

The proxy proves only that a session exists. The route-group root does the authoritative check in the render layer.

The authorization model gains one type. It mirrors the existing ops-tier `dashboard` shape, so there is one pattern and not two. A marketing group grants it. **This solves the placement problem.** Marketing never gets an ops-tier account, never needs operator MFA, and never touches Grafana. The ops tier's least-authority rule stays intact.

### Identity, PII, and retention are declared at the start

Events carry the session id. When the visitor is authenticated, they also carry the identity id. That makes this table a **PII store by definition**, and it is treated as one from the first migration, per [ADR-0301](0301-data-lifecycle-privacy.md). It has:

- a declared data class with a retention period
- schema-level PII tags
- reach from the erasure and DSAR workflows
- pruning by a retention `Schedule`

Raw IP addresses are never stored. At ingest, the user-agent becomes a parsed device class.

This design-time work is most of the reason the analytics store is a service we own and not a vendored product: **an erasure workflow cannot reach into a third-party component's schema.**

### Consent, and where its boundary falls

[ePrivacy](https://eur-lex.europa.eu/eli/dir/2002/58/oj) `Art. 5(3)` applies to **storing or reading information on the visitor's device**. It does not apply to processing in general. So the boundary is a technical line, not a legal judgement, and the split sits on that line:

| Path | Client-side storage | Basis |
| --- | --- | --- |
| Ops RUM: errors, web vitals, traces | **none.** The session id lives in memory for the page's lifetime and is never persisted | legitimate interest, per GDPR `Art. 6(1)(f)`. There is no `Art. 5(3)` trigger, so there is no consent gate |
| `marketing.*`: journey, funnel, retention | persistent, because the questions span visits | **consent**, recorded before the first event |

The load-bearing part is the ops path without storage. Because of it, a visitor who refuses analytics still gets working error reporting. A refusal also does not reduce the platform's ability to see that something is broken.

| Concern | Decision |
| --- | --- |
| Consent record | first-party, written through the analytics service. It carries a timestamp, the version of the purpose text shown, and the signal's source. GDPR `Art. 7(1)` requires that consent is demonstrable later |
| Withdrawal | through the same control that grants it, per `Art. 7(3)`. Withdrawal stops emission on the next event, not on a support request |
| Prior signals | [Global Privacy Control](https://globalprivacycontrol.org/) counts as a refusal. A visitor who sends it never gets a prompt. A prompt to someone who already answered is the dark pattern that the rule exists to stop |
| Enforcement | **two points.** The browser wrapper emits no `marketing.*` event without a recorded grant. The analytics service drops any event that arrives without one. The second point exists because the first runs on a client the platform does not control |
| The consent record itself | PII. It has a declared class and a declared retention, and the erasure and DSAR workflows reach it like every other row, per [ADR-0301](0301-data-lifecycle-privacy.md) |
| Purpose mapping | the one thing that varies by project and by counsel: which events fall under which purpose. It is configuration, reviewed at instantiation. **The mechanism above does not change with the answer** |

So consent is not deferred. The platform ships the mechanism. A project's legal review sets the purpose mapping that the mechanism enforces. A regime with no consent requirement sets the mapping to match, and the code path is the same.

### Session replay is deferred

Capture is open source, and self-hosted transport works. **The player is not open source.** Rendering a recorded session is a vendor cloud feature, and the OSS distribution has no documented player. So self-hosted replay means building a player or adopting OpenReplay. Both are real projects. Replay is also the worst PII surface here: it captures the DOM, which has no bound by construction.

| Field | Value |
| --- | --- |
| **Trigger** | three distinct incidents in one quarter where traces and RUM logs alone could not reproduce a reported bug |
| **Seam** | the capture instrumentation attaches to the agent that already runs, and payloads use the same session id as key |
| **Cost if adopted late** | the incidents that caused the adoption are already unreproducible |

When that trigger fires, a separate ADR chooses between building a player and adopting OpenReplay.

### Scale seam: ClickHouse

Postgres as a row store is the floor. It is not a claim about the ceiling.

| Field | Value |
| --- | --- |
| **Trigger** | the p95 of the funnel query exceeds 2s against the declared rollup window, or the events table sustains more than about 10M rows per month |
| **Seam** | collection, the routing connector, and the panel do not change. Only the service's store and queries move. The collector split buys exactly this |

Two other stores were compared with it.

| Option | Shape | Verdict |
| --- | --- | --- |
| TimescaleDB | a Postgres extension with hypertables, columnar compression, and continuous aggregates | It keeps one engine. But the two features worth adopting it for are under [the Timescale License](https://www.tigerdata.com/legal/licenses), not Apache-2.0. That licence permits self-hosting. The operator's images do not carry the extension, per [ADR-0300](0300-data.md), so the store gains an image to build |
| DuckDB | an in-process analytical engine over one file | It has no server, so only the service that embeds it can write. It is correct for a query someone runs, and wrong for the store a panel reads |

## Consequences

### Positive

- **Zero new platform components.** The Core floor and the operational surface do not change.
- **Correlation is free**, because there is one agent and one session identity. No other option gets this without a second agent or a vendor.
- **Analytics data follows the same privacy discipline as everything else** from the first migration. It is not the one store the erasure workflow cannot reach.
- **Marketing is served without a larger ops tier.**
- **The backend stays swappable**, because the browser never learns where events are stored.

### Negative and Risks

- **Marketing gets a panel we build, not exploration they drive.** Every new question is a PR. This is the real cost, and it is a people cost, not a component cost. The question rate can grow past the platform team's capacity. The escape hatch is then **PostHog Cloud**, not a self-hosted rebuild, and the switch is a deliberate decision.
- **Faro de-duplicates consecutive identical events.** So click counts are too low until the emitters are shaped to prevent it. A test proves this, so it is not an assumption.
- **Analytics with consent only is not a census.** A funnel measures the population that consents. The refusal rate is itself a confounder, because refusers are not a random sample. Marketing reads these numbers as a directional panel, not as traffic truth. Only the ops RUM path sees everyone.
- **Two enforcement points can disagree.** The service learns of a withdrawal at most one event after the browser. So a withdrawn visitor's in-flight event is still sent, and the server drops it. That is the correct failure direction, and it is still a discarded write.
- **The ops path stays without storage permanently.** An ops feature that needs a cross-visit identifier crosses the `Art. 5(3)` line and moves behind consent. Examples are a returning-user metric and a durable device id. The boundary is cheap to hold now and expensive to move later.
- **Funnel SQL is work that a free hosted tier gives for nothing.** This is accepted in exchange for the correlation requirement and zero operational surface.
- **A routing-connector mistake sends identity-bearing events into Loki.** One line of configuration can always cause this. It needs a standing test, not careful review.

## Rules

- The frontend has exactly one browser telemetry agent. A second analytics SDK is not added: it creates a second session identity and breaks error-to-journey correlation.
- Marketing events are emitted under the reserved `marketing.*` namespace and routed out of the logs pipeline at the collector. A `marketing.*` event that reaches Loki is a defect.
- Analytics storage is a first-party service on the existing cluster. A dedicated analytics datastore joins the platform only on the documented ClickHouse trigger.
- The marketing panel is a route group on the product origin, page-gated by `Checker` in addition to the session gate. Marketing surfaces on the ops tier are not created.
- The events table carries a declared data class and schema-level PII tags, and the erasure and DSAR workflows reach it. Raw IP addresses are never stored.
- Session replay ships only after the documented incident trigger fires, and only through its own ADR.
- The ops RUM path writes nothing to client-side storage. Its session id is in memory and per page. A persistent identifier on that path is a defect. `(CI: e2e)`
- A `marketing.*` event is emitted only against a recorded consent grant, and the analytics service drops any event that arrives without one. Both gates exist. Neither is enough alone.
- Global Privacy Control counts as a refusal, and a visitor who sends it gets no prompt. `(ref: Global Privacy Control)`
- The consent record carries a timestamp, the purpose-text version, and the signal source. The erasure and DSAR workflows reach it, per [ADR-0301](0301-data-lifecycle-privacy.md).
- The purpose mapping is configuration, reviewed at project instantiation. A change to it never changes the enforcement path.
