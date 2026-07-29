# ADR-0025: Service Map & Application-Observability UI

- **Status:** Accepted
- **Date:** 2026-07-23
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0003](0003-cluster-topology.md), [ADR-0004](0004-gitops.md), [ADR-0011](0011-observability.md), [ADR-0017](0017-url-and-domain-structure.md), [ADR-0024](0024-kubernetes-debug-ui.md)

## Context

[ADR-0011](0011-observability.md) gives the platform a Grafana/LGTM backend for all four
signals. Two UI questions remain above that backend:

1. **Where does an operator start?** "Is something wrong, and where?" needs a landing
   page that lists every workload and drills into one — not a folder of disconnected
   dashboards.
2. **What owns the service map?** "What talks to what, and is the network denying
   something right now?" is a topology question the signal dashboards do not answer.

[ADR-0003](0003-cluster-topology.md) already runs Cilium with **Hubble** (agent +
relay) as the audit surface for the default-deny NetworkPolicy posture — so a live
flow graph already exists in the cluster; the only question is which UI serves it.

## Decision drivers

1. **One pane of glass.** Operators should start in one place; two tools that both
   appear to own the same signals is a real operational cost.
2. **Dashboards as code** ([ADR-0004](0004-gitops.md)/[ADR-0011](0011-observability.md)):
   the observability surface must live in git.
3. **Bounded footprint** ([ADR-0000](0000-platform-foundations.md)): the template pays
   for signal, not for stacks.
4. **A service map matters** — it is the fastest "what talks to what" answer — but it
   is a secondary surface, not the landing page.

## Decision

- **Grafana owns application observability.** The landing page is the
  **Applications** dashboard (Grafana's home dashboard): one row per workload,
  kubeletstats-driven so idle services still appear. Each workload links to the
  **Service detail** dashboard: SLO tiles, RED, CPU/memory (kubeletstats), logs
  (Loki), traces (Tempo), continuous profiling (Pyroscope flame graph). All
  dashboards are JSON in `infra/observability/dashboards/` ([ADR-0011](0011-observability.md)).
- **The bundled Hubble UI is the service map**, auth-gated at `hubble.ops.<host>`
  (ops forward-auth: operator claim + AAL2 + `dashboard:hubble#view`,
  [ADR-0017](0017-url-and-domain-structure.md)). `hubble.ui.enabled=true` in the
  Cilium values; served at the origin root (its React Router cannot run under a path
  prefix). It also owns **interactive drop investigation** (`verdict=DROPPED` +
  reason, live). It reads the relay's live flow stream, so it costs nothing beyond
  what [ADR-0003](0003-cluster-topology.md) already runs.
- **Grafana does NOT get a service-map dashboard.** Both candidate data sources were
  evaluated and fail structurally:
  - *Tempo `metrics-generator` `service_graphs`* — edges appear only when both sides
    of a CLIENT/SERVER span pair are processed in one instance; here it produces ~1
    edge. The generator, Prometheus's `--web.enable-remote-write-receiver`, and a
    tempo→prometheus NetworkPolicy rule it would need are not deployed.
  - *Hubble `flow` metric* — with `sourceContext=workload` the client side of most
    intra-cluster flows resolves to an empty label (measured: 82/391 series with an
    empty source; zero platform→platform workload edges), so a Node Graph collapses
    into one unnamed hub. The `flow` metric stays off in the Cilium values.
- **Policy drops**: the `hubble_drop_total` metric is enabled for what a live UI
  cannot do — **history** (the `hubble-drops` dashboard) and **alerting**
  (`PolicyDropsDetected` on `rate(hubble_drop_total{reason="POLICY_DENIED"}[5m])`,
  `infra/observability/alerts/policy-drops.yaml`). No per-service drop panels: live
  investigation is Hubble UI's.
- **Accepted trade-offs of Hubble UI:** it collapses workloads sharing
  `app.kubernetes.io/name` into one card (all of Temporal's roles render as a single
  "temporal" node) — cosmetic here, because the map is for topology and per-workload
  detail lives in Grafana, where `k8s_deployment_name` distinguishes roles. And
  upstream is in maintenance mode (last release v0.13.5, Apr 2024) — accepted for a
  bundled, near-free component that is not an operated stack.

### Alternatives considered

- **Coroot Community Edition** (Apache-2.0) — the strongest alternative, evaluated in
  depth: an eBPF APM (operator, node-agent, cluster-agent, ClickHouse + Keeper, its
  own Prometheus) that keys workloads by Deployment (no name collapse) and bundles a
  service map, RED, SLOs, profiling, and database health in one UI. Rejected on the
  drivers:
  - *One pane:* it duplicates nearly everything the Grafana stack serves — while its
    unique signals (overview page, SLO tiles, profiling) can be built as Grafana
    dashboards, which is exactly what this ADR does. Two overlapping panels is the
    cost driver 1 exists to avoid.
  - *Dashboards as code:* Coroot CE dashboards are UI-only click-ops state in
    ClickHouse — not in git, not reviewable, invisible to Argo ([ADR-0004](0004-gitops.md)).
  - *Footprint:* five always-on components plus ClickHouse storage against Hubble
    UI's near-zero marginal cost; plus CE quirks (no SSO/RBAC, ~7-day retention,
    tracefs/debugfs mounts required on k3d nodes) and no stable query API for the
    acceptance gauge ([ADR-0018](0018-testing-strategy.md)).
  - Its eBPF-inferred extras (connection-level traces without instrumentation, DB
    health inspections) are real, but instrumented services already ship richer OTLP
    signals.
- **Grafana Node-Graph service map** — both feeds fail structurally (see Decision).
- **Isovalent/Cisco Enterprise Hubble** — a maintained UI without the collapse
  defect, but commercial.
- **No map at all** — the `hubble` CLI answers point queries but not "show me the
  topology"; the UI is effectively free once Hubble runs anyway.

### Start at Grafana, escalate to Hubble UI

The sequence (also in `docs/dev-loop.md`):

> **Start at `grafana.ops.<host>`** — *"is something wrong, and where?"* Applications
> overview → service detail: SLOs, RED, resources, logs, traces, profiling.
> **Escalate to `hubble.ops.<host>`** — *"what talks to what, and is the network
> denying something right now?"* Live service map, flows, drop verdicts.

There is no signal overlap: every application signal is Grafana's alone; the live
flow map and drop inspection are Hubble UI's alone. Drop *history* and drop
*alerting* are Grafana's (they need Prometheus retention, which the UI lacks).

## Consequences

### Positive

- One stack to operate, one place to look first; no second observability suite to
  patch, store for, or reconcile with.
- Every dashboard is a git artifact — reviewable, reproducible, Argo-visible.
- The map costs nothing extra: Hubble agent + relay already run for the audit
  surface ([ADR-0009](0009-api-gateway.md)).

### Negative / Risks

- **The map collapses multi-role workloads by name** — accepted as cosmetic since
  per-workload detail is Grafana's.
- **Hubble UI upstream is stagnant** (v0.13.5, Apr 2024). Accepted for a bundled,
  near-free component; if it breaks outright, this ADR gets revisited.
- Idle, event-driven services show blank RED panels until traffic arrives (pushed
  signals have no samples); kubeletstats rows are always present. Expected, not a bug.

## Rules

- Application observability (overview, SLO/RED, resources, logs, traces, profiling)
  is owned by the Grafana stack; dashboards live as JSON under
  `infra/observability/dashboards/` ([ADR-0011](0011-observability.md)). `(review-only)`
- The service map is the bundled Hubble UI, served at `hubble.ops.<host>` behind the
  ops forward-auth (operator claim + AAL2 + `dashboard:hubble#view`). No separate
  APM suite (e.g. Coroot) is deployed. `(review-only)`
- No Grafana service-map dashboard is built from Tempo `service_graphs` or the Hubble
  `flow` metric — both fail structurally (see Decision); re-adding one requires
  revisiting this ADR. `(review-only)`
- The Hubble `drop` metric stays enabled for history + alerting
  (`PolicyDropsDetected`); the `flow`, `tcp`, `http`, and `dns` Hubble metrics stay
  off. `(review-only)`
