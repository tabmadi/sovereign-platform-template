# ADR-0600: Local Development Loop

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0100](0100-language-and-runtime.md), [ADR-0101](0101-monorepo.md), [ADR-0200](0200-cluster-topology.md), [ADR-0201](0201-gitops.md), [ADR-0205](0205-environment-parity.md), [ADR-0206](0206-cluster-networking.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0304](0304-identity-and-authorization.md), [ADR-0305](0305-edge-auth-and-traffic-policy.md), [ADR-0400](0400-frontend.md), [ADR-0601](0601-testing-strategy.md)
- **Decides:** Two local tiers run on kind, `cluster:up` for the inner loop and `cluster:up full` for the platform, with a vendored mock and no second system definition.

## Context

[ADR-0205](0205-environment-parity.md) fixes the parity contract across environments. This ADR decides what runs on an engineer's machine. It defines which tiers exist, how a tier is composed, what builds it, and which parts of the platform its contract replaces.

Three jobs need different tiers, and one tier cannot serve all three:

| Job | Optimises for | Needs |
| --- | --- | --- |
| Iterate on the code of one service | speed | that service running natively, with its dependencies reachable |
| Build a UI screen | speed, across many services | an authenticated page. The services behind it do not change |
| Check that the platform behaves like production | fidelity | the real charts and the real operators |

By default, the second job has no cheap answer. A single panel screen calls `/products`, `/orders`, `/orgs`, and `/charges`. These are four services that the engineer does not change.

The full-platform tier serves them, but the platform dominates its footprint completely. The observability stack alone uses more than every service, per [ADR-0601](0601-testing-strategy.md). None of that cost renders a table. The gap grows with the fleet: the services behind a screen increase, but the service under change stays at one.

Two properties make the missing tier cheap:

- [ADR-0303](0303-api-contracts-and-lifecycle.md) produces exactly the artifact that a mock needs. The `gen:openapi-public` projection at `apps/frontend/public/devportal/openapi/internal.json` is one merged OpenAPI 3.1 document. It holds exactly the operations at audience `>= internal`, with `servers: /api`. It is committed and checked for drift.
- The auth stack is small. Kratos plus Oathkeeper plus an ephemeral Postgres costs almost nothing next to the full tier.

So the question is not how to simulate the platform. The question is **which parts are cheap enough to keep real, and which are worth replacing with their contract**.

## Decision drivers

1. **The spec is the only source of mock behaviour.** The mock does not serve a response shape that a committed OpenAPI artifact cannot produce.
2. **No development-only code in the application**, and never in the authentication path. A branch in the app's authn gate that grants a session is a production risk taken for developer convenience.
3. **A tier costs what it runs.** For each component, the question is whether a real component is cheaper than its contract. So the design removes components.
4. **Nothing new in any deployed environment.** This is local tooling: no chart, no environment, and no image built from our source.
5. **Coexistence with Helm and Argo CD.** A second orchestrator that wants to own the same resources is a conflict.
6. **A tool adopted here is inherited, not chosen.** Every derived project gets this toolchain without a new decision. So active maintenance and an OSS licence are entry gates, not scoring columns. Popularity does not measure fitness.

## Considered options

### Local Kubernetes approach

| Approach | How it works | Cost | Verdict |
| --- | --- | --- | --- |
| **Local cluster** | a scaled-down copy of the whole system on the laptop | the laptop's resource ceiling. Stand-ins can drift | **Chosen.** No shared infra, no platform team, full isolation, and it works offline *(reasoned)* |
| Sync tools | a tool watches files, rebuilds images, and deploys again | a second orchestrator beside Helm and Argo, and an image build on the hot path | **Partly chosen:** the deploy step, not the watch loop |
| Shared cluster, one service local | the base cluster runs remotely, and the service under development joins it | needs a platform team. It has contention unless someone builds isolation at the request level | The highest fidelity. It is the destination past the ceiling below |
| Cloud workspaces | the whole dev environment moves to a remote machine | a cost for each engineer, a dependency on the network, and the weakest local tooling | Unrelated to parity |

### Local Kubernetes distribution

The approach above chooses a cluster on the laptop. This section chooses which one. Every option runs the same charts, per [ADR-0205](0205-environment-parity.md). So the comparison covers what the distribution changes under the charts.

Conformance makes a chart apply. It does not make the cluster behave the same. A distribution can differ from [ADR-0200](0200-cluster-topology.md) and [ADR-0206](0206-cluster-networking.md) at four layers. A chart that applies cleanly shows none of them:

| Layer | What a deployed environment runs | What a difference hides |
| --- | --- | --- |
| Distribution | upstream Kubernetes, shipped and upgraded by Talos | a behaviour of the Kubernetes version, and any patch that a vendor carries |
| Datastore | embedded etcd | the watch, compaction, and optimistic-concurrency semantics that the operators on the floor depend on. These are properties of **etcd**, not of quorum. A single-member etcd is still a Raft group. It serves watch streams, MVCC revisions, compaction, and compare-and-swap in the same way. So the full tier reproduces them at any node count |
| Service datapath | Cilium's eBPF dataplane, with `cluster.proxy.disabled: true` and no kube-proxy | Service routing, source-IP preservation, and backend health semantics |
| Edge | the committed Traefik chart | middleware and CRD behaviour on the path of every request |

| Option | Node shape | Getting an image in | Differs at | Verdict |
| --- | --- | --- | --- | --- |
| **kind** | upstream Kubernetes in Docker, provisioned by kubeadm | `kind load docker-image`, or a local registry | node count and the machine config, in both tiers | **Chosen for both tiers.** It runs upstream Kubernetes on etcd, declines kube-proxy at create time, and bundles no edge. So Cilium runs its eBPF dataplane against the committed chart. There is one provisioner, one image path, and one bring-up to debug *(reasoned)* |
| Talos in Docker | Talos nodes as containers, driven by `talosctl` and a machine config | a local registry only. A Talos node holds no image that the cluster did not pull | the host kernel and the installer path: no system extensions, no disk layout, no upgrade path. Container mode lacks the `upgrade` and `reset` APIs | **Rejected after a real run.** Its case was to exercise the machine config, and that case is weaker than it looks. The local patch is not the deployed one, so the tier validates a config that exists nowhere else. Its cost was measured: see the operating cost below *(measured)* |
| k3d | k3s in Docker containers | `k3d image import`, or the built-in registry | all four | Its bundles are the loss that [ADR-0200](0200-cluster-topology.md) already names, and kine and kube-proxy add two more. Its case was speed and footprint, and a measurement removes both: equal on create and destroy, and slightly heavier at idle |
| minikube | a VM or a container, with many drivers | `minikube image load`, or its Docker daemon | the datapath and the edge, plus its addon layer | The most portable across host operating systems, and the heaviest cluster. Its addons are a second source of cluster configuration, which works against parity |
| Docker Desktop or Orbstack Kubernetes | bundled with the host tool | shares the host image store, so no load step at all | the datapath and the edge, managed by the vendor | The best image path in the field, but no control of the cluster lifecycle. It is one cluster, tied to one desktop product. The lifecycle of [ADR-0205](0205-environment-parity.md), where each engineer recreates clusters freely, needs that control |
| Two distributions, one for each tier | not applicable | not applicable | not applicable | **Rejected on its operating cost.** Every seam between the two caused its own defect. A stand-in cleanup deleted the resource that shared its name. An image-unwedge tool worked on one tier only. A preload path branched for each tier. A tier boundary is a workload question. To make it a distribution question puts a second product under it |

The measurement behind these verdicts used a bare single-node cluster of each option, with no CNI and no load balancer. It compared the time to a ready API and the idle memory of the node container. To take it again, create one cluster of each and sample both. A result that reverses it makes the k3d row wrong, not stale.

**The operating cost of a Talos full tier is measured, not predicted.** The tier ran on Talos in Docker. In the next 48 hours, 17 of 84 commits touched cluster machinery. 13 of those dealt with problems that belonged to that provisioner alone:

- node IPs that collided with the shared registry container on a pinned docker network
- a kubelet bind-mount that the read-only root needs before a provisioner starts
- a TLS stanza that Talos refuses on a plaintext mirror
- node memory and disk thresholds sized for a laptop
- an image path that needs a preload, because a Talos node holds nothing that the cluster did not pull

None of these are properties of the platform under test. They are properties of running that OS in a container on a developer's machine.

**That cost bought less fidelity than it seems.** `talosctl cluster create docker` is a supported path, and its own documentation names CI pipelines and local testing. But container mode does not offer the `upgrade` and `reset` APIs, and those are the Talos lifecycle worth rehearsing. The local machine config is also not the deployed one, on purpose. So the tier showed that *a* machine config delivers a CNI and disables kube-proxy, with content that no deployed environment applies. The deployed machine config is exercised where its disks, extensions, and installer are real.

**The parity ladder stays the same. Only the node under it changes.** [ADR-0205](0205-environment-parity.md) permits implementation differences in the inner loop and forbids them in the full tier. That rule forbids differences in *the platform*: the charts, the operators, the sync order, and the datapath. Every one of those is identical on kind. CI, label-gated previews, and pre-merge validation run the full tier. It exercises production's implementation of everything above the node.

**Storage comes from kind in both tiers.** kind ships a provisioner and a default StorageClass, so the `local-path` chart stays off locally. If it were on, two provisioners would share one default annotation, and the second would win with no warning. A deployed environment runs the chart, because Talos ships no provisioner, per [ADR-0207](0207-cluster-storage.md). This is the one component whose local source differs from the deployed one. The difference is a StorageClass, not a behaviour: kind's provisioner is the same `local-path-provisioner` that the chart installs.

**Both local tiers have a single node, and this ADR states the cost in advance.** A local tier never existed to test quorum. Nothing here kills two of three members. The datastore semantics above, watch, compaction, MVCC, and compare-and-swap, are single-member properties of etcd. The three-node deployed environments exercise Raft consensus, leader election, and partition behaviour, per [ADR-0200](0200-cluster-topology.md).

A second node would not add quorum either, and its benefits are fewer than they seem:

- Anti-affinity and PodDisruptionBudgets do not engage. The local tier runs charts at a single replica, and nothing drains a node.
- A node-pinned volume cannot bind to the wrong node when only one node exists.

**The one real loss is the datapath between nodes.** Every pod is on one node, so Service routing between nodes never runs. WireGuard transparent encryption encrypts nothing, because no traffic leaves the node, per [ADR-0206](0206-cluster-networking.md). A regression there does not come from an ordinary change. It comes from a Cilium upgrade or an edit to the encryption values. It appears on the first deployed environment, not on a laptop. That is the accepted trade: the tier gives up a datapath rehearsal and costs one node.

**The two tiers differ only in workloads.** Everything else matches: upstream Kubernetes, etcd, Cilium's eBPF dataplane without kube-proxy, and the committed Traefik chart. Cilium is the same chart with the same WireGuard encryption in both tiers. So the inner loop enforces NetworkPolicy, as every other environment does, per [ADR-0206](0206-cluster-networking.md).

The inner loop cannot show anything that the machine config carries. The full tier shows it, and no tier stands behind the full tier. [ADR-0205](0205-environment-parity.md) makes CI and the label-gated preview that same tier with a different lifecycle. So a difference in the full tier reaches a deployed environment with no check.

**The ceiling of about 20 services is the trigger to revisit this decision.** Below it, the common view is that all services run locally. Above it, the common view is the opposite. A project that grows past it moves to the third approach. Meanwhile, the cheap thing to protect is **trace-context propagation**. Request-level isolation builds on it, for example Lyft's staging overrides, Uber's SLATE, and Signadot's sandboxes. OTel is already wired. Correct propagation keeps that option open.

### Orchestrator

Skaffold, Tilt, DevSpace, and Okteto promote live file sync as their main feature. Here it does not matter: **the inner loop runs the service natively on the host, so no container exists to sync into.** Four of the five orchestrators solve a problem that this design does not have.

| Tool | Resolves the dependencies of each service on a subset | Parallel config system | Verdict |
| --- | --- | --- | --- |
| Garden | **the only one that does** | `garden.yml` for each action | The right convention, the wrong dependency. See below |
| Skaffold | partly, at module level | `skaffold.yaml` | Adopting it again reverses [ADR-0101](0101-monorepo.md) and adds no capability |
| Tilt | **explicitly not**, as documented | Starlark | The healthiest project in the set. Its subset mechanism ignores dependencies, and that is the exact failure to fix |
| DevSpace | coarse: across repos, always first | `devspace.yaml` | The wrong level of detail |
| Okteto | no | `okteto.yml` | Built for remote namespaces |
| **mise, bash, Helm, and Argo** | no. **This is the gap** | none | **Chosen**, and the gap is closed below *(reasoned)* |

**The platform adopts Garden's convention, not Garden.** There are two independent reasons:

- *Stewardship.* A company owns Garden's open-source repository. Its commit and release rate is ten times lower than Tilt's and Skaffold's. Driver 6 makes active maintenance an entry gate, not a scoring column, and Garden does not meet it.
- *Architecture.* To adopt Garden means to adopt its whole config system: its own build, test, and deploy verbs, and its own environment model. That does not sit beside Helm, Argo CD, and mise. It duplicates them and collides with [ADR-0101](0101-monorepo.md) and [ADR-0201](0201-gitops.md). Two orchestrators would then resolve a graph over six services.

A like-for-like sizing gave Garden about 210 fewer lines: about 400 against about 610. Most of the difference was readiness-gated ordering and the image build and import.

Garden does **not** win on graph resolution, the property that first made it attractive. mise already removes duplicates and runs tasks in parallel. The three hardest pieces have no Garden model and stay in bash in both designs:

- docker-bridge discovery in the edge glue
- SOPS secret materialisation
- the Argo pause and resume

### Local-process seam

| Tool | Cluster-side component | Modifies the workload | Gives the process the pod's env and files | Runs a process outside a container |
| --- | --- | --- | --- | --- |
| mirrord | a temporary agent pod | no | **yes** | yes |
| Telepresence | Traffic Manager plus a sidecar | yes | yes | yes, but needs local root |
| Gefyra | none | no | no | **no**. Docker only, and that is the whole inner loop |
| **Edge glue plus port-forward** | none | no | no. A `.env` copied by hand | yes |

**mirrord closes the one remaining weak cell:** it gives a natively run process the pod's environment and files. Its design has no cluster component, which fits the constraints. This ADR compares it and does not adopt it, because the local-process seam works without it.

### API mock

| Tool | 3.1 support | Source of truth | Runtime added | Verdict |
| --- | --- | --- | --- | --- |
| **Prism, from Stoplight** | full | the spec. It serves committed `examples`, and otherwise generates from schemas | a container, with no `mise` tool and no `package.json` | **Chosen.** Request validation gives free feedback: an unknown route gets 404, and a bad body gets 422 *(documented)* |
| MSW | not applicable | typed handlers | in-process | An in-process double, not a running API. Nothing outside the Next server can reach it. It owns the test layer, and that separate concern is the justification that driver 5 requires |
| Microcks | full | the spec, native to GitOps | **MongoDB** | The best GitOps fit, and the only one that also does contract testing. But a datastore that joins the floor for a development mock fails the budget rule |
| `muonsoft/openapi-mock` | **3.0 core, through kin-openapi** | the spec | none, it is a Go binary | The best language fit. It is rejected as the primary mock on a correctness risk: the specs are 3.1. It is the documented fallback if the vendored container becomes unacceptable, on the condition that it proves 3.1 support |
| WireMock or Imposter | good | their own DSL | **JVM** | Excluded by [ADR-0100](0100-language-and-runtime.md) |
| Mockoon | import only | **its own JSON file**. The import is a fork | GUI | The spec stops being the source of truth on the second day |
| Hoverfly | not applicable | recorded traffic | none, it is Go | It needs real traffic to capture first. It adds to a real environment and does not replace one |
| Fake services from `ogen` | full | the spec | none | The highest fidelity, including state, at a cost **for each service**. Across a fleet, this is a parallel implementation of the platform |
| No mock | not applicable | not applicable | none | The true baseline. It does not scale with a growing fleet, and it does not help an engineer who changes no service |

### Identity source

| Option | Why |
| --- | --- |
| **The real Kratos** | **Chosen.** It is cheap, and its behaviour *is* the contract *(reasoned)* |
| A fake IdP: `mock-oauth2-server`, Dex, or a seeded Keycloak | The standard answer elsewhere, because OIDC is a **protocol boundary** where any conforming provider can replace another. Kratos is not that boundary. The frontend couples to Kratos's own surface: browser self-service flows, flow ids, `ui.nodes`, CSRF in flow state, opaque session cookies, and `/sessions/whoami`. A convincing fake reimplements Kratos's flow state machine, and that is a second implementation. This is a property of Kratos, not a ban. **Hydra** *is* a protocol boundary, so a fake OAuth2 provider is legitimate for third-party client work |
| A bypass inside the application | Rejected on driver 2, and it saves nothing. A working bypass must return a fully populated `Session` for the gates after `whoami()`: identity id, email, roles, and AAL. So a fake identity, maintained by hand, remains anyway. It also lacks the login, expiry, and cookie behaviour that made a real Kratos worthwhile |

## Decision

### Two tiers

| Tier | Command | Distribution | Parity | What runs | For |
| --- | --- | --- | --- | --- | --- |
| **Inner loop** | `cluster:up` plus a service's own tasks | kind | **interface** | the local floor. The service under change runs natively on the host | daily coding, UI work |
| **Full platform** | `cluster:up full` | kind | **implementation** | the real platform charts at `instances=1`: CNPG, the Temporal chart, OpenFGA, SeaweedFS, observability, edge, and auth | e2e per [ADR-0601](0601-testing-strategy.md), pre-merge validation, CI, label-gated PR previews |

The inner loop runs the service natively against lightweight stand-ins: a plain Postgres, `temporal server start-dev`, and in-memory OpenFGA. `dev:forward` makes them reachable. The stand-ins honour the same wire contract, so a bug that appears against them also appears in production. The hot path has no image build, no new deploy, and no file watch.

The full platform runs the same charts on the same distribution as a deployed environment. The `local` values overlay scales them to one replica. Cilium is installed from the committed chart, and the cluster declines kube-proxy at create time. etcd is the datastore, per [ADR-0200](0200-cluster-topology.md) and [ADR-0206](0206-cluster-networking.md). This tier catches operator behaviour, sync order, and chart wiring. It is the exact configuration that CI and PR previews use.

**The two tiers are two clusters, not two states of one cluster.** The inner loop survives a full-tier teardown, and neither bring-up disturbs the other. Each has its own `kubectl` context. A service's local port is the same in both, per `scripts/lib/ports.sh`.

**Only the entrypoint names a tier.** `scripts/cluster.sh` takes the tier as an argument, because it creates the tier, per [ADR-0101](0101-monorepo.md). Every other script acts on a cluster that it did not create, and reads the tier from the machine. The tiers share the edge's host ports, so at most one tier serves at a time, and the answer is always clear. The argument exists to remove a hardcoded default. A tool that assumes the inner loop while the full tier serves resolves to a context that does not exist. Every call inside it then fails as if the platform were down.

Images reach the full tier through a local registry. A deployed environment uses the same path: Argo CD pulls a tag from a registry, and does not find the image already on the node. The inner loop keeps the direct import, because nothing there reconciles from git.

### Native and in-cluster are chosen for each service

| Mode | What runs | Cost | Limits |
| --- | --- | --- | --- |
| **Native**, with `service:dev` and `mise run server` | the service on the host, behind the real edge | the lightest | no pod env or files, and no NetworkPolicy enforcement |
| **In-cluster**, with `cluster:add` | the service from the working tree, in the cluster | an image build for each change | no debugger attach |

**Any number of services can run natively at the same time**, each on its own registered port. To debug a flow across three services, run all three natively with breakpoints in all three. Everything they call stays in the cluster.

That needs a **committed port registry** in `scripts/lib/ports.sh`, not a convention. Every server binds `:8080` in the cluster, and that collides as soon as a second server runs on the host.

Ad-hoc ports would live in each engineer's gitignored `.env`. Nobody could share them or give them defaults. One stable port for each service on every machine lets a caller's `CATALOG_URL` ship a working default. `lint:ports` enforces two things: each port is unique, and each service binds the port that the registry assigns. `:8080` stays unassigned, because the host maps it to the edge.

### Composition: a floor, plus declarations by each service

There are no named profiles. **The floor** is always present. `cluster:up` brings up Cilium, Traefik, cert-manager, Postgres, Kratos, and Oathkeeper. It also brings up the host edge glue and the seeded test identities.

Cilium is in the floor for two reasons. A CNI must exist before any pod. It is also the mechanism that [ADR-0206](0206-cluster-networking.md) makes the trust boundary between services. So a service's NetworkPolicy is enforced from the first tier up. A missing allow rule fails where someone wrote it, not in a deployed environment.

The chart, its WireGuard encryption, and its eBPF dataplane are the same in every tier. Only the delivery differs. The nodes of a deployed environment carry the inline manifest in their machine config. A local node has no machine config. So `cluster:up` installs the same chart imperatively, on a cluster created without kube-proxy.

**No values differ.** The inner loop declines kube-proxy when it creates the cluster, and does not compensate for it later. So Cilium runs the committed `kubeProxyReplacement` setting in every tier. A local override of a Cilium value is a defect. It makes the datapath under a local test differ from the datapath under the deployed workload.

The identity stack is in the floor on purpose. Kratos and Oathkeeper are cheap. Their behaviour **is** the contract that every service consumes: cookies, CSRF, session expiry, AAL, and `401` and `403` responses.

A service reached through this edge gets real Oathkeeper identity headers. A service called with curl directly on `:8080` gets forged ones. A backend engineer who wants only Postgres still pays for the edge. This ADR accepts that trade in advance.

**Everything else is opt-in. The service that needs a component declares it** in its own `.mise.toml`:

| Family | Declares | Satisfied by | Guard |
| --- | --- | --- | --- |
| `dep:*` | infrastructure that the service reads: Postgres, Temporal, OpenFGA | a label slice of `infra/local/deps.yaml` | Ready or not |
| `svc:*` | other services that it calls over HTTP | the callee, deployed and forwarded to its registered port | **answered or not** |

What runs is **the base plus the declared dependencies of every running service**. No table needs maintenance, because a service knows its own dependencies, and a named profile never can.

`svc:*` exists because a microservices repo cannot leave out the second family. The orders checkout saga calls catalog and payment, per [ADR-0302](0302-temporal.md). Without them, a worker starts cleanly and fails on the first checkout. That failure comes later than a missing database, so its cause is harder to find.

**The default is to deploy the callee. The override is to run it natively.** The usual case is work on the caller, and the callees then need no attention. `svc:catalog` checks that *the port answers*, not that a deployment exists. So a native catalog also satisfies the graph. The cross-service debugging case is the single-service case with more callees started by hand.

On purpose, `cluster:add` does **not** address dependency components. `postgres` is both a platform chart and a `deps.yaml` slice. As names that users type, components would be ambiguous. They stay internal to the graph. So `cluster:add` resolves names over two disjoint namespaces: services and platform charts. A name in both is a repo bug, not a user error.

### mise supplies the graph

A service's nested `.mise.toml` can depend on tasks from the root config. mise removes duplicate diamond dependencies, so a shared `cluster:up` runs once. Independent dependencies run in parallel. These are Garden's graph-execution semantics, in a tool that is already pinned.

```toml
# root .mise.toml
[tasks."dep:temporal"]
depends = ["cluster:up"]
run = "bash scripts/dep-apply.sh temporal"

# services/orders/.mise.toml
[tasks.worker]
depends = ["env", "dep:postgres", "dep:temporal", "svc:catalog", "svc:payment"]
run = "go run ./cmd/worker"
```

| Layer | Owns |
| --- | --- |
| mise | the dependency graph and the task vocabulary. Declarations only, with no logic in `.mise.toml` |
| bash | one small idempotent installer for each component, `dep-apply.sh`, or each sibling, `svc-apply.sh` |
| Helm | the component units: the same charts in every tier |
| Argo CD | `cluster:up full` only |

**One property is not free.** Garden checks status and skips work that is already done. mise does not. Its `sources` and `outputs` staleness check uses files, and the readiness of Temporal is not a file. Without a guard, every `mise run server` pays again for a full apply and a rollout wait.

So the guard is **central**, in `dep-apply.sh` and `svc-apply.sh`, and not written by hand for each component. One shared readiness check of about twenty lines covers everything. A component that forgot its own guard would slow the inner loop with no warning. For this reason, the guard does not live in the components.

### The service contract

Every service takes part in the same way. `lint:service-contract` checks this.

| A service must | Because |
| --- | --- |
| Live at `services/<name>/`, with the same name everywhere | `cluster:add` resolves names over two disjoint namespaces |
| Expose `server`, `test`, `lint`, and `build`, plus `worker`, `migrate`, and `generate` when it has them | CI and `cluster:add` call them by name, per [ADR-0101](0101-monorepo.md) |
| Register a local port in `scripts/lib/ports.sh`, and set the same `PORT` in its `.mise.toml` | It can then run natively beside other services, and the `<SVC>_URL` of each caller has a working default |
| Declare `dep:*` for the infrastructure it reads | The graph brings up exactly that, and the deploy path reads the same list |
| Declare `svc:*` for every service it calls over HTTP | Otherwise it starts cleanly and fails on the first cross-service call |
| Ship a `.env.example` that covers every variable it reads | `mise run server` seeds `.env` from it. A variable not listed takes a default with no warning |
| Ship a values file for each environment under `infra/gitops/services/<env>/values/`, or declare `# platform/not-deployed: <env>` | The ApplicationSet generates one Argo Application for each values file. Without a file, the service is absent from that environment, and nothing reports it |
| Ship a `Dockerfile` and a `README.md` | CI and `cluster:add` build the image by the same path |
| Bind `httpmw.ListenAddr()` | This is `:8080` in the cluster. The chart's containerPort, the IngressRoutes, and the NetworkPolicies all expect it |

**The values-file rule needs an explicit opt-out, because a git-directory generator does not treat a missing file as an error.** A missing file produces no Application and no diagnostic. The failure it guards against is silent and crosses services. In every environment, `infra/auth/oathkeeper/values.yaml` points the `remote_json` authorizer at `authz-server` by service DNS. So if `authz` has no values file for an environment, every gated dashboard request there resolves to a Service that does not exist.

The set of values files is this platform's deployment surface. It is stated, not inferred.

**The check cannot verify that the declarations are true.** A reviewer checks that a service with `dep:temporal` uses Temporal at all. A reviewer also checks that a new HTTP call has its `svc:*` edge. A cross-service call without its edge is the most likely regression of the local loop.

### GitOps locally

Argo CD reconciles committed git state, so it is **not** the engine of the inner loop.

The **full tier does run Argo CD**. A local bootstrap in `infra/gitops/local-bootstrap/` applies the same app-of-apps that production uses and syncs committed `master`. So the tier exercises sync order, app discovery, and secret materialisation as production does. The CNI arrives in the machine config. So Argo CD itself is the one component installed imperatively before the root app.

Three escape hatches cover uncommitted infra:

| Change | Path |
| --- | --- |
| Chart or values | `cluster:add -- <chart>` pauses Argo auto-sync on that one app and runs `helm upgrade` from the working tree |
| GitOps wiring: sync waves, ApplicationSets, app definitions | push a branch and point the local root app's `targetRevision` at it. This exercises the real delivery path |
| Machine config, CNI, or CRD | `cluster:down -- full` plus a fresh `cluster:up -- full`. A machine-config change reaches a deployed node in the same way. A CNI swap on a live cluster interrupts networking for a short time. This comes from the component, not from a gap in the tooling |

`cluster:remove` reverses `cluster:add` **and turns Argo auto-sync back on**, which the add path paused.

### The mock serves data. It never serves identity

**The mock has no authentication or authorization duty.** It issues no `401`, knows nothing of sessions, and ignores every credential it receives.

Nothing there needs a mock. Authentication is enforced outside OpenAPI: Oathkeeper validates at the edge and injects identity headers. So no service spec declares a `securityScheme`. A contract mock takes all its behaviour from the spec, and the specs say that every operation is open. A mock that emits `401` responses needs auth behaviour written by hand in a second place.

The same reasoning covers authorization. In the real service, `GET /orders` returns the caller's orders, filtered by the identity header. A mock that returns three arbitrary orders is **equally useful** to build the orders table: its columns, empty state, pagination, loading skeleton, and error state. Correct ownership is a property of the real service's query.

### The mock's input is the committed projection

The mock gets `internal.json` and nothing else. By design, this file is the frontend's edge surface: merged, with `servers: /api`, and checked for drift.

**A glob over `services/*/openapi.yaml` is not an acceptable replacement.** It captures `services/authz/`, a service with only `cluster` audience whose `servers` is `/`. It also captures `services/_template/`, which is scaffolding. A merge of those with `servers: /api` publishes `/api/identities` and `/api/items`. These routes do not exist at the real edge and must not exist there. They would reverse the invariant that `lint:api-audience` enforces. The projection also removes the merge step, its tooling, and its collision handling.

### Fidelity comes from the contract, not from the tool

The mock runs **examples first**. It serves the committed `example` and `examples` values from the spec. Where none exist, it falls back to schema generation. Schema-generated responses are only a starting point. An array schema with no `minItems` can generate an empty list. An open object schema generates fields that the real API never returns.

The fix belongs in the contract. Examples in `services/<service>/openapi.yaml` make mock responses deterministic and reviewed. The same examples render in the Scalar developer portal. So one investment serves two consumers.

### UI work is the floor plus the mock

| Component | State on `cluster:up` | Why |
| --- | --- | --- |
| Cilium | real | the CNI that every pod needs, and the NetworkPolicy enforcement point, per [ADR-0206](0206-cluster-networking.md) |
| Traefik | real | routes `/api` to the mock and `/` to the host `next dev`. It owns the same-origin contract |
| Kratos | real | login, logout, CSRF, cookie attributes, 7-day expiry, AAL |
| Oathkeeper | real | the `401` and `403` behaviour that the mock cannot invent |
| cert-manager | real | issues the wildcard TLS that the edge serves |
| Postgres, ephemeral | real | Kratos's store |
| **The mock** | added on top | replaces every application service on `/api` |
| Temporal, OpenFGA, CNPG, observability, Go services | absent unless declared | none of them renders a page |

The application's authentication path is **byte-identical to production**. It has no bypass, no development provider, and no `NODE_ENV` branch, because nothing needs one. For landing pages and logged-out surfaces, the mock runs alone with the auth stack down. That is a smaller part of the same tier, not a separate tier.

### Identity comes from a seeded real login

`cluster:up` seeds the committed deterministic test identities that [ADR-0601](0601-testing-strategy.md) defines. It does not invent a second, development-only identity. `scripts/auth-token.sh` logs in through the real native flow. Kratos sessions last **7 days**, so a human logs in about once a week. The bootstrap exists so that a fresh cluster is usable at once, and CI never types a password.

### The mock is local tooling only

It joins no tier in [`docs/operational-surface.md`](../operational-surface.md). That inventory covers software that the platform *operates*. The mock runs only on an engineer's machine, as k6 does. Its absence from the inventory is a decision.

The mock is forbidden wherever a test asserts correctness, per driver 4 of [ADR-0601](0601-testing-strategy.md). It never runs in `mise run test`, `ci:affected`, the e2e or visual suites, or any deployed environment. Its only consumer is a human who looks at a browser.

The mock's validating-proxy mode is not used either. The platform already answers that question twice. ogen generates the server from the spec. Every generated Go client validates responses against the spec. So a response that violates the spec fails the integration tests that drive it.

Both checks miss the edge's own error responses: `401`, `403`, and `429` from Traefik and Oathkeeper. No generated client receives them. E2e asserts this small, fixed set against the Problem envelope.

### Local domain and local-only manifests

`*.localtest.me` is real public DNS that resolves to `127.0.0.1` with no host configuration. `.local` is reserved for mDNS, per [RFC 6762](https://www.rfc-editor.org/rfc/rfc6762), and collides with Avahi and Bonjour. `*.localhost` and `*.test` mark a name as local more strongly. But they need a modern resolver or a hosts entry.

A short, listed set of manifests has no production equivalent:

| File | Why it is local-only |
| --- | --- |
| `infra/local/deps.yaml` | the dependency stand-ins of the inner loop. The full tier does not use it |
| `infra/local/edge-auth.yaml` | routes `/auth` and the landing page to a `next dev` on the host |
| `infra/local/mock.yaml` | the mock Deployment, Service, and `/api` IngressRoute, with the real edge middleware chain. Every run stamps the spec ConfigMap from the committed projection |
| The CoreDNS rewrite: the `coredns` stage in `scripts/lib/cluster.sh` | resolves the env host to Traefik from inside the cluster, because `127.0.0.1` in a pod is the pod's own loopback. It is a stage, not a manifest, because kind runs stock CoreDNS without a custom-record mechanism. The stage patches the Corefile and restarts CoreDNS |
| A local CA that issues the wildcard | the same cert-manager mechanism with a local ClusterIssuer. It is a **CA**, not a self-signed leaf. A leaf cannot be a trust anchor. That would force `NODE_TLS_REJECT_UNAUTHORIZED=0` and stop the frontend from running as its production image locally |

## Consequences

### Positive

- The inner loop stays fast. Above the floor, a service pays only for what it declares.
- The full tier validates the same software, delivered in the same way as in a deployed environment, before a change reaches one. This covers operators, sync order, chart wiring, the etcd datastore, and the datapath without kube-proxy.
- One provisioner serves both tiers, so a bring-up defect needs one fix. A second provisioner added seams: an image path for each tier, an unwedge tool for each tier, and a stand-in cleanup that matched resources by name across two clusters. None of these exist here.
- Both tiers run upstream Kubernetes on etcd. So the first tier already shows a behaviour of the Kubernetes version, a watch or compaction semantic, and a difference in Service routing.
- NetworkPolicy and the eBPF datapath are the same in every tier. So an undeclared caller and a wrong routing assumption both fail in the tier that introduced them.
- No Cilium value differs between tiers. So the local network posture is the deployed network posture, not a copy that only looks similar.
- The frontend has a tier that costs a fraction of `cluster:up full`, and the authentication path stays unchanged.
- No development-only code ships in `apps/frontend/`. A screen cannot work locally and return `403` in staging, because the local gates are the real gates.
- The mock cannot drift from the contract. Its only input is an artifact that is checked for drift.
- Examples serve the developer portal and the mock at the same time. The test-identity bootstrap has two consumers, so it runs daily, not only nightly.
- No new tool to learn. A contributor who knows bash, Helm, and mise can read the whole dev loop.

### Negative and Risks

- **We own the dependency resolution that Garden gives for free.** The graph is small, and the trade is fair. But it must not grow into a general-purpose engine by accident. The discipline: `.mise.toml` files stay declarations, and each bash script installs exactly one component. Shell logic that grows in task definitions rebuilds Garden badly.
- **`svc:*` owns the one long-lived process that the dev loop runs.** A mise task must return for the graph to continue, but the callee's port-forward must outlive the task. So `svc-apply.sh` detaches the port-forward and tracks it by pidfile, and `cluster:remove` reaps it. This is the least elegant part of the design and the price of not adopting a process manager. It is limited to one script. If it becomes a source of bugs, mirrord replaces it.
- **A service's callee list carries weight.** Nothing detects a missing `svc:*` edge. The call fails at runtime.
- **A third vendored Node tool.** Prism's image is third-party Node software that the repo runs but does not write. The Playwright runner and the Lowdefy console are the other two. Its scope is strict: a local-only container, no Node in any `.mise.toml`, no `package.json`, no lockfile, and never in an image built from our source.
- **The mock is stateless.** A read after a create does not show the write. A `WorkflowHandle`'s `result_url` polls nothing. This is the true limit of the tier.
- **Examples need maintenance.** `response-example-required` enforces an example on every `2xx` response. Nothing checks that the example is still true after a schema change. Minimal examples, reviewed as part of the contract diff, reduce this risk. A wrong example is a wrong contract, visible in the same PR.
- **The floor is not free.** Cilium, Traefik, cert-manager, Kratos, Oathkeeper, and Postgres must be up before any service runs. That cost removes every development-only auth branch.
- **No local tier exercises the machine config.** A deployed environment is the first to apply the mechanism that [ADR-0206](0206-cluster-networking.md) uses to deliver the CNI and disable kube-proxy. A defect in it appears there. This is a known cost of the decision. A local Talos tier validated a container-profile config that no deployed environment applies. So the trade gives up a rehearsal of the mechanism and removes the operating cost measured above. A change to `infra/talos/patches/` is reviewed against a deployed environment, never against a laptop.
- **The full tier costs laptop RAM and disk.** Its shape is one node that runs the whole platform. kind does not cap its node container, so the tier takes what the platform needs and does not crash against a limit. The failure mode is pressure on the host, not a pod evicted from a node that had room on paper. Disk fails first. The node's image store holds every platform image. A laptop that is almost full gets a `disk-pressure` taint, which evicts the platform that it started. Declarations for each service exist so that daily work runs only its slice on the smaller tier.
- **One node is not a quorum.** The inner loop runs single-member etcd. Leader election, quorum loss, and anything else that needs three members is a question for the full tier.
- **The full tier's own limit is the node.** A container-provisioned node does not exercise the distribution, the host kernel, system extensions, the disk layout, the installer, or the upgrade path. So a change to those is validated where those layers are real.
- **Two mocking mechanisms exist:** MSW at the test layer, and Prism at the dev-loop layer. An explicit layer boundary limits this, and e2e permits neither.
- **Evaluate this decision again at the ceiling of about 20 services**, or when the graph outgrows a declaration plus one shared installer. Both signals are visible, not gradual.

## Rules

- Local development runs two tiers: the `cluster:up` inner loop and `cluster:up full`. There are no named profiles.
- Both local tiers run on kind, as two clusters with two contexts. The bring-up of one tier never changes the other, and no local tier shares a cluster with another.
- `scripts/cluster.sh` is the only script that names a tier, and it takes the tier as an argument. Every other script resolves the tier from the running cluster. A tier hardcoded as a consumer's default is a defect.
- Both local tiers are a single node. They differ in which workloads run, never in how the cluster is built. A difference introduced between them is a defect.
- No local tier exercises the datapath between nodes. Service routing between nodes and the WireGuard encryption that [ADR-0206](0206-cluster-networking.md) enables are first exercised in a deployed environment.
- Every local cluster is created without a CNI and without kube-proxy. A distribution that bundles either is not used.
- No local tier applies a machine config. The delivery mechanism that [ADR-0206](0206-cluster-networking.md) decides is exercised in a deployed environment, and `infra/talos/` carries no local variant.
- Cilium is in the floor of both tiers. It comes from the committed chart, with WireGuard on and its eBPF dataplane in place of kube-proxy, and is installed imperatively before Argo CD exists. No Cilium value differs between tiers.
- Images reach a local tier through the local registry or through `kind load`. The registry runs the same implementation as a deployed environment, per [ADR-0105](0105-image-registry.md). So the local image path is not a second product.
- What runs locally is the floor plus the declared dependencies of the running services. A service declares `dep:*` for infrastructure and `svc:*` for every service it calls over HTTP. `(CI: lint:service-contract, lint:service-deps)`
- `.mise.toml` files carry declarations only. Component logic lives in one idempotent installer script for each component, and each script exits fast when its component is already ready.
- Every mise task has a command or a dependency. A task with neither passes and does nothing. `(CI: lint:tasks)`
- Every service registers a local port in `scripts/lib/ports.sh` and binds `httpmw.ListenAddr()`. `:8080` stays unassigned. `(CI: lint:ports)`
- Every service ships a values file for each environment, or declares `# platform/not-deployed: <env>`. Absence is never inferred. `(CI: lint:service-contract)`
- Argo CD is the engine for `cluster:up full` only. Uncommitted infra changes go through `cluster:add` or a branch `targetRevision`, never through direct edits to cluster state.
- API mocking exists only for the UI development loop. The mock appears in no deployed environment, no chart, and no image built from our own source.
- The mock's only input is the committed `internal.json` projection. A glob over `services/*/openapi.yaml`, route files written by hand, and standalone fixture bodies are not used.
- The mock serves no authentication or authorization behaviour: no `401`, no session awareness, and no identity headers.
- The application contains no development-only authentication code. A session bypass, a fake session object, or a branch on the environment in the session path blocks review. A branch on the environment that grants nothing does not. `(CI: lint:auth-inline)`
- Authenticated local development uses the real Kratos with the committed test identity. Fake identity providers are not used for Kratos. They stay permitted for Hydra, which is a protocol boundary.
- The mock runs examples first. Schema generation is a fallback behind a flag, for an endpoint without an example.
- The mock is forbidden in `mise run test`, `ci:affected`, and the e2e and visual suites.
- The mock ships as a vendored container and adds no `package.json`, lockfile, or `node_modules`. `(CI: lint:node-scope)`
- The mock is local tooling and joins no tier in [`docs/operational-surface.md`](../operational-surface.md).
- Statelessness is the limit of the tier. Persistence, workflow progress, and authorization decisions are exercised against real services, never asserted against the mock.
