# GitOps runbook

How-to for operating the ArgoCD-based deploy path. The decision (ArgoCD + ApplicationSets, app-of-apps,
reconcile from Git) is [ADR-0004](../adr/0004-gitops.md); this is the operational procedure.

## Model

- ArgoCD reconciles every environment from `master`. **A working-tree change is invisible in-cluster
  until it is pushed** ([ADR-0004](../adr/0004-gitops.md)).
- `selfHeal` reverts direct `kubectl`/`helm` edits, so a change must land on `master` (or be applied in a
  deliberately watched window) to persist.
- Configuration is files in this repo; nothing is set by clicking in the Argo UI
  ([ADR-0000](../adr/0000-platform-foundations.md) principle 3).

## Deploy a change

1. Merge the change to `master`.
2. ArgoCD detects and syncs it. Watch: `argocd.ops.<host>` ([ADR-0017](../adr/0017-url-and-domain-structure.md))
   or `kubectl get applications -n argocd`.

## Local full platform

```sh
mise run cluster:full           # brings the real charts up at single replica, via ArgoCD from master
```

This is the same mechanism the persistent dev/staging/prod clusters use
([ADR-0003](../adr/0003-cluster-topology.md), [ADR-0016](../adr/0016-environment-parity.md)).

## Diagnose a stuck sync

- `kubectl get applications -n argocd` — which app is OutOfSync/Degraded.
- Inspect the app's events/conditions in the Argo UI or `kubectl describe application <name> -n argocd`.
- CRD→operator→instance ordering is handled by sync waves; a first-run platform sync is slow by design.
- If a node's containerd wedges on a large image pull, recover per
  [docs/cluster/dr-runbook.md](../cluster/dr-runbook.md) (`mise run cluster:heal` / image import), not by
  restarting the node.

## Break-glass

When the auth plane gating the Argo UI is down, reach it via `kubectl port-forward`
([docs/ops/break-glass.md](../ops/break-glass.md)).
