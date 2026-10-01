# Sovereign Platform Template

A reference architecture for **self-hosted product platforms**. It is a monorepo where every reusable decision is already made. Each decision is recorded in an [ADR](docs/adr), and a machine enforces it.

Fork it, generate from it, or read the ADRs and ignore the code. All three are valid uses.

**The stance, in three lines:**

- **The menu is omakase.** The stack is decided in advance. You start at `build features`, not at `pick tools`.
- **A paved road, with exits.** You can deviate, and the deviation is documented. It must be on purpose.
- **Machines enforce it.** Rules are admission policies, type checks, and drift checks. Review is the fallback, not the mechanism.

---

## Find your profile

This template ships one profile and documents three neighbours.

| Profile | You are here if | Style | Data | Deployables | Platform floor | What platform work looks like |
| --- | --- | --- | --- | --- | --- | --- |
| `modular-monolith` | No decomposition force applies. See the next section | Modular monolith | one database | 1 | whatever the provider runs for you | nobody's job. The provider operates it |
| `service-based` | Teams block each other on deploys, and a shared database is still acceptable | Service-based | services share a database | usually 3 to 8 | a few components, on managed foundations | part of a backend role |
| `microservices` | Services must change their data without coordination, so each service owns its data | Microservices | each service owns its data | often 15 or more | large, but still on managed foundations | a standing responsibility that a named person owns |
| **`sovereign`**, **this repo** | Self-hosting is *binding*, not preferred | Microservices | each service owns its data | often 15 or more | **everything, and it is fixed for any service count** | **a primary responsibility, and it never rests on one person** |

[ADR-0000](docs/adr/0000-platform-foundations.md) sets the positions. [`docs/operational-surface.md`](docs/operational-surface.md) is the component inventory of this repo, and it is the only place where components are counted.

> **These are not maturity levels.** For most systems, a modular monolith is a correct *final* state. Higher rows are more expensive answers to pressures that you may not have. Richards and Ford treat architecture styles as **risk profiles rated against characteristics**, not as a ladder.

**This repo implements `sovereign`.** The other three rows are positions, not presets to generate. A project at one of them does better with a smaller template. For `modular-monolith`, that is [nextjs-mvp-template](https://github.com/tabmadi/nextjs-mvp-template), with the same conventions at that scale.

---

## What forces decomposition

The service count is an **outcome**, not a target. Each force alone justifies a boundary. **If no force applies, build a modular monolith.**

| # | Force | Test |
| --- | --- | --- |
| 1 | Independent deploy cadence | Two parts must ship without a coordinated release |
| 2 | Number of teams | Teams block each other. This is Conway's law: it counts teams, not headcount and not features |
| 3 | Failure isolation | The failure of one part must not take another part down, as a *stated requirement* |
| 4 | Resource heterogeneity | Truly different scaling profiles: CPU, IO, or memory |
| 5 | Technology heterogeneity | A part must run on another runtime, such as ML in Python or chain code in Rust |
| 6 | Compliance boundary | Data residency or audit scope is cheaper to enforce by structure than by policy |

---

## The three characteristics

The product category, such as `fintech`, `B2B SaaS`, or `marketplace`, decides almost nothing. Two products in one category often sit at opposite ends of every axis. These three axes decide almost everything:

| Axis | Question | Range | This repo |
| --- | --- | --- | --- |
| **A: Decomposition pressure** | Must parts ship, scale, or fail independently | from monolith to many services | high |
| **B: Operational sovereignty** | Who is permitted to run it | from managed, through hybrid, to self-hosted | **maximum** |
| **C: Correctness stakes** | What a wrong answer costs | from cosmetic, through transactional, to regulated | high |

**Axis B is the choice that makes this repo different.** Most reference architectures at this position on A and C assume managed services underneath. This one does not. That single decision creates more of the machinery here than A and C together.

---

## Need and capacity

> **Need decides what you build. Capacity decides what you can run. The gap is your risk.**

Team size is a **budget, not a design driver**. It tells you only whether you can operate what you have.

What `sovereign` costs to run:

- **An always-on platform floor of about two dozen components**: gateway, GitOps, identity, authz, workflow, data, storage, observability, registry, forge, and outbound mail. [`docs/operational-surface.md`](docs/operational-surface.md) is the inventory.
- **Platform work as a primary responsibility, not a rotation.** A rotation optimises for the incident in front of it. The real cost of this floor is the upgrades and drills that nothing forces you to do this week. This is the most common way a self-hosted platform decays.
- **No Core component whose only competent operator is one person.** The floor stays operable through a departure and an absence at the same time.

**This repo states no headcount, and you should not infer one.** The answer depends on your coverage hours, your operational skill, and your tolerance for detection latency. `docs/operational-surface.md` has the recurring obligation and the failure-response requirement of every component. Sum that against your own facts, and you get your number, not ours.

**If the number is higher than what you have**, read [`docs/adoption-path.md`](docs/adoption-path.md). It is the ranked list of what to give up, and in what order.

**Building it with an LLM changes the authoring cost and nothing else.** Generating a service, a chart, or a migration is now cheap. This moves the bottleneck, and it does not remove it:

- The operational surface does not change.
- Coherent review gets harder as the volume of generated change grows. A reviewer must know that a generated change agrees with the twenty decisions it touches.

The ADRs and the Rules sections exist partly for this reason. They are the constraint that an agent must follow when nobody has time to work out the reasons again.

**Fewer services make the platform relatively heavier.** The floor is fixed. So with a few services, the ratio of application work to platform work is about 1:1, and the case for austerity is *stronger*.

---

## What you do not need on day one

Not everything here ships at once. Capabilities are deferred behind a **hard trigger**: an *observable* condition, never `when we grow`. A deferral without a trigger is `temporary`, and [ADR-0000](docs/adr/0000-platform-foundations.md) forbids that.

A deferral is safe only when a **seam** exists. A seam is a pre-built slot where the capability fits in without restructuring:

- ✅ **The seam exists.** Adoption is additive. Deferral costs nothing but the wait.
- ⚠️ **No full seam.** Adoption is structural. This is a *bet*, not a deferral. Adopt earlier, or accept a rewrite later.

| Capability | Trigger | Seam | Tier |
| --- | --- | --- | --- |
| Ory Hydra, the OAuth2 server | A public API or an external machine client exists | ✅ behind a flag. The internal request shape does not change | Opt-in |
| Mimir, for metrics at scale | Prometheus needs multi-tenancy, HA, or long retention | ✅ the same query API. Dashboards and alerts move unchanged | Scale |
| Tail sampling | Trace volume makes head sampling lose data | ✅ services only emit to `localhost:4317` | Scale |
| Loki and Tempo microservices mode | The ingest volume of a single backend needs it | ✅ the same storage and the same API | Scale |
| Rust or Python service | A *measured* shortfall of Go, or a need for an ecosystem native to that runtime | ✅ contracts are HTTP with OpenAPI, not shared code | Opt-in |
| Storybook | A second frontend app, or a design-system maintainer | ⚠️ | Opt-in |
| Service mesh | A measured need that Cilium with WireGuard cannot meet | ⚠️ partial. mTLS is covered, and policy for each request is not | Scale |
| Escalation and paging | An on-call rota exists | ⚠️ **no credible self-hosted escalation layer exists**. Alertmanager does the routing, and a hosted service does the paging, per [0502](docs/adr/0502-alerting-and-on-call.md) | Opt-in |

A deferral on purpose, with the trigger written down, is the **last responsible moment** applied to architecture. It is not the same as an open decision.

---

## When not to use this

- **No decomposition force applies.** Use `modular-monolith`. This is the common case.
- **Platform work would be a rotation, not someone's primary job.** The floor is heavier than its component count suggests. Read [`docs/adoption-path.md`](docs/adoption-path.md) before you adopt. Move down axis B on purpose. Do not find the gap during an incident.
- **Managed services are acceptable to you.** Much of this repo solves a problem that you do not have.
- **Correctness stakes are low.** The typing, contract, and policy discipline here is priced for systems that handle money. For you, it will feel like friction.

---

## Lower on the sovereignty axis

Axis B is an axis, not a test of virtue. **A smaller team should sit lower on it, on purpose.** That is a better answer than to adopt the self-hosted floor and hope.

Axis B is also the axis that this template is **least coupled to**. A move down it swaps *operators*, not architecture. A managed swap does not change:

- the ADRs
- the OpenAPI contracts and codegen
- the service template
- the Helm and GitOps trees
- policy-as-admission
- the repo layout
- the release flow
- the local dev loop

[`docs/adoption-path.md`](docs/adoption-path.md) is the canonical ranked order of swaps. It has three bands:

- deferrals, which cost only the wait
- managed swaps, which cost sovereignty
- capability concessions, which are bets

Each row has a restore trigger and a cost to reverse. The document also marks the line past which a project runs a different platform.

**A hybrid position is legitimate and common.** Self-host the orchestrator and the stateless platform. Use managed Postgres, object storage, email, and paging. This removes most of the pager load. It keeps the parts that were usually the reason for self-hosting.

---

## How tools are chosen

Ten principles decide every entry in the stack table below. A principle must pass one test to be on this list:

> **A principle earns its place only if it has rejected something we wanted.**

A principle that cannot name a casualty is a statement of virtue, not a criterion.

Each principle is **anchored** to an external standard. Where no standard applies, it is marked **local**. A borrowed criterion survives a new debate, and a house rule gets argued again every year. [ADR-0000](docs/adr/0000-platform-foundations.md) has the full reasons.

**Selection: how a tool gets in:**

| # | Principle | Anchored to | It rejected |
| --- | --- | --- | --- |
| 1 | Configuration lives in the repository, not in the component | [OpenGitOps](https://opengitops.dev/) principles 1 and 2, extended one level out | SigNoz, OpenObserve, Coroot, Zitadel |
| 2 | The always-on floor is the budget, measured in concerns | [Team Topologies](https://teamtopologies.com/key-concepts-content/what-is-a-thinnest-viable-platform-tvp), with cognitive load as the unit, applied to operators and not to users | GitLab CE, Coroot, a second CI system |
| 3 | Operational sovereignty: run it yourself | axis B, above | every managed service |
| 4 | Spend novelty by exit cost, not by taste | [Innovation tokens](https://mcfunley.com/choose-boring-technology) | Garage, Encore |
| 5 | One primitive per concern, with no parallel mechanisms for one problem | **local**. It follows from principle 2 | Woodpecker, Tekton, Argo Workflows |
| 6 | Two languages, and no ambient runtime | [12-Factor II](https://12factor.net/dependencies): *never relies on implicit existence of system-wide packages*. The two-language cap itself is **local** | Semgrep and sqlfluff, which both need Python |
| 7 | No adoption without a recorded comparison | **local**. It is principle 4 applied to the record, and [0002](docs/adr/0002-tool-adoption.md) sets the depth | *the process gate for all of the above* |

**Construction: how the system is built once a tool is in:**

| # | Principle | Anchored to | It rejected |
| --- | --- | --- | --- |
| 8 | Local-prod parity at the manifest and API layer | [12-Factor X](https://12factor.net/dev-prod-parity): *resists the urge to use different backing services between development and production* | Docker Compose, which is a second definition of the system |
| 9 | Generated code is committed and drift-checked in CI | **local**. It is principle 1 applied to generated artifacts | codegen at runtime or at deploy |
| 10 | Service boundaries are HTTP with OpenAPI. Never shared code, and never a shared database | Fowler, [*IntegrationDatabase*](https://martinfowler.com/bliki/IntegrationDatabase.html): *integration databases should be avoided* | shared libraries and shared schemas as coupling |

Read principle 4 twice, because people often misread it as conservatism. **Be adventurous where abandonment costs days**: CI, query layers, registries, and policy engines. **Be conservative where it costs months and customer data**: storage, databases, and the message bus. Talos, Kyverno, and zot all sit on the cheap-exit side of that line. SeaweedFS and CNPG sit on the expensive side, and they were chosen with that in mind.

---

## Stack at a glance

Every row is a decision recorded in an ADR, with a comparison against the alternatives and the trigger that would open it again. A tool with no recorded comparison is an assumption, not a decision.

Every tool here also has a row in [`docs/tool-register.md`](docs/tool-register.md). The row has its exit-cost tier, licence, governing body, and the alternatives it was recorded against.

| Concern | Current decision | ADR |
| --- | --- | --- |
| Backend language | Go | [0100](docs/adr/0100-language-and-runtime.md) |
| Frontend | Next.js and TypeScript on Bun, one app with route groups | [0100](docs/adr/0100-language-and-runtime.md), [0400](docs/adr/0400-frontend.md) |
| Design system | `shadcn/ui`, vendored as source, on Tailwind, with the brand in one token file | [0400](docs/adr/0400-frontend.md), [0701](docs/adr/0701-product-design-and-discovery.md) |
| Task runner | `mise` | [0101](docs/adr/0101-monorepo.md) |
| Machines | Talos Linux, configured by machine config | [0200](docs/adr/0200-cluster-topology.md) |
| Cloud resources | Terraform, for each project. Skipped where the infrastructure is provided | [0200](docs/adr/0200-cluster-topology.md) |
| Cluster | upstream Kubernetes on etcd in every tier, on kind for both local tiers | [0200](docs/adr/0200-cluster-topology.md), [0600](docs/adr/0600-local-development-loop.md) |
| Deploy | Argo CD, the only mechanism. One shared Helm chart, with values for each environment | [0201](docs/adr/0201-gitops.md) |
| Network and policy | Cilium with Hubble, WireGuard, default-deny | [0206](docs/adr/0206-cluster-networking.md) |
| Policy enforcement | Kyverno at admission, PSA `restricted`, CiliumNetworkPolicy, CI lints | [0203](docs/adr/0203-policy-enforcement.md) |
| Resource governance | LimitRange, ResourceQuota, PriorityClass, PDB | [0204](docs/adr/0204-resource-management.md) |
| Edge | Traefik, Ory Oathkeeper, and cert-manager | [0305](docs/adr/0305-edge-auth-and-traffic-policy.md) |
| Identity and authz | Ory Kratos and OpenFGA. Hydra when a public API exists | [0304](docs/adr/0304-identity-and-authorization.md) |
| Trust tiers | product apex, and `*.ops.<host>` for operator tooling | [0306](docs/adr/0306-trust-tiers-and-urls.md) |
| Secrets | SOPS and age, decrypted in the cluster by an operator | [0202](docs/adr/0202-secrets.md) |
| Database | PostgreSQL on CNPG. sqlc, dbmate, sqruff | [0300](docs/adr/0300-data.md) |
| Object storage | SeaweedFS everywhere. In prod it runs outside the cluster with Object Lock | [0207](docs/adr/0207-cluster-storage.md), [0205](docs/adr/0205-environment-parity.md) |
| Workflows | self-hosted Temporal, versioned workers | [0302](docs/adr/0302-temporal.md) |
| API contract | hand-written OpenAPI 3.1. ogen, openapi-typescript, vacuum, oasdiff | [0303](docs/adr/0303-api-contracts-and-lifecycle.md) |
| API mocking | Prism, vendored, from the committed projection | [0600](docs/adr/0600-local-development-loop.md) |
| Observability | OpenTelemetry into Grafana, Loki, Tempo, Prometheus, Pyroscope | [0500](docs/adr/0500-observability.md) |
| Operator UIs | Grafana funnel, Hubble UI, Headlamp | [0501](docs/adr/0501-operator-uis-and-dashboards.md) |
| Alerting | Prometheus rules and Alertmanager. Escalation goes to a hosted service | [0502](docs/adr/0502-alerting-and-on-call.md) |
| Error tracking | OTel exceptions with a computed `error.fingerprint`. No separate product | [0503](docs/adr/0503-error-tracking.md) |
| Source control and CI | Forgejo and Forgejo Actions, entered through `mise run ci:*`. A provider-hosted forge is the bootstrap path | [0102](docs/adr/0102-source-control-and-ci.md) |
| Supply chain | cosign with a key pair held in SOPS, syft SBOM, SLSA provenance, Trivy as a merge gate | [0104](docs/adr/0104-supply-chain-security.md) |
| Registry | zot, one instance for each environment, backed by object storage | [0105](docs/adr/0105-image-registry.md) |
| Testing | Playwright, k6, `go test`, `bun test` | [0601](docs/adr/0601-testing-strategy.md) |
| Internal admin | Lowdefy over the service APIs. pgweb, read-only | [0401](docs/adr/0401-internal-admin.md) |
| Analytics | Faro events into a first-party service | [0700](docs/adr/0700-analytics.md) |
| Dependency updates | Renovate, grouped, with digest pinning | [0106](docs/adr/0106-dependency-updates.md) |
| Template propagation | Copier, which tracks upstream with a 3-way merge | [0106](docs/adr/0106-dependency-updates.md) |

---

## Getting started

```sh
# One-time setup
curl https://mise.run | sh
mise install                    # pinned toolchain from .mise.toml
mise run setup                  # git hooks
mise run secrets:age            # generate your age key, per ADR-0202

# Local cluster: the same charts as production, on two tiers
mise run cluster:up             # the floor: edge, identity, Postgres, mocks
mise run cluster:up -- full     # the whole platform, driven by ArgoCD, with observability

# Inner loop on one service: a native process, no image build
cd services/catalog
mise run server
```

The full walkthrough is [`docs/dev-loop.md`](docs/dev-loop.md).

---

## Layout

```text
services/<name>/     Go service: OpenAPI contract, server, worker, sqlc, migrations
apps/frontend/       one Next.js app, with the route groups landing, panel, analytics, and devportal
apps/admin/          Lowdefy YAML for internal admin
libs/go/<name>/      shared Go packages: observability, middleware, errors
libs/{go,ts}/sdks/   generated OpenAPI clients, committed and drift-checked in CI
infra/helm/          the shared service chart, and the platform component charts
infra/gitops/        Argo CD Applications and the values for each environment
infra/talos/         machine configs
infra/terraform/     provisioning, where the project owns its infrastructure
docs/adr/            the decisions, and the reasons for them
```

These conventions are not negotiable for each service. [0101](docs/adr/0101-monorepo.md), [0300](docs/adr/0300-data.md), and [0303](docs/adr/0303-api-contracts-and-lifecycle.md) depend on them. A deviation needs a new ADR.

---

## Worked example: the shop

A small example that uses every mechanism once. It is not a realistic product.

| Service | Demonstrates |
| --- | --- |
| `orgs` | Kratos identity, B2B multi-tenancy, and OpenFGA ReBAC |
| `catalog` | Plain CRUD: contract, handler, sqlc, migrations, observability |
| `orders` | A Temporal checkout saga that calls `catalog` and `payment` over HTTP |
| `payment` | A child workflow with idempotency and compensation |

Build real services from `services/_template/`.

---

## How decisions are recorded

- **[ADRs](docs/adr)**: every load-bearing decision, with a comparison against the alternatives and the trigger that would open it again. Start at [ADR-0000](docs/adr/0000-platform-foundations.md). [`docs/adr/README.md`](docs/adr/README.md) has the block map and the full index.
- **[ADR-0001](docs/adr/0001-documentation-and-output-conventions.md)**: the rules for these documents. It covers density, banned constructs, section order, and the same rules for code comments.
- **Rules sections**: each ADR ends with flat, greppable normative statements. They are written so that humans and LLMs apply them the same way.
- **Fitness functions**: machines enforce rules wherever possible, through admission control, type checking, drift-checked codegen, and static analysis for architectural invariants. A rule that a machine enforces names its mechanism, per [ADR-0001](docs/adr/0001-documentation-and-output-conventions.md).

---

## Prior art

This template borrows its framing:

- **Richards and Ford, *Fundamentals of Software Architecture***: architecture styles rated against characteristics as risk profiles. This is the source of the profile table above, and of the term *service-based architecture*.
- **Team Topologies**: cognitive load as the sizing unit. Here it applies to the people who run the platform, not to the people who build on it.
- **DORA and *Accelerate***: capability models instead of maturity ladders.
- **Ford, Parsons, and Kua, *Building Evolutionary Architectures***: fitness functions.
- **Poppendieck, *Lean Software Development***: the last responsible moment.
- **Feathers, *Working Effectively with Legacy Code***: seams.
- **Fowler, *MonolithFirst* and *MicroservicePremium***: the prerequisite bar for decomposition.
- **12-Factor**, **Choose Boring Technology**, and the **CNCF Platforms White Paper**.

### Where the published platform handbooks are stronger

This repo is closest to the genre of the internal engineering handbook. Examples:

- the [paved road](https://netflixtechblog.com/full-cycle-developers-at-netflix-a08c31f83249) of Netflix
- the account by [Monzo](https://monzo.com/blog/2016/09/19/building-a-modern-bank-backend) of running a bank on a large set of services
- the writing by [Shopify](https://shopify.engineering/deconstructing-monolith-designing-software-maximizes-developer-productivity) on decomposition

The term *paved road* at the top of this file comes from Netflix.

**They are better than this repo at the one thing a template cannot fake: operational narrative.** Each one is written by a team about a platform it has run at scale for years. So real events back the reasons: outages that happened, migrations that went badly, and decisions that were reversed. That evidence is the most valuable part of the genre, and none of it is here.

This repo offers the falsifiable half instead. Every decision states what it was compared against, what would open it again, and how it is enforced. [`docs/reference/`](docs/reference/) combines the decisions into the numbers they add up to, and this includes the unflattering numbers. Read the handbooks for what happens when a platform meets reality. Read this repo for the record of what was chosen and why. You can argue with it before you own the consequences.

---

## Using this repo

- **It is a template, not a product.** Fork it and own your copy. There is no support channel and no compatibility promise.
- **Generated projects** track upstream through the 3-way merge of Copier.
- **Disagreement is expected.** The ADRs record the reasons so that you can overturn a decision on purpose, not by accident. If a comparison table is wrong, that is the most useful issue you can open.
