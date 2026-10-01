# ADR-0503: Error Tracking

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0400](0400-frontend.md), [ADR-0500](0500-observability.md), [ADR-0502](0502-alerting-and-on-call.md)
- **Decides:** Errors are OpenTelemetry data grouped by a computed fingerprint, and no error-tracking product joins the floor.

## Context

Errors already reach the backends, per [ADR-0400](0400-frontend.md) and [ADR-0500](0500-observability.md):

- Services emit `ERROR`-level structured logs into Loki.
- Failing requests go into Tempo, head-sampled at full rate.
- The frontend's Faro agent forwards JS errors through the same collector.

Finding an error is solved.

No component covers what a dedicated error tracker sells:

| Capability | Covered by the floor |
| --- | --- |
| Find an error, with its trace and logs | yes |
| Collapse repeat occurrences of one fault into one entry | no |
| Notice a fault never seen before | no |
| Know which release introduced it, and that a fixed one returned | no |
| Readable frames from minified frontend code | no |
| Assign, resolve, and reopen an issue | no, **and not wanted** |

The last row sets the shape of this decision. Issue lifecycle is a workflow product, and this platform does not want one. Triage lives in the forge's issues, per [ADR-0102](0102-source-control-and-ci.md). A second place to mark work done is a second backlog. What remains worth having is **grouping** and **novelty detection**. Both are properties of the telemetry, not of a workflow.

## Decision drivers

1. **Cross-signal correlation**, per driver 6 of [ADR-0500](0500-observability.md). An error must reach its trace, its logs, and its profile. A tracker with its own store is a signal island. The only way back out of it is a copied trace id.
2. **One primitive per concern**, per principle 5 of [ADR-0000](0000-platform-foundations.md). A tracker adds a second SDK, a second agent in the browser, and a second ingest path for telemetry that the collector already carries.
3. **The always-on floor is the budget**, per principle 2. A component joins Core only when nothing on the floor covers its concern.
4. **Operational sovereignty**, per principle 3. Stack traces and error messages are some of the most sensitive telemetry a platform emits.
5. **Cardinality discipline**, per [ADR-0500](0500-observability.md). Grouping keys have no bound by nature, and a label with no bound destroys a metrics store.

## Considered options

| Option | Added always-on components | Correlation with traces and logs | Licence | Verdict |
| --- | --- | --- | --- | --- |
| **OTel `exception.*` records in the existing backends** | **none** | native: the same collector, the same trace ids, the same Grafana | none | **Chosen.** It gives grouping and novelty at no floor cost *(reasoned)* |
| **GlitchTip** | Django app, Postgres, Redis | a copied trace id, by hand | MIT | The strongest self-hosted tracker for this platform's size. It is Sentry-SDK-compatible, so the ingest protocol is an exit. **Deferred to a Scale swap**, not rejected. The trigger is below |
| Sentry, [self-hosted](https://develop.sentry.dev/self-hosted/) | Kafka, ClickHouse, Snuba, Relay, Redis, Postgres, and several worker classes | the same island | **BUSL or FSL, not OSI open source** | Rejected for two reasons. It brings a datastore fleet and a message bus to the floor for one concern. Its licence also makes it a governance dependency, not a component we own. Upstream supports Compose. Kubernetes has only a community chart |
| Highlight.io | ClickHouse and its own services | the same island | Apache-2.0 | Open and capable, with session replay. It is a second observability platform next to the Grafana stack. [ADR-0500](0500-observability.md) already refused that consolidation when it rejected SigNoz |
| [Bugsink](https://github.com/bugsink/bugsink) | one service and its database | a copied trace id, by hand | Polyform Shield: source-available, non-compete | The same shape as the row above, with a smaller footprint. Its licence is recorded, and it does not disqualify the tool, per principle 4. GlitchTip is MIT and has the longer operating history. That is the whole difference |
| Sentry SaaS, Bugsnag, Rollbar | none | the same island | proprietary | Fails principle 3, and stack traces are the payload most likely to carry user data. It would join the swap list of [ADR-0000](0000-platform-foundations.md), not the floor |
| Do nothing | none | native | none | The honest baseline. Errors stay findable but cannot be grouped. A fault that fires all the time looks the same as a fault that fired once |

**The two open trackers lose to a design, not to a rival product.** GlitchTip and Highlight are both good at their work, and weight is not the whole objection.

An error tracker owns a *second copy* of telemetry that the collector already carries. The step from an exception to the trace that produced it becomes a copy-paste between two systems. [ADR-0500](0500-observability.md) spent components to avoid signal islands. Adding one back to gain grouping reverses that trade.

## Decision

**Errors are OpenTelemetry data, not a separate product.**

| Concern | Decision |
| --- | --- |
| Recording | a failure is recorded as an OTel exception with `exception.type`, `exception.message`, and `exception.stacktrace`. It goes on the active span and into a log record. `libs/go/observability` and the frontend wiring do this. Service authors do not write it by hand |
| Grouping | services compute a stable **`error.fingerprint`**. It is a hash over the exception type and the top application frames. Line numbers, addresses, and vendor frames are excluded, so a cosmetic edit does not create a new fault |
| Cardinality | `error.fingerprint` is **log structured metadata and a span attribute only**. It is never a Loki stream label and never a metric label, per [ADR-0500](0500-observability.md) |
| Counting | one bounded metric, `errors_total{service, kind}`. `kind` is a small closed enumeration that the `obs` helpers own. The fingerprint is not on this metric |
| Release attribution | every record carries the image tag and commit that [ADR-0103](0103-release-and-versioning.md) already stamps. So the deploy that introduced an error is a filter |
| Frontend frames | source maps are kept as build artefacts per release and are **not** shipped to the browser. Symbolication is a deliberate step against the stored map, not an always-on service |
| Alerting | rate and burst alerts on `errors_total` route through [ADR-0502](0502-alerting-and-on-call.md). A dashboard groups by fingerprint over the log store |
| Triage | the forge's issues, per [ADR-0102](0102-source-control-and-ci.md). Nothing else tracks state on an error |

**Error messages carry no interpolated user data.** This is the same rule as for structured logging, per [ADR-0001](0001-documentation-and-output-conventions.md): context is attributes. A stack trace is exported telemetry. An interpolated identifier in a message is PII that no downstream redaction layer can find.

### Novelty detection is the weak edge

Grouping by fingerprint is a query. Knowing that a fingerprint is new is state, and the floor holds no store for it.

The default is a scheduled comparison of the current window's fingerprints against the previous window. A set difference emits a `ticket`-severity alert. This catches a new fault within the window. It misses a fault that appeared and stopped inside the window. That guarantee is narrower than a tracker's persistent fingerprint store, not equal to it.

### GlitchTip is the Scale swap

| Field | Value |
| --- | --- |
| **Trigger** | fingerprint triage becomes routine work, not incident work, such as a recurring session to group errors by hand. Or the window comparison above misses a fault that reached a customer |
| **Seam** | ✓ GlitchTip ingests the Sentry envelope protocol, and the collector can fan out to a second exporter. Adopting it adds a destination. It does not change how services record errors |
| **Cost if adopted late** | triage stays manual, and novelty stays bound to the window. Nothing needs new instrumentation, because the services already emit the `exception.*` records that GlitchTip needs |

The seam is real and the cost of waiting has a bound. So this is a deferral, not a bet.

### What would change this decision

| Change | Effect |
| --- | --- |
| Errors need state: assignment, resolution, regression detection | **Decisive**, and it is the trigger above. State is what a tracker sells, and a query cannot hold it |
| The fingerprint is unstable across cosmetic edits | **None on the decision**, and decisive on the hash. The frame-selection rule is the thing to fix, and this ADR owns it |
| A frontend error needs a readable stack in the UI | **None.** Symbolication against the kept source map is a deliberate step. Shipping maps to the browser is a different decision, in [ADR-0400](0400-frontend.md) |
| Error volume grows past the log store's retention | **None on the product choice**, and decisive on retention: the same signal, a shorter window. [ADR-0500](0500-observability.md) owns it |
| A vendor error tracker becomes acceptable | **Decisive**. It is a move down axis B, not a change of mechanism, per [`adoption-path.md`](../adoption-path.md) |

## Consequences

### Positive

- No component joins the floor, and no second SDK reaches the browser or the services.
- An error is one click from its trace, its logs, and its profile, because it never left the pipeline that carries them.
- The fingerprint rule makes grouping a property of the data, so grouping survives a change of backend.
- A later tracker is an exporter, not an instrumentation project.

### Negative and Risks

- **No issue lifecycle.** Nobody assigns, resolves, or reopens an error. This is a deliberate choice: that work belongs in the forge, and a second backlog is worse than none.
- **Novelty detection is bound to the window**, as above. This is the biggest gap and the clearest trigger for the swap.
- **Frontend symbolication is a manual step** against a stored source map. A minified trace is unreadable until someone does it.
- **The fingerprint is ours to get right.** Too coarse, and it merges distinct faults. Too fine, and it creates a new fault per release. It lives in the `obs` helpers, so it is tuned in one place, and it has unit tests.
- **Grouping is a query, not a landing page.** An engineer runs a dashboard and does not open an inbox.

## Where the source maps are kept

A map is useless if nobody can find it for the release that produced the trace. So keeping maps per release needs a store, not a convention.

| Option | Verdict |
| --- | --- |
| **The registry, as an OCI artefact through `oras`** | **Chosen.** The registry already holds this release's artefacts. So it is one auth model, one retention policy, and one digest-addressed store. The archive is tagged with the release, and `oras pull` fetches it when a trace needs symbolication *(reasoned)* |
| `crane` against the same registry | The same store, through a different tool. `crane` is built for images and for copies between registries. `oras` exists to push an arbitrary blob as a typed artefact. The artefact type stops an image client from trying to run it |
| A plain object-store upload | A second store to secure, expire, and remember, with the same release data as the registry. It also has no digest addressing, so finding the map for an image depends on a naming convention |
| A CI artefact store | Tied to the forge's retention window, not the release's. [ADR-0102](0102-source-control-and-ci.md) keeps the forge cheap to leave. An artefact that only that forge can serve is the coupling that rule exists to avoid |

The archive is never reachable from the product origin. A map served to a browser gives away the unminified application. That is the whole reason the build strips it.

## Rules

- A failure is recorded as an OTel exception with `exception.type`, `exception.message`, and `exception.stacktrace`. No service carries a second error-reporting SDK. `(ref: OTel semconv)`
- `error.fingerprint` is a span attribute and log structured metadata. It is never a Loki stream label and never a metric label.
- Error messages carry no interpolated user data. Context is attributes, per [ADR-0001](0001-documentation-and-output-conventions.md).
- Errors are not tracked as issues anywhere except the forge. No component holds resolution state on an error.
- Source maps are build artefacts, kept per release, and never served to the browser.
