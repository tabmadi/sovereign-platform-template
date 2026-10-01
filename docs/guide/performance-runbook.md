# Load and performance runbook

This guide shows how to run a load test, read it, and record a baseline. [ADR-0601](../adr/0601-testing-strategy.md) holds the decision: k6, `test/perf/`, and OTLP into the existing collector.

## Model

- **k6** is the only load generator. It is a single static Go binary. `test/perf/.mise.toml` pins it, not the root toolchain. `mise run perf*` installs it on first use.
- Scenarios are JavaScript that **k6's own embedded engine** runs. No Node runs here. `test/perf/` has no `package.json`, no lockfile, and no `node_modules`. If you add one, `mise run lint:node-scope` fails.
- Runs drive the **edge** at `https://dev.localtest.me:8443/api/<path>`. So Traefik and the Oathkeeper forward-auth hop are inside every measurement.
- Metrics leave k6 over **OTLP into the cluster's OTel collector**. They land in Prometheus as `k6_*` series, on the same time axis as `k8s_pod_*`. No new component ingests them.

## Prerequisites

You need a running full tier: `mise run cluster:up -- full`. In a fresh checkout, the first `mise run perf*` also needs `mise trust test/perf/.mise.toml`.

## Run one

```bash
mise run perf:seed          # bulk products, so the read path has a realistic table
mise run perf:smoke         # ~30s: checks that the scenarios and the target are wired
mise run perf               # the baseline: `load` profile, both scenarios, ~7min
mise run perf:stress        # ramp to saturation; thresholds are EXPECTED to fail
mise run perf:soak          # ~30min sustained, for leak detection
mise run perf:seed -- --clean   # remove the seeded rows
```

`--clean` removes seeded **products** only. A `checkout` run also creates real orders and real Temporal workflow executions. No marker separates those from a human's orders. A `stress` run creates about 1,700 orders. They stay in place on purpose, because a guess by timestamp is unsafe. If the volume starts to matter, recreate the environment: `mise run cluster:down -- full && mise run cluster:up -- full`.

All of these settings are optional:

| Variable | Default | Effect |
| --- | --- | --- |
| `PERF_HOST` | `dev.localtest.me:8443` | the target edge. It is the only way to leave localhost |
| `PERF_VUS` | set by each profile | overrides the peak VU count |
| `PERF_OTLP` | `1` | `0` skips the collector forward. Results then stay in the terminal |
| `PERF_OTLP_PORT` | `14317` | the loopback port for the collector forward |

To run one scenario at one profile directly, run `bash test/perf/run.sh checkout stress`.

## The two scenarios

| Scenario | Drives | The ceiling it finds |
| --- | --- | --- |
| `browse` | `GET /api/products`, `GET /api/products/{id}` | edge throughput and the Postgres connection pool. Each request is cheap, so it saturates those first |
| `checkout` | `POST /api/orders`, polled until a terminal status | Temporal workflow throughput. Each request is expensive |

## Reading the result

You need both of these places:

1. **The terminal summary.** Thresholds set the exit code, so this is the pass or fail result. A threshold breach on a nightly `load` run is a performance regression to triage.
2. **The `Load test` dashboard** in Grafana, uid `load-test`. It shows the generator's throughput and latency above pod CPU, memory, and limit use for the same window. Here a number becomes a diagnosis.

### What the shapes mean

- **Throughput stays flat while VUs keep climbing.** You found the knee. Some resource is saturated at that request rate. The panels in the bottom row name it.
- **p99 moves away from p50 while throughput is flat.** This is queueing. Saturation shows this shape *before* it shows errors. It is the earliest true signal.
- **`checkout_settle` p95 climbs while `create_order` latency stays flat.** This is the typical async failure. The API accepts work faster than the Temporal workers finish it. Confirm it on `temporal schedule→start p95` in the bottom row.
- **Latency climbs while pod CPU stays flat.** The load is not CPU-bound. Look at the connection pool, the `postgres` backends, and lock contention. Do not look at the replica count.
- **Memory climbs through a soak and does not come back down.** This is a leak. Compare it with `Memory headroom against limit`. The OOM kill happens at 1.0.
- **The edge uses more CPU than the service.** This is expected on the read path. It is the reason `browse` drives the edge and not a port-forwarded pod. A measurement on the local tier at about 128 requests per second gave these figures: Oathkeeper about 190 mc, Traefik about 185 mc, and catalog about 120 mc. So the ingress and forward-auth hop costs about three times the business logic it protects. For sizing from a read-heavy workload, size the edge first.

### Two traps

- **When `Dropped iterations` is above 0, the numbers are wrong.** k6 could not start iterations on time. So the generator, not the platform, is the bottleneck, and every figure on the dashboard is too low. Before you trust such a run, take the `k6-operator` swap in the [operational surface](../operational-surface.md).
- **`checkout_settle` cannot resolve below the poll interval.** The interval is 1s, set by `POLL_INTERVAL_S` in `test/perf/scenarios/checkout.js`. A p95 of about 1.0s on an idle cluster means `too fast to measure`, not `one second`. The metric gets its resolution under load, where the real settle time is well above the interval.

### `stress` measures concurrency, not maximum throughput

Every scenario has think time: a `sleep` between requests. It makes a VU act like a user, not a tight loop. As a side effect, **each VU sends at most about one request per second**. So the `stress` profile's request rate depends on its VU count, not on the platform's capacity.

A measurement on the local tier gave these results, with latency flat at a p95 of about 5ms:

- 20 VUs produced 17 requests per second.
- 140 VUs produced 115 requests per second.

That is a straight line, not a knee. The generator limits its own pace, and the platform was never the constraint.

To find the real ceiling, raise `PERF_VUS` well past the profile default. Stop when latency bends or when `Dropped iterations` goes above zero. At that point, see the trap above, and take the k6-operator swap. The other method is to remove think time. Do that in a separate scenario, not by an edit to these scenarios. The baseline stays comparable only while its shape stays fixed.

### Seeding changes the server's work, not the response

`GET /api/products` runs `order by created_at desc limit 100` over an **unindexed** `created_at`. So the response holds at most 100 rows, for any number of products. But every request sorts the whole table to find them. Seeding does not grow the payload. It grows the server cost of each request, and that cost degrades with scale. This has two effects:

- `catalog_page_size` stops at 100. It does not report the table size.
- A latency number for this endpoint has no meaning without the seeded row count beside it.

## Local numbers are not capacity numbers

The generator runs on the same host as the cluster node and competes with it for CPU. A laptop's node count is not a production topology. **Saturation shapes transfer. Absolute ceilings do not.** Treat a local run as a relative regression signal against the previous baseline. For absolute figures, take the `k6-operator` Scale swap and generate load inside the cluster.

## Record a baseline

Run `mise run perf` on a quiet machine. Then record these values in the PR that changes performance:

- the `load` profile's p95 for each endpoint, and the checkout settle p95
- peak pod memory and CPU for the services under test
- the catalog row count, which is the `mise run perf:seed` size. A latency number without it has no meaning

Compare like with like: the same profile, the same seed size, and the same tier.

### The Prometheus side of a baseline is not durable

On the local tier, Prometheus's TSDB is an `emptyDir`, per the POC floor of ADR-0500. So **any rollout of the observability chart destroys all metric history.** `mise run cluster:add -- observability` and `cluster:down` both delete it at once, with no warning. A resource or capacity comparison that queries earlier numbers from Prometheus fails. It fails exactly when you redeploy to apply the change under measurement.

The `test/perf/results/*.json` summaries are files, and they survive. For this reason, they are the authoritative record. Copy them to a safe place before a redeploy. Write the peaks of each pod into the PR or the values comment. Do not expect to query them again.

### Interpreting a small delta

At the load profile, this platform serves latencies of a few milliseconds. So a *relative* percentage misleads. In one session, p95 varied between **4.40ms and 5.69ms across about 15 identical runs**. That is a spread of plus or minus 13% from noise alone. Two rules follow:

- Judge a latency change by its ABSOLUTE size first. At 5ms, a change below one millisecond is noise, however large the percentage looks.
- A freshly rolled cluster is slower for the first minutes. Postgres restarts with a cold buffer cache. Loki, Tempo, and the collectors all ingest again at the same time. Wait until the cluster settles, or take two samples, before you trust a regression.

## Cadence

| Suite | When |
| --- | --- |
| `perf:smoke` | for each PR, behind a label, together with `e2e:smoke` |
| `perf` with `load` | nightly, and before a release |
| `perf:stress` | on demand, before a sizing or HPA decision, per [ADR-0204](../adr/0204-resource-management.md) |

Performance suites are **not** part of `mise run test`, `check`, or `ci:affected`. They never gate a merge implicitly.
