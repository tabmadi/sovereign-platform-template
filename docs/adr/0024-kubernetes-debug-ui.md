# ADR-0024: Kubernetes Debug UI

- **Status:** Accepted
- **Date:** 2026-07-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0004](0004-gitops.md), [ADR-0011](0011-observability.md), [ADR-0017](0017-url-and-domain-structure.md), [ADR-0025](0025-service-map-apm-ui.md)

## Context

The ops surfaces answer different questions: ArgoCD (what is deployed), Grafana (signals), Hubble UI
(service map / network flows, [ADR-0025](0025-service-map-apm-ui.md)), Temporal (workflows). None does the k9s job — *what pods exist right now, describe them, tail
their logs, exec in, port-forward*. During an incident that gap is filled today by a laptop with
`kubectl`, which is fine for engineers with cluster access but leaves no shared, auth-gated view.

## Decision drivers

1. **A live pod-level view** that complements, not duplicates, the existing ops tools.
2. **Consistent with the ops-tier pattern** ([ADR-0017](0017-url-and-domain-structure.md)) — one origin,
   one gate, no new concepts.
3. **Does not fight GitOps** ([ADR-0000](0000-platform-foundations.md) principle 3): the cluster's desired
   state lives in Git, not in a UI a click can mutate.
4. **Self-host, low surface** ([ADR-0000](0000-platform-foundations.md)).

## Decision

- **Tool: Headlamp** (CNCF Sandbox, Apache-2.0). A single in-cluster deployment, OIDC/header aware, drops
  into the existing pattern as one more ops origin.
- **Ops-tier origin `headlamp.ops.<host>`**, behind the ops forward-auth: coarse `operator` claim + AAL2, with
  the optional per-tool OpenFGA grant `dashboard:headlamp#view` ([ADR-0017](0017-url-and-domain-structure.md)).
- **Read-only by default.** Headlamp runs bound to the built-in **`view` ClusterRole** — list/get/watch
  across the cluster, describe, and tailing pod logs. `view` grants no `create` verbs, so there is **no
  exec, no port-forward**, and it **cannot read `Secret` objects** (secrets are excluded from `view`). It
  is a *debugging* surface, **not a control surface**: it does not create, edit, or delete reconciled
  resources. Desired state changes go through Git and ArgoCD ([ADR-0004](0004-gitops.md)). This scoping is
  what keeps it consistent with the "no clicking in UIs to persist state" principle. A project that wants
  interactive exec/port-forward for diagnosis swaps `view` for a custom role that adds those verbs
  explicitly — and takes on the wider surface knowingly.
- **Core component** ([docs/operational-surface.md](../operational-surface.md)): deployed in every
  environment. A project that does not want it removes it like any Core part — `enabled: false` in the env
  overlay, per this ADR.
- **Alternatives rejected:** k9s (excellent, but a TUI — no shared web origin, no edge gating); Kubernetes
  Dashboard (token-handling and past-CVE security baggage we do not want on an ops origin).

## Consequences

### Positive

- The k9s workflow gets a shared, auth-gated web home without a new access model — one row in the ops
  tier.
- Read-only-by-default means it cannot become a GitOps-bypassing control plane.
- During an incident, an operator reaches pods, describe, and logs through the same login as every other
  dashboard.

### Negative / Risks

- `view` cannot read `Secret` objects, exec, or port-forward, but log tailing still exposes any sensitive
  value an application logs, and pod specs/ConfigMaps expose inline-literal env values; access is therefore
  gated behind operator + AAL2. A project needing tighter limits narrows the ClusterRole further (e.g.
  dropping `pods/log`).
- One more always-on component to patch, in every environment. Accepted as Core operational surface; a
  project that does not want the surface removes it per this ADR.

### Follow-ups

- `infra/helm/platform/headlamp/` with the read-only ClusterRole and the flag gate.
- `headlamp.ops.<host>` IngressRoute + Oathkeeper rule ([docs/gateway/runbook.md](../gateway/runbook.md)).
- Optional `dashboard:headlamp` grant in the OpenFGA schema for the fine per-tool layer.

## Rules

- The Kubernetes debug UI is Headlamp, a Core component deployed via Helm + ArgoCD in every environment,
  served at `headlamp.ops.<host>` behind the ops forward-auth (operator claim + AAL2). `(review-only)`
- Headlamp runs with a read-only ClusterRole by default; it is a debugging surface, not a control surface.
  Desired-state changes go through Git/ArgoCD, never the UI ([ADR-0004](0004-gitops.md)). `(review-only)`
