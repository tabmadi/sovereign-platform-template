# ADR-0020: Resource Management & Scheduling

- **Status:** Accepted
- **Date:** 2026-07-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0003](0003-cluster-topology.md), [ADR-0006](0006-temporal.md)

## Context

Application services, stateful platform components, and batch/bootstrap Jobs all share the three-node set
([ADR-0003](0003-cluster-topology.md)). Without resource governance a single noisy service can starve
Temporal, Postgres, or the observability stack, and the scheduler has no basis for eviction order. At the
target scale a small team cannot babysit per-pod tuning, so the policy must be defaulted, not per-service.

## Decision drivers

1. **No workload can starve a Core component** ([docs/operational-surface.md](../operational-surface.md)).
2. **Defaults over per-service tuning** — the policy applies to every namespace without per-service work.
3. **Predictable eviction order** under pressure.
4. **Boring, in-tree Kubernetes primitives** ([ADR-0003](0003-cluster-topology.md)).

## Decision

Every container declares resources, and each namespace carries guardrails.

- **Requests and limits are mandatory.** Every container sets CPU/memory requests and memory limits. CPU
  limits are set only where throttling is desired; CPU requests plus priority handle contention. A
  container with no requests is a defect.
- **`LimitRange` per namespace** supplies default requests/limits so a missing value fails safe rather
  than scheduling unbounded.
- **`ResourceQuota` per namespace** caps aggregate CPU/memory so one namespace cannot consume the cluster.
- **`PriorityClass` tiers** set eviction order: `platform-critical` (CNPG, Temporal, OpenFGA, Kratos,
  Oathkeeper, edge, observability) > `product` (application services) > `batch` (bootstrap/one-shot Jobs).
  Under pressure, batch dies first, Core last.
- **`PodDisruptionBudget`** for every multi-replica and stateful component, so voluntary disruptions
  (drains, upgrades) never take quorum below one.
- **No HPA by default.** Autoscaling is opt-in per service when a measured, sustained load signal justifies
  it — the same "grow on a trigger, not a guess" discipline as [ADR-0003](0003-cluster-topology.md)'s node
  growth. A service adds an HPA with a documented signal; it is not template default machinery.

## Consequences

### Positive

- A noisy service cannot starve a Core component; eviction order is deterministic.
- Guardrails are namespace-level defaults, not per-service toil.
- Capacity pressure surfaces as quota/`LimitRange` rejections in CI-reviewed manifests, not as 3am OOMs.

### Negative / Risks

- Requests set too low still overcommit; too high waste capacity. Mitigated by observability
  ([ADR-0011](0011-observability.md)) feeding right-sizing over time.
- `ResourceQuota` can block a deploy when a namespace is full — intended back-pressure, but it must be a
  legible failure, not a silent pending pod.

### Follow-ups

- `LimitRange`, `ResourceQuota`, and the three `PriorityClass` objects in the platform charts.
- `PodDisruptionBudget` on CNPG, Temporal, OpenFGA, Loki/Tempo, and the edge.
- Default requests/limits in `services/_template/` chart values.

## Rules

- Every container declares CPU/memory requests and a memory limit. A container without requests is a
  defect. `(review-only)`
- Every namespace has a `LimitRange` (default requests/limits) and a `ResourceQuota` (aggregate cap).
  `(review-only)`
- Workloads carry a `PriorityClass`: `platform-critical` > `product` > `batch`; batch is evicted first.
  `(review-only)`
- Every multi-replica or stateful component has a `PodDisruptionBudget` that preserves quorum.
  `(review-only)`
- HPA is opt-in per service on a documented sustained-load signal, never a template default. `(review-only)`
