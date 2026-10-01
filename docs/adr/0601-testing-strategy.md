# ADR-0601: Testing Strategy

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0100](0100-language-and-runtime.md), [ADR-0101](0101-monorepo.md), [ADR-0204](0204-resource-management.md), [ADR-0205](0205-environment-parity.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0400](0400-frontend.md), [ADR-0500](0500-observability.md), [ADR-0600](0600-local-development-loop.md)
- **Decides:** Correctness is tested in layers from unit tests to e2e on the full local platform, and load testing sits beside the layers without gating them.

## Context

Other ADRs fix parts of testing, and none owns the whole:

- [ADR-0101](0101-monorepo.md) fixes the task names and affected-detection.
- [ADR-0400](0400-frontend.md) fixes the frontend unit and component tests.
- [ADR-0205](0205-environment-parity.md) fixes the tier that e2e runs on.
- [ADR-0304](0304-identity-and-authorization.md) fixes its own authz conformance suite.

This ADR owns the question that crosses them. It defines the acceptance test for a working platform, where that test lives, what drives it, and when it runs.

Testing answers two separate questions. A suite that mixes them answers neither:

| Question | Verdict | Load |
| --- | --- | --- |
| **Is it correct?** | works, or broken | about one user |
| **What does it cost, and where does it break?** | within budget, regressed, or saturated | past the knee, on purpose |

Three accepted decisions depend on the second answer:

- [ADR-0204](0204-resource-management.md) requires CPU and memory requests for each container. It makes HPA opt-in, based on `a documented sustained-load signal`. Both rules exist because nothing produces the number.
- [ADR-0500](0500-observability.md) and [ADR-0501](0501-operator-uis-and-dashboards.md) define the tools that observe saturation: the capacity row, and the `ClusterCPURequestsCommitted` and `NodeMemoryPressure` alerts. Nobody knows the shape of an alert that nobody has seen fire.
- [ADR-0000](0000-platform-foundations.md) claims that **fixed platform cost dominates variable application cost**. The claim is quantitative, and load testing measures it.

A measurement on `cluster:up full` with one node, during the e2e suite, gave this result: **no business service is among the top consumers of memory or CPU.** The observability stack alone uses more than all services together. At about one user, all of the cost is platform cost. The `load-test` dashboard can reproduce this measurement.

The absolute footprint grows with the fleet and with log volume. The shape does not grow, and the tiers below depend on that.

## Decision drivers

1. **The rendered, authenticated UI is the final guarantee.** A working dashboard behind a real session proves that the edge, auth, services, and data are wired. Browser acceptance is the gauge. Cheaper checks exist to find the location of a failure faster.
2. **One tool, one way**, per principle 5 of [ADR-0000](0000-platform-foundations.md). One engine drives product journeys, operator dashboards, and visual regression.
3. **The cost is the bring-up, not the test.** Every full-platform suite shares one expensive prerequisite. So the cadence spreads one bring-up across every suite that needs it.
4. **No mocks in acceptance.** E2e runs against real services.
5. **Cost for each service.** An automatic full-platform bring-up on every PR does not scale with a growing fleet.
6. **No new always-on component and no new runtime** for load testing. A generator that runs for minutes each week must not join the Core floor in [`docs/operational-surface.md`](../operational-surface.md).
7. **Results land in the stack that already runs.** A load tool with its own metrics store, dashboards, and query language is a second observability plane.

## Considered options

### Browser, e2e, and visual engine

| Option | Cross-origin | Visual regression | Runtime | Verdict |
| --- | --- | --- | --- | --- |
| **Playwright, in TypeScript** | native, with a driver in a separate process | built in: [`toHaveScreenshot`](https://playwright.dev/docs/test-snapshots) | Node | **Chosen.** Its auto-waiting gives the fewest flaky results on heavy SPA dashboards. It crosses the Kratos redirect and the `*.ops.<host>` subdomains natively, per [ADR-0306](0306-trust-tiers-and-urls.md) *(documented)* |
| WebdriverIO | BiDi | an added service | Node | More flaky results by default, and its added visual service fails where sensitivity is highest. Its decisive strength, native mobile, is not used here. It does not remove the Node runtime either |
| Cypress | works against it: a single browser context | good | Node | The auth-redirect and ops-subdomain topology is its weak point |
| Puppeteer | CDP, Chromium first | **none** | Node | Much of this field builds on this automation library. It has no runner, assertions, retries, or baseline flow. Playwright is that library plus the parts that a suite needs |
| Rod or chromedp, in pure Go | workable | **none**. Pixel diffing, baselines, and a review flow must be written by hand | Go | The only path without Node. It is rejected on the two most needed capabilities. Raw-CDP auto-wait is weaker on heavy dashboards |
| Stagehand, Midscene, Shortest | from the engine below | from the engine below | Node | They build on Playwright or CDP, or put a nondeterministic LLM in the loop and lean towards the cloud. They wrap an engine that must still be chosen |

### Load generator

| Option | Runtime added | Scenario artefact | Metrics path | Verdict |
| --- | --- | --- | --- | --- |
| **k6, from Grafana** | none. A single static Go binary with an embedded JS engine, Sobek | committed JS files | built-in OTLP output | **Chosen.** Thresholds set the exit code, so a run is a CI gate with no wrapper *(documented)* |
| Locust | Python: a third toolchain, a pip tree, and an image | committed Python | its own store, which needs an exporter sidecar | Fails drivers 6 and 7 |
| Gatling | JVM, with a Scala or Java DSL | committed DSL | an HTML report, which is a second, offline results plane | The strongest reporting in the field, rejected on drivers 6 and 7 |
| JMeter | JVM | **an XML blob written in a GUI** | its own | A reviewer sees a blob. This works against config-as-code, per principle 1 of [ADR-0000](0000-platform-foundations.md) |
| Vegeta | none, it is Go | a URL list | its own | It sends requests to URLs at a constant rate. The interesting path has several steps and state, and Vegeta models that only through shell scripts around it |
| Write one in Go | none | Go | ours | It rebuilds VU scheduling, ramping executors, percentile aggregation, and threshold evaluation, only to avoid one pinned binary |

### Where a service integration test gets its dependencies

| Option | Source of Postgres, Temporal, OpenFGA | Fidelity to production | Cost per run | Verdict |
| --- | --- | --- | --- | --- |
| **`cluster:up` plus the service's declared components** | the same charts that production runs, per [ADR-0205](0205-environment-parity.md) | **the operators, the CRDs, and the network policy** | one cluster, shared by every test in the run | **Chosen.** Each service already declares its dependencies for deployment. So the test environment comes from the deploy manifest, and nobody describes it twice *(reasoned)* |
| testcontainers-go | one container for each dependency, started by the test process | plain images: no CNPG, no operator behaviour, no NetworkPolicy | one container set for each package, removed afterwards | The industry default for Go service tests. Each service then declares its dependencies a second time, in Go. It also cannot exercise the operator-managed behaviour of this platform's data tier: failover, the pooler, the seeded authz model |
| A shared long-lived test database | a persistent environment | high | none per run, but tests interfere with each other permanently | State leaks between runs. A failing test becomes a question about who else was running |
| Mocks at the repository boundary | nothing | none. The SQL never runs | fastest | It tests the code against its own assumptions about Postgres. That layer is exactly what these tests exist to check |

**testcontainers is the strongest rejected option**, for one specific reason. This platform's dependencies are operator-managed, so a plain `postgres:17` container is not what production runs. For a platform built on plain images, that verdict reverses.

### Contract testing

| Option | What it verifies | Where the truth lives | Verdict |
| --- | --- | --- | --- |
| **The generated client, compiled against the spec** | that the consumer and the provider agree, at build time | the OpenAPI spec, per [ADR-0303](0303-api-contracts-and-lifecycle.md) | **Chosen by inheritance.** Every consumer calls through generated code, and CI fails on stale generated code. So a contract break is a compile error, not a test failure *(reasoned)* |
| Pact, or another consumer-driven contract broker | that a consumer's expectations still hold | pacts that consumers write, plus a broker to store them | Consumer-driven contracts solve a problem that this repo does not have: consumers that ship separately from providers. Here they ship in the same commit, per [ADR-0103](0103-release-and-versioning.md). The broker is also a component |
| Microcks as a contract test | that a running provider matches the spec | the spec | [ADR-0600](0600-local-development-loop.md) already compares it as a mock and rejects it on its MongoDB dependency. The same cost applies here |
| schemathesis or another spec fuzzer | that the provider handles the inputs that the spec permits | the spec | An addition, not an alternative. It tests robustness, and the generated client tests agreement |

### Runtime for the Playwright runner

Bun is the only JS runtime, per [ADR-0100](0100-language-and-runtime.md). It **cannot run a browser test runner reliably**.

Playwright, like every Node browser runner, starts the browser with extra file descriptors, fd 3 and fd 4, as a pipe transport. It also forks workers over Node IPC. These are rarely used corners of `child_process`, and Bun does not match them. The browser launch hangs or crashes with a segfault, and the runner produces no output. The gap covers the whole Node ecosystem. It is not a Playwright bug. It is also not a temporary state to build on, per [ADR-0000](0000-platform-foundations.md).

So Node is permitted as a **test-only escape hatch**. Its scope is the e2e and visual runner alone.

## Decision

### Correctness layers

| Layer | Tool | Environment | Role |
| --- | --- | --- | --- |
| Unit and component | `go test`, `bun test` | none, or `happy-dom` | logic and component shape in isolation |
| Service integration | `go test` with generated SDK clients, per [ADR-0303](0303-api-contracts-and-lifecycle.md) | `cluster:up` plus the service's declared components | one service against real Postgres, Temporal, and OpenFGA |
| Preflight readiness | Go or shell | `cluster:up full` | failure **localiser**: pods ready, ports open, Postgres and Oathkeeper reachable |
| **Browser acceptance** | **Playwright** | `cluster:up full` | **the gauge**: product journeys and operator dashboards behind a real AAL2 session |
| Visual regression | Playwright `toHaveScreenshot` | `cluster:up full`, or a static render | component shape against committed baselines |

Preflight runs before the browser suite. So a red e2e result reads at once as `infra down`, not as `app broken`. Preflight is triage, not a second acceptance test. The browser test gives the final verdict.

**These are layers, not a pyramid.** Counted by number of tests, not by scope, the shape is closer to a honeycomb. It has a thin base, a thick middle, and a top that carries the verdict. Three properties give it this shape:

- **The mock-heavy integration tier of a pyramid has little left to catch.** Clients and validators are generated from the spec and checked for drift, per [ADR-0303](0303-api-contracts-and-lifecycle.md).
- **The costly failures on this platform cross services and involve auth.** Examples are a header injected at the edge, an AAL2 session, and an OpenFGA tuple. None of these is visible below the browser layer.
- **The usual objection to a heavy top does not apply here.** `cluster:up full` runs the same charts as production, per [ADR-0205](0205-environment-parity.md). So end-to-end tests do not run against a fiction.

### Load is a fourth concern, not a fifth layer

Load testing sits beside these layers, not on top of them. A red load run means `slower than the budget`, not `broken`. So **performance tests are not part of `mise run test`, `ci:affected`, or the e2e suites, and they never gate a merge implicitly**.

### Layout

| Workspace | Contents |
| --- | --- |
| `test/e2e/platform/` | cross-service product journeys, from register through catalog and order to pay, and operator-dashboard journeys behind an AAL2 session |
| `test/e2e/frontend/(landing\|panel\|devportal)/` | frontend suites for each route group |
| `test/e2e/visual/` | component visual regression against committed baselines |
| `test/perf/lib/` | shared configuration, target resolution, thresholds, response checks |
| `test/perf/scenarios/` | one runnable k6 script for each load shape |
| `test/perf/seed/` | bulk data provisioning, so read paths meet a realistic table |

All e2e and visual tests share one Playwright config in the `test/e2e/` workspace at the repo root.

### Runtime containment

`test/e2e/.mise.toml` pins Node, never the root toolchain. So Node installs only for a developer who runs the suite. `test/perf/.mise.toml` pins k6 as an island tool. The root `perf*` tasks delegate with `mise run -C test/perf <task>`.

k6 scenarios are JavaScript on k6's own embedded engine. **This does not extend the Node escape hatch.** `test/perf/` has no `package.json`, no lockfile, no `node_modules`, and no Node binary. `lint:node-scope` asserts that npm exists only in `test/e2e/`.

### Load scenarios

Both committed scenarios drive **through the edge**: Traefik, then Oathkeeper, then the service. They do not drive a port-forwarded pod. The edge is part of the system under test, and [ADR-0305](0305-edge-auth-and-traffic-policy.md) puts a forward-auth hop on every request.

| Scenario | Path | The ceiling it finds |
| --- | --- | --- |
| `browse` | `GET /api/products`, `GET /api/products/{id}` | the edge and the connection pool. Each request is cheap |
| `checkout` | `POST /api/orders`, then a poll until a terminal status | workflow throughput: the edge, orders, the Temporal saga, catalog, and payment |

`PROFILE` selects one of four profiles. The profiles are data, not duplicated files:

| Profile | Shape |
| --- | --- |
| **`smoke`** | 1 VU for seconds. It proves that the script and the target are wired |
| **`load`** | the steady baseline that regressions are measured against |
| **`stress`** | a ramp past the knee until thresholds break |
| **`soak`** | sustained load, for leak detection |

### Load results reach Prometheus through the collector

k6 runs with `--out opentelemetry` and exports to the existing OTel collector. This keeps the invariant of [ADR-0500](0500-observability.md): the only path to Prometheus is an OTLP push. So a load run needs no remote-write receiver and no scrape config.

- Series carry the `k6_*` prefix, set by `K6_OTEL_METRIC_PREFIX`, and the label `service_name="k6"`. So they sit next to `k8s_pod_cpu_usage` on one time axis, and nobody mistakes them for a service's own telemetry.
- k6's `url`, `name`, and `error` system tags are **not** exported. They are unbounded by design: a URL label creates one series for each product id. A hand-written `endpoint` route-template tag replaces them.
- `--no-usage-report` turns off anonymous usage reporting. This matches the no-phone-home position for Temporal and the object store.

The **`load-test` dashboard** compares k6 throughput, latency percentiles, and error rate with pod CPU, memory, and limit use. It sits **outside the L1 to L3 triage funnel** of [ADR-0501](0501-operator-uis-and-dashboards.md). That funnel diagnoses an unplanned incident. A load test is a planned experiment, and the operator knows what they are looking at. The `perf` task output links to the dashboard. Overview does not.

### Where load comes from

The default runner is k6 on the developer or CI machine, aimed at the edge. It adds nothing to the cluster. The generator competes with the node for host CPU. So **local numbers are a regression signal and a saturation-shape signal, never an absolute capacity figure**.

**Scale swap:** `k6-operator`, which generates load from several pods inside the cluster. **Trigger:** k6 reports `dropped_iterations` above 0 at the target rate, or absolute capacity figures are needed. **Seam:** the scenarios stay the same. Only the place where the VUs run changes.

### Cadence

| Suite | Trigger | Contents |
| --- | --- | --- |
| Unit, component, and integration | each PR, scoped to affected services, per [ADR-0101](0101-monorepo.md) | `go test`, `bun test`, integration with dependencies only |
| `e2e:smoke` | each PR, **behind a label** | one golden product path plus the render of a key dashboard |
| `perf:smoke` | each PR, behind a label, together with `e2e:smoke` | a check that the scenarios still run, about 30s |
| `e2e` | nightly when there was activity, and before a release, per [ADR-0103](0103-release-and-versioning.md) | every journey, every operator dashboard, all visual baselines |
| `perf` with `load` | nightly when there was activity, and before a release | the tracked baseline number |
| `perf:stress` | on demand, before a capacity decision | the knee, which gives the sizing and HPA signal for [ADR-0204](0204-resource-management.md) |

Affected-detection scopes the cheap layers that run on each PR. The full-platform suites are separate CI jobs and are not part of `ci:affected`. Every e2e test crosses service boundaries by nature.

Load thresholds live in the scenario files. They are **budgets, not SLOs**. They are looser than the service SLOs of [ADR-0500](0500-observability.md) on purpose. A load run pushes into a range where the SLO is expected to break. A threshold breach fails the run. A nightly breach is a regression to triage, not a rollback trigger.

### Test data

Kratos starts with an empty identity store and no seeded user. Mail goes to the non-production sink, not to a recipient, per [ADR-0307](0307-outbound-email.md). E2e ships a **committed deterministic test-identity bootstrap**: an AAL1 product user and AAL2 operators. It provisions the identities in the same way in CI and locally. This is the disposable-credential pattern that SOPS uses for the local age key, per [ADR-0205](0205-environment-parity.md). The identities live at `test/e2e/fixtures/identities.ts`.

No test depends on state that someone created by hand. The same bootstrap provisions the identity that the `edge` development profile logs in as, per [ADR-0600](0600-local-development-loop.md). So the bootstrap runs every day, not only nightly.

Load runs generate real data. A checkout run creates real orders and Temporal executions in the target environment. `test/perf/` refuses to run against a target unless someone points it there explicitly. Seeded data carries a recognisable prefix, so it can be found and removed.

### Visual baselines

The CI gate diffs committed, accepted snapshots against the baselines in `test/e2e/visual/`. An intended UI change updates the baseline in the same PR. **The committed baselines are the only visual record.** Design happens in the repository, so no external file exists to diff against, per [ADR-0400](0400-frontend.md) and [ADR-0701](0701-product-design-and-discovery.md). A baseline proves that nothing moved by accident. Whether an intended change is an improvement is a human judgement, made on the PR.

**Deferred:** component-isolation tooling, Storybook, and a hosted review UI, Argos. **Trigger:** the built-in baseline diffing stops scaling. **Seam:** both use the same committed baselines, so their adoption only adds to the setup.

## Consequences

### Positive

- One acceptance gauge, a rendered and authenticated UI, and one tool drives it.
- Operator dashboards are first-class tests. A green run proves the edge, auth, services, and data from end to end.
- One bring-up is shared across every full-platform suite. This keeps the heavy tier affordable.
- The requests, limits, and HPA triggers of [ADR-0204](0204-resource-management.md) are no longer judgement calls.
- The capacity alerts and the Overview capacity row become testable before an incident tests them.
- Load adds no always-on component, no new runtime, and no second metrics plane. It adds one pinned binary and text files.

### Negative and Risks

- **Node returns as an approved runtime.** It is limited to the `test/e2e/` runner and CI. It is never in a service, in app or library code, or in an image built from our own source. [ADR-0100](0100-language-and-runtime.md) approves one other Node island for the same vendored-tool reason: the Lowdefy admin console of [ADR-0401](0401-internal-admin.md).
- **With label-gated smoke, a PR without the label gets no full-platform signal until the nightly run.** So a cross-service break can stay in `master` for up to about 24h. This is the accepted cost of not paying for a full bring-up on each PR.
- **Operator-dashboard e2e runs only in the nightly suite.** So platform-contract regressions appear within 24h.
- **The gauge is also the bottleneck.** The verdict sits at the slowest layer, which has the most flaky results. A broken top layer blocks the signal completely. Preflight finds the cause, but it does not make the layer faster or more stable.
- **Heavy SPA dashboards can give flaky results.** Playwright auto-wait and the preflight gate reduce this.
- **Local load numbers are not capacity numbers.** Every report of results states this. The k6-operator swap resolves it when absolute figures are needed.
- **A single local node is not a production topology.** Saturation shapes transfer, but absolute ceilings do not. [ADR-0205](0205-environment-parity.md) states the same limit for the local tier.
- **Scenario rot.** A scenario that drives `/api/orders` breaks when that contract changes, and it is not on the path for each PR. The label-gated `perf:smoke` and the nightly run reduce this.
- **JavaScript appears again outside the approved island.** The rule of no Node, no npm, and no lockfile limits it. So does keeping `test/perf/` out of the Bun workspace.

## Rules

- Playwright, in TypeScript, is the only browser e2e and visual-regression tool. Cypress, WebdriverIO, Selenium, and pure-Go browser libraries are not used.
- All e2e and visual tests live in the `test/e2e/` workspace at the repo root, under one Playwright config.
- The browser acceptance test is the platform's acceptance gauge. Operator dashboards are tested as rendered pages behind a real AAL2 session, not by HTTP status alone.
- Preflight readiness checks run before the browser suite to find the location of a failure. They are not acceptance tests.
- E2e runs against `cluster:up full` with real services. MSW and all mocking are forbidden in e2e, including the development API mock and the `edge` profile of [ADR-0600](0600-local-development-loop.md).
- Service integration tests run against `cluster:up` plus the service's declared components, and drive services through their generated SDK clients. They do not import the code of another service.
- Visual regression gates on committed `toHaveScreenshot` baselines. An intended UI change updates the baseline in the same PR.
- E2e provisions a committed deterministic test identity: an AAL1 user plus an AAL2 operator. No test relies on state created by hand.
- Node is permitted only as the Playwright runner. It is pinned in `test/e2e/.mise.toml` against the root `[env] NODE_VERSION`, never in the root toolchain. `(CI: lint:node-scope)`
- k6 is the only load-generation tool. Locust, Gatling, JMeter, Vegeta, and self-written generators are not used.
- Performance tests live in `test/perf/` as committed JavaScript, never as a plan written in a GUI or recorded.
- `test/perf/` contains no `package.json`, no npm lockfile, and no `node_modules`. `(CI: lint:node-scope)`
- The k6 binary is pinned in `test/perf/.mise.toml`, never in the root `[tools]`.
- Load metrics reach Prometheus as an OTLP push through the OTel collector. No private metrics store, exporter sidecar, or remote-write receiver is added.
- Load series carry the `k6_*` prefix and `service_name="k6"`. k6's `url`, `name`, and `error` tags are not exported. Request identity is a bounded `endpoint` route-template tag.
- k6 runs with `--no-usage-report`.
- Every scenario declares thresholds, and the exit code is the verdict. A scenario without thresholds is a defect.
- Load shapes are data selected by `PROFILE`, not duplicated scenario files.
- Scenarios drive the edge, not port-forwarded pods, so the gateway and the forward-auth hop are inside the measurement.
- Performance suites are not part of `mise run test`, `ci:affected`, or the e2e suites, and never gate a merge implicitly.
- Results from a generator on the same host are reported as relative regression signals, never as absolute capacity figures.
- Load against a shared environment requires an explicit target. The only default target of `test/perf/` is the local edge.
- The full e2e and perf suites run nightly when there was activity, and before a release. Smoke suites run on a PR only when it has the label. Neither is part of `ci:affected`.
