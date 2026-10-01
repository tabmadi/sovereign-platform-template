# ADR-0204: Resource Management and Scheduling

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0104](0104-supply-chain-security.md), [ADR-0200](0200-cluster-topology.md), [ADR-0201](0201-gitops.md), [ADR-0203](0203-policy-enforcement.md), [ADR-0302](0302-temporal.md), [ADR-0500](0500-observability.md), [ADR-0601](0601-testing-strategy.md)
- **Decides:** Every container declares requests and a memory limit, no container declares a CPU limit, and namespaces carry in-tree guardrails.

## Context

Application services, stateful platform components, and batch Jobs share the same node set, per [ADR-0200](0200-cluster-topology.md). Without resource governance, one noisy service starves Temporal, Postgres, or the observability stack. The scheduler then has no basis for an eviction order.

The platform-engineering budget in [ADR-0000](0000-platform-foundations.md) leaves nobody to tune each pod by hand. So the policy must be a default, not a per-service task.

## Decision drivers

1. **No workload can starve a Core component**, per [`docs/operational-surface.md`](../operational-surface.md).
2. **Defaults over per-service tuning.** The policy applies to every namespace with no per-service work.
3. **A predictable eviction order** under pressure.
4. **Boring in-tree Kubernetes primitives**, per principle 5 of [ADR-0000](0000-platform-foundations.md).

## Considered options

### Guardrails

| Option | Applies with no per-service work | Bypassable | Added components | Verdict |
| --- | --- | --- | --- | --- |
| **`LimitRange`, `ResourceQuota`, `PriorityClass`, and `PodDisruptionBudget`** | yes. They are namespace-scoped | no. They are API-server objects | **none. They are in-tree** | **Chosen.** The API server already enforces these four primitives *(reasoned)* |
| Per-service requests only, reviewed by hand | no | yes, by omission | none | The omission is the failure mode, and review does not catch what is absent |
| A mutating admission policy that stamps defaults | yes | no | an admission controller | It reaches one case that the chosen option cannot: a chart with no field to set. A controller only for defaults turns driver 4 upside down. Where [ADR-0104](0104-supply-chain-security.md) brings Kyverno for signature verification, Kyverno covers that case as a side effect |
| Vertical Pod Autoscaler | yes | no | one controller | It rewrites requests from observed usage. This conflicts with values that come from a recorded measurement and are reviewed in git |

### CPU limits

| Option | Behaviour under contention | Failure mode | Verdict |
| --- | --- | --- | --- |
| **Requests and memory limits, no CPU limit** | CPU is shared in proportion to requests, and a burst may use idle capacity | a busy neighbour slows a burst | **Chosen.** Memory is incompressible, so its limit is the only barrier between one leak and an OOM across the node. CPU is compressible, so a limit adds nothing that the requests do not already give *(measured)* |
| A CPU limit on every container | CFS throttles at the quota even when the node is idle | a burst becomes tail latency, which looks like a code defect | Measured: `temporal-history` bursts to 2121m from almost idle. A 500m limit that looks reasonable cuts it to a quarter, and this shows only as slow checkouts |
| CPU limits equal to requests | no bursts. Guaranteed QoS class | capacity stays idle while a pod throttles | It buys a predictable eviction order, and the `PriorityClass` tiers already give that |
| No limits of any kind | nothing bounds a leak | one leak takes the node | The difference above is the point: memory needs the limit, and CPU does not |

### Autoscaling

| Option | Scales on | Added components | Verdict |
| --- | --- | --- | --- |
| **No HPA by default, opt-in per service** | a documented sustained-load signal | none | **Chosen.** This is the one place where driver 2 points the other way. A default that guesses is worse than an explicit opt-in *(reasoned)* |
| An HPA on CPU for every service | CPU usage as a share of the request | none. It is in-tree | With no CPU limit, that share is a weak signal. A service with no load history oscillates against it |
| Vertical Pod Autoscaler | observed usage, written back into requests | one controller | The same as above: it overwrites reviewed, measured values |
| VPA in recommendation-only mode | the same, as advice | one controller and a dashboard | The [ADR-0601](0601-testing-strategy.md) load suite already produces this advice, into a dashboard that already exists |
| KEDA | queue depth and external metrics | one controller and its CRDs | The right answer for event-driven scaling. Nothing here scales on a queue: Temporal workers pull their own work |

## Decision

Every container declares resources, and each namespace carries guardrails.

| Guardrail | Role |
| --- | --- |
| **Requests and memory limits, mandatory** | Every container sets CPU and memory requests and a memory limit. A container with neither its own values nor a namespace default is a defect |
| **`LimitRange` per namespace** | It supplies default requests and limits. A missing value then fails safe, and the pod does not schedule unbounded |
| **`ResourceQuota` per namespace** | It caps total CPU and memory, so one namespace cannot consume the cluster |
| **`PriorityClass` tiers** | From high to low: `platform-critical`, `product`, `batch`. Under pressure, batch dies first and Core dies last |
| **`PodDisruptionBudget`** | On every multi-replica and stateful component. A drain or upgrade then never takes quorum below one |

**No container sets a CPU limit. Every container sets a memory limit.** Requests and the priority tiers handle contention.

**Autoscaling is opt-in per service**, on a documented sustained-load signal. This is the same grow-on-a-trigger rule as node growth in [ADR-0200](0200-cluster-topology.md). It is not default template machinery.

### Ordering

All four guardrails live in `infra/helm/platform/resource-governance/`, in the **base** tier, per [ADR-0201](0201-gitops.md). Sync waves inside that chart order them against each other:

- PriorityClass: -5
- LimitRange: -4
- ResourceQuota and PDB: -3

A `LimitRange` sets defaults only for pods created after it. The API server rejects a pod that names an absent `PriorityClass`.

### Sizings are measured, not estimated

Every number comes from `cluster:up full` under the [ADR-0601](0601-testing-strategy.md) load suite. The `load-test` dashboard can derive each one again. These measurements changed decisions:

| Workload | Measured peak | Consequence |
| --- | --- | --- |
| Tempo | **1858Mi**, about 400Mi at rest | The heaviest pod in the cluster. The 512Mi namespace default would OOM-kill it during the runs that observe it. Explicit 3Gi limit |
| temporal-history | **2121m CPU**, 647Mi | The strongest evidence for the rule of no CPU limits. A 500m limit throttles it to a quarter of its measured need |
| Oathkeeper and Traefik | 192m and 184m CPU | On the read path, the edge costs about 3 times as much as catalog. Size the edge first |
| Loki | 453Mi | 88% of the namespace default. Explicit 1Gi |
| Postgres | 373Mi, 267m CPU | no change |

### Memory sizing uses the working set

`k8s_pod_memory_limit_utilization_ratio` divides memory **usage** by the limit, and usage counts reclaimable page cache. So the ratio shows two to three times the real pressure, across every pod measured here. `otel-cluster` reported 97.9% against a true 58.0%.

The OOM killer acts on the **working set**. So limits are sized against `k8s_pod_memory_working_set_bytes / k8s_container_memory_limit_bytes`. The `load-test` dashboard computes this value.

### Deliberate gaps

This table keeps the documentation and the cluster in agreement.

| Gap | Reason |
| --- | --- |
| `kube-system` has a `LimitRange` and **no `ResourceQuota`** | A quota rejects pod creation. In `kube-system`, the rejected pods are the CNI DaemonSet, CoreDNS, and the ingress controller. Recovery from a rejected system pod needs a working cluster. So the line is at objects that can only add defaults |
| **No `min` or `max` on any `LimitRange`** | Both reject pods. A `min.memory: 16Mi` floor would reject Cilium's `install-cni-binaries` initContainer on every node, and that initContainer correctly requests 10Mi. A render of every chart before apply caught this |
| **Only one `PodDisruptionBudget` is enabled** | A PDB with `minAvailable: 1` in front of a single-replica workload permits zero disruptions, and `kubectl drain` hangs forever. On a single-node tier, only `postgres-pgbouncer` runs two replicas. The other PDBs are declared and disabled in values. They are the list that a multi-node environment enables as it scales those components out |
| **Temporal pods cannot declare `priorityClassName`** | The upstream chart exposes `resources` per role and no priority field, so these pods inherit the `globalDefault`. For this reason, `platform-critical` is the default, not `product`. The workloads that *cannot* declare a priority are the ones that need the high one. The workloads the platform team controls declare `product` explicitly, to sit below the platform |
| **One CPU limit remains** | `temporal-worker-controller-manager` inherits `limits.cpu: 500m` from its subchart. Helm does not support the removal of a nested subchart key from a parent values file. This is a [long-standing Helm coalescing limitation](https://github.com/helm/helm/issues/9136). Accepted, because 500m is about 80 times the measured 6m peak of a leader-elected reconciler. It is allow-listed with a reason, and so is Cilium's init-container limit |

## Consequences

### Positive

- A noisy service cannot starve a Core component, and the eviction order is deterministic.
- Guardrails are namespace-level defaults, not repeated work per service.
- Capacity pressure shows as quota rejections in manifests that CI reviews, not as OOMs in the night.
- Every committed number traces to a recorded measurement. After a traffic change, a new derivation is mechanical.

### Negative and Risks

- **Requests that are too low still overcommit. Requests that are too high waste capacity.** Observability feeds right-sizing, per [ADR-0500](0500-observability.md), and the load suite produces the number. Both reduce the risk.
- **`ResourceQuota` can block a deploy when a namespace is full.** This back-pressure is intended. It must be a clear failure, not a pod that stays pending with no message. `lint:resource-governance` prints how much of its quota each namespace uses on every CI run, so the team sees the cap coming.
- **A values file cannot govern a chart that has no field for a value.** `platform-critical` is the `globalDefault` so that those charts inherit the priority they need. This is a workaround, not a control. It moves every workload without an annotation upward, including workloads that should sit below the platform. Mutation at admission time replaces it, per [ADR-0104](0104-supply-chain-security.md).

## Rules

- Every container declares CPU and memory requests and a memory limit, or it lands in a namespace whose `LimitRange` supplies them. A container with neither is a defect. `(CI: lint:resource-governance)`
- No container sets a CPU limit unless throttling is the intent. An inherited limit that cannot be removed is allow-listed with a reason. `(CI: lint:resource-governance)`
- A `LimitRange` may only add defaults and never reject: no `min` and no `max`. A rejection of a third-party pod on a floor that the platform invented is a self-inflicted outage. `(CI: lint:resource-governance)`
- Every namespace that the platform owns has a `LimitRange` and a `ResourceQuota`. `kube-system` is the documented exception. `(CI: lint:resource-governance)`
- The summed requests and memory limits of a namespace fit inside its `ResourceQuota`, and every run reports how much of the quota is used. `(CI: lint:resource-governance)`
- Workloads carry a `PriorityClass`. `platform-critical` is the `globalDefault`, so charts that cannot express a priority inherit the right one. Product workloads explicitly choose a lower class.
- Every multi-replica or stateful component has a `PodDisruptionBudget` that preserves quorum. A single-replica workload gets none.
- Requests and limits come from measurement, per [ADR-0601](0601-testing-strategy.md), and the measurement is recorded next to the value.
- Memory sizing uses the working set, never the ratio of memory usage to the limit.
- HPA is opt-in per service on a documented sustained-load signal, never a template default.
