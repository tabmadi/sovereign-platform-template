# GitOps runbook

This guide shows how to operate the Argo CD deploy path. [ADR-0201](../adr/0201-gitops.md) holds the decision. This guide is the procedure.

## Model

- Argo CD reconciles every environment from `master`. **The cluster cannot see a working-tree change until you push it.**
- `selfHeal` reverts direct `kubectl` and `helm` edits. So a change must land on `master` to persist. [ADR-0600](../adr/0600-local-development-loop.md) holds the two exceptions: `cluster:add` and a branch `targetRevision`.
- Configuration is files in this repo. Nothing is set by a click in the Argo UI, per principle 1 of [ADR-0000](../adr/0000-platform-foundations.md).

## Deploy a change

1. Merge to `master`.
2. Wait for Argo CD to detect and sync the change. Watch it at `argocd.ops.<host>`, per [ADR-0306](../adr/0306-trust-tiers-and-urls.md). Or run `kubectl get applications -n argocd`.

## Add an alert or a dashboard

Both are files that their own Application reconciles, per [ADR-0500](../adr/0500-observability.md).

| Artefact | Location | What to check before merging |
| --- | --- | --- |
| Prometheus alert rule | `infra/observability/alerts/*.yaml` | the rule has a `severity` of `page` or `ticket`, per [ADR-0502](../adr/0502-alerting-and-on-call.md) |
| Grafana dashboard | `infra/observability/dashboards/*.json` | the `uid` is stable. Links and the funnel depend on it, per [ADR-0501](../adr/0501-operator-uis-and-dashboards.md) |

Each directory is a chart, and its own Application reconciles it. The chart's template globs the directory into the ConfigMap that the consumer mounts. So **adding the file is the whole step**. You update no index.

Each directory is a chart, not a plain directory source, because neither artefact is a Kubernetes manifest. A dashboard is Grafana JSON, and a rule file uses the native Prometheus format. So both must be generated into a ConfigMap, not applied. Kustomize is not used anywhere, per [ADR-0201](../adr/0201-gitops.md).

This shape has one failure mode: one malformed file fails the render for the whole directory. The Application's condition then names the chart.

A firing alert appears in three places:

- the Prometheus alerts page
- the `ALERTS` series
- the Alertmanager receiver that its `severity` selects

A rule without a `severity` label is a defect. Nothing pages anyone, because no escalation receiver is attached.

## Silence an alert

Silences are configuration. So they live in the repository like everything else, per principle 1 of [ADR-0000](../adr/0000-platform-foundations.md). Review cannot see a silence created in the Alertmanager UI, and the next reconcile removes it. The `alertmanager-silence-sync` CronJob does this removal. Every ten minutes, it reconciles the live silences to the committed file. So a UI silence lasts until the next run and no longer.

1. Add the matcher to `infra/observability/alertmanager/silences.yaml`.
2. **Set `endsAt` to an explicit timestamp.** A silence with no end removes an alert without anyone's decision.
3. Write the reason in the comment above the matcher. State what the silence suppresses, and what makes it safe to remove.
4. Merge. Argo CD reconciles the file like any other file.

Delete an expired silence from the file. Do not extend it. A second extension shows that the rule under the silence is wrong. Fix the rule in one of two ways:

- If the threshold fires without a need for human action, demote the rule to `ticket`.
- If the condition is acceptable, delete the rule and record the reason in the owning ADR.

## Bring up the full platform locally

```sh
mise run cluster:up -- full     # the real charts at single replica, via Argo CD from master
```

The deployed clusters use this same mechanism, per [ADR-0600](../adr/0600-local-development-loop.md). To exercise **uncommitted** GitOps wiring, see [gitops-local](gitops-local.md).

## Bootstrap a deployed environment

Set the new cluster as the current kubectl context. Then run:

```sh
CLUSTER_AGE_KEY=<path to its age key> mise run argocd:bootstrap <env>
```

The task lays the floor that Argo CD cannot install for itself:

- Argo CD
- Traefik
- the age key
- the forge credential of a private repository

It then applies the root Application, per [ADR-0200](../adr/0200-cluster-topology.md). Set `CLUSTER_AGE_KEY` only where the machine config does not already carry the key.

When the applications are Healthy, log in as the first operator. See [break-glass](break-glass.md).

## Verify an environment

```sh
mise run verify                          # the local tier that is up
VERIFY_HOST=<apex> mise run verify       # a deployed environment, through the current kubectl context
```

The deployed mode adds three checks:

- a purchase through every service with disposable identities
- the self-service escalation probe
- a mail submission

It deletes everything it creates.

## Diagnose a stuck sync

- Run `kubectl get applications -n argocd`. Find the app that is OutOfSync or Degraded.
- Run `kubectl describe application <name> -n argocd`. Read its events and conditions.
- Sync waves handle the order: CRD, then operator, then instance. The first platform sync is slow by design.
- Every Application has a `retry` policy, so a transient error heals itself. When the retries run out, a manual `argocd app sync` is the break-glass. A cluster rebuild is never the fix.
- If a node's containerd hangs on a large image pull, run `mise run cluster:heal`, per [dev-loop](../dev-loop.md). Do not restart the node.

## When the symptom names the wrong layer

Cluster faults in this platform often look like something unrelated. The component that *reports* the error is rarely the component that is broken. Someone diagnosed each of these the long way at least once.

| What you see | The usual cause |
| --- | --- |
| Cilium agents fail fatally on `Unable to find all Cilium CRDs` | The **operator cannot schedule**. Check the node taints. `disk-pressure` is the common one. On a laptop, the node's `image filesystem` is your whole disk |
| Helm hangs in pre-install, and the Events list is empty | **Nothing can schedule at all.** A cluster of only control-plane nodes taints every node. The fix is `allowSchedulingOnControlPlanes` |
| Pods time out on `10.96.0.1:443`, and Cilium reports healthy | **RBAC or the dataplane**, not the API server. `cilium-dbg` reports the agent's own view. It shows `KubeProxyReplacement: True` and `Cluster health: 3/3` while no pod can reach a Service |
| etcd is stuck in `Preparing`, and waits on a service that is Running | The **etcd spec is missing**. The waiting list is static. It names every precondition, not the unmet one. A bootstrap sent before a post-apply reboot writes a spec that dies with the old instance |
| A pod stays in `ContainerCreating` with **no pull events at all** | A **volume**, not an image. A missing secret, or a hostPath that the kubelet never got, stays in mount with no error |
| `403 Forbidden` on the pull of `registry.k8s.io/etcd`, and the cluster never bootstraps | A **proxy** that the machine config does not carry. See [`http-proxy`](http-proxy.md) |
| One admission webhook times out, and other webhooks work | The webhook pod **is older than the current CNI**. A CNI replacement leaves stale endpoints for pods that were already running. Only pods that nothing restarted since then are affected. Roll the deployment |
| A replica join retries forever with `no route to host` | **Network policy**, not routing. A Cilium drop looks like `no route to host` to the caller. `hubble observe --verdict DROPPED` shows the missing rule in one line |
| An Application reports **OutOfSync, but `argocd app diff` prints nothing** | A **mutating webhook** and a client-side diff. The live object has fields that no chart rendered, so the diff never converges. A tier waits for every Application to be Synced, so one such resource blocks every later wave. The fix is `controller.diff.server.side`, per [ADR-0201](../adr/0201-gitops.md) |
| Applications look Synced but are hours **stale**, and nothing consumes a refresh annotation | The **application controller is restarting**, usually from OOM. The sign is a `status.reconciledAt` that falls behind. Every Application keeps its last status while nothing reconciles |
| An admission webhook times out **intermittently**, and works after a restart | The API server reaches a pod from its own node's address. Cilium classifies that address as `host` or `remote-node`, **never** as `kube-apiserver`. A policy that admits only that entity works only when the webhook shares a node with the caller |
| Every ops panel answers **404**, but the routes exist | Traefik **drops a router when it cannot build the router's middleware**. Only Traefik's log shows the reason: `kubernetes service not found: platform/edge-errors`. The panel looks unrouted, not unbacked |
| A registry push retries layers forever with `unexpected EOF` | A **timeout on one of the hops**. An image push is the longest request that the edge carries. The first of Traefik or the registry to cut the connection decides. So both timeouts are set together, per [ADR-0105](../adr/0105-image-registry.md) |

**The habit that saves the most time: verify the dataplane with a pod.**

```sh
kubectl run t --rm -i --restart=Never --image=docker.io/library/busybox:1.37 -- \
  sh -c 'wget -T10 -O/dev/null https://10.96.0.1:443/version
         nslookup kubernetes.default.svc.cluster.local'
```

A 401 from the API means that the connection worked. That is success, not failure. A failed name resolution means that Service routing is dead. This is true whatever each component's own health endpoint reports.

Both halves of that image reference matter. Admission rejects the short forms that people usually write in this command:

- `busybox` is denied. The allow-list holds repositories in registry-qualified form.
- `docker.io/library/busybox` without a tag is denied. Every entry needs a tag or a digest. ADR-0104 exists to reject an implicit `latest`.

Query the **fully qualified** Service name. The pod resolves a short name through its search list. So a working cluster first prints one `NXDOMAIN` for each suffix that does not match. That looks like a DNS failure, but it is not one.

A namespace under the `restricted` Pod Security profile needs four fields that `kubectl run` omits:

- `runAsNonRoot`
- `allowPrivilegeEscalation: false`
- `capabilities.drop: [ALL]`
- `seccompProfile`

In such a namespace, apply a Pod manifest that carries them.

## Move the repository

A new owner or name on the forge changes every `repoURL`. Argo CD's git client does not follow the forge's redirect. So make the move explicit:

1. Authenticate by the forge's origin, not the repository URL. Use an `argocd.argoproj.io/secret-type: repo-creds` Secret whose `url` is `https://forge.<apex>/`. It matches both the old and the new path.
2. Commit the new `repoURL` everywhere and push.
3. Apply the root application again: `kubectl apply -f infra/gitops/<env>-bootstrap/root-application.yaml`. It cannot fetch its own rename commit through the old URL.
4. Annotate every ApplicationSet with `argocd.argoproj.io/application-set-refresh=true`. Their status keeps the failed sync from the move. The root's health wait does not clear until they refresh.

## Break-glass

When the auth plane that gates the Argo UI is down, reach the UI with `kubectl port-forward`. See [break-glass](break-glass.md).
