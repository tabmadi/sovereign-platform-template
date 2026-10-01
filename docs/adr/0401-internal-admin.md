# ADR-0401: Internal Admin Tool

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0100](0100-language-and-runtime.md), [ADR-0101](0101-monorepo.md), [ADR-0201](0201-gitops.md), [ADR-0202](0202-secrets.md), [ADR-0300](0300-data.md), [ADR-0302](0302-temporal.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0304](0304-identity-and-authorization.md), [ADR-0306](0306-trust-tiers-and-urls.md), [ADR-0500](0500-observability.md)
- **Decides:** Lowdefy pages over the service APIs are the admin surface, and every admin mutation goes through the Go API, not raw SQL.

## Context

A service fleet creates a steady need for back-office screens. Without a tool, people do that work with `psql`, `curl`, and workflows started by hand. The result is uneven and error-prone, and it depends on whoever knows the right commands.

The workload is:

| Share | Need |
| --- | --- |
| about 90% | CRUD over Postgres-backed resources that service REST APIs expose |
| | buttons that call a service endpoint, such as reset, requeue, or recompute |
| | small forms, now and then, that build a request body |

Each service owns its own database, per [ADR-0300](0300-data.md). Each spec already describes the resource shapes and operations, per [ADR-0303](0303-api-contracts-and-lifecycle.md).

## Decision drivers

1. **Declarative over imperative.** Admin pages are files in the repo, so a page edit is a file edit, per principle 1 of [ADR-0000](0000-platform-foundations.md).
2. **REST through services, never direct SQL.** Admin convenience does not bypass service boundaries.
3. **Generated from the spec, custom for the rest.** The specs describe every resource, so most pages are generated.
4. **A small change costs a small amount of work for the person who makes it.** Backend and platform engineers edit admin screens between other work. A frontend team does not. The cost of an edit is what the editor must learn again, not the language. Examples are a build, a component library, a data-fetching layer, and a review from another discipline.
5. **Zero new auth surface.** The edge authenticates, and the tool trusts the upstream identity header.
6. **One stateless container.** No new database and no new operator.

## Considered options

| Option | Config format | Licence | Verdict |
| --- | --- | --- | --- |
| **Lowdefy** | **pure YAML**, about 30 lines per page | [Apache-2.0](https://github.com/lowdefy/lowdefy/blob/main/LICENSE) | **Chosen.** These engineers already read YAML every day for Helm, Kubernetes, mise, and GitOps. YAML is dense, and LLMs write it well. Lowdefy has first-class REST and Postgres connectors. It is stateless when it uses external auth *(documented)* |
| **An `(admin)` route group in the existing frontend** | **React, in the app that already exists** | not applicable, first-party | **The baseline, and the real contender.** It adds no component and reuses the design system, session, and generated clients. It loses on driver 4. Every CRUD screen is React written by hand, by the people whom driver 4 describes as unwilling to write it. The generated pages in the chosen option are exactly that work. It also puts an operator-facing surface inside the product origin, against [ADR-0306](0306-trust-tiers-and-urls.md) |
| Appsmith | positional widget-tree JSON | Apache-2.0 | A diff cannot show it for review, and an LLM cannot edit it. Its OSS authentication is limited |
| Windmill | scripts and a YAML app definition | [AGPL-3.0](https://github.com/windmill-labs/windmill/blob/main/LICENSE-AGPL) | The closest competitor on driver 1, with real config as files. But it is a workflow and job platform first. Adopting it puts a second execution engine next to Temporal, per [ADR-0302](0302-temporal.md) |
| ToolJet | authored in the UI | AGPL-3.0 | Excluded on the authoring model before the licence matters |
| Budibase | authored in the UI | GPL-3.0 | The same as above |
| Retool | authored in the UI | proprietary, SaaS-first | Fails principle 3 completely |
| Refine, react-admin | **React** | MIT | Capable and type-safe against the generated clients, but the authoring surface is React. A small change lands in hooks and providers. Driver 4 exists to avoid exactly that |
| NocoDB | UI-first | AGPL-3.0 | A database UI, not an application builder. Driver 2 forbids the direct-SQL shape that it does best |
| Directus | UI-first | [BUSL 1.1](https://directus.io/bsl) | The same as above, and the licence is not OSI-approved |

### The read-only database inspector

| Option | Shape | Read-only enforcement | Verdict |
| --- | --- | --- | --- |
| **pgweb** | a single Go binary | the `--readonly` flag, and a read-only database role | **Chosen.** It has the same one-stateless-container shape as Lowdefy, and two independent read-only layers *(reasoned)* |
| pgAdmin | a stateful Python application | none, because it is a full client | It goes against a toolchain of single binaries, per [ADR-0100](0100-language-and-runtime.md). It offers write access that the role must then remove |
| CloudBeaver | a Java server | at the connection level | A heavier runtime again, for extra features that break-glass does not use |
| `psql` through `talosctl` and a pod | none | the role only | Always available, and the real fallback. It is not a UI. The inspector exists so that an operator does not need this row during an incident |

## Decision

### The write-path invariant

**Every admin mutation goes through the service's Go API, never through raw SQL.** This is load-bearing, and the tool choice comes second to it.

The API does three things, per [ADR-0304](0304-identity-and-authorization.md) and [ADR-0302](0302-temporal.md):

- it enforces domain invariants
- it does the **dual write to OpenFGA**
- it can trigger a workflow

A raw-SQL write bypasses all three. The authorization store falls out of sync with the application database, and every invariant the service guarantees is skipped.

The invariant applies to both tools:

- **Lowdefy is correct only when it points at the API.** Direct Postgres connections exist only as a **read-only** escape hatch.
- **pgweb and `psql` speak only raw SQL**, so they are never the write path. They are allowed as break-glass **inspectors** that run SELECTs during an incident. They are read-only **at the database-role level**, not by convention. The user cannot run `UPDATE` at all.

### Deployment

| Property | Value |
| --- | --- |
| Chart | `infra/helm/platform/lowdefy/`, reconciled by Argo CD |
| Shape | one stateless container, with no persistent volume |
| Datastore | **none.** Lowdefy's built-in auth providers need a session store. They are not configured, so no store is needed |
| Origin | `lowdefy.ops.<host>`, per [ADR-0306](0306-trust-tiers-and-urls.md). It is its own ops-tier origin behind the forward-auth, never a product path |
| Coarse gate | the `operator` claim and AAL2, with **no authz call**, per [ADR-0304](0304-identity-and-authorization.md). So the admin console does not fail when the product authorization plane fails |
| Identity | Oathkeeper forwards the authenticated identity as a header, and Lowdefy exposes it to pages |
| Fine-grained authorization | `Checker` calls inside **the service APIs that the pages call** enforce it. The admin tool owns no RBAC of its own |

### Repository layout

```text
apps/admin/
├── lowdefy.yaml       # root config: connections, page index, theme
├── pages/             # hand-written pages not tied to one service
├── custom/<service>/  # hand-written pages the generator cannot express
└── _generated/        # tools/admin-gen output, committed, drift-checked, never edited
    ├── pages.yaml     # page index: hand-written first, then generated
    └── <service>/
        ├── <resource>.yaml    # one CRUD page per x-admin: crud tag
        └── <operationId>.yaml # one action page per x-admin: action operation
```

`apps/admin/` is the second application under `apps/`. [ADR-0101](0101-monorepo.md) requires an ADR for it, and this is that ADR. The server itself deploys from its platform chart. `apps/admin/` holds only the configuration mounted into it.

### Generation from the spec

`tools/admin-gen/` generates pages from the service specs. Two markers drive it:

| Marker | Placed on | Produces |
| --- | --- | --- |
| `x-admin: crud` | a tag | one CRUD page with a list table. It adds a create form where a collection `POST` returns **201**. It adds an edit form where `PUT` exists, and a delete control where `DELETE` exists |
| `x-admin: action` | an operation | one action page, with inputs for path parameters and the request body, and a button that calls the endpoint |

An async `202` create is a workflow trigger, not a form to scaffold. So a resource with an async create stays list-only.

The generator emits **only REST-connector pages**, and each page calls its service in-cluster. It never generates direct-database pages. Pages use raw spec paths, so the output does not depend on the edge prefix. The output is deterministic, committed, and drift-checked. `mise run gen:admin` runs it inside `mise run gen`.

The `x-admin` markers are specification extensions. So they are stripped from the rendered developer portals and never leak into public docs.

The spec already describes every resource. So a page that needs shaping beyond the generator can be scaffolded by hand under `custom/`, directly from the spec. Neither a human nor an LLM needs to learn React.

### Connections

| Kind | Purpose | Credentials |
| --- | --- | --- |
| REST, one per service | **the write path.** Auth is the user's session, which the edge forwards as identity headers | none |
| Postgres, one per service database | **read-only.** Views that the REST API cannot serve: cross-table joins for diagnostics, and raw inspection | read-only roles. The operator materialises them from SOPS-encrypted files, per [ADR-0202](0202-secrets.md) |

### What would change this decision

| Change | Effect |
| --- | --- |
| A frontend team edits the admin surface | **Decisive.** Driver 4 is a claim about who makes the edit. If those people write React every day, the `(admin)` route group wins on every other driver |
| A page needs interaction that the config format cannot express | **None, once.** `custom/` exists for this. **Decisive if it repeats**, because a config tool with a growing hand-written region is a framework with extra steps |
| Admin screens must use the design system | **Decisive.** Operator tooling is deliberately outside the design contract, per [ADR-0400](0400-frontend.md). If it moves inside, the surface belongs in the frontend app |
| Upstream stalls | **Decisive**, on the trigger in *Negative and Risks* below |
| An admin action needs to bypass a service API | **None.** The write-path invariant ranks above the tool. A mutation that the API cannot express is a missing endpoint |

### What this tool does not own

| Concern | Owner |
| --- | --- |
| Dashboards, logs, traces | Grafana, per [ADR-0500](0500-observability.md). Admin pages link out |
| External API consumers | the devportal route group, per [ADR-0400](0400-frontend.md) |
| Long-running operations | Temporal, per [ADR-0302](0302-temporal.md). Admin pages start workflows over REST. They do not orchestrate them |

## Consequences

### Positive

- Admin pages are files in the same repo. They are reviewed in PRs, and `git blame` works on them.
- Authoring with an LLM is the easiest path, not a workaround.
- Backend and platform engineers make small admin changes without touching React.
- One stateless container: no datastore, no operator, and no new auth integration.
- The contract work gives admin pages for free. A new service gets coverage when it ships a spec.
- Service boundaries hold, because admin actions go through REST and not around it.

### Negative and Risks

- **Lowdefy's community is the smallest of any component on the floor.** If upstream stalls, the platform owns a server with YAML configs. The configuration is declarative and portable, so the lock-in is the runtime and not the data. But the pages are the smaller half of the loss. The larger half is the operator habits built on them, and those habits transfer to nothing.

**The fallback has a name, and it is the runner-up.**

| Field | Value |
| --- | --- |
| **Trigger** | upstream releases stop for two quarters, or a security advisory against the runtime gets no answer for one quarter |
| **Seam** | ✓ the `(admin)` route group in the existing frontend, with its cost in *Considered options* above. The write path does not change, because both authoring surfaces call the same service APIs. The generated CRUD pages are generated again, not ported |
| **Cost if adopted late** | every hand-written custom page is rewritten in React once. The surface moves from an ops-tier origin into the product app. [ADR-0306](0306-trust-tiers-and-urls.md) treats that as a tier change, not a move |

So the weakest dependency on the floor is a **deferral, not a bet**. The alternative exists, it is first-party, and it is already compared.

- **No compile-time type safety between a spec change and a page.** The generator and the drift check keep generated pages in step. Only review and runtime errors on first load catch problems in hand-written pages.
- **Read-only Postgres connections are a discipline risk**, because an engineer could try to add a mutation behind them. Enforcement at the database-role level mitigates this, not convention.
- **The generated directory makes PR diffs larger** on spec changes. The same committed and drift-checked convention as every other generated artifact mitigates this. Generated pages are plain by design. Anything richer is a custom page.
- **It is a Node island**, per [ADR-0100](0100-language-and-runtime.md). It is installed and run, not built, so upstream chooses the runtime. It stays inside this app's image and its optional local tasks.

## Rules

- The internal admin tool is Lowdefy, self-hosted and deployed through Helm and Argo CD.
- Admin pages live as YAML in `apps/admin/`. The generated directory is never edited by hand. `(CI: ci:gen)`
- **Every admin mutation goes through the service Go API, never raw SQL.**
- Direct Postgres connections, both Lowdefy's and pgweb's, are read-only. They are used only for inspection that the REST API cannot serve, and the database role enforces read-only.
- Lowdefy's built-in auth and sessions are not used, and no datastore is deployed for it.
- The admin console is served on its own ops-tier origin behind the forward-auth. Fine-grained authorization is the `Checker` call inside the service APIs that the pages call.
- The spec markers determine the generated pages. A service with neither marker gets no generated pages. `(CI: lint:openapi)`
- `apps/admin/` is the only first-party application under `apps/` besides the frontend. A third one requires its own ADR.
- Lowdefy is pinned to a specific release tag. `(CI: lint:floating-tags)`
