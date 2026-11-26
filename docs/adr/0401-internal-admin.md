# ADR-0401: Internal Admin Tool

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0110](0110-language-and-runtime.md), [ADR-0111](0111-monorepo.md), [ADR-0201](0201-gitops.md), [ADR-0300](0300-data.md), [ADR-0302](0302-temporal.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0304](0304-identity-and-authorization.md), [ADR-0306](0306-trust-tiers-and-urls.md), [ADR-0400](0400-frontend.md), [ADR-0500](0500-observability.md)
- **Decides:** A first-party console renders the admin pages from the specs, and every admin mutation goes through the Go API, not raw SQL.

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

1. **Declarative over imperative.** An admin page is a marker in a spec, so a page edit is a file edit, per principle 1 of [ADR-0000](0000-platform-foundations.md).
2. **REST through services, never direct SQL.** Admin convenience does not bypass service boundaries.
3. **Generated from the spec.** The specs describe every resource, so the pages come from them.
4. **A small change costs a small amount of work for the person who makes it.** Backend and platform engineers edit admin screens between other work. A frontend team does not. The cost of an edit is what the editor must learn again, not the language.
5. **Zero new auth surface.** The edge authenticates, and the tool trusts the upstream identity header.
6. **One stateless container.** No new database and no new operator.
7. **One toolchain.** The console builds and runs with the Bun install and the Node.js runtime of every other workspace, per [ADR-0110](0110-language-and-runtime.md).

## Considered options

| Option | 1 Authoring surface | 7 Toolchain | Verdict |
| --- | --- | --- | --- |
| **A first-party console that renders a manifest of the specs** | **the `x-admin` markers in each spec** | **a member of the root Bun workspace, on Node.js** | **Chosen.** A new page is a marker, and the generic pages hold every form, table, and action. The console reuses the stack of the frontend, so it adds no runtime and no package manager |
| Lowdefy | YAML pages, generated from the same markers | its CLI stops unless `pnpm` is on `PATH`, at build and at start | Rejected on driver 7. It needs a second package manager and its own dev shell. Its community is the smallest of any candidate |
| An `(admin)` route group in the existing frontend | React, in the app that already exists | the frontend's | Rejected. Every screen is React written by hand, against driver 4. It also puts an operator surface inside the product origin, against [ADR-0306](0306-trust-tiers-and-urls.md) |
| Refine, react-admin | React | the frontend's | Rejected on driver 4. A small change lands in hooks and providers |
| Appsmith | positional widget-tree JSON | its own server | Rejected. A diff cannot show it for review, and an LLM cannot edit it |
| Windmill | scripts and a YAML app definition | its own server | Rejected. It is a workflow and job platform first, and it puts a second execution engine next to Temporal, per [ADR-0302](0302-temporal.md) |
| ToolJet, Budibase, Retool | authored in the UI | their own servers | Rejected on the authoring model. Retool also fails principle 3 |
| NocoDB, Directus | UI-first database tools | their own servers | Rejected. Driver 2 forbids the direct-SQL shape that they do best |

Sources:

- [Lowdefy](https://docs.lowdefy.com/), [Appsmith](https://docs.appsmith.com/), [Budibase](https://docs.budibase.com/), [ToolJet](https://docs.tooljet.com/), [react-admin](https://marmelab.com/react-admin/).

### The read-only database inspector

| Option | Shape | 2 Read-only enforcement | Verdict |
| --- | --- | --- | --- |
| **pgweb** | a single Go binary | the `--readonly` flag, and a read-only database role | **Chosen.** It is one stateless container like the console, with two independent read-only layers *(reasoned)* |
| pgAdmin | a stateful Python application | none, because it is a full client | Rejected. It offers write access that the role must then remove |
| CloudBeaver | a Java server | at the connection level | Rejected. A heavier runtime, for features that break-glass does not use |
| `psql` through `talosctl` and a pod | none | the role only | Always available, and the real fallback. It is not a UI |

Sources:

- [pgweb](https://github.com/sosedoff/pgweb), [pgAdmin](https://www.pgadmin.org/).

## Decision

### The write-path invariant

**Every admin mutation goes through the service's Go API, never through raw SQL.** This is load-bearing, and the tool choice comes second to it.

The API does three things, per [ADR-0304](0304-identity-and-authorization.md) and [ADR-0302](0302-temporal.md):

- it enforces domain invariants
- it does the **dual write to OpenFGA**
- it can trigger a workflow

A raw-SQL write bypasses all three. The authorization store falls out of sync with the application database, and every invariant the service guarantees is skipped.

The invariant applies to both tools:

- **The console calls only the service APIs.** It has no database connection.
- **pgweb and `psql` speak only raw SQL**, so they are never the write path. They are break-glass **inspectors** that run SELECTs during an incident. They are read-only **at the database-role level**, not by convention.

### Deployment

| Property | Value |
| --- | --- |
| Chart | `infra/helm/platform/admin/`, reconciled by Argo CD |
| Shape | one stateless Next.js server on Node.js, with no persistent volume |
| Datastore | **none** |
| Origin | `admin.ops.<host>`, per [ADR-0306](0306-trust-tiers-and-urls.md). It is its own ops-tier origin behind the forward-auth, never a product path |
| Coarse gate | the `operator` claim and AAL2, with **no authz call**, per [ADR-0304](0304-identity-and-authorization.md). So the console does not fail when the product authorization plane fails |
| Identity | Oathkeeper forwards the authenticated identity as a header, and the console shows it |
| Service calls | from the console server to each service, east-west on its server port. The browser never calls a service |
| Fine-grained authorization | `Checker` calls inside **the service APIs that the pages call** enforce it. The console owns no RBAC of its own |

### Repository layout

```text
apps/admin/
├── _generated/
│   └── manifest.json   # `tabkit gen admin` output, committed, drift-checked, never edited
└── src/
    ├── app/            # the dashboard, one generic page route, and one Server Action
    └── lib/            # the manifest types, the service client, and the form helpers
```

`apps/admin/` is the second application under `apps/`. [ADR-0111](0111-monorepo.md) requires an ADR for it, and this is that ADR.

### Generation from the spec

`tabkit gen admin` writes one manifest from the service specs. Two markers drive it:

| Marker | Placed on | Produces |
| --- | --- | --- |
| `x-admin: crud` | a tag | a list page. It adds a create page where a collection `POST` returns **201**, and an edit page where `PUT` or `DELETE` exists |
| `x-admin: action` | an operation | an action page, with inputs for path parameters and the request body, and a button that calls the endpoint |

An async `202` create is a workflow trigger, not a form. So a resource with an async create stays list-only.

The manifest names each page, its service, its calls, and its fields. A `Money` property becomes an amount field and a currency field. The output is deterministic, committed, and drift-checked. `just gen-admin` runs it inside `just gen`.

The `x-admin` markers are specification extensions. So they are stripped from the rendered developer portals and never leak into public docs.

A view that the generator cannot make, such as the dashboard across services, is a hand-written page of the console.

### What would change this decision

| Change | Effect |
| --- | --- |
| A frontend team edits the admin surface | **Decisive.** Driver 4 is a claim about who makes the edit. If those people write React every day, the `(admin)` route group wins on every other driver |
| Hand-written pages grow past the generated ones | **Decisive.** A console of mostly hand-written pages is a second frontend, and it belongs in the frontend app |
| Admin screens must use the design system | **Decisive.** Operator tooling is deliberately outside the design contract, per [ADR-0400](0400-frontend.md). If it moves inside, the surface belongs in the frontend app |
| An admin action needs to bypass a service API | **None.** The write-path invariant ranks above the tool. A mutation that the API cannot express is a missing endpoint |

### What this tool does not own

| Concern | Owner |
| --- | --- |
| Dashboards, logs, traces | Grafana, per [ADR-0500](0500-observability.md). Admin pages link out |
| External API consumers | the devportal route group, per [ADR-0400](0400-frontend.md) |
| Long-running operations | Temporal, per [ADR-0302](0302-temporal.md). Admin pages start workflows over REST. They do not orchestrate them |

## Consequences

### Positive

- A new service gets admin pages when it ships a spec with markers. No page code changes.
- Backend and platform engineers make small admin changes in the spec, without touching React.
- The console builds, tests, and runs with the toolchain of the frontend. It adds no package manager, no dev shell, and no runtime.
- One stateless container: no datastore, no operator, and no new auth integration.
- Service boundaries hold, because admin actions go through REST and not around it.

### Negative and Risks

- **The platform owns the console code.** A form or table bug is a bug in every generated page at once. Unit tests cover the form helpers, and the e2e suite drives each kind of page, per [ADR-0601](0601-testing-strategy.md).
- **The generic pages are plain by design.** A page that needs more is a hand-written page, and it is React.
- **The generated manifest makes PR diffs larger** on spec changes. The same committed and drift-checked convention as every other generated artifact mitigates this.

## Rules

- The admin console is the first-party app in `apps/admin/`, deployed through Helm and Argo CD.
- The console renders the pages of `apps/admin/_generated/manifest.json`. The manifest is never edited by hand. `(CI: ci-gen)`
- **Every admin mutation goes through the service Go API, never raw SQL.** The console has no database connection.
- pgweb connects with a read-only database role. It is used only for inspection that the REST API cannot serve.
- The console has no auth or session store of its own, and no datastore is deployed for it.
- The admin console is served on its own ops-tier origin behind the forward-auth. Fine-grained authorization is the `Checker` call inside the service APIs that the pages call.
- The spec markers determine the generated pages. A service with neither marker gets no generated pages. `(CI: lint-openapi)`
- `apps/admin/` is the only first-party application under `apps/` besides the frontend. A third one requires its own ADR.
