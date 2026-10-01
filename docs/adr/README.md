# Architecture Decision Records

This directory records every decision that binds more than one service or is hard to reverse. ADR-0000 holds the thesis, the principles, and the process. [ADR-0001](0001-documentation-and-output-conventions.md) holds the rules for writing these documents.

A new ADR starts from [`_template.md`](_template.md).

Every ADR has a **Decides** line in its header. It is one declarative sentence that names what is true of the platform because of the ADR. The *Decides* column below is that line, shortened for the index. Reading the column is the fastest complete pass over the set. `(CI: lint:adr-xref)`

## Numbering

Numbers come in **blocks of a hundred, one block per layer**. Inside a block, numbers are sequential. The first two digits give the layer, so a new ADR goes into its block without renumbering the set. The gaps are deliberate.

| Block | Layer |
| --- | --- |
| `00xx` | Foundations and conventions |
| `01xx` | Repository and delivery |
| `02xx` | Infrastructure |
| `03xx` | Application platform |
| `04xx` | Interfaces |
| `05xx` | Observability |
| `06xx` | Development loop |
| `07xx` | Product |

Each layer has a hundred slots, not ten, so a layer can grow without renumbering the set. The index below is the set. This page does not count the ADRs in a block, so a new ADR changes one table only.

## The set

### 00xx: Foundations and conventions

| ADR | Title | Decides |
| --- | --- | --- |
| [0000](0000-platform-foundations.md) | Platform Foundations | The three axes and this platform's position on them, the principles, and the ADR process |
| [0001](0001-documentation-and-output-conventions.md) | Documentation and Output Conventions | How docs, ADRs, logs, CLI output, and code comments are written |
| [0002](0002-tool-adoption.md) | Tool Adoption and Comparison Requirement | The three exit-cost tiers, the depth of comparison each owes, and the tool register |
| [0003](0003-naming-and-identifiers.md) | Naming and Identifiers | The resource slug grammar, entity identifiers, and casing per surface |

### 01xx: Repository and delivery

| ADR | Title | Decides |
| --- | --- | --- |
| [0100](0100-language-and-runtime.md) | Language and Runtime | Go and TypeScript, and what may not be added |
| [0101](0101-monorepo.md) | Monorepo Structure and Build | Layout, task runner, affected detection, caching |
| [0102](0102-source-control-and-ci.md) | Source Control and CI Platform | The forge, where pipelines run, and the build identity |
| [0103](0103-release-and-versioning.md) | Release, Tagging and Versioning | Conventional Commits, CalVer, image tags |
| [0104](0104-supply-chain-security.md) | Supply-Chain Security | Signing, scanning, admission verification |
| [0105](0105-image-registry.md) | Image Registry | Where images and their attestations live |
| [0106](0106-dependency-updates.md) | Dependency Updates and Template Propagation | What moves the pins, and how a template fix reaches a generated project |

### 02xx: Infrastructure

| ADR | Title | Decides |
| --- | --- | --- |
| [0200](0200-cluster-topology.md) | Cluster Topology and Hosting | Where production runs, what a node is, and what recovering a cluster costs |
| [0201](0201-gitops.md) | GitOps and Deploy | Argo CD as the delivery engine, repository topology, sync policy |
| [0202](0202-secrets.md) | Secrets Management | SOPS and age, the recipient model, key lifecycle |
| [0203](0203-policy-enforcement.md) | Policy Enforcement Strategy | Which layer enforces which class of invariant, and how each layer fails |
| [0204](0204-resource-management.md) | Resource Management and Scheduling | Requests, limits, priority classes, quotas |
| [0205](0205-environment-parity.md) | Environment Parity | What may differ across environments, what may not, and the PR preview tier |
| [0206](0206-cluster-networking.md) | Cluster Networking | The CNI, the day-one postures, and why no service mesh |
| [0207](0207-cluster-storage.md) | Cluster Storage and Backups | Node-local volumes, one object store everywhere, and where backups live |

### 03xx: Application platform

| ADR | Title | Decides |
| --- | --- | --- |
| [0300](0300-data.md) | Data and Migrations | Postgres, CNPG, sqlc, migrations, multi-tenancy |
| [0301](0301-data-lifecycle-privacy.md) | Data Lifecycle and Privacy | Retention, erasure, subject access |
| [0302](0302-temporal.md) | Durable Execution with Temporal | What earns a workflow, and how workers deploy |
| [0303](0303-api-contracts-and-lifecycle.md) | API Contracts, Codegen and Lifecycle | OpenAPI 3.1, ogen, audience, versioning |
| [0304](0304-identity-and-authorization.md) | Identity and Authorization | Kratos, Hydra, OpenFGA, organisations |
| [0305](0305-edge-auth-and-traffic-policy.md) | Edge Authentication and Traffic Policy | Oathkeeper forward-auth, rate limits, security headers |
| [0306](0306-trust-tiers-and-urls.md) | Trust Tiers and URL Structure | The `ops.` boundary, cookies, routing, the flat `/api` path |
| [0307](0307-outbound-email.md) | Outbound Email | The sending path that identity flows depend on, and its pre-built exit |

### 04xx: Interfaces

| ADR | Title | Decides |
| --- | --- | --- |
| [0400](0400-frontend.md) | Frontend Stack and Conventions | Next.js, rendering, styling, forms, CSP, portals |
| [0401](0401-internal-admin.md) | Internal Admin Tool | Lowdefy over the API, and the write-path invariant |

### 05xx: Observability

| ADR | Title | Decides |
| --- | --- | --- |
| [0500](0500-observability.md) | Observability | OpenTelemetry, the Grafana backend, cardinality discipline |
| [0501](0501-operator-uis-and-dashboards.md) | Operator UIs and Dashboard Hierarchy | Which UI answers which question, and the L1 to L3 funnel |
| [0502](0502-alerting-and-on-call.md) | Alerting and On-Call | Where alerts route, and where escalation is conceded |
| [0503](0503-error-tracking.md) | Error Tracking | Errors as OTel data, fingerprint grouping, and why no tracker joins the floor |

### 06xx: Development loop

| ADR | Title | Decides |
| --- | --- | --- |
| [0600](0600-local-development-loop.md) | Local Development Loop | The two local tiers, dependency graph, service contract, API mock |
| [0601](0601-testing-strategy.md) | Testing Strategy | Correctness layers, the acceptance gauge, load testing |

### 07xx: Product

| ADR | Title | Decides |
| --- | --- | --- |
| [0700](0700-analytics.md) | Marketing and Product Analytics | One browser agent, the Collector split, the analytics store |
| [0701](0701-product-design-and-discovery.md) | Product Design and Discovery | Design authored in the repository against one data seam, and research as dated evidence |

## Registries

An ADR names each of these three documents as the only record of a fact. A decision links to them and does not repeat what they hold.

| Document | Holds |
| --- | --- |
| [`operational-surface.md`](../operational-surface.md) | every platform component, its tier, and what it obliges |
| [`adoption-path.md`](../adoption-path.md) | the ranked order in which the floor is reduced |
| [`tool-register.md`](../tool-register.md) | every tool, its exit-cost tier, licence, governing body, and owning ADR |
