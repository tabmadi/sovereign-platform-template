# ADR-0501: Operator UIs and Dashboard Hierarchy

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0200](0200-cluster-topology.md), [ADR-0201](0201-gitops.md), [ADR-0306](0306-trust-tiers-and-urls.md), [ADR-0500](0500-observability.md), [ADR-0601](0601-testing-strategy.md)
- **Decides:** Three dashboard levels answer one question each, and every operator UI is admitted for the question it answers, not for its coverage.

## Context

[ADR-0500](0500-observability.md) pins the Grafana LGTM backend for all four signals. Above that backend, an operator in an incident asks four questions. Each question needs a surface that owns it:

| Question | Owning surface |
| --- | --- |
| Whether anything is wrong now, and where | Grafana |
| What talks to what, and whether the network denies a flow | Hubble UI |
| Which pods exist, their descriptions, and their logs | Headlamp |
| What is deployed, and whether it synced | Argo CD, per [ADR-0201](0201-gitops.md) |

Cilium already runs the Hubble agent and relay as the audit surface for the default-deny NetworkPolicy posture, per [ADR-0206](0206-cluster-networking.md). So a live flow graph exists in the cluster, and only its UI is an open question.

Without a stated dashboard structure, a growing dashboard set leads to two failures: one mega-dashboard that nobody reads, and sprawl that nobody owns.

## Decision drivers

1. **One pane of glass.** Two tools that seem to own the same signals are an operational cost, not redundancy.
2. **Dashboards as code**, per principle 1 of [ADR-0000](0000-platform-foundations.md). The observability surface lives in git.
3. **Bounded footprint**, per principle 2 of [ADR-0000](0000-platform-foundations.md). The template pays for signal, not for stacks.
4. **The landing page answers one question in seconds**, without a scan of a table.
5. **No UI mutates desired state.** A debug surface is not a control surface.

## Considered options

### Application-observability suite

| Option | Service map | Dashboards as code | Footprint | Verdict |
| --- | --- | --- | --- | --- |
| **Grafana stack and bundled Hubble UI** | Hubble UI, live | JSON in git | zero added, because both already run | **Chosen** *(reasoned)* |
| [Coroot Community Edition](https://github.com/coroot/coroot/blob/main/LICENSE), Apache-2.0 | keyed by Deployment, with no name collapse | **UI-only click-ops state in ClickHouse**. It is not in git, not reviewable, and invisible to Argo | five always-on components and ClickHouse | Rejected. It fails driver 2 completely and duplicates most of the Grafana stack. CE also has no SSO or RBAC and about 7 days of retention. It needs tracefs and debugfs mounts. It has no stable query API for the acceptance gauge of [ADR-0601](0601-testing-strategy.md). Its eBPF extras cover uninstrumented workloads, and instrumented services already give more through OTLP |
| Cisco Isovalent Enterprise Hubble | maintained, with no collapse defect | not applicable | not applicable | Commercial, per principle 3 of [ADR-0000](0000-platform-foundations.md) |
| No map at all | the `hubble` CLI answers only point queries | not applicable | zero | The UI is free once Hubble runs |

### Service-map data source inside Grafana

Both candidate feeds fail by structure, so no Grafana service-map dashboard is built.

| Feed | Failure | Consequence |
| --- | --- | --- |
| Tempo `metrics-generator` `service_graphs` | An edge appears only when both sides of a `CLIENT` and `SERVER` span pair land in one instance. Measured: about 1 edge | The generator, Prometheus's `--web.enable-remote-write-receiver`, and a NetworkPolicy rule from Tempo to Prometheus stay undeployed |
| Hubble `flow` metric | With `sourceContext=workload`, the client side of most intra-cluster flows resolves to an empty label. Measured: 82 of 391 series with an empty source, and zero edges from platform to platform | A Node Graph collapses into one unnamed hub. The `flow` metric stays off |

### Kubernetes debug UI

| Option | Shared web origin | Verdict |
| --- | --- | --- |
| **[Headlamp](https://headlamp.dev/)**, CNCF Sandbox, Apache-2.0 | yes, aware of OIDC and headers | **Chosen.** It is one in-cluster deployment, and it fits the existing ops-origin pattern *(documented)* |
| k9s | no, it is a TUI | No shared origin and no edge gating. An engineer with cluster credentials already uses it. That is the point: this row is about the operator who has no credentials |
| Lens, or its OpenLens build | no, it is a desktop application | An install and credentials per workstation. So access comes from handing out kubeconfigs, not from an edge session |
| Skooner | yes | A lighter in-cluster dashboard. It uses a service-account token model, not forward-auth, and has fewer maintainers than the chosen option |
| Kubernetes Dashboard | yes | Its token-handling design and its CVE history are unwanted on an ops origin |
| `kubectl` alone, the honest baseline | no | Cluster credentials on a workstation answer every question that Headlamp answers. That is the distribution problem: one credential per workstation, not one origin behind the edge, per [ADR-0306](0306-trust-tiers-and-urls.md) |

## Decision

### Grafana owns application observability

Dashboards form a funnel of three levels. Each level answers one question and links down. All are JSON under `infra/observability/dashboards/`, per [ADR-0500](0500-observability.md).

| Level | Dashboard | Question | Home |
| --- | --- | --- | --- |
| L1 | **Overview**, `overview.json` | Whether anything is wrong now, and where | **yes** |
| L1.5 | **Applications**, `applications.json` | What runs, and how big or busy each workload is | |
| L2 | **Service detail**, `service-detail.json` | Which symptom this service shows: SLO, RED, resources, logs, traces, profiles | |
| L3 | **Platform components**, `platform-components.json` | Whether a stateful dependency is the cause | |
| L3 | **Network: policy denials**, `hubble-drops.json` | Whether a NetworkPolicy blocks a flow | |

**Overview's contract: every panel turns red or links down a level.** It has no deep-dive timeseries. The rows are in this order:

1. **Cluster capacity**: node CPU, memory, and free disk. Committed CPU and memory requests. Used pod slots.
2. Firing Prometheus alerts: a count and a table, from `ALERTS`.
3. Cluster-wide golden signals: total requests per second, 5xx percentage, p95.
4. Per-service SLO table: the SLIs and window that [ADR-0500](0500-observability.md) defines. The expressions match the Service detail SLO tiles, and each row links to it.
5. One-line platform-dependency stats for Postgres, Temporal, and policy drops, with links to their L3 dashboards.

Capacity sits above the alert count. This is the one exception to the rule that the verdict comes first. Capacity is the only *leading* row, and that earns it the position. Exhausted disk, memory, or schedulable capacity is still actionable, but a firing alert is already the incident. Capacity also has no other home, because every other panel is per service or per dependency.

The row shows both ceilings, because they are different failures. Committed requests predict that the scheduler refuses the next pod. Real usage predicts that the kernel kills a container. Either can happen while the other looks healthy.

**Applications** is the workload directory, one click below Overview. kubeletstats drives it, so idle and non-HTTP pods appear. The SLO table depends on HTTP traffic and does not guarantee this.

A new panel states its place. It changes the L1 verdict, or it describes one service at L2, or one dependency at L3. A question that fits none of the three is a Grafana Explore query, not a committed dashboard.

### Hubble UI owns the service map

Hubble UI is served at `hubble.ops.<host>` behind the ops forward-auth. That requires the operator claim and AAL2, with `dashboard:hubble#view` as the optional per-tool refinement, per [ADR-0304](0304-identity-and-authorization.md). `hubble.ui.enabled=true` in the Cilium values sets it up at the origin root, because its React Router cannot run under a path prefix. It reads the relay's live flow stream. It owns interactive drop investigation: `verdict=DROPPED` and the reason, live.

Two defects are accepted:

- **It collapses workloads that share `app.kubernetes.io/name` into one card.** All Temporal roles show as one `temporal` node. This is cosmetic. The map serves topology, and per-workload detail belongs to Grafana, where `k8s_deployment_name` separates the roles.
- **Upstream releases are slow.** This is accepted against the liveness criterion. It is a read-only viewer over data already collected, so abandonment costs the view and not the data. Under principle 4 of [ADR-0000](0000-platform-foundations.md), that is a low exit cost. The flows stay readable through the Hubble CLI and the drop metrics in Grafana.

### Headlamp owns pod-level debugging

Headlamp is served at `headlamp.ops.<host>` behind the same ops forward-auth. The optional per-tool grant is `dashboard:headlamp#view`.

Headlamp is bound to the built-in **`view` ClusterRole**. It allows list, get, watch, describe, and pod-log tailing. `view` grants no `create` verbs, so there is **no exec and no port-forward**, and it **cannot read `Secret` objects**. It is a debugging surface, not a control surface. It does not create, edit, or delete reconciled resources. Desired-state changes go through git and Argo CD.

A project that wants interactive exec or port-forward swaps `view` for a custom role with those verbs. It accepts the wider surface knowingly. A project that wants tighter limits narrows the role further, for example by dropping `pods/log`.

### Metric split between live and historical

`hubble_drop_total` is on for two things a live UI cannot do:

- **history**, in the `hubble-drops` dashboard
- **alerting**, through `PolicyDropsDetected` on `rate(hubble_drop_total{reason="POLICY_DENIED"}[5m])` in `infra/observability/alerts/policy-drops.yaml`

There are no per-service drop panels, because live investigation belongs to Hubble UI. The `flow`, `tcp`, `http`, and `dns` Hubble metrics stay off.

### Triage path

1. **Grafana `overview`**: whether anything is wrong, and which service or component.
2. **Service detail**: which symptom.
3. **Platform components**, **policy denials**, logs, traces: the cause.
4. **Hubble UI**: what talks to what, and whether the network denies a flow now.
5. **Headlamp**: which pods exist, and what they report.

No signal overlaps. Every application signal belongs to Grafana. The live flow map and drop inspection belong to Hubble UI. Drop history and alerting belong to Grafana, because they need Prometheus retention, which the UI does not have.

## Consequences

### Positive

- One stack to operate and one place to look first. There is no second observability suite to patch, store data for, or reconcile.
- Every dashboard is a git artifact: reviewable, reproducible, and visible to Argo.
- Operators land on a verdict, not on a table.
- The map and the debug UI cost nothing extra. Hubble already runs for the audit surface, and Headlamp is one deployment on the existing ops-origin pattern.
- Because UIs are read-only by default, no UI becomes a control plane that bypasses GitOps.

### Negative and Risks

- The map collapses multi-role workloads by name. This is accepted as cosmetic.
- Hubble UI upstream is stagnant. This is accepted, with the exception recorded above.
- Idle event-driven services show empty RED panels until traffic arrives. kubeletstats rows are always present.
- `view` blocks secrets, exec, and port-forward. But log tailing still shows any sensitive value an application logs. Pod specs and ConfigMaps also show inline env literals. Access requires the operator claim and AAL2.
- Headlamp is one more always-on component to patch in every environment. It is accepted as Core operational surface. A project removes it with `enabled: false` in the env overlay.

## Rules

- The Grafana stack owns application observability: overview, SLO and RED, resources, logs, traces, and profiling. Dashboards live as JSON under `infra/observability/dashboards/`.
- Dashboards sit in the funnel of L1, L1.5, L2, and L3. `overview.json` is the Grafana home dashboard, and every one of its panels turns red or links down a level.
- A question that fits no level in the funnel is a Grafana Explore query, not a committed dashboard.
- The service map is the bundled Hubble UI at `hubble.ops.<host>` behind the ops forward-auth. No separate APM suite is deployed.
- No Grafana service-map dashboard is built from Tempo `service_graphs` or the Hubble `flow` metric. Both fail by structure. Adding one back requires a new review of this ADR.
- The Hubble `drop` metric stays on for history and alerting. The `flow`, `tcp`, `http`, and `dns` metrics stay off.
- The Kubernetes debug UI is Headlamp. It is a Core component, deployed through Helm and Argo CD in every environment at `headlamp.ops.<host>` behind the ops forward-auth.
- Headlamp runs with a read-only ClusterRole. It is a debugging surface, not a control surface. Desired-state changes go through git and Argo CD, never through a UI.
