# ADR-0201: GitOps and Deploy

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0101](0101-monorepo.md), [ADR-0103](0103-release-and-versioning.md), [ADR-0200](0200-cluster-topology.md), [ADR-0202](0202-secrets.md), [ADR-0205](0205-environment-parity.md), [ADR-0600](0600-local-development-loop.md)
- **Decides:** Argo CD is the only deploy mechanism, and it reconciles one shared Helm chart from this repository with values per environment.

## Context

Three environments run one cluster each, per [ADR-0200](0200-cluster-topology.md). Deploys cover the service fleet, the frontend, and every platform component, including the GitOps controller itself.

This ADR answers five questions:

- How code reaches a cluster.
- How the record of what runs in production stays auditable and revertable.
- Whether services and platform components share deploy machinery.
- How environments differ without three copies of each manifest.
- How images are promoted.

## Decision drivers

1. **The cluster reconciles itself.** Nothing outside the cluster holds credentials to it. The controller reports divergence from the declared state and never assumes it away.
2. **Onboarding cost stays flat as the fleet grows.** The Nth service must not add an Nth hand-written deploy manifest.
3. **The bootstrap order can be expressed.** A CNI comes before any pod, a secret operator before the secrets, and a database before its consumers.
4. **PRs are the audit log.** Every change to what runs in production is a merged PR, and rollback is `git revert`.
5. **One chart per concern, with differences in values.** A difference between environments must not become a second copy of the manifest.

Two constraints come from other ADRs, and they select nothing below, because every option meets them:

- An image is built once and promoted by SHA, per [ADR-0101](0101-monorepo.md).
- No secret value reaches git in plaintext, per [ADR-0202](0202-secrets.md).

## Considered options

### The controller

| Option | Fleet fan-out | Ordered bootstrap | Operator UI | Verdict |
| --- | --- | --- | --- | --- |
| **Argo CD** | **[ApplicationSet generators](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators/)**: git-directory, list, and cluster. They fan out across the fleet with no manifest per service | sync waves, health checks, and hooks before and after sync | strong. It answers what is deployed during on-call | **Chosen.** Apache-2.0, CNCF graduated *(documented)* |
| Flux | a Kustomization and a HelmRelease per target, or a hand-written generator | `dependsOn` | none first-party | Driver 2 decides it: onboarding a service must not require a new manifest |
| Flux with a third-party UI | the same as Flux | the same as Flux | Flamingo renders Flux resources through Argo's UI | It adds a second project to the floor to get back what Argo CD ships. It leaves driver 2 unanswered |
| CI pushes with `helm upgrade` | not applicable | script order | none | CI holds cluster credentials, and drift is invisible. It fails drivers 1 and 4 |

### Templating

| Option | Environment differences | Cost of the Nth service | Verdict |
| --- | --- | --- | --- |
| **Helm values** | one values file per target | one values file against a shared chart | **Chosen.** It is driver 5 in its cheapest form. The ecosystem ships charts, so third-party components need no translation *(reasoned)* |
| Kustomize overlays | a base, plus a patch directory per environment | a base, plus one overlay directory per environment | A patch matches the base by structure, so a base change can silently turn a patch into a no-op. Directories multiply by services times environments, against driver 2 |
| Helm rendered, then a Kustomize post-render | both | both | Two templating systems for one concern. Principle 5 refuses this |
| CUE, Timoni, or jsonnet | typed and composable | strong | A third language in the deploy layer. Every upstream component still arrives as a chart that needs a wrapper |
| A manifest per environment, the honest baseline | copies | three copies | Driver 5 exists to refuse this |

### Ordering generated Applications

| Option | Ordering it can express | Effect on sync policy | Verdict |
| --- | --- | --- | --- |
| **Four ApplicationSets under a root app-of-apps** | between tiers, by sync wave on the root's children | none. Each generated Application keeps its own automated sync | **Chosen.** The ordering sits at the only level Argo sequences, and the sync policy stays per environment *(reasoned)* |
| One ApplicationSet, with sync waves on the generated Applications | **none.** The waves are inert, as the Decision explains | none | This is how most readers understand the feature, and it does not work |
| One ApplicationSet with `RollingSync` progressive syncs | between steps inside the set | **forces automated sync off** on every generated Application | It is built for ordering. To get that ordering, it removes the continuous reconciliation that driver 1 requires |

## Decision

### Argo CD in every cluster

Helm installs Argo CD, and Argo CD manages its own state through the App-of-Apps pattern.

### GitOps state lives in this monorepo

```text
infra/
├── helm/
│   ├── platform/<comp>/        # one chart per platform component
│   └── service/                # one shared chart for every backend service
└── gitops/
    ├── bootstrap/              # root Application and ApplicationSets
    ├── platform/<env>/values.yaml
    └── services/<env>/values/<svc>.yaml
```

With a single repo, one PR changes service code, its chart values, and its deploy state atomically.

**A separate deploy-state repo is deferred.**

| Field | Value |
| --- | --- |
| **Trigger** | Promotion commits outnumber code commits on `master`, or a code review opens against a diff that is more than half values bumps |
| **Seam** | ✓ Deploy state is already one subtree, `infra/gitops/`. Every Application's `source` names a repo URL and a path. A move changes those URLs and the CI job that commits promotions |
| **Cost if adopted late** | The history of the moved subtree splits or is rewritten. The cut invalidates every open prod promotion PR. The cost grows with the number of environments, not with time |

### Templating

| Target | Chart | Environment differences |
| --- | --- | --- |
| Platform component | `infra/helm/platform/<comp>/` | `infra/gitops/platform/<env>/values.yaml` |
| Backend service | **one shared chart** at `infra/helm/service/` | one values file per service per environment |

The shared chart has parameters for these:

- image, ports, and replicas
- environment variables and ingress paths
- resource requests and limits
- the Temporal worker and the migration init container
- secret references

Kustomize is not used. A difference that a value cannot express is a chart change, not an overlay.

A new service is the service folder, per [ADR-0101](0101-monorepo.md), plus one values file per environment. The ApplicationSet does the rest.

### Fan-out and ordering

Each environment has five ApplicationSets, ordered by sync wave on the root app-of-apps. **Each wave is named for the reason it must come before the next.** A chart belongs to the last wave whose successors still resolve it. So a reader can check the ladder chart by chart, and does not need to memorise a layering.

| Wave | Set | Components | Why it comes before the next |
| --- | --- | --- | --- |
| `-10` | AppProjects | one `AppProject` per environment | An Application cannot cite a project that does not exist |
| `0` | `platform-admission` | namespaces and PSA, kyverno, priority classes, resource-governance, network-policies, cert-manager, sops-operator, local-path | Admission runs once, at creation. A policy that arrives later has already missed what it gates |
| `1` | secrets | the `SopsSecret` of the environment | The operator that decrypts it is running |
| `2` | `platform-stores` | postgres, seaweedfs | Every later wave reads one of them, and they need the decrypted credentials |
| `3` | `platform-telemetry` | observability, alertmanager | `otel-agent` exports to `tempo` and `loki` **by name**, so the backends cannot come after the collector |
| `4` | `platform-core` | zot, otel-agent, ory, edge-errors, mailpit, maddy, temporal, openfga, public-tls | everything that a service resolves by name |
| `5` | gateway | Traefik middlewares and cross-cutting IngressRoutes | Its `problem-json-errors` middleware names `edge-errors` |
| `6` | services | one Application per service, from a git-directory generator over the values files | nothing comes after it |
| `7` | `platform-consoles` | pgweb, headlamp, lowdefy | Nothing resolves a console |

**The rule alone does not predict two placements:**

- `zot` sits in core, but no DNS name resolves it. Deployed nodes pull images from it, so it comes before anything that starts later. It also needs the wave-2 bucket.
- The mounted-config Applications sit one wave *before* the tier that mounts them. These are Prometheus rules, Grafana dashboards, and Alertmanager silences. A pod whose ConfigMap volume is missing cannot start.

**A wave holds only what a later wave resolves.** An operator console is a read surface over the platform, per [ADR-0501](0501-operator-uis-and-dashboards.md). No workload looks one up. The gateway's ops routes are `IngressRoute`s, and they answer as soon as their backend appears. A wave that holds a console makes every later wave wait for a dashboard. It also puts the console's pods on the node while the store's consumers still elect a leader.

The rule also works in the other direction, and this half is easier to get wrong. A component that nothing resolves may still come late. A component that something resolves may never come late. Telemetry is the example: the collector names its backends, so the backends come before it. No reordering for speed may cross that edge.

Cilium and Argo CD are in no tier, in any environment. Both are installed imperatively before Argo runs. This is the one-time bootstrap step that this ADR permits. No pod schedules before the CNI exists, and Argo cannot apply its own first install.

Management through this set also breaks both components:

- Every generated Application targets the `platform` namespace. Cilium runs in `kube-system`, and Argo CD runs in `argocd`.
- Both charts carry cluster-scoped RBAC. The rendered `ClusterRoleBinding` keeps its name and rebinds the subject to `platform:<sa>`. This overwrites the correct binding.
- The component then loses the access that its own `ClusterRole` grants, and it still reports healthy.

**The waves inside one set are inert.** The ApplicationSet controller creates the Applications that one ApplicationSet generates. They are not synced as a parent's resources. So Argo never sequences them among themselves, and it applies them concurrently. Ordering exists only between the children of a root app-of-apps. For this reason, each tier is its own set.

**The gates work only because the API server computes the diff.** Every Application here syncs with `ServerSideApply`. The cluster runs mutating webhooks: CNPG sets defaults on a `Cluster`, and Kyverno mutates pods. So the live object correctly carries fields that no chart rendered. A client-side diff calls that drift forever, and the Application never reports Synced. A tier is Healthy only when every Application it generated is **Synced and Healthy**. So one such resource holds its wave shut, and no later tier runs. `controller.diff.server.side` diffs against the API server's dry-run instead. Without it, an Application reports OutOfSync while `argocd app diff` prints nothing.

**A custom health check makes the waves real gates.** By default, ApplicationSet health reflects only successful templating. A custom health check on the `ApplicationSet` kind walks `.status.resources`. It reports Progressing until every generated Application is Synced and Healthy. So wave 3 blocks until waves 0 through 2 are up.

A second health check on the CNPG `Cluster` kind makes the gate from data to core honest. Without it, Argo reports the unknown CRD as Healthy as soon as it applies. Core then starts against a Postgres that is not ready. Charts inside a tier still run concurrently and must tolerate that.

Each service Application puts the environment's `shared.yaml` before the service's own values file. A setting that is true of every service in an environment is then declared once, not per service. The registry's pull credential is one example. A default repeated eight times is a default that one service will miss.

A new service appears in dev as soon as its values file lands in `master`, with no change to the Argo configuration. **This keeps onboarding cost flat as the fleet grows.**

### Naming and grouping

Generated Applications are named `<env>-<tier>-<component>`, and env is always the prefix: `dev-platform-postgres`, `prod-service-orders`. Cross-cutting apps with no environment keep a bare name.

The name only helps the display. **Grouping uses Argo's real primitives:**

| Primitive | Role |
| --- | --- |
| **AppProject per environment** | Every generated app sets `spec.project: <env>`. This makes each environment a first-class tenancy boundary, with scoped `sourceRepos` and `destinations`. Sync windows live here. The hand-applied `root` seed and the shared `gateway` app stay in the built-in `default` project, because they create the projects or span all environments |
| **Labels** | `env`, `app.kubernetes.io/part-of`, and `app.kubernetes.io/component` sit on every Application and ApplicationSet. The UI and `argocd app list -l` can then filter by concept |

### Image promotion

CI builds one image per service per commit, tagged by SHA, per [ADR-0101](0101-monorepo.md). A promotion is a commit that pins an environment's values file to the image's digest, per [ADR-0105](0105-image-registry.md).

| Environment | Trigger | Cadence |
| --- | --- | --- |
| dev | A merge to `master` builds images. When every one of them is in the registry, the same workflow commits the digests to `master`. Argo syncs continuously | every merge |
| staging | The same commit pins staging. A sync window of `05:00 UTC, 1h` batches everything that landed since the last window | daily |
| prod | The release tag `v<YYYY.0M.MICRO>`, per [ADR-0103](0103-release-and-versioning.md), opens the digest pin as a pull request. The pull request merges when its checks pass, and the workflow publishes the release | per release |

**Every deployed environment pins by digest**, not by tag, because nobody can re-push a digest. The prod promotion workflow gates on rollout completion, not on Argo reporting Healthy.

**Dev and staging promote by commit. Prod promotes by pull request.** A pull request that a job opens runs CI only if the forge lets a job token trigger workflows. So a bump that waits on those checks can wait forever. A commit made after the images exist cannot wait forever. Prod keeps the pull request, because a release is the one promotion that a person answers for.

The sync-window model batches deploys with no ceremony. Engineers merge freely, and environments come together on a predictable schedule. The release is the one human decision that matters. **Argo CD Image Updater is not used.** It would move deploy state outside the git history, and driver 4 makes that history the audit log.

**A cluster reconciles its own environment and no other.** The ApplicationSets under `infra/gitops/<env>-bootstrap/` name one environment. The generator's `server` field is the cluster that Argo runs in. A set that lists three environments against that one address makes three copies of every chart, and they compete for the same objects. Narrowing the set later is worse than the mistake itself. Deleting the extra Applications prunes objects that the remaining one still owns. Where the namespaces chart is among them, this includes the namespace that Argo itself runs in.

### Sync policy

| Environment | Platform sync | Services sync | Sync window | `selfHeal` | `prune` |
| --- | --- | --- | --- | --- | --- |
| dev | auto | auto | none | true | true |
| staging | auto | auto | `05:00 UTC, 1h` daily | true | true |
| prod | **manual** | auto, on release tag | none, event-driven | false for platform, true for services | true |

`manualSync: true` on the AppProject's sync window permits an ad hoc `argocd app sync` outside the window for incident response.

**The production platform uses `selfHeal=false`.** A manual intervention during an incident then stays visible, and Argo does not silently revert it. Drift raises a notification.

**Failed syncs are retried.** Every Application and ApplicationSet template carries `retry` with `limit: 20` and exponential backoff from 10s to 2m.

`automated` with `selfHeal` does **not** re-run a sync that errored on the same commit, because `selfHeal` reacts only to live drift. Without `retry`, a short repo-server restart during bootstrap leaves the app on a stale `ComparisonError` until someone syncs by hand. This is most dangerous on the hand-applied root app. If it gets stuck, Argo never creates its wave-gated children. A manual sync is the break-glass after the retries run out. A cluster rebuild is never the remedy for a transient failure.

### Bootstrap

This step comes after node provisioning, per [ADR-0200](0200-cluster-topology.md):

```sh
mise run argocd:bootstrap <env>
```

It installs Argo CD and the rest of the bootstrap floor from ADR-0200. Then it applies the root Application. Everything else follows from the root Application, and from then on Argo CD reconciles Argo CD. **The bootstrap is the only non-GitOps action in a cluster's lifetime.**

### Secrets

An in-cluster operator decrypts encrypted files from the repo into native Kubernetes `Secret`s. Helm values reference those Secrets by name. [ADR-0202](0202-secrets.md) sets the mechanism.

### Local development

Argo CD is the engine for the full local tier only, and it deploys from committed `master`. This exercises sync ordering and secret materialisation as production does. The inner loop runs natively, and Argo does not drive it. [ADR-0600](0600-local-development-loop.md) sets both tiers and the escape hatches for work on uncommitted infrastructure.

## Consequences

### Positive

- `git show <sha>` shows what runs in production. There is no ambiguity and no rebuild per environment.
- A new service is a folder plus one values file per environment.
- One shared service chart keeps the deploy shape consistent. A chart change applies to every service at once.
- Image promotion is a reviewable PR, so audit and rollback use git.
- Sync is automatic where mistakes are cheap, tag-driven where they are expensive, and manual where each case is different.
- Sync windows set the deploy cadence on the environment, not through a tag ceremony.

### Negative and Risks

- **The shared service chart is a coupling point.** A breaking change touches every service. Three things reduce the risk: chart versioning, CI that renders the chart against the values of every service, and a review checklist for chart changes.
- **Deploy state in a single repo mixes promotion commits with feature commits.** A title prefix and a separate code owner on the GitOps tree reduce the risk. The deferred split above bounds it.
- **Staging batches by window**, so behaviour after each single merge is not visible there. Accepted: this is the explicit goal. A manual sync is available when the next window is too far away.
- **A bad merge stays on `master` until the next staging window.** Full CI on PRs and dev running `master` continuously reduce the risk.
- **Argo CD itself can fail.** An HA install in production reduces the risk. Downtime blocks new syncs, and running workloads are not affected.
- **Sync waves gate on custom health checks that the platform team maintains.** A bug there gives a false ordering guarantee, which is worse than none. The checks are small and committed, and every local full-tier bring-up exercises them.

## Rules

- Argo CD is the only mechanism that applies manifests to a cluster. `kubectl apply` is permitted only for the one-time bootstrap step.
- Every backend service deploys through the shared chart with a values file per environment. Each platform component has one chart. `(CI: lint:service-contract)`
- Environment differences live in values files, never in chart logic that depends on the environment name.
- An image is built once and promoted by an update to values files. It is never rebuilt for another environment. `(CI: publish.yml)`
- Promotion to dev and staging is a commit that the publishing workflow makes when every image it built is in the registry. Sync windows enforce the cadence. Promotion to production is automatic on a release tag, through a pull request that merges when its checks pass. Every deployed environment pins by digest.
- An environment's bootstrap directory names that environment alone. `(CI: lint:gitops-env-scope)`
- No environment is deployed through a values-bump PR that a person opens by hand.
- Argo CD Image Updater and similar auto-promoters are not used.
- Production platform syncs are manual with `selfHeal=false`. Production services sync automatically with `selfHeal=true`.
- Every Application and ApplicationSet carries a `retry` policy.
- Secret values never appear in git. Manifests carry SOPS-encrypted files or references to the Secrets that those files produce.
