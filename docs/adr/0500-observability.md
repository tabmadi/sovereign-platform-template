# ADR-0500: Observability

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0100](0100-language-and-runtime.md), [ADR-0103](0103-release-and-versioning.md), [ADR-0200](0200-cluster-topology.md), [ADR-0302](0302-temporal.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0304](0304-identity-and-authorization.md), [ADR-0305](0305-edge-auth-and-traffic-policy.md), [ADR-0400](0400-frontend.md), [ADR-0501](0501-operator-uis-and-dashboards.md), [ADR-0502](0502-alerting-and-on-call.md), [ADR-0503](0503-error-tracking.md), [ADR-0600](0600-local-development-loop.md)
- **Decides:** Every service is instrumented for all four signals through one `obs.Init` call, exports to a Grafana backend, and declares its SLIs.

## Context

A platform team cannot hold a whole fleet in its head. Observability is its only path to diagnose problems across that fleet, per [ADR-0000](0000-platform-foundations.md).

This ADR decides four things:

- which signals
- which backend
- how the signals are collected
- what a service author must do

**The requirement of zero work per service is load-bearing.** Without it, observability falls behind the fleet and never catches up. A new service does not need a new collector pipeline, a new dashboard, or a new alert.

## Decision drivers

1. **Configuration lives in the repository**, per principle 1 of [ADR-0000](0000-platform-foundations.md). Dashboards and alerts are files that are reviewed and reconciled.
2. **OpenTelemetry first.** Instrumentation is vendor-neutral, so backends stay replaceable.
3. **Pre-wired defaults in shared libraries.** Service code makes one call and gets everything.
4. **Self-host**, per principle 3 of [ADR-0000](0000-platform-foundations.md).
5. **The query language outlives the backend.** Dashboards, alert rules, and engineers' habits all use it. So a proprietary query language is the real lock-in.
6. **Cross-signal correlation.** A log links to its trace, a trace to its profile, and a metric to trace exemplars.

## Considered options

### The backend stack

| Option | Dashboards and alerts as code | Signals covered | Query language | Verdict |
| --- | --- | --- | --- | --- |
| **Grafana stack: Loki, Prometheus, Tempo, Pyroscope** | **JSON and YAML files in git**, reconciled by Argo | all four, and browser RUM through a Faro receiver | PromQL, LogQL, and TraceQL, all portable | **Chosen** *(reasoned)* |
| VictoriaMetrics, VictoriaLogs, VictoriaTraces | files, and Grafana stays the UI | three, with no continuous profiling | **PromQL-compatible**, and MetricsQL | The serious challenger on operational weight. It uses much less resource than Prometheus and Loki at the same retention. It keeps driver 5, because Grafana and PromQL do not change. It loses on completeness. Profiling has no counterpart, so Pyroscope stays and the consolidation is partial. The components also differ in maturity, and the traces backend is the youngest |
| SigNoz | **UI-only click-ops state in ClickHouse** | three, with no continuous profiling | its own | It merges four components into one. Against a fixed operational budget, that is the strongest case any option here makes. It fails driver 1 completely. The same driver rejects Coroot in [ADR-0501](0501-operator-uis-and-dashboards.md). It also loses continuous profiling and the Faro RUM receiver |
| OpenObserve | **UI-only click-ops state** | three | its own | The same failure as SigNoz on driver 1, and a query language that is not portable |
| Elastic stack | index templates and dashboards can be exported, but the working source of truth is the UI | three | its own | It is heavier to operate than the whole Grafana stack. Its query language is the one that does not travel. Elasticsearch has offered AGPL-3.0 again since 2024, so the licence is no longer the objection |
| One vendor's managed platform | not applicable | all | proprietary | Excluded by driver 4 |

### Component substitutions inside the stack

The table above chose a stack. Each member was also compared with the strongest single-signal alternative. A stack that is right as a whole can still carry one wrong component.

| Component | Alternative | Verdict |
| --- | --- | --- |
| Grafana | [Perses](https://www.cncf.io/projects/perses/) | Dashboards as code is its native model, not a convention. That is the one place where an option beats Grafana on driver 1. It replaces only the UI. Hubble, CNPG, and k6 all publish Grafana dashboards, so adopting it splits the dashboard surface until its plugin ecosystem covers them. CNCF Sandbox |
| Grafana | Kibana | The UI of the Elastic stack above. It does not read the other three signals |
| Prometheus | [InfluxDB 3 Core](https://www.influxdata.com/blog/influxdb3-open-source-public-alpha-jan-27/) | Its query range has a cap of 432 Parquet files, which is about 72 hours. Enterprise lifts the cap. An SLO window is 30 days |
| Tempo | Jaeger | It needs Cassandra, Elasticsearch, or OpenSearch behind it. Tempo uses an object store, which this platform runs anyway, per [ADR-0207](0207-cluster-storage.md) |
| Tempo | Zipkin | A JVM on the floor, which [ADR-0100](0100-language-and-runtime.md) bars, behind a second datastore |
| Pyroscope | [Parca](https://github.com/parca-dev/parca) | Its own UI next to Grafana's. Continuous profiling pays off here because a profile opens from the trace that led to it. That join is Grafana's |

### The collection tier

| Option | Added workloads | Enrichment with pod metadata | Verdict |
| --- | --- | --- | --- |
| **OTel Collector as a DaemonSet** | one per node | at the node, from the kubelet | **Chosen.** Every service emits to `localhost:4317`. So the destination is a collector concern, not an application concern *(reasoned)* |
| DaemonSet and a gateway Deployment | one per node, and a tier | as above | The right shape once spans must be held to sample on outcome. It is the deferral below, and adding it changes no service |
| A gateway Deployment only | one tier | **no.** The collector is off-node, so the workload must send pod attributes | Every service then owns resource-attribute correctness. Driver 3 removes exactly that |
| Grafana Alloy for everything | one per node | yes | It already runs for `pprof` scraping, and it is a Grafana distribution of the same collector. Using it for OTLP too trades the vendor-neutral collector for a vendor's build, against driver 2 |
| Vector | one per node | yes for logs | Good at logs, but not an OTLP-native path for traces or profiles. So it covers one signal of four |
| Direct from SDK to backend | none | in each service | Every service learns every backend's address and protocol. A backend change becomes a fleet-wide redeploy |

The deciding property is the same one that decided identity in [ADR-0304](0304-identity-and-authorization.md) and the operator UIs: **a component whose configuration lives in its own database is invisible to review and to Argo.** Applying that to observability and not to identity, or the reverse, would be the inconsistency.

## Decision

### All four signals, instrumented on day one

The four signals are logs, metrics, traces, and continuous profiles. Every service has all four from creation. Partial instrumentation leads to knowledge that only one team has, such as metrics here and traces there. The per-service cost principle cannot absorb that.

### Instrumentation: one call

`libs/go/observability/` wires every signal:

```go
func main() {
    shutdown, err := obs.Init(ctx, obs.Config{ServiceName: "payment"})
    if err != nil { log.Fatal(err) }
    defer shutdown(ctx)
}
```

`obs.Init` does six things in order:

1. Reads `OTEL_*` environment variables. There are no service-specific flags.
2. Configures the global tracer, meter, and logger providers with OTLP exporters that point at the node-local collector.
3. Configures `slog` with an OTel-aware handler that **attaches `trace_id` and `span_id` from the context automatically**.
4. Registers `pprof` endpoints on the admin port, so any profiler or a human reaches a live process.
5. Serves `/livez` and `/readyz` on the admin port.
6. Returns a shutdown function that flushes all signals.

**Liveness never checks dependencies.** So a short dependency failure takes the pod out of Service rotation through `/readyz`, **without** a restart. The shared dependency wiring registers its own checks. So each service gets exactly the checks for the dependencies it opens, with no per-service code. Servers probe both endpoints. Workers probe liveness only.

Service authors never touch the OTel SDK. Custom spans and counters go through `obs` helpers.

**Pre-wired middleware**, which the service template imports automatically:

| Package | Wraps | Emits |
| --- | --- | --- |
| `libs/go/httpmw/` | HTTP server and client | trace span, RED metrics, structured access log |
| `libs/go/dbmw/` | the `pgx` tracer | a span per query, statement metrics |
| `libs/go/temporalmw/` | Temporal client and worker interceptors | workflow and activity spans, duration metrics |
| `libs/go/authmw/` | identity-header reading | authz-failure metrics, user and org attributes on the active span |

**What a service author adds** beyond the defaults:

- log messages with business meaning
- custom RED metrics for business KPIs
- custom spans, only where the middleware does not already cover a slow operation

### Backend

| Component | Role | Storage |
| --- | --- | --- |
| Loki | logs | monolithic mode, backed by the external bucket |
| Tempo | traces | monolithic mode, backed by the external bucket |
| Prometheus | metrics | single binary, local TSDB, native OTLP ingest, and no object-storage dependency |
| Pyroscope | profiles | see below |
| Grafana | one UI for all signals, with cross-signal navigation | none |

Sizing: production runs Loki and Tempo at two replicas each, and Grafana at two. Prometheus runs single, because its HA path is the Mimir swap, not a replica count. Non-prod runs single replicas. There, failure tolerance for observability is not worth the resources.

**Mimir is the metrics scale swap.** It beats Thanos and Cortex because its query API is Prometheus's, without a sidecar or a query layer in front. It beats a VictoriaMetrics cluster because that cluster changes the query dialect of the dashboards and alert rules.

| Field | Value |
| --- | --- |
| **Trigger** | Prometheus's active-series count crosses the paging threshold below and more memory is no longer the cheap answer. Or a retention obligation needs more than one local TSDB holds |
| **Seam** | ✓ Prometheus-compatible: the same query API, dashboards, and alert rules. The change is storage configuration, and no instrumentation moves |
| **Cost if adopted late** | the series that forced the change are already dropped, or the TSDB is already trimmed. So the history the migration was meant to keep is already lost |

Loki and Tempo have the same seam into their own microservices modes. Object storage already holds the data, so the split is a values change, not a data migration.

### Collection: one collector tier

The OTel Collector runs as a **DaemonSet** on every node. Services send OTLP to `localhost:4317`. The agent does these steps:

- batches the data
- enriches it with Kubernetes resource attributes
- applies head sampling
- enforces resource limits
- exports directly to the backends

There is no gateway deployment.

**Tail sampling is deferred.**

| Field | Value |
| --- | --- |
| **Trigger** | a latency investigation fails twice because head sampling discarded the slow traces |
| **Seam** | ✓ services only emit to `localhost:4317`. So the gateway tier is a deploy and a collector config change, and no service changes |
| **Cost if adopted late** | nothing structural. The investigations that caused it are already over, and tail sampling cannot recover a span that was never kept |

**Logs take a separate path.** Services write structured JSON to **stdout**. The agent reads the pod log files, parses them, attaches attributes, and forwards them. Because logs go to stdout first, they survive even when the OTel SDK fails to start. That is [12-Factor XI](https://12factor.net/logs): the service writes an event stream and never handles routing or storage. The collector is the router.

**Browser telemetry** comes from the frontend's Faro agent, per [ADR-0400](0400-frontend.md). It enters through a `faro` receiver on the same collector. A Traefik route feeds that receiver, on a vendor-neutral path that names the concern and not the agent. The receiver emits web traces and RUM events into the same pipelines. So browser and service signals share backends and trace ids.

### Continuous profiling

`obs.Init` already registers pprof endpoints, so every Go service can be profiled at zero cost. An **Alloy** agent scrapes those endpoints and pushes to **Pyroscope**. Grafana shows the result as the flame-graph panel on the service-detail dashboard, per [ADR-0501](0501-operator-uis-and-dashboards.md). So profiles sit in the same pane as the signals that led to them.

An eBPF node-agent profiler was an option with zero instrumentation. It was rejected together with its whole suite, per [ADR-0501](0501-operator-uis-and-dashboards.md). The pprof endpoints already exist. So scraping them adds no instrumentation cost and keeps profiles in the same backend family.

### Conventions

| Concern | Rule |
| --- | --- |
| Log format | structured JSON to stdout. `fmt.Println` for diagnostics is not used |
| Log levels | `DEBUG` off in production, `INFO` for lifecycle, `WARN` for recoverable abnormal states, `ERROR` for failed operations. `FATAL` and `PANIC` only at startup |
| Trace context | W3C `traceparent` across HTTP and Temporal. Traefik and Oathkeeper keep it at the edge |
| Resource attributes | set once by `obs.Init`. They are the service name, the version and build SHA from the baked-in build info, the namespace, and the environment. [ADR-0103](0103-release-and-versioning.md) sets the build info |
| Metric naming | OTel semantic conventions where they exist, and `<service>_<noun>_<unit>_<type>` where they do not |
| HTTP RED | the stable semantic-convention histogram. No parallel custom duration metric is recorded, and dashboards query only the stable name |
| Workload CPU and memory | the collector's `kubeletstats` receiver, so **every pod appears even when idle**. Pushed signals exist only under live traffic, and that difference is expected |
| PII | never in logs, metrics, traces, or profiles. `libs/go/observability/redact/` provides safe formatters |
| Sampling | head sampling at 100% for errors and 5% for healthy traces, configured centrally. Local development sets healthy traces to 100%, so a developer sees the request they made. Service authors do not set rates |

### Cardinality discipline

High-cardinality labels destroy a metrics store. There are three layers of defence:

1. **API-level enforcement.** The `obs` metric helpers take an allow-listed label set. They do not expose arbitrary attributes.
2. **Live alerts.** The TSDB series count feeds an alert. It warns at 70% of the active-series ceiling and pages at 90%. Service-level alerts fire when a single metric grows past its budget.
3. **Quarterly audit.** A Temporal `Schedule` opens a tracking issue with the top series counts per service.

### Service level objectives

An SLO is a definition, not a component. This ADR decides it for two reasons. The SLIs are signals that this ADR already requires. Three other decisions also assume a definition exists:

- the SLO tiles of [ADR-0501](0501-operator-uis-and-dashboards.md)
- the error budgets of [ADR-0502](0502-alerting-and-on-call.md)
- the load thresholds of [ADR-0601](0601-testing-strategy.md)

**Every service declares two SLIs, and both come from the stable RED histogram.** There is no new instrumentation, and no second source of truth for what `up` means:

| SLI | Expression | Good event |
| --- | --- | --- |
| **Availability** | request count by status class | a response that is not `5xx`. A `4xx` is the caller's fault and does not spend the budget |
| **Latency** | the duration histogram's cumulative buckets | a request that completes under the service's declared threshold |

| Field | Value |
| --- | --- |
| Where declared | `slo.yaml` next to the service's dashboard and alert defaults, inherited from `services/_template/` |
| Window | 30 days, rolling. A calendar month resets the budget on a date and not on a fault |
| Scope | the service's own request path. A dependency's failure also spends the dependant's budget, because the user experienced it |
| Excluded | anything without a live caller: `/livez`, `/readyz`, and the admin port |

**The objective is a per-project number. The platform states its ceiling, not its value.** A target is a claim about response, so the floor's detection latency limits it. An objective tighter than the time to notice a fault is a number nobody can meet. [`docs/reference/detection-latency.md`](../reference/detection-latency.md) holds that composition per failure class. The escalation trigger of [ADR-0502](0502-alerting-and-on-call.md) raises the ceiling.

So the template ships the **mechanism and the default thresholds**, and it does not ship the objective. A number inherited from a template is a number nobody chose. Nobody spends an error budget that nobody chose. They ignore it.

### Dashboards and alerts as code

| Artefact | Source | Delivery |
| --- | --- | --- |
| Dashboards | JSON at `infra/observability/dashboards/` | a ConfigMap mounted by Grafana's file provisioner |
| Alerts | native Prometheus rule files at `infra/observability/alerts/` | a ConfigMap mounted into Prometheus |

Routing, grouping, and silencing belong to **Alertmanager**, as decided in [ADR-0502](0502-alerting-and-on-call.md). Alerts evaluate here, from these files. They are never authored as Grafana-managed rules.

Per-service defaults ship in `services/_template/`: a default dashboard and a default alert set, inherited by name convention.

### Local development

Observability runs in the full tier, per [ADR-0600](0600-local-development-loop.md). It uses the same chart as every environment, at a single replica. So the test covers the backend wiring itself, not only the export from the service. The inner loop has no collector.

Service code is the same locally and in production. The same `obs.Init` works against either. When neither runs, the exporter has no collector to reach.

**Browser RUM needs a stand-in locally**, because the dev server runs on the host with no edge in front of it. A dev-only route handler does three things:

- it forwards beacons to a port-forwarded collector when one is configured
- it returns `204` when none is configured, so the console gets no spam
- it returns `404` in production, because in the cluster Traefik owns that path, not the frontend pod

## Consequences

### Positive

- Zero observability work per service. The template is the contract, and a service that follows it is fully observable.
- One UI, four signals, and deep correlation.
- OTel first keeps the backend replaceable.
- Logging to stdout first handles failure modes by default.
- Dashboards and alerts are reviewed like code.

### Negative and Risks

- **The backend has a real operational cost**, even in monolithic mode. Each backend stays a system with its own runbook. The mitigations are single-binary deployments, bucket durability, a local TSDB with no dependencies for metrics, and single replicas in non-prod.
- **Cardinality discipline depends on three layers of defence.** None of them is enough alone.
- **No tail sampling by default.** Head sampling can drop a slow trace whose siblings looked healthy. This is accepted, and the gateway seam is documented.
- **Profiling scrapes first-party services only.** Third-party components without pprof endpoints are not profiled. Metrics and logs cover their health.
- **Alerts route, but nothing pages.** [ADR-0502](0502-alerting-and-on-call.md) ships the routing tree and leaves escalation as a recorded concession. So an overnight incident is found in the morning.

## Rules

- Every service initialises observability with `obs.Init`. Direct OTel SDK use in service code is not permitted. `(CI: ci:lint)`
- Every service imports the pre-wired middleware by default.
- Logs are structured JSON to stdout. `fmt.Println` and unstructured loggers are not used. `(CI: lint:log-vocab)`
- Log levels follow the conventions table, and `DEBUG` is off in production.
- Metrics use the `obs` helpers with allow-listed labels. High-cardinality attributes are not used as metric labels. `(CI: ci:lint)`
- Trace context propagates through W3C `traceparent`. The edge keeps it, and Temporal middleware propagates it. `(ref: W3C Trace Context)`
- PII is never written to logs, metrics, traces, or profiles.
- Sampling is configured centrally. Service authors do not set sampling rates.
- Dashboards live as JSON and alerts as YAML under `infra/observability/`. UI-only edits are not made. Changes are PRs.
- The backend is the Grafana stack and a single-tier collector. Other backends require an ADR.
- Every service declares an availability SLI and a latency SLI in `slo.yaml`. Both come from the stable RED histogram over a 30-day rolling window. `(CI: lint:service-contract)`
- A `5xx` spends the budget and a `4xx` does not. Health and admin endpoints are excluded from both SLIs.
- An availability objective is stated per project, and it is never tighter than the detection latency that its coverage supports.
- Long-term log and trace data lives in the off-cluster bucket. Local volumes hold only hot cache.
- Every service exposes `/livez` and `/readyz` on the admin port, and liveness never checks dependencies. `(CI: lint:service-contract)`
