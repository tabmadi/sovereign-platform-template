# ADR-0000: Platform Foundations

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0001](0001-documentation-and-output-conventions.md), [ADR-0002](0002-tool-adoption.md)
- **Decides:** This platform sits at decomposition-high, sovereignty-maximal, and stakes-high, and ten anchored principles with a recorded comparison admit every tool.

## Purpose

Every other ADR references this ADR. It fixes five things:

1. **The thesis**: the platform's position on three axes, and what follows from it.
2. **The principles** that every later decision must honour. Each is anchored to an external standard or marked local.
3. **The ADR process**: how decisions are made, recorded, and changed.
4. **Prior art**: the sources that the framing of this document rests on.
5. **Vocabulary** that the rest of the documents use consistently.

This ADR chooses no technology. The other ADRs choose technology.

## Thesis

This is a **self-hosted product platform**. Its parts ship, scale, and fail independently. The owning organisation controls every piece of its infrastructure. A wrong answer costs money. Every reusable choice is decided in advance, so work starts at `build features`, not at `pick stacks`.

We state no target service count. A service count is an **outcome**, not a target. A number encodes a set of pressures, and once the number is written down, it hides them. The sections below name the pressures directly.

### The three axes

Three mostly independent questions force the architecture. The position on each question decides the choices below. The product category, such as `fintech`, `B2B SaaS`, or `marketplace`, decides almost nothing. Two products in the same category often sit at opposite ends of every axis.

| Axis | The question | Range, from low to high |
| --- | --- | --- |
| **A: Decomposition pressure** | Whether the parts must ship, scale, or fail *independently* | monolith, modular monolith, few services, many services |
| **B: Operational sovereignty** | Who is permitted to run it | managed cloud, hybrid, fully self-hosted |
| **C: Correctness stakes** | What a wrong answer costs | cosmetic, transactional, financial or regulated |

**Our position: A high, B maximal, C high.** Axis B is the choice that sets this platform apart. Most platforms at this position on A and C assume managed services underneath. This one does not. That single decision creates more of the machinery in this repo than A and C together.

Later ADRs cite this position and do not restate it. It changes here, in one line, and the change re-opens every ADR that rests on it.

**Positions on these axes are not maturity levels.** A monolith is a correct *terminal* state for most systems, not a stop on the way to something else. A higher position is not better. It is a more expensive answer to a pressure that a system may not have. This repo uses levels in one place: the CNCF project tiers in principle 4. They are *recorded evidence about a dependency*, never a target for ourselves.

This follows Richards and Ford, who treat architecture styles as **risk profiles rated against characteristics**. It refuses the numbered-ladder genre of CMMI and the maturity models after it. DORA and *Accelerate* refuse that genre on the same grounds: a ladder implies that every rung leads to the next one, and these positions do not.

**The closest workable alternative is this position with axis B lower.** Several ADRs here answer questions that a platform at that position would not face.

### Axis A: what forces decomposition

Service count is derived, not chosen. Each force below justifies a boundary on its own.

| # | Force | The test |
| --- | --- | --- |
| 1 | Independent deploy cadence | Two parts must ship without a coordinated release |
| 2 | Number of teams | Teams block each other. Conway's law applies: teams count, not headcount and not features |
| 3 | Failure isolation | A *stated requirement* says that the failure of one part must not take another part down |
| 4 | Resource heterogeneity | The parts have truly different scaling profiles: CPU-bound, IO-bound, or memory-bound |
| 5 | Technology heterogeneity | A part must run on another runtime, per an [ADR-0100](0100-language-and-runtime.md) escape hatch |
| 6 | Compliance boundary | A structural boundary enforces data residency or audit scope at a lower cost than a policy does |

**A new service names the force that justifies it.** When none of the six forces applies, the part is not split. Nothing here requires a high service count. The same machinery serves three deployables, and several ADRs get cheaper at that size.

### Capacity is a separate question from need

The axes say what a system *should* be. They say nothing about whether a team can operate it.

> **Need decides what gets built. Capacity decides what can run. The gap between them is the risk.**

So team size is not a design driver. It is a budget. It does not tell a project to build thirty services. It tells the project what it can afford to operate. A platform target stated as a headcount mixes the two questions. The result is a thesis whose two halves never agree.

This position on axis B requires this capacity:

- **An always-on platform floor of a couple of dozen components.** The floor covers gateway, GitOps, identity, authz, workflow, data, storage, observability, registry, forge, and outbound mail. The floor is **fixed**: it does not shrink with fewer services. [`docs/operational-surface.md`](../operational-surface.md) is the inventory and the only place that counts the components.
- **Platform work as a primary responsibility, not a rotation.** A rotation optimises for the incident in front of it. The real cost of the floor is upgrades, drills, and rotations that nothing forces anyone to do this week. Delay of that work is the most common way a self-hosted platform decays.
- **No Core component with only one competent operator.** The floor must stay operable through a departure and an absence at the same time. This is a constraint on how knowledge is spread across people. Each project computes its own lower bound from it and from its coverage obligations.

**This ADR states no headcount, and a reader does not infer one.** The capacity that a project needs depends on facts that this repository does not know: coverage hours, existing operational skill, regulatory obligations, and tolerance for detection latency. This repository supplies the demand side. [`docs/operational-surface.md`](../operational-surface.md) carries the recurring obligation and the failure-response requirement of every Core component. A project sums that column against its own facts. That is how the number is derived and not borrowed.

One consequence follows. Platform cost is fixed and application cost is variable, so **the fewer services run, the heavier the platform is in proportion.** At many services, the ratio of application workloads to platform workloads is comfortable. At a handful of services, the two are about equal. So fewer services *strengthen* the case for a small, minimal platform. They do not relax it.

### Signals the floor has outgrown its capacity

Capacity is observed, not asserted. Any of these signals, if it continues, means that the gap between need and capacity is open:

- A Core component is more than one release behind its supported window, and nobody has scheduled the upgrade.
- The team skipped a restore drill or a break-glass rehearsal twice in a row.
- An alert fired, and nobody looked at it until the next working day. No ADR records this as a deliberate choice.
- The onboarding of a second competent operator for a Core component was postponed for a full quarter.
- Nobody would volunteer to debug a Core component during an incident.

The response is the one that principle 3 permits: reduce the floor per [`docs/adoption-path.md`](../adoption-path.md), move down axis B, or add capacity. The response is never to hold the floor and hope.

### Moving down axis B

Axis B is a real axis, not a test of virtue. Sovereignty below maximal is a legitimate position. An ADR of its own records that position, so the platform does not drift into it. It is the right answer for a team that cannot staff the platform. It is also better than holding the self-hosted floor and hoping.

**Axis B is the axis this platform is least coupled to.** A move down it changes the *operators*, not the architecture. A managed swap leaves these unchanged:

- the ADR set
- OpenAPI contracts and codegen
- the service template
- the Helm and GitOps trees
- policy-as-admission
- the repo layout
- release and versioning
- the local dev loop

The concessions are ranked by **capacity returned per unit of sovereignty conceded**, not by ease. [`docs/adoption-path.md`](../adoption-path.md) carries the ranked list and is the only place that orders it. In the same way, [`docs/operational-surface.md`](../operational-surface.md) is the only place that counts components. Outbound email is first and Kubernetes is last. That document states the reason in each row.

A **hybrid** position is legitimate and common. It self-hosts the orchestrator and the stateless platform. It takes managed Postgres, object storage, email, and paging. That removes most of the pager burden. It keeps the parts whose sovereignty was usually the reason for the choice. A reversal is a migration per component in either direction, so the position is a deliberate choice.

A system that has taken most of that list is no longer at A-high and B-maximal. The machinery here may then exceed its need.

**A concession of the operator is not the only way to get smaller, and the three ways are not interchangeable.** A capability can also be *deferred*: it is removed while its seam stays, so it returns as a chart. It can also be *conceded outright*, which is a bet paid for in application code. [`docs/adoption-path.md`](../adoption-path.md) separates the three ways and orders them. It also states where a reduction stops being a smaller instance of this platform and becomes a different platform.

### What follows from the thesis

- **Per-service cost compounds.** The service count multiplies any choice that adds RAM, CI time, or onboarding cost per service. At many services, this cost is a threat to the platform's survival. At few services, it is a matter of efficiency. It is never free.
- **One way to do things.** When the platform picks a tool or a pattern, it picks it for everyone. A per-service deviation requires a new ADR.

The principles below state the rest of what follows, because each one also decides tools.

## Principles

The principles below decide everything else in this repo. Every later ADR is checked against them. When a decision violates a principle, the principle wins, or *this document* changes the principle. A principle is never waived silently.

**The test for a place on this list:** a principle earns its place only if it has **rejected something we wanted**. A statement that cannot name a casualty is a virtue statement, not a criterion. It does not belong here.

Each principle is **anchored** to an external standard, or is marked **local** where no standard applies. The distinction is load-bearing. A borrowed criterion survives a new debate, and a house rule is debated again every year. A reader can tell which is which without asking.

### Selection: how a tool gets in

**1. Configuration lives in the repository, not in the component.** This covers dashboards, alert rules, identity schemas, OAuth2 clients, and authz models. Sometimes the database of the running system is the source of truth and the UI is the editor. Then the configuration is invisible to review and to Argo, and git cannot reproduce it.

- *Anchor:* [OpenGitOps](https://opengitops.dev/) principles 1, *Declarative*, and 2, *Versioned and Immutable*, v1.0.0, from the CNCF GitOps Working Group, **extended one level out**. OpenGitOps governs the system state that a GitOps agent reconciles. We apply the same requirement to the own configuration of each platform component. The extension is ours, and the principle is not.
- *Rejected:* SigNoz, OpenObserve, and Coroot, per [ADR-0501](0501-operator-uis-and-dashboards.md), and Zitadel, per [ADR-0304](0304-identity-and-authorization.md).
- *What it costs:* an observability stack of several components instead of one product, per [ADR-0500](0500-observability.md). This principle is expensive, and the platform applies it anyway. That is what makes it a principle.

**2. The always-on floor is the budget.** A simpler tool that covers 90% of the need beats a richer tool that needs a dedicated operator. [`docs/operational-surface.md`](../operational-surface.md) sorts components into the Core, Scale, and Opt-in tiers. A component joins Core only when no existing Core component covers its concern.

**The floor is measured in concerns, not in charts.** Two components that one person operates as one concern cost less than one component that nobody has debugged. So the tiering asks what a component obliges, not what it weighs. For the same reason, [`docs/operational-surface.md`](../operational-surface.md) carries a recurring obligation and a failure-response requirement per row, not a component count.

- *Anchor:* Team Topologies by Skelton and Pais, with **cognitive load as the sizing unit**. The direction is **local**. The [*thinnest viable platform*](https://teamtopologies.com/key-concepts-content/what-is-a-thinnest-viable-platform-tvp) bounds what a platform imposes on the teams that build on it. This principle bounds what the platform imposes on the people who run it. The unit is borrowed, and the constraint is ours. A platform can satisfy one and fail the other. The machinery paragraph below extends the same unit to the repository's own automation. It restates the **Rule of Parsimony** of the Unix philosophy, from Raymond's [*The Art of Unix Programming*](https://www.catb.org/esr/writings/taoup/html/), and McIlroy's *do one thing well*. **KISS** is its informal name.
- *Rejected:* GitLab CE, Coroot, and every second CI system.

**The budget covers the repository's own machinery.** Tasks, scripts, tests, and workflows cost what components cost. Someone has to understand, run, and repair them, and every generated project inherits them. A new mechanism names the failure class it owns or the mechanism it replaces. A mechanism that owns neither, or duplicates the work of another, is deleted. Additions and deletions land together, so the machinery budget falls as the platform grows. Review enforces this against [`docs/reference/build-path.md`](../reference/build-path.md), which records the failure class that each mechanism owns. A count ratchet never enforces it, because a ratchet deletes valuable checks to pay for new files. The binding definition of *simple* is local. It is the fewest independent mechanisms that cover the requirement:

- one owner per failure class
- no second mechanism for a concern
- a boot-and-verify path that a newcomer can run without help

*Simple* does not mean *few features*. The thesis and principles 3 and 4 set the capability count.

**3. Operational sovereignty: we run it ourselves.** This is not `self-host by default`. It is **axis B at maximum**, a hard constraint and not a preference with an exit. Every component runs on infrastructure that the owning organisation controls. Managed services are not adopted to reclaim operational budget.

- *Anchor:* axis B, above. The position is ours, and the axis is not.
- *Rejected:* every managed service, including where one costs less.

*Why there is no soft exit.* The tempting version of this principle moves components to managed services when the platform crowds out feature work. That reverses the causality that the thesis states: **capacity is the thing to change, not the constraint.**

Sometimes sovereignty binds for real: through data residency, regulatory control, cost predictability, or a refusal to depend on third-party operators. Then hiring resolves a capacity shortfall. Where sovereignty does not bind, the position on axis B is different. Its own ADR records that position, and it is not an escape hatch inside this ADR.

*The consequence.* Axis B at maximum removes a set of services that are otherwise invisible defaults:

- transactional email delivery, per [ADR-0307](0307-outbound-email.md)
- alert routing, per [ADR-0502](0502-alerting-and-on-call.md)
- source control and CI, per [ADR-0102](0102-source-control-and-ci.md)
- image registry, per [ADR-0105](0105-image-registry.md)
- object storage, per [ADR-0200](0200-cluster-topology.md)
- single sign-on across platform consoles, per [ADR-0304](0304-identity-and-authorization.md)

Each one is a first-class decision here, not a signup. Some carry costs that engineering effort cannot fully remove. Outbound email deliverability is the main example.

*Where axis B is not maximal.* Maximum is a position, not a claim of zero external dependencies. Five dependencies remain. Each one is recorded here, so nobody discovers it later.

| Dependency | Why it stays | Blast radius if it fails |
| --- | --- | --- |
| Compute and network provider | [ADR-0200](0200-cluster-topology.md) runs on plain instances, and someone provisions them. Sovereignty covers the *stack*, not the metal | total for that environment. The provider-neutral bootstrap mitigates it, and the bootstrap is what makes the substrate replaceable |
| Public ACME certificate authority | [ADR-0200](0200-cluster-topology.md) issues wildcards through cert-manager against a public CA | renewals fail, and the certificate lifetime is the buffer. A private CA is the exit, at the cost of distributing a trust anchor |
| DNS registrar and authoritative DNS | the domain is delegated, and DNS-01 needs a provider API. Outbound mail needs `PTR` delegation, per [ADR-0307](0307-outbound-email.md) | the edge is unreachable, issuance is blocked, and mail is undeliverable. This item is the hardest on the list to substitute. The registrar half cannot be self-hosted at all. The zone data is public, so sovereignty gains little here |
| Upstream package and image sources | Go modules, npm, Helm charts, and base images come from where their publishers put them | builds fail, and running workloads do not. Digest pins make what already runs immune, per [ADR-0104](0104-supply-chain-security.md) |
| Escalation and paging | no mature self-hosted layer exists, per [ADR-0502](0502-alerting-and-on-call.md) | deferred, not depended on. Nothing pages |

None of these is a soft exit from principle 3. Each one is a dependency at a layer that the platform does not claim to own, or a recorded concession with a named cost. A dependency that is not on this list and not decided in an ADR is a defect.

**4. Spend novelty by exit cost, not by taste.** Novelty is a fixed budget, and *where* it is spent matters as much as how much. The platform is adventurous where abandonment costs days: CI, observability query layers, registries, and policy engines. It is conservative where abandonment costs months and customer data: object storage, databases, and the message bus. `Actively maintained` is adequate assurance for the first class and inadequate for the second.

- *Anchor:* McKinley, [*Choose Boring Technology*](https://mcfunley.com/choose-boring-technology), which treats innovation tokens as a budget and not as a preference. The budget is *about three*, and this platform holds more young components than that.
- *Rejected:* Garage, which is too young for the data plane and single-vendor, and Encore, a data-plane-shaped lock-in that looks like a control-plane tool.
- *Accepted on the same rule:* Talos, Kyverno, zot, Prism, and Lowdefy, all young and all cheap to leave.
- Licence, governing body, and project maturity are **recorded** per tool, and they do **not** veto. Project maturity is the CNCF tier and the Thoughtworks Radar ring. Provenance is evidence about exit cost, not a rule of its own.

**The exit-cost rule makes the count affordable, not the count itself.** McKinley's budget is a proxy for recovery cost. This principle measures recovery cost directly. The proxy loses that measure when it counts a cheap exit and an expensive exit as equal tokens.

**Every young component carries a named fallback and an observable trigger in its owning ADR.** A novel choice with a recorded runner-up is a deferral. A novel choice without one is a bet.

| Component | Fallback | Trigger that promotes the fallback | Owning ADR |
| --- | --- | --- | --- |
| Cilium | Calico in its eBPF dataplane | a committed traffic-splitting delivery requirement. Traffic splitting is the one capability that Cilium lacks | [ADR-0206](0206-cluster-networking.md) |
| OpenFGA | SpiceDB, equal on capability | a governance change at the vendor. The `Checker` seam makes the swap a library, model, and chart change | [ADR-0304](0304-identity-and-authorization.md) |
| Lowdefy | the `(admin)` route group in the existing frontend | upstream releases stop for two quarters, or a runtime security advisory has no answer for one quarter | [ADR-0401](0401-internal-admin.md) |
| Prism | `muonsoft/openapi-mock` | the vendored container proves unacceptable. The swap is gated on proof of OpenAPI 3.1 support | [ADR-0600](0600-local-development-loop.md) |
| zot | CNCF Distribution | the registry conformance of zot regresses, or its object-storage backend stops tracking the OCI referrers API | [ADR-0105](0105-image-registry.md) |
| Talos | Debian stable converged by provisioning, with Kubernetes installed separately | the immutable-node model blocks a workload that the platform commits to run | [ADR-0200](0200-cluster-topology.md) |
| Kyverno | the CI lint layer, which already covers the same rule classes at a weaker layer | a cluster-wide admission outage traced to the webhook, twice | [ADR-0203](0203-policy-enforcement.md) |
| SeaweedFS | any S3-compatible store, reached through the same client | the S3 layer fails a checksum round-trip that the documented escapes do not close | [ADR-0207](0207-cluster-storage.md) |

**SeaweedFS is the only young component on the expensive-exit side.** So its row names a fallback that the unchanged client reaches, not a migration. The other component that holds customer data is PostgreSQL, which is the boring choice by any reading.

**5. One primitive per concern.** No parallel mechanisms exist for the same problem. There is one workflow engine, [Temporal](0302-temporal.md), one queue model, one deploy mechanism, and one manifest tree. Durable, multi-step, or cross-service async work is a Temporal workflow. A trivial best-effort job may use the sanctioned transactional-outbox path. That path serves the same concern with one lighter primitive, and it is not a competing engine.

- *Anchor:* **local**, because it follows from principle 2. Every parallel mechanism is a second runbook.
- *Rejected:* Woodpecker, Tekton, Argo Workflows, and Jenkins, all viable and all a second system beside the forge.

**The rule governs the repository's own machinery.** Two tasks, scripts, tests, or workflows that own one failure class are one mechanism under two names. The narrower or slower one is deleted. A mechanism that owns no failure class is deleted too.

**6. Two languages, and no ambient runtime.** The languages are Go and TypeScript. An escape hatch, such as Rust or Python, requires its own ADR with a measured need. No tool may assume a runtime that is not pinned in `.mise.toml`.

- *Anchor:* [12-Factor II](https://12factor.net/dependencies) for the ambient-runtime half: *A twelve-factor app never relies on implicit existence of system-wide packages*. The two-language cap itself is **local**.
- *Rejected:* Semgrep and sqlfluff, because both need ambient Python. So static analysis is `ast-grep` and SQL lint is `sqruff`.

**7. No adoption without a recorded comparison.** A tool with no recorded comparison against its alternatives is an assumption, not a decision.

- *Anchor:* **local**, because it is principle 4 applied to the record. Exit cost sets the depth. [ADR-0002](0002-tool-adoption.md) defines the three tiers and what each tier owes. A tool whose abandonment costs months and customer data owes a full table. Weeks owe a short table, and days owe a register line.
- *Rejected:* nothing directly. This is the process gate that makes principles 1 to 6 enforceable and not only aspirational.

### Construction: how the system is built once a tool is in

**8. Local-prod parity at the manifest and API layer.** Topology may differ. Charts, code, and commands do not.

- *Anchor:* [12-Factor X](https://12factor.net/dev-prod-parity): *resists the urge to use different backing services between development and production*.
- *Rejected:* Docker Compose for local development. It is a second definition of the system, and its drift from the real manifests fails at runtime, not at build time.

**9. Generated code is committed and drift-checked in CI.** Review catches drift, not the runtime.

- *Anchor:* **local**, because it is principle 1 applied to generated artifacts.
- *Rejected:* generation at build, deploy, or run time.

**10. Service boundaries are HTTP with OpenAPI.** Services compose through generated clients. They never use shared code, a shared database, or a direct workflow call into the namespace of another service.

- *Anchor:* Fowler, [*IntegrationDatabase*](https://martinfowler.com/bliki/IntegrationDatabase.html). A shared database *becomes a point of coupling between the applications that access it*. Fowler calls it *a deep coupling that significantly increases the risk involved in changing those applications*.
- *Rejected:* shared libraries and shared schemas as integration mechanisms.

## ADR process

### How an ADR must be written

Two rules look like principles, but they are not selection criteria. They govern *how a decision is recorded*, so they live here.

**Decisions are unambiguous.** When an ADR says `do X`, it never adds `or Y in some cases`. A **measurable trigger** expresses conditional behaviour, not a judgement call. An ADR that requires taste to apply has not finished deciding.

**No `temporary`.** Anything described as temporary becomes permanent. So a solution is either committed, or deferred behind a hard trigger. A deferral is complete only when three things are written down:

| Field | Requirement |
| --- | --- |
| **Trigger** | An *observable* condition. `When we grow` is not a trigger. `When Prometheus exceeds its retention window` is a trigger |
| **Seam** | Whether the slot for the thing already exists |
| **Cost if adopted late** | What the delay buys, and what it risks |

A deferral **with a seam** is additive: a later adoption changes configuration, not structure. A deferral **without a seam** is a *bet*, and the owning ADR labels it as one. The two look the same in a backlog and differ in a review.

[`docs/operational-surface.md`](../operational-surface.md) holds the Core, Scale, and Opt-in tiers that this applies to, and records what is deferred.

### When to write an ADR

An ADR is written when a decision is **load-bearing for more than one service** or **hard to reverse**. Examples:

- The choice or replacement of a platform-wide tool: a database, gateway, IdP, or observability backend.
- The definition of a cross-service contract: auth headers, the error format, or the workflow handle shape.
- The sanction of a per-service exception: a Rust service, a non-default storage class, or a long-running workflow.

Single-service implementation details do **not** get an ADR. They live in the service's README.

### Statuses

- **Proposed**: open for review. A PR links it, and it binds once it is accepted.
- **Accepted**: merged. It binds all services.
- **Superseded by ADR-XXXX**: a newer decision replaced it. It is kept for history.
- **Amended by ADR-XXXX**: modified in part. The amendment cites the sections it changes.

There is no `Rejected` or `Draft` status. A rejected proposal is a closed PR, not a committed file.

**Scope:** the last two statuses belong to a project generated from this template. Such a project is a living system with real history. **This template's own set carries no history.** Every ADR here reads `Accepted` and carries the date the set was written. An ADR that must change is rewritten in place, per [ADR-0001](0001-documentation-and-output-conventions.md).

### Structure, numbering, and prose

[ADR-0001](0001-documentation-and-output-conventions.md) owns all three: the section order, the blocks-of-a-hundred numbering, and the density rules.

One rule belongs here instead, because it is a selection criterion and not a style: **the comparison table in *Considered options* is mandatory**, per principle 7. [ADR-0002](0002-tool-adoption.md) sets its depth per tier. A long deep-dive belongs in the PR discussion, not in the ADR.

### Who decides

The platform team decides. One reviewer with platform-team approval is enough to merge an ADR. A 24-hour async comment window resolves a disagreement. An unresolved disagreement escalates to a synchronous decision call.

## Prior art

This ADR borrows its framing and does not invent it. Where a decision here has an external anchor, the decision cites it at the point of use. The sources below are what the structure itself rests on.

| Source | What this document takes from it |
| --- | --- |
| Richards and Ford, *Fundamentals of Software Architecture* | Architecture styles rated against characteristics as **risk profiles**, not levels. The term *service-based architecture* |
| DORA and *Accelerate* | Capability models over maturity ladders |
| Team Topologies, by Skelton and Pais | **Cognitive load as the sizing unit**, in principle 2. Its *thinnest viable platform* bounds what a platform imposes on its users. Principle 2 borrows the unit and applies it to the operators |
| [OpenGitOps](https://opengitops.dev/) v1.0.0, CNCF | Declarative and versioned configuration, in principle 1 |
| [12-Factor](https://12factor.net/) | Explicit dependencies in principle 6 of this ADR, and dev-prod parity in principle 8. *12-Factor conformance* below gives the full mapping |
| McKinley, [*Choose Boring Technology*](https://mcfunley.com/choose-boring-technology) | Innovation tokens as a budget, in principle 4 |
| Raymond, [*The Art of Unix Programming*](https://www.catb.org/esr/writings/taoup/html/), and McIlroy | The **Rule of Parsimony** and *do one thing well*, applied to the repository's own machinery in principles 2 and 5 |
| Fowler, [*IntegrationDatabase*](https://martinfowler.com/bliki/IntegrationDatabase.html), *MonolithFirst*, *MicroservicePremium* | Service boundaries in principle 10, and the prerequisite bar for decomposition |
| Ford, Parsons, and Kua, *Building Evolutionary Architectures* | **Fitness functions**. The Rules sections are designed to be executable, not advisory |
| Poppendieck, *Lean Software Development* | The **last responsible moment**: deferral with a written trigger |
| Feathers, *Working Effectively with Legacy Code* | **Seams** |
| Conway, 1968 | Boundaries track teams, not features, in force 2 of axis A |
| Nygard, [*Documenting Architecture Decisions*](https://www.cognitect.com/blog/2011/11/15/documenting-architecture-decisions), 2011 | The ADR form itself: one decision per file, immutable once accepted, and superseded, not edited. [MADR](https://adr.github.io/madr/) supplies the section set, per [ADR-0001](0001-documentation-and-output-conventions.md) |
| [CNCF Platforms White Paper](https://tag-app-delivery.cncf.io/whitepapers/platforms/) | Platform as a product with users. It gives the capability framing behind the tiers in [`docs/operational-surface.md`](../operational-surface.md) |

### 12-Factor conformance

[12-Factor](https://12factor.net/) predates Kubernetes. The orchestrator satisfies several of its factors, with no decision of ours. Two factors anchor a principle above and are cited at the point of use. This table records the rest, so a reader who knows the canon finds the matching decision without reading the set.

| Factor | Decided in | Verdict |
| --- | --- | --- |
| I: Codebase | [ADR-0101](0101-monorepo.md), [ADR-0201](0201-gitops.md) | conforms: one repo, and one SHA through every environment |
| II: Dependencies | principle 6 above, [ADR-0100](0100-language-and-runtime.md) | conforms, and anchors principle 6 |
| III: Config | [ADR-0202](0202-secrets.md), [ADR-0205](0205-environment-parity.md) | conforms: the env contract is identical in every tier, and values come from SOPS-derived Secrets |
| IV: Backing services | [ADR-0300](0300-data.md), [ADR-0302](0302-temporal.md), [ADR-0205](0205-environment-parity.md) | conforms: the provider may differ per tier, and the wire contract may not |
| V: Build, release, run | [ADR-0103](0103-release-and-versioning.md), [ADR-0201](0201-gitops.md) | conforms: immutable SHA tags, digest-pinned production, and no moving tags |
| VI: Processes | [ADR-0200](0200-cluster-topology.md), [ADR-0401](0401-internal-admin.md) | conforms: the application tier is stateless. State is Postgres, object storage, and Temporal |
| VII: Port binding | none | not applicable: a Kubernetes `Service` owns it, and there is no decision to make |
| VIII: Concurrency | [ADR-0204](0204-resource-management.md) | conforms, scoped: scale-out is opt-in on a measured signal, never a template default |
| IX: Disposability | [ADR-0302](0302-temporal.md), [ADR-0204](0204-resource-management.md) | conforms, and the worker-drain rule cites it |
| X: Dev-prod parity | principle 8 above, [ADR-0205](0205-environment-parity.md), [ADR-0600](0600-local-development-loop.md) | conforms, scoped: it anchors principle 8. Scale and inner-loop stand-ins may differ |
| XI: Logs | [ADR-0500](0500-observability.md) | conforms: structured JSON to stdout, routed by the collector |
| XII: Admin processes | [ADR-0300](0300-data.md), [ADR-0401](0401-internal-admin.md) | conforms, scoped: the same image and release, never a host shell |

### Standards deliberately not adopted

Principle 7 applies to standards as it applies to tools: a standard with no recorded comparison is an assumption. The standards below were weighed and refused. The reason is recorded, so the question does not reopen for free. Here, refusal means *not adopted as a normative reference*. It never means that the underlying concern is unaddressed.

| Standard | Why not |
| --- | --- |
| **ISO 27001**, **SOC 2** | Certification frameworks that describe an audited management system. They are not design guidance. The controls they examine are already decided: supply chain in [ADR-0104](0104-supply-chain-security.md), secrets in [ADR-0202](0202-secrets.md), retention in [ADR-0301](0301-data-lifecycle-privacy.md), and access in [ADR-0304](0304-identity-and-authorization.md). The adoption of one adds an evidence programme and an auditor. That is a commercial decision about who buys the product, not an architectural one |
| **NIST SSDF**, SP 800-218 | A crosswalk over practices that [ADR-0104](0104-supply-chain-security.md) already decides through SLSA provenance, cosign signing, and admission verification. Its adoption produces a mapping table to maintain and changes no control |
| **PCI DSS** | **Scope-triggered, not refused.** The platform stores no cardholder data, and a payment integration hands off to a provider. A project that takes card data directly brings PCI scope with it. That changes [ADR-0300](0300-data.md) and [ADR-0301](0301-data-lifecycle-privacy.md), not this document |
| **TUF** | It solves repository compromise, rollback, and key distribution for a public update system with untrusted mirrors and many unknown consumers. This registry serves one estate, pinned by digest and verified at admission, per [ADR-0104](0104-supply-chain-security.md) and [ADR-0105](0105-image-registry.md). Its threat model is not ours |
| **AsyncAPI** | There is no async wire contract to describe. Durable async is Temporal workflows typed in Go, per [ADR-0302](0302-temporal.md), and the outbox is in-process. AsyncAPI would document a message bus that this platform does not run |
| **OAM**, **Score**, **Backstage** | Abstraction layers over Kubernetes for teams who must not read manifests. Principle 2 bounds the floor, and the shared chart of [ADR-0201](0201-gitops.md) already *is* the abstraction. A second layer over it has no reader |
| **CIS Kubernetes Benchmark** | Written against a general Kubernetes with a mutable node. Talos removes most of what it audits: no SSH, no kubelet config file, and no host package manager, per [ADR-0200](0200-cluster-topology.md). So a large share of its findings are not applicable, not passing. Pod Security Standards assert workload hardening directly instead |

[ADR-0001](0001-documentation-and-output-conventions.md) records one more refusal on the same basis: the keyword grades of [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119). They are rejected because every Rule here binds, and a `SHOULD` tier invites negotiation.

## Vocabulary

All ADRs use these terms consistently. If a term is ambiguous in a later ADR, this glossary wins.

**Four words carry a second, unrelated sense elsewhere in the repository.** Both senses are correct, and the subject shows which sense is meant.

| Word | Glossary sense | The other sense |
| --- | --- | --- |
| **floor** | the guaranteed minimum of the platform or of a primitive | *baseline* in a load-test run is the reference measurement that a later run is compared against, per [`docs/guide/performance-runbook.md`](../guide/performance-runbook.md). [`docs/security-baseline.md`](../security-baseline.md) is the index of controls |
| **ceiling** | the point where an approach stops working, stated as a trigger | the `limits` field of a container, which is a scheduler value, per [ADR-0204](0204-resource-management.md) |
| **trigger** | the observable condition that makes a deferred capability due | a *threshold* is a number whose doubling would change the decision, per [ADR-0001](0001-documentation-and-output-conventions.md). A trigger often tests a threshold, and the two are not interchangeable. One is a number, and the other is a condition |
| **first-class** | served by the default path, not by a special case beside it | *native execution* is a service that runs as a host process and not in a container, per [ADR-0600](0600-local-development-loop.md) |

- **Axis position**: this platform's load-bearing assumption, set in *Thesis* above: **A high, B maximal, C high**. An ADR cites the axis position and does not restate a service count or a headcount. So the assumption changes in one place.
- **Seam**: a pre-built slot that a deferred capability drops into without restructuring. A deferral with a seam is additive. A deferral without one is a bet.
- **Anchor**: the external standard that a principle rests on. A principle without one is marked **local**.
- **Trigger**: the observable condition that makes a deferred capability due. A deferral states one, or it is indefinite.
- **Day one**: present in the first deployment, not deferred behind a trigger.
- **Floor**: the guaranteed minimum. For the platform, it is the components that run before any service is added. For a library or a primitive, it is what it supplies before composition. A floor is not a target.
- **Ceiling**: the point where an approach stops working. A ceiling is stated as a trigger, never as a limit that is quietly tolerated.
- **Escape hatch**: a sanctioned, bounded exception to a default. It names what is permitted and where. An unbounded escape hatch is a second default.
- **Island**: a bounded region that runs something other than the platform default: a language, a runtime, or a signal store. An island pins its own tools and does not widen the exception around it.
- **Load-bearing**: a fact that the decision rests on. If the fact is removed, the decision changes. A fact that survives removal is context.
- **First-class**: served by the default path, not by a special case beside it.
- **Hot path**: the per-request code path. Every request pays the cost added here.
- **Blast radius**: what a failure or a compromise reaches before something stops it.
- **A signal with no reader**: an output whose only value is that someone else consults it, produced where nobody does. It is cost without benefit. The test is to name the reader. A SemVer bump names a pinner, per [ADR-0103](0103-release-and-versioning.md). A keyless signature names a stranger who verifies without the cooperation of the signer, per [ADR-0104](0104-supply-chain-security.md). An abstraction layer names whoever must not read the manifests underneath. Where the named reader does not exist here, the signal is refused, and the escape hatch is the arrival of that reader.
- **Break-glass**: the documented procedure to bypass a normal control during an incident. It is written down before anyone needs it.
- **Service**: a deployable unit under `services/<name>/` that owns a slice of business state and an OpenAPI surface. It may include an HTTP server, a Temporal worker, and migrations.
- **Frontend app**: the single Next.js application under `apps/frontend/`. Route groups separate audiences, and the deploy unit is one app.
- **Platform component**: infrastructure software that the services depend on, such as Postgres, the Temporal server, the gateway, the IdP, and the observability stack. It lives under `infra/helm/platform/`.
- **Library**: shared code under `libs/go/<name>/` or `libs/ts/<name>/`. It has no business state.
- **Generated client**: code under `libs/{go,ts}/sdks/<service>/` that is produced from the OpenAPI spec of a service. It is committed to the repo.
- **Workflow** and **Activity**: Temporal terms, per ADR-0302.
- **Authz-relevant mutation**: a state change that affects who can see or modify a resource, per ADR-0304.
- **Affected**: in CI, the set of services and apps that the diff of a PR influences, per ADR-0101.
- **Environment**: one of `dev`, `staging`, or `prod`. Each one is a single cluster on day one, per ADR-0200.

## Consequences

### Positive

- A newcomer, human or LLM, reads one short document and learns the platform's worldview.
- Later ADRs do not argue the principles again. They cite them.
- Coherence is a checkable property: an ADR either follows the principles or amends them.

### Negative and Risks

- **The axis positions are the load-bearing assumption.** A system that sits much lower on axis A or B needs a new evaluation of several later ADRs. This risk is acknowledged and not mitigated. *Moving down axis B* above exists so that the new evaluation is guided, not improvised.
- **The list is longer than most people hold in their head.** Two facts mitigate this. Most principles are anchored to standards that a reader may already know. Every principle names what it rejected, and a criterion with a casualty is easier to recall than an abstraction.
- Strong opinions reduce flexibility. A team that needs to deviate justifies the deviation in a new ADR.

## Rules

### Process

- An ADR exists for every decision that binds more than one service or is hard to reverse.
- An ADR follows the structure, numbering, and prose rules of [ADR-0001](0001-documentation-and-output-conventions.md).
- **No tool is adopted without a recorded comparison against its alternatives**, per principle 7. The comparison is a table with prose cells, not a scoring grid. Its depth is the depth that [ADR-0002](0002-tool-adoption.md) sets for the tier of the tool. `(CI: lint:tool-register)`
- Every young component carries a named fallback and an observable trigger in its owning ADR. A novel adoption without one is a bet, and is labelled as one.
- An accepted ADR binds every service. A per-service deviation requires a new ADR.
- A decision is unambiguous: no `or Y in some cases` without a measurable trigger.
- Nothing is `temporary`. A solution is either committed or deferred behind a hard trigger. The deferral records the trigger, whether a **seam** exists, and the cost of a late adoption. A deferral without a seam is a **bet** and is labelled as one.

### Selection

- Configuration lives in this repo, not in the component. UI-only state is not allowed for anything reconciled into a cluster, and not for the own configuration of a component either.
- Platform components are tiered Core, Scale, and Opt-in in [`docs/operational-surface.md`](../operational-surface.md). A component joins Core only when no existing Core component covers its concern. A Scale variant replaces its Core counterpart only on the measured trigger documented there.
- Every component runs on infrastructure we control. Managed services are not adopted to reclaim operational budget.
- Novelty is spent by exit cost: freely where abandonment costs days, and conservatively where it costs months and customer data.
- One primitive per concern. Parallel mechanisms for the same problem require an ADR that retires the incumbent.
- One primitive per concern covers the repository's own machinery. A task, script, test, or workflow names the failure class it owns or the mechanism it replaces. One that names neither, or duplicates the work of another, is deleted. Additions and deletions land in the same change.
- Go and TypeScript only. No tool may assume a runtime that is not pinned in `.mise.toml`. `(CI: lint:node-scope)`
- Licence, governing body, and project maturity are **recorded** for every component and **do not veto** a choice.

### Construction

- Local and production differ in topology only. Charts, code, and commands do not diverge.
- Generated code is committed and drift-checked in CI. `(CI: ci:gen)`
- Service-to-service communication is HTTP through generated OpenAPI clients. Shared databases, shared code, and cross-service workflow calls are forbidden. `(CI: ci:lint)`
- Local development uses the same Helm charts, container images, and commands as production. Topology may differ, and the interface may not.
