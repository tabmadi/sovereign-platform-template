# ADR-0302: Durable Execution with Temporal

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0100](0100-language-and-runtime.md), [ADR-0103](0103-release-and-versioning.md), [ADR-0200](0200-cluster-topology.md), [ADR-0201](0201-gitops.md), [ADR-0205](0205-environment-parity.md), [ADR-0300](0300-data.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0304](0304-identity-and-authorization.md), [ADR-0500](0500-observability.md)
- **Decides:** Temporal is the durable-execution layer and the default async primitive, with five criteria deciding what earns a workflow.

## Context

The platform needs one answer to a family of related problems:

- Operations that span **multiple services or external systems** and must not leave the system half-applied.
- Operations that need **compensation on failure**.
- **Scheduled and periodic work**: reports, reconciliations, cleanup.
- **Background and async work**: emails, thumbnails, indexing, fan-out.
- **Authz-relevant mutations** that write to both the application database and the authorization datastore, atomic in effect, per [ADR-0304](0304-identity-and-authorization.md).

Without one durable-execution platform, each problem grows its own machinery: outbox tables, dead-letter queues, retry loops, cron jobs, and custom idempotency. Repeated across a fleet, that machinery cannot be maintained.

## Decision drivers

1. **One reliability primitive, not five.** DLQs, cron, and ad-hoc retries do not exist beside a workflow engine. One sanctioned lighter path is the single deliberate exception, bounded below.
2. **Service boundaries stay HTTP and OpenAPI.** A workflow engine does not become the cross-service bus.
3. **The second workflow costs much less than the first.** The adopted tool makes reliability a library call, not a design exercise. Otherwise the fleet goes back to hand-written retries.
4. **A workflow is written in the service's own language**, not in a separate modelling notation kept beside it.
5. **Operational sovereignty**, per principle 3 of [ADR-0000](0000-platform-foundations.md).

## Considered options

### The engine

| Option | Workflow is authored as | Added datastores | Verdict |
| --- | --- | --- | --- |
| **Temporal, self-hosted** | ordinary Go, replayed deterministically | none: a database on the existing Postgres cluster | **Chosen.** One model holds activities, child workflows, signals, queries, timers, schedules, and sagas. It has first-party SDKs for the mainstream runtimes *(documented)* |
| Restate | ordinary code, a similar model | its own embedded log | A simpler operational shape and a close model. It is younger, with fewer operators. The saga and long-timer ergonomics that this platform depends on are its newest part |
| Cadence | the same as Temporal, its predecessor | Cassandra or a SQL store | No advantage over the project that followed it |
| Netflix Conductor or Orkes Conductor | **a JSON DAG definition**, with workers in any language | Elasticsearch plus a persistence store | Fails driver 4: the workflow is a document, so the logic lives beside the code, not in it. The search dependency is also a second datastore |
| Camunda 8 or Zeebe | **BPMN**, authored in a modeller | Elasticsearch or OpenSearch, plus brokers and gateways | The most capable engine here for a process that a non-engineer must read. That is not this platform's problem. BPMN is the exact failure of driver 4, and the component set is a platform of its own |
| Windmill, Inngest, DBOS | varies: scripts, functions, or a library over Postgres | varies | Lighter, and each answers a narrower part: scheduled scripts, event-driven functions, or single-database transactions. None covers cross-service sagas with timers, and that case is the reason for this ADR |
| DIY: outbox, queue, cron, retry loops | four mechanisms | none new | It builds a weaker Temporal four times, once per service |
| Kubernetes Jobs, CronJobs, Argo Workflows | pipeline DAGs | none new | Not business workflows. Kept for pure infrastructure tasks |
| Temporal Cloud | the same as Temporal | none | Fails driver 5. Client call sites stay cloud-neutral, so a deploy reverses the position, not a rewrite |

## Decision

Self-hosted Temporal is the platform's durable-execution layer and the default async primitive.

### When something is a workflow

A workflow is the right primitive when **any** of these is true:

1. The operation has two or more logical steps, and partial completion is a bad state.
2. It touches more than one service or external system.
3. It must compensate on failure, not return an error.
4. It lives long compared with a request.
5. It must survive process restarts by design.

It is the wrong primitive for a single atomic action inside one service.

| Operation | Primitive |
| --- | --- |
| Register user: identity, orgs, authz tuples, welcome email | Workflow |
| Checkout: reserve, charge, order, deduct, confirm | Workflow |
| Payment, often a child workflow of checkout | Workflow |
| Refund: compensation across systems | Workflow |
| Authz-relevant resource mutation | Workflow, per [ADR-0304](0304-identity-and-authorization.md) |
| Daily reconciliation | Workflow on a Temporal `Schedule`, not a `CronJob` |
| Transactional email, fire-and-forget | Outbox, or a workflow if delivery must be tracked |
| Thumbnail or document index | Outbox, or a workflow if part of a larger process |
| Update profile name, add to cart, list orders | Neither: synchronous |

### The outbox seam

A **trivial best-effort** job can use a transactional outbox instead. The triggering row and an `outbox` row commit in one Postgres transaction, and a small per-service dispatcher drains it.

A job stays on the outbox only while **all four** conditions are true. When one fails, the job is a workflow:

1. It has one logical step.
2. It runs inside one service, with no cross-service coordination that must not half-apply.
3. It is best-effort: losing it or running it twice is acceptable. So at-least-once dispatch with an idempotent handler is enough.
4. It needs no compensation on failure.

Temporal is the default, and the outbox is the sanctioned lighter path for the trivial case. The platform does not adopt a blanket rule that all async work is a workflow. That rule forbids the four-condition case on principle, not on cost, and the four conditions are narrow enough to police.

### Architecture: co-located workflows, HTTP between services

Workflows, activities, and workers live inside the service that owns the business process.

```text
services/<service>/
├── openapi.yaml
├── cmd/{server,worker}/main.go
├── internal/
│   ├── handlers/        # HTTP handlers from generated server stubs
│   ├── workflows/       # workflows owned by this service
│   ├── activities/      # activities owned by this service
│   ├── domain/
│   └── store/
└── migrations/
```

**Process-owner rule.** A workflow lives in the service that owns the *business process*, not the one that owns the most data. Register-user lives in identity, even though it writes to orgs and the authz store. Checkout lives in checkout, even though it calls payment, inventory, and orders. A service whose main job is to orchestrate others is a legitimate shape.

**Cross-service invocation is HTTP only:**

1. The owning service exposes an HTTP endpoint that starts the workflow internally.
2. The caller invokes it through the generated client.
3. The response is `202 Accepted` with a handle that conforms to the `WorkflowHandle` schema, per [ADR-0303](0303-api-contracts-and-lifecycle.md).

A service never starts another service's workflow through the Temporal client. That imports the callee's workflow input struct. It also bypasses OpenAPI, tracing, and the identity-header contract.

**Waiting on a cross-service workflow** uses one of these mechanisms, chosen by need:

| Mechanism | How |
| --- | --- |
| Poll the handle | the owning service exposes `GET /<resource>/{id}`, which returns `{status, result?}`. The caller's workflow polls with backoff |
| Webhook callback | the caller passes `callback_url`, and the owning service sends a POST on completion. The caller's workflow waits on a signal that its own webhook handler raises |
| Fire-and-forget | the caller does not need the result |

Direct Temporal signals across service boundaries are not used.

### Activity placement

| Scope of use | Location | Note |
| --- | --- | --- |
| The workflows of one service | `services/<service>/internal/activities/` | the common case |
| Generic infrastructure: email, object storage, metrics, webhooks | `libs/go/temporal-activities/<concern>/` | stateless and service-agnostic, with no dependency on `services/` |
| Logically owned by another service | **not shared**. Each caller writes a thin activity that wraps the owning service's generated client | the shared thing is the HTTP API |

Domain logic in `libs/` that shares an activity across services couples them behind the API boundary. Principle 10 of [ADR-0000](0000-platform-foundations.md) sets that boundary.

### Wall-clock

By default, a workflow's wall-clock fits inside one production deploy cycle. The reasons are event-history size and operational legibility. The reason is not to avoid versioning: the next section handles versioning directly.

A longer wall-clock is permitted, and it requires:

1. an entry in `docs/reference/long-running-workflows.md` with the expected wall-clock,
2. replay tests over historical event histories in CI,
3. a documented `workflow.GetVersion` patching plan. A workflow that outlives a deploy is always resumed by code that did not start it.

### Worker Deployment Versioning

The failure mode: a worker that runs after a deploy resumes a workflow that started before it. If the code no longer replays the recorded history, the execution dies with a non-determinism error. A short wall-clock makes the exposure window smaller but does not close it. A thirty-second checkout can still be in progress when a worker rolls.

| Option | In-flight work on deploy | Cost per workflow author | Added components | Verdict |
| --- | --- | --- | --- | --- |
| Worker Deployment Versioning, reconciled by the Temporal Worker Controller | pinned to the version that started it | none in the ordinary case | **one controller with an admission webhook** | The strongest mechanism. The platform layer buys the reliability once. **Deferred**, on the trigger below: it puts a young reconciler in the deploy path of every service. It closes a window that the wall-clock rule already bounds |
| `workflow.GetVersion` patching only | survives, if every divergence is guarded | **a patch branch per change, kept until no history references it** | none | The mechanism that versioning replaces. Its cost grows with the number of changes, not the number of workflows. A missed guard is a non-determinism error in production |
| Build-ID versioning without the controller | pinned, until the old pods go | none | none | Temporal has the versioning APIs, so the routing behaviour is the same. It fails on the second row of the table below. A rolling `Deployment` deletes the pods of the pinned version when rollout completes |
| Versioning driven from CI, not a reconciler | pinned | none | none | Version registration and promotion happen once, at deploy time. Draining is a state that changes long after the pipeline exits |
| **No versioning. Keep workflows short, and patch what can diverge** | exposed for the duration of a workflow | a wall-clock budget per workflow, and a guard on a divergent change | none | **Chosen as the floor.** It makes the window smaller but does not close it. The remaining risk is weighed against a component that every deploy would depend on *(reasoned)* |

**The floor is the honest baseline, and the controller is deferred.** Workers run as plain Deployments. The wall-clock rule already keeps a workflow inside one deploy cycle. So the exposure window is a rollout, not a workflow lifetime. A workflow change that could diverge in flight is guarded with `workflow.GetVersion`.

This is the last row of the table plus the second row. For the executions this platform runs, it buys the same reliability as the first row. It does so without a young controller and an admission webhook in the path of every deploy.

Versioning is the better mechanism, but it has a cost: it is a reconciler on the deploy path. The Build-ID row shows why a reconciler is required as soon as versioning is on.

| Field | Value |
| --- | --- |
| **Trigger** | a workflow's wall-clock legitimately exceeds a deploy cycle, which is the first entry in `docs/reference/long-running-workflows.md`. Or a non-determinism failure reaches production twice |
| **Seam** | ✓ the worker is a chart value. Adoption installs the controller and renders `WorkerDeployment` CRs, not Deployments. Workflow code does not change, because Pinned executions need no patching |
| **Cost if adopted late** | the `GetVersion` branches written before adoption stay until no event history references them. The wall-clock rule bounds this: a history that no longer exists cannot pin a branch |

This is a **deferral, not a bet.** The seam is a chart value. The versioning APIs belong to the server, and they are present whether or not anything drives them.

### What adopting versioning brings with it

When the trigger fires, the controller drives versioning, not a chart. Four properties are the reason:

| Consequence | Detail |
| --- | --- |
| **The Build ID tracks the code, not the release channel** | The controller derives it from the image tag plus a hash of the pod template. So a configuration-only change is also a new version. This is stricter than a Build ID from the image alone, per [ADR-0103](0103-release-and-versioning.md), and it is why the chart does not compute it |
| **A pin is only as good as the pods behind it** | A pin to a version that no pod serves is worse than no pin: the execution does not fail over, it waits. A rolling `Deployment` deletes the old version's pods when rollout completes. Protection then lasts seconds, not the workflow's lifetime. So workers are `WorkerDeployment` CRs, reconciled by the **Temporal Worker Controller**. It keeps one Deployment per Build ID alive until Temporal reports it Drained. Only Temporal knows the drainage state, and it changes long after a sync ends. So keeping a version until its work finishes is reconciler work, and a chart cannot template it |
| **Promotion belongs to the controller** | It registers each version and promotes per `rollout.strategy`. It injects the deployment and build-ID environment variables itself, and upstream states that nobody sets them by hand. Rollback sets the current version to the previous Build ID. Its pods still exist because sunset is delayed |
| **Sessions and versioning exclude each other** | The SDK refuses `EnableSessionWorker` together with versioning. So a service that needs sessions opts out explicitly and owes a patching plan instead |

**Deleting a `WorkerDeployment` blocks while its workers still poll.** The CR carries a delete-protection finalizer. On delete, the controller asks Temporal to remove each version. Temporal refuses while pods of that version exist, and for one more poller-expiry window after they are gone. The controller retries without limit, so the CR stays `Terminating` and Argo CD cannot recreate it.

So removing a worker means first scaling the versioned Deployments to zero, and then waiting for pollers to expire. The break-glass is to patch the finalizer away. The version records on the Temporal side then age out.

### Draining a worker on rollout

This is separate from replay safety, and people often confuse the two. When a worker pod rolls, **in-flight activities are lost unless the worker is told to wait**. The Go SDK's `WorkerStopTimeout` defaults to no wait, so the platform sets it explicitly. The chart derives `terminationGracePeriodSeconds` from it, so kubelet always waits strictly longer than the worker. A grace period configured on its own causes a silent regression.

This takes [12-Factor IX](https://12factor.net/disposability) further than the factor goes. The factor asks a process to shut down gracefully on `SIGTERM`. It leaves the length of *gracefully* to the platform. For a worker with an in-flight activity, that length is the stop timeout, and the grace period follows from it.

### What Temporal replaces

| Legacy pattern | Replacement |
| --- | --- |
| Multi-step or cross-service outbox machinery | Workflows. The database write and the downstream effect are activities in one workflow. The transactional outbox stays only for the trivial best-effort case |
| Event bus, such as NATS or Kafka | **Not adopted.** HTTP plus signals through webhook callbacks cover cross-service notification. The deferral below covers the case they do not |
| Kubernetes `CronJob` for business-meaningful work | Temporal `Schedule`. `CronJob` stays for pure infrastructure |
| Background queues | Workflows on a `background-tq` queue, except trivial best-effort jobs on the outbox seam |

**A publish-subscribe bus is deferred.**

| Field | Value |
| --- | --- |
| **Trigger** | one event has three or more independent consumers that the producer must not know. Or a consumer needs to replay an event stream from a time when it was not running |
| **Seam** | ⚠ **a bet.** Cross-service notification is point-to-point: an HTTP call or a signal that names its target. So adopting a bus rewrites the producers, not only the transport. Nothing here publishes to a topic that a broker could take over |
| **Cost if adopted late** | every producer already names its consumers. The fan-out is then coded into N call sites, and each one must be found and inverted |

### Operational shape

| Element | Value |
| --- | --- |
| Server | the Temporal monolith binary, with all four roles in one process, installed with Helm. A separate database on the platform Postgres cluster backs it |
| Workers | one deployment per service. It registers only that service's workflows and activities, and ships with its service |
| Task queues | named per service, plus a shared `background-tq` |
| Namespaces | one per environment |
| History retention | 30 days in production, 7 days outside production |
| Local | the inner loop uses `temporal server start-dev` for speed. The full tier runs this same chart at one replica, backed by CNPG, per [ADR-0600](0600-local-development-loop.md) |

### Conventions

| Convention | Rule |
| --- | --- |
| Determinism | no `time.Now()`, no `math/rand`, no direct I/O, and no goroutines: use `workflow.Go`. Side effects go through activities |
| Idempotency | every activity accepts two calls with the same input. Run ID plus activity ID is the natural key for external calls |
| Payload size | activity inputs and outputs stay in kilobytes. Large payloads go through the object bucket, and activities pass references |
| Timeouts | explicit. The default activity `StartToCloseTimeout` is 30s, and the default `WorkflowExecutionTimeout` is 1h. An override carries a justification in the workflow file |
| Errors | typed through `temporal.NewApplicationError` with stable types. Retry policy keys off those types |
| Workflow IDs | encode business intent: `payment-{order_id}`, not `payment-{uuid}`. Idempotency is a property of the business operation |
| SDK call sites | only in `internal/workflows/` and `internal/activities/` |

### Cross-cutting integrations

Other ADRs own these concerns, and nothing here overrides them:

- [ADR-0304](0304-identity-and-authorization.md) owns the authz dual-write discipline.
- [ADR-0303](0303-api-contracts-and-lifecycle.md) owns the `WorkflowHandle` shape.
- [ADR-0304](0304-identity-and-authorization.md) owns service-to-service identity propagation.
- [ADR-0500](0500-observability.md) owns trace propagation.

## Consequences

### Positive

- One reliability primitive answers four problems. Engineers learn it once, and no second runtime needs operation.
- Saga compensation becomes routine, not custom work.
- Multi-step outbox machinery has no place to live. The outbox stays only as the deliberate lighter path.
- The structure solves the authz dual-write risk, so review does not have to police it.
- Service boundaries stay HTTP and OpenAPI.

### Negative and Risks

- **Non-determinism rules are a real mental cost.** Deferred versioning leaves that cost with the workflow author. `workflowcheck`, a review checklist, and the wall-clock rule reduce it. The wall-clock rule keeps the set of reachable histories small enough to reason about. Versioning removes that reasoning, not only bounds it, and its trigger buys that.
- **A rollout during an in-flight execution can still kill it.** The window is a rollout, not a workflow lifetime, and it is not zero. This is the accepted remaining risk of the deferral. Its second occurrence in production is the trigger.
- **The deferral's cost is patch branches**, one per divergent change, kept until no event history references it. The wall-clock rule bounds how long they stay. Only the rate of workflow logic changes bounds their count.
- **The Temporal server is critical infrastructure.** HA Postgres and replay tests that prove workflows tolerate restarts reduce this.
- **Per-activity latency in the tens of milliseconds** rules out workflows in request paths under 100ms. The scope rule already excludes those.
- **One worker deployment per service multiplies the pod count.** Accepted: it preserves ownership.

## Rules

- Temporal is the platform's durable-execution mechanism and the default async primitive. No DLQs, ad-hoc retry loops, or cron jobs are used for business-meaningful periodic work.
- A workflow exists if the operation matches at least one of the five scope criteria. A trivial best-effort job that matches none can use the outbox seam.
- A service's workflows, activities, and worker live under `services/<service>/`. No top-level workflow directory exists. `(CI: ci:lint)`
- Cross-service workflow invocation is HTTP through the generated client. Direct Temporal-client calls across service boundaries are not used. `(CI: ci:lint)`
- Waiting on a cross-service result is polling, a webhook callback, or fire-and-forget. Direct cross-service signals are not used.
- Activities are placed by ownership. They are never shared across services as a domain wrapper.
- A workflow's wall-clock fits one production deploy cycle. A longer one requires an entry in `docs/reference/long-running-workflows.md` with replay tests.
- Workers run unversioned. Replay safety across a deploy rests on the wall-clock rule, and on `workflow.GetVersion` guarding any change that a running history can reach.
- A change that alters a workflow's command sequence is guarded, or the workflow is drained before the change ships. An unguarded divergent change is a non-determinism error in production.
- Worker Deployment Versioning is adopted only on its recorded trigger, and adoption brings the controller with it. A versioned worker is then a `WorkerDeployment` reconciled by the controller, never a plain `Deployment`. Only the controller sets Build IDs and the deployment and build-ID environment variables.
- Where versioning is adopted, sunset delays are only made longer, never shorter toward zero.
- Worker graceful stop is configured. `terminationGracePeriodSeconds` is derived from the worker stop timeout, never set on its own.
- Workflow code is deterministic, and side effects go through activities. `(CI: ci:lint)`
- Activities are idempotent and accept retries.
- Every activity that a workflow executes by name is registered on that service's worker. `(CI: lint:activity-register)`
- Workflow IDs encode business intent, not opaque UUIDs.
- Activity inputs and outputs stay in kilobytes. Larger payloads go through the bucket by reference.
- Periodic business-meaningful work uses a Temporal `Schedule`. `CronJob` is only for pure infrastructure.
- Temporal Cloud is not used.
