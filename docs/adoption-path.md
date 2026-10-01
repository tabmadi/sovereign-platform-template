# Adoption Path: Reducing and Growing the Floor

[`operational-surface.md`](operational-surface.md) is the inventory. It lists what the template runs, and it holds the budget rule for what can join it. This document runs in the other direction. It answers **what a project gives up, in what order, and what it costs to take back.**

The Core floor is **a position on a path, not the start of one.** A project can arrive with less capacity than the floor needs. The template does not exclude it. The project enters below the floor and records the rungs it skipped. A project that grows past the floor moves up into the Scale tier. Both directions use the same mechanism, and this document holds both ends of it.

## Three ways to get smaller, and they are not the same

| Move | What changes | What is kept | Where it lives |
| --- | --- | --- | --- |
| **Defer a capability** | the function is absent | the seam that lets it return as a chart | Band 1, below |
| **Give up the operator** | someone else runs it. Axis B moves down | the whole capability | Band 2, below |
| **Give up the capability** | the function goes, and its absence shapes the application | nothing. This is a bet | Band 3, below |
| **Defer scale** | the thin variant runs until a measured signal appears | the seam to the heavier variant | [`operational-surface.md`](operational-surface.md), *Scale* |

Only the first three moves reduce the floor. The fourth is the growth direction. It lives in the inventory, next to the components it applies to. But it obeys the same rule as the other three. The Scale table in [`operational-surface.md`](operational-surface.md) records the **cost to reverse** for each row. A swap that is cheap to adopt is not always cheap to leave.

## The ordering rule

The first idea is to rank by savings and drop the heaviest component first. That is wrong here. The cost to reverse does not follow the cost to run. A reduction taken in the wrong order costs twice.

> **A removal with a seam is a deferral. A removal without a seam is a bet.**

This is the Scale-tier rule of [`operational-surface.md`](operational-surface.md), read backwards. It gives the order:

1. **Take every deferral before any bet.** Use all of Band 1 first, however little each row saves.
2. **Prefer giving up the operator to giving up the capability.** Band 2 costs money and vendor coupling. Band 3 costs a rewrite, later, under pressure.
3. **Never buy capacity with a bet when a deferral would buy it.** If Band 1 and Band 2 together do not close the gap, the position on axis B is wrong. See *Moving down axis B* in [ADR-0000](adr/0000-platform-foundations.md). Take that decision on purpose. Do not keep cutting the floor.

Every row below has a **restore trigger**: the observable condition that brings the component back. A reduction without a restore trigger is not a reduction. It is an omission.

## Band 1: deferrals below the floor

The seam exists. You remove each row by not deploying a chart, and you restore it by deploying the chart. Application code does not change in either direction. So these rows are safe to take first, and safe to take all of.

| Removed | What covers the concern instead | Restore trigger | Cost to reverse |
| --- | --- | --- | --- |
| **Hubble UI** | `hubble observe` on the CLI. The agent and relay run in both cases as the audit surface for default-deny, per [ADR-0206](adr/0206-cluster-networking.md) | flow debugging becomes routine and not occasional, or a person who is not the author needs to read drop verdicts | a values field, per [ADR-0501](adr/0501-operator-uis-and-dashboards.md) |
| **pgweb** | `psql` over a port-forward, against the same read-only role | break-glass DB inspection happens under time pressure so often that the port-forward is the delay | a chart, per [ADR-0401](adr/0401-internal-admin.md) |
| **Headlamp** | `kubectl`, which every operator of this platform must have anyway | a person who needs to read cluster state does not use `kubectl` | a chart, per [ADR-0501](adr/0501-operator-uis-and-dashboards.md) |
| **Pyroscope** and **Alloy** | metrics and traces show *what* is slow. Nothing shows *where* in the code | a CPU or memory regression that metrics locate to a service but not to a function, twice | two charts. Services already expose `pprof`, so nothing needs new instrumentation, per [ADR-0500](adr/0500-observability.md) |
| **Lowdefy admin** | the Go API directly, and any DB inspector that is still deployed | a person who does not write API calls does an operational task, or a support workflow becomes recurring | a chart and its YAML pages, per [ADR-0401](adr/0401-internal-admin.md) |
| **Tempo** | logs correlated by trace ID. The log line has the trace ID in both cases | a fault crosses more than two services, and log correlation is no longer enough | a chart and one collector exporter. OpenTelemetry instrumentation does not change. That is the purpose of the OTel-first rule in [ADR-0500](adr/0500-observability.md) |

**Take this band from top to bottom.** The upper rows lose a convenience. The lower rows lose a diagnostic. A project at axis C high that takes every row in this band has a longer time to diagnose. It says so in the same place where it records its detection posture.

**Lowdefy and pgweb affect each other.** If you drop both, the only path to the data is `psql`. That is a legitimate position for a team where everyone is an engineer. It stops working as soon as a person who is not an engineer does support work.

## Band 2: giving up the operator

The capability does not change, and axis B moves down. Nothing in the architecture moves. A managed swap does not affect:

- the ADR set
- the OpenAPI contracts and codegen
- the service template
- the Helm and GitOps trees
- policy-as-admission
- the repo layout
- release and versioning
- the local dev loop

The rank is the **capacity returned for each unit of sovereignty given up**, not the ease:

| # | Self-hosted here | Managed equivalent | Why this rank |
| --- | --- | --- | --- |
| 1 | Outbound email, with maddy | Any transactional email provider | Deliverability is a matter of reputation, not technology. It is the one cost that engineering effort cannot remove, per [ADR-0307](adr/0307-outbound-email.md). Give this up first, even at high sovereignty |
| 2 | Alert routing and on-call, with Alertmanager | A hosted paging service | No mature self-hosted escalation layer exists. The alternative is a rota and a phone, per [ADR-0502](adr/0502-alerting-and-on-call.md) |
| 3 | PostgreSQL, with CNPG | Managed Postgres | The highest operational risk for each unit of engineering time. Backups, PITR, failover, and major upgrades all move to the rota of someone else |
| 4 | Object storage, with SeaweedFS | Any S3-compatible service with Object Lock | Removes a stateful production component and the off-cluster host it runs on. Object Lock is a requirement of the replaced row, per [ADR-0200](adr/0200-cluster-topology.md). It is not an optional extra. Non-prod keeps the in-cluster instance, so the local loop stays offline |
| 5 | Observability, with the Grafana stack | A hosted observability backend | A family of backends goes to one vendor. OpenTelemetry instrumentation does not change, per [ADR-0500](adr/0500-observability.md) |
| 6 | Temporal | Temporal Cloud | Workflow code stays the same. Only the connection target changes, per [ADR-0302](adr/0302-temporal.md) |
| 7 | Forge and CI, with Forgejo | A hosted forge | Cheap to move in either direction, because `mise run ci:*` keeps workflows thin, per [ADR-0102](adr/0102-source-control-and-ci.md) |
| 8 | Image registry, with zot | A hosted registry | Check that cosign policy and scanning match before the swap, per [ADR-0105](adr/0105-image-registry.md) |
| 9 | Identity, with Ory | A hosted IdP | Late, not first. The headless requirement of [ADR-0304](adr/0304-identity-and-authorization.md) leaves few options. Identity data is also the most painful data to migrate twice |
| 10 | Kubernetes, with Talos | Managed Kubernetes | Keep the API and drop the substrate. This removes all node provisioning of [ADR-0200](adr/0200-cluster-topology.md) |

A **hybrid** position is legitimate and common. Self-host the orchestrator and the stateless platform. Use managed Postgres, object storage, email, and paging. This removes most of the pager load. It keeps the parts whose sovereignty was usually the reason for the choice.

Reversal is a migration for each component in either direction. So choose each row on purpose. Rows 1, 2, 7, and 8 are close to free to reverse. Rows 3 and 9 include a data migration, and they need the most thought.

## Band 3: giving up the capability

These rows are **bets**. There is no seam. Without the component, the application is written differently. To restore the component later, you change code that was shaped by its absence. Each row states what the bet is.

| Removed | What the application does instead | Cost if the bet is wrong | Cost to reverse |
| --- | --- | --- | --- |
| **Temporal** | an outbox table and a small worker for each job, with retries and compensation written by hand | every multi-step process that gets a second call, a compensation, or a durability guarantee grows its own state machine. At axis C high, each one is a separate correctness surface | a rewrite of every such process, and the platform components. [`operational-surface.md`](operational-surface.md) already names outbox with worker as the shape before Temporal for a *single trivial job*. This row applies it to the whole platform, and there it stops being cheap |
| **OpenFGA** | Postgres RLS, per [ADR-0300](adr/0300-data.md), and role claims from the session | relationship-shaped rules become custom queries spread across services. Examples are sharing, delegation, and nested org structures. The authorization model can no longer be inspected in one place | model the authorization domain again and migrate every relationship into tuples. It is cheap while the model stays flat, and the model never stays flat |
| **Kyverno** | CI-only checks: signature verification and digest pinning are enforced before merge, not at admission | every `(enforced: Kyverno)` annotation in the ADR set becomes a convention with no enforcement. Anything that reaches the cluster by another path is unchecked: a manual `kubectl apply`, a break-glass action, or a compromised pipeline, per [ADR-0104](adr/0104-supply-chain-security.md) | a chart, and an audit of what was admitted in the meantime. The component is cheap to restore. The trust gap it leaves cannot be closed after the fact |
| **Cilium's default-deny and WireGuard posture** | a simpler CNI with no network policy and no east-west encryption | lateral movement has no limit inside the cluster. The multi-tenant isolation argument rests on RLS alone | **the highest in this document.** [ADR-0200](adr/0200-cluster-topology.md) records that the CNI cannot be hot-swapped on a live cluster. The bootstrap sets the security posture. To reverse this row takes a cluster rebuild and a migration |

### The line

**A project that takes rows from this band is no longer at A high, B maximal, and C high.** It changes its position on axis A or C, not only its operating budget. The mechanism in this repository is calibrated for the position that the project left.

That is a legitimate place to be. It is not a legitimate place to *drift* into. A project that takes any Band 3 row records it in **an ADR of its own**. That ADR states the new position on the axes, and it explicitly supersedes the affected decisions. [ADR-0000](adr/0000-platform-foundations.md) requires the same for a move down axis B. If you delete a component and keep the ADR that requires it, the result is a documented system that nobody runs. The conventions of this repository exist to prevent that failure.

If more than one row here looks necessary, this template is not the right starting point for that project. A smaller template costs less than this one held together by exceptions.

## Irreducible

**This section is about functions, not components.** Every row below has a good managed form, and Band 2 already ranks most of them. What cannot be reduced is that *something* performs the function. It does not have to be the component that this repository chose. It does not have to be self-hosted.

Read each row as: *you can stop operating this. You cannot stop having it.*

| Function | Self-hosted here | Managed form | Why the function does not reduce |
| --- | --- | --- | --- |
| An edge with TLS | Traefik and cert-manager | a cloud load balancer with managed certificates | Traffic has to arrive somewhere, and something has to terminate it. `(ref: RFC 8555)` |
| A relational store | PostgreSQL on CNPG | any managed Postgres. **Band 2, rank 3** | Every stateful component here is a Postgres tenant, per [ADR-0300](adr/0300-data.md) |
| Authentication | Kratos and Oathkeeper | a hosted IdP. **Band 2, rank 9**. Few options exist, because [ADR-0304](adr/0304-identity-and-authorization.md) requires headless | Every service consumes the edge identity contract, per [ADR-0305](adr/0305-edge-auth-and-traffic-policy.md) |
| Reconciliation from git | Argo CD | a hosted GitOps control plane | Principle 1. You can give up the *tool*. If you give up reconciliation, the cluster state no longer follows from the repository, per [ADR-0201](adr/0201-gitops.md) |
| Secret encryption at rest in git | SOPS and its operator | a cloud KMS as the SOPS key backend. The file format and the workflow do not change | Without it, secrets leave the repository, and the deploy is no longer reproducible, per [ADR-0202](adr/0202-secrets.md) |
| Metrics, logs, and one place to read them | Prometheus, Loki, Grafana, and the OTel Collector | a hosted observability backend. **Band 2, rank 5** | Below this there is no detection at all. Band 1 removes the *third* and *fourth* signals. It does not touch the first two |
| A container runtime with an API | Kubernetes, shipped by Talos | any managed Kubernetes. **Band 2, rank 10** | It is the deploy target of every artefact, per [ADR-0200](adr/0200-cluster-topology.md) |
| An image registry | zot | GHCR, ECR, Artifact Registry, or any OCI registry. **Band 2, rank 8**. Check that it stores referrers, because signatures and attestations live next to the image, per [ADR-0105](adr/0105-image-registry.md) | Pods pull from somewhere |
| A forge | Forgejo | GitHub, GitLab, or any hosted forge. **Band 2, rank 7**. Workflows are a portable subset of `mise run` calls, so that this stays cheap, per [ADR-0102](adr/0102-source-control-and-ci.md) | Principle 1 again: the repository is the source of truth, so something has to host it |
| An outbound **transactional** mail path | maddy | a transactional provider such as Postmark, SES, or Mailgun. **Band 2, rank 1**. It is the first thing to give up at any sovereignty level | Identity verification and recovery have no production path without one, per [ADR-0307](adr/0307-outbound-email.md) |

**A note on mail, because the substitution is easy to get wrong.** Google Workspace, Microsoft 365, and similar products sell **human mailboxes**. [ADR-0307](adr/0307-outbound-email.md) treats human mailboxes as a separate system from transactional sending. They have a different egress IP and a different DKIM selector, and they never use the same sender, by design. Mailboxes do not replace maddy. If platform mail goes through a mailbox suite, it loses the reputation separation that the ADR depends on. The managed form of *this row* is a transactional provider. You can buy both, and they are two purchases.

**No row here is a reason to stay self-hosted.** If capacity is the binding constraint, Band 2 is the intended response, and all of it is available.

## Hardenings a project takes on its own

These are the reverse of a reduction. The template holds each position at a chosen default. The risk profile of a project can justify paying more than the floor does. Each hardening is additive, so none of them moves a band.

| Hardening | The default, and why | Take it when |
| --- | --- | --- |
| **Ops tooling on its own registrable domain** | One session cookie is scoped to the parent host. So it reaches the apex and every `*.ops.<host>` origin. Tier isolation rests on authorization in each tool and a second factor, not on cookie scope. So an XSS on the product origin can use an operator's session to reach the ops tools, per [ADR-0306](adr/0306-trust-tiers-and-urls.md) | The product surface renders content that one user supplies to another, or content that is not first-party is hosted under the apex. It costs a second DNS zone and a second certificate chain for each environment. It is the strongest available answer |
| **An ops-tier OIDC session** | The same risk, at a lower cost. One auth proxy in front of the ops tier mints its own scoped session. The product cookie stays host-only on the apex | The separate domain is not worth its DNS and certificate cost, but you still want the shared-token risk gone. It adds one component to the floor |
| **Per-workload certificate identity** | Services trust `X-User-Id` because default-deny lets only sanctioned callers reach the port. Code inside any sanctioned caller can forge it, per [ADR-0305](adr/0305-edge-auth-and-traffic-policy.md) | A service performs a monetary mutation, or a second team owns a service in the cluster. It uses Cilium mutual auth and SPIFFE, with no sidecars |
| **A paging receiver** | Alerts route to email and to a paging webhook that is not wired. The Watchdog has its own heartbeat receiver, which is also not wired. Nothing pages, so overnight detection happens on the next working day, per [ADR-0502](adr/0502-alerting-and-on-call.md) | The project states an availability objective that is tighter than the next working day. The objective and the receiver are one decision, not two |

**A project records every hardening it takes.** Each one changes what an ADR states is true of the platform. So it amends the Rules of the owning ADR in the project's copy. This is the same obligation as a Band 3 concession, in the other direction.

## Growing back

Every restore trigger above points up. The same seam mechanism continues past the floor into the **Scale** tier of [`operational-surface.md`](operational-surface.md). There, each row has a trigger to adopt and a cost to reverse, in the same shape as here.

**Not every rung of the ladder is equally reversible.** The difference does not follow the direction of travel:

- Going up, ClickHouse and Longhorn are the expensive rungs to undo.
- Going down, the Cilium posture is the expensive rung, because the bootstrap sets the CNI.
- Everything else, in both directions, is a chart or a values change.

The full ladder, from smallest to largest:

| Position | What it is |
| --- | --- |
| Band 3 taken | a different platform, at a different point on the axes, recorded in its own ADR |
| Bands 1 and 2 taken | the capabilities of the floor, thinner, and partly operated by others |
| Band 1 taken | the floor without its convenience surfaces and third-signal surfaces |
| **The Core floor** | what this template ships |
| Scale rows swapped in | the heavier variants of the floor, each on a measured trigger |

No rung on this ladder is a *maturity level*, and moving up is not progress. [ADR-0000](adr/0000-platform-foundations.md) makes this point about the axes, and it holds here too. A higher position is a more expensive answer to a pressure that a system may not have.

## How to use this

1. Read the Core table in [`operational-surface.md`](operational-surface.md), with the **recurring obligation** and **failure needs** columns. That is the demand side. It is the same for every adopter.
2. Compare it with your coverage obligations, your operational skill, and your tolerance for detection latency. The gap between them is the risk.
3. See *Capacity is a separate question from need* in [ADR-0000](adr/0000-platform-foundations.md).
4. If a gap exists, close it with all of Band 1, then Band 2 in order.
5. If a gap remains after both bands, do not go into Band 3 to close it.
6. Read *Moving down axis B* again. The position has the wrong price, not the floor.

Each row you take removes its obligation from the demand side. **This is the only honest way to lower the capacity that this platform needs.** The alternative is to hold the floor and hope. [ADR-0000](adr/0000-platform-foundations.md) names that as the failure mode.

## Where a reduction is written down

A project records every reduction in its own repository, next to the restore trigger that it watches. A reduction that nobody wrote down looks the same as a forgotten component. The weight of the record differs by band:

| Band | Recorded as | Why that weight |
| --- | --- | --- |
| **1: deferral** | a values change, and a row in the project's own register of what is deferred and what would restore it | The seam does not change, and every ADR stays true. The chart is off, and the record is the trigger |
| **2: managed swap** | a values change, and an amendment to the *Rules* of the owning ADR that names the managed operator | The capability does not change, but the operator does. The ADR states who runs it, so the ADR stops being true. It needs an amendment, not a new document |
| **3: capability concession** | an ADR of its own that states the new position on the axes and explicitly supersedes the affected decisions | The absence shapes the application. That is a different system, and it needs the argument written down |

**Band 2 decides whether this path stays cheap.** An amendment is one paragraph. If teams treat it as a full new debate, they skip the record and drift. Name the managed service, mark the rule that it changes, and keep the trigger that would bring it back in-house.

## A worked example

This section walks one project from end to end. The rules above are complete but abstract, and a first adopter reasons by analogy in any case.

**The project.** A B2B product that handles money. Axis A is high: three teams ship on their own. Axis C is high: a wrong answer is a transaction. Axis B does not match. The project prefers self-hosting but is not bound to it. Platform work is a real part of several jobs, and it is not the whole job of anyone.

**Step 1: the demand side.** The team reads the Core table of [`operational-surface.md`](operational-surface.md) against their own coverage. Three rows cost more than they can afford:

- CNPG needs *a person who has done a failover and a PITR before*.
- maddy needs deliverability work.
- Alertmanager means that *nothing pages anyone*, on a product that moves money.

**Step 2: all of Band 1.** They take every row: no Hubble UI, no pgweb, no Headlamp, no Pyroscope or Alloy, no Lowdefy, and no Tempo. Each one is a chart that they do not deploy, and application code does not change. They record that the time to diagnose is now longer. They expect the restore trigger for Tempo to fire first: a fault that crosses more than two services.

**Step 3: Band 2, in order.**

- Rank 1: maddy moves to a transactional provider. The deliverability obligation leaves completely.
- Rank 2: a hosted paging service. This also fires the escalation trigger of [ADR-0502](adr/0502-alerting-and-on-call.md). At axis C high with money in flight, they cannot hold next-working-day detection, per [`reference/detection-latency.md`](reference/detection-latency.md).
- Rank 3: managed Postgres. It returns the most capacity in the document, and it removes the obligation with the highest stakes on the floor.

**Step 4: stop.** Three Band 2 rows close the gap, so they never open Band 3. Axis B moves from maximal to hybrid. That is a chosen position, not a drift. The architecture does not change: the ADRs, the contracts, the service template, the Helm and GitOps trees, and the local loop stay the same.

**What they now carry:**

- three rules amended to name a managed operator
- six deferral triggers to watch
- one paging subscription
- a written record that their SLO is defensible, because a receiver exists to defend it

They no longer pretend that part-time operators could hold the full floor. This document exists to produce that outcome.
