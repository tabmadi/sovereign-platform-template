# Detection Latency

Each decision below is defensible alone, and no ADR puts them together. This document does. For each failure class, it states what detects the failure and how long detection takes. This number bounds an availability objective, per [ADR-0500](../adr/0500-observability.md). The escalation trigger of [ADR-0502](../adr/0502-alerting-and-on-call.md) pays to lower it.

**Detection is not response.** Every row states the time to notice. [`incident-management`](../guide/incident-management.md) covers what happens next.

## The four positions that set these numbers

| Position | Effect on detection | Owning decision |
| --- | --- | --- |
| Nothing pages | out-of-hours detection is the next working day, for every class | [ADR-0502](../adr/0502-alerting-and-on-call.md) |
| Per-PR e2e runs only with a label, and full e2e runs nightly | a cross-service regression can stay in `master` until the nightly run | [ADR-0601](../adr/0601-testing-strategy.md) |
| The production platform runs `selfHeal=false` | drift stays until a human reads the notification | [ADR-0201](../adr/0201-gitops.md) |
| Backup restore is rehearsed quarterly | a backup that cannot be restored is found at the rehearsal, or at the restore | [ADR-0207](../adr/0207-cluster-storage.md) |

## Per failure class

**In hours** assumes that someone reads alert mail and dashboards. **Out of hours** assumes that nobody does, because nothing rings.

| Failure | What detects it | In hours | Out of hours |
| --- | --- | --- | --- |
| Pod crashloop, one service | an Alertmanager rule, then email | minutes | next working day |
| Node lost | an Alertmanager rule, then email | minutes | next working day |
| Error-rate spike in production | the `errors_total` rate alert of [ADR-0503](../adr/0503-error-tracking.md), then email | minutes | next working day |
| Latency regression inside the SLO | the burn-rate rule at `ticket` severity, per [ADR-0502](../adr/0502-alerting-and-on-call.md) | hours | next working day |
| Cross-service regression merged to `master` | the nightly full e2e suite, unless the PR had the e2e label | **up to a day** | **up to a day** |
| Operator dashboard broken | the nightly suite only. No per-PR coverage exists | **up to a day** | **up to a day** |
| Cluster drift from the repository | an Argo CD notification, because production does not self-heal | hours | next working day |
| Certificate close to expiry | the cert-manager renewal failure alert | minutes to hours | next working day. The renewal window is weeks, so this is the slowest failure to become urgent |
| Backup failing | the backup job's own alert. For a backup that *runs* and cannot be restored, the quarterly restore rehearsal | minutes for a failed job. **Up to a quarter** for a backup that cannot be restored | same |
| Silent data corruption | nothing systematic. It shows as an application fault or at a restore | **unbounded** | **unbounded** |
| Alertmanager itself down, cluster up | the `alertmanager-watchdog-check` CronJob, per [ADR-0502](../adr/0502-alerting-and-on-call.md). Every five minutes it asks Alertmanager for a firing `Watchdog`, and fails when there is none. It exits 1 for a missing `Watchdog` and 2 when it cannot reach Alertmanager at all. Read the log: only exit 1 means that alerting is broken | within five minutes | until someone notices the failed job, which is the next working day |
| Alertmanager down with the cluster | nothing. The check runs in the cluster that it watches, so it stops with that cluster | **unbounded** | **unbounded** |
| A `marketing.*` event reaching the log store | the standing routing assertion in the e2e suite, per [ADR-0700](../adr/0700-analytics.md) | at the next suite run | same |
| Recovery objectives missed | the quarterly restore rehearsal measures RTO and RPO against the values that [ADR-0200](../adr/0200-cluster-topology.md) states | **up to a quarter** | same |

## Reading the table

**Two rows are unbounded, and they are the ones to change first.** An unbounded row is not a long detection time. It means there is no detection, and the fault is found by its consequence and not by a signal. Silent data corruption has no systematic detector at any budget that this platform accepts.

Alertmanager's own failure has two shapes, and this split is the honest part:

- Routing is broken while the cluster runs. This is the common shape, and the platform detects it. The `Watchdog` has a consumer that does not travel through the pipeline that it checks.
- The cluster is down. The platform does not detect this shape. The consumer runs in the cluster that it watches, and goes quiet with it.

To detect the second shape, a consumer outside that domain is necessary. The `watchdogWebhook` receiver is the seam for it, per [ADR-0502](../adr/0502-alerting-and-on-call.md). It ships connected to nothing, so the row stays unbounded until something connects to it.

**A failed check is not the same as a broken pipeline.** The Watchdog check shares a namespace with the thing that it queries. So it also fails when Alertmanager is only unreachable: starting, rescheduled, or cut off by a NetworkPolicy. This is a real observation, and the check does not retry it on purpose. But it gives no verdict about routing. So the check reports it as exit 2 with its own message, not as a missing `Watchdog`. Some clusters have a node that restarts with its host. On such a cluster, exit 2 within a few minutes after a node comes back is expected and is not a defect. Only a series of exit 1 results means what the row says.

**This table is also the RTO bound.** [ADR-0200](../adr/0200-cluster-topology.md) states recovery in under 30 minutes, measured from the start of recovery. Out of hours, the detection time of the failing row adds to that figure before a user sees the service restored. So the recovery objective and the detection objective are stated separately. One summed number would be wrong for half of the day.

**The dominant term is not the alerting stack.** Rules evaluate in seconds and route in seconds. Many rows have *next working day* as their out-of-hours figure. In each of them, the receiver reaches an inbox and not a person. So the honest summary is: **this platform detects at the speed of someone looking.**

**The two rows of up to a day come from a test-scheduling choice**, not from an observability choice. The fix is to run e2e on the pull requests that touch more than one service. Affected-detection already finds those pull requests, so no new component is necessary.

**This table bounds an availability objective.** A target can allow less downtime than the detection time of the row that breaks first. Nothing here can keep such a target. To raise the limit, use the escalation trigger of [ADR-0502](../adr/0502-alerting-and-on-call.md). Its price is a hosted paging service and a rota.
