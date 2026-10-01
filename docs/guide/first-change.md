# Your first change

[`reading-path`](../reading-path.md) helps you understand the platform. This guide takes you to a merged pull request.

It walks one change, **adding a field to a service**, through every gate that the change passes. The change is small on purpose, because the field is not the point. A two-line edit to an OpenAPI file touches eight mechanisms. The platform is fast to work in when you know which mechanism reports to you.

**What you need first:** a local floor. Run `mise run cluster:up`. If the floor does not start, read [`../dev-loop.md`](../dev-loop.md).

## The change

`catalog` serves products. You add a `restock_at` timestamp to the product resource. It is readable on `GET`, writable on `PUT`, and stored.

## 1. The contract, first and always

Edit `services/catalog/openapi.yaml`. Edit nothing else yet.

```yaml
    restock_at:
      type: string
      format: date-time
      description: When the next restock is expected.
```

**The spec is the source, not a description of the code.** Handlers, clients, and validators are generated from this file. So a field that is not in the spec does not exist, per [ADR-0303](../adr/0303-api-contracts-and-lifecycle.md).

Three rules bind that field, and a gate checks each one:

| Rule | Why | Gate |
| --- | --- | --- |
| Timestamps are RFC 3339, UTC, with a literal `Z` | one wire format. An offset other than `Z` is rejected, not converted, per [ADR-0003](../adr/0003-naming-and-identifiers.md) | `lint:openapi` |
| Property names are `snake_case` | each surface has one fixed wire casing | `lint:openapi` |
| Shared shapes come from `tools/codegen/shared-components.yaml` | timestamps, identifiers, and the error envelope are identical across specs, because they are one file, not five copies | `lint:openapi` |

**If the field holds money, stop and read [ADR-0003](../adr/0003-naming-and-identifiers.md) before you type.** A money field of type `number` is a contract defect, because the generated TypeScript client parses it as a double. Use a `string` that carries a decimal, backed by Postgres `numeric`.

## 2. Generate

```sh
mise run gen
```

This rewrites three trees from the edited spec:

- `libs/go/sdks/catalog/`: the ogen server interface, with validation compiled into the decoder, and the Go client that other services call through
- `libs/ts/sdks/catalog/`: the TypeScript client that the frontend calls through
- `apps/admin/_generated/`: the Lowdefy CRUD pages

**Generated code is committed**, per principle 9 of [ADR-0000](../adr/0000-platform-foundations.md). Commit it in the same pull request as the spec change. Nobody edits, lints, or formats it by hand. If the output is wrong, the input is wrong.

Your build now fails, and that is the mechanism at work. ogen widened the server interface, so the compiler shows the handler that lacks the field.

## 3. Migration

```sh
cd services/catalog
dbmate --migrations-dir migrations new add_restock_at
```

Write the `up` and the `down`. The SQL you write is the SQL that runs. No schema DSL sits between you and the database, per [ADR-0300](../adr/0300-data.md).

```sql
ALTER TABLE products ADD COLUMN restock_at timestamptz;
```

Use `timestamptz`, never `timestamp`. A column that holds personal data also needs its class in this same migration. The creating migration is the only place that records this fact:

```sql
COMMENT ON COLUMN products.owner_email IS 'pii:contact';
```

`lint:sql` checks both.

## 4. Query and handler

Add the column to the sqlc query, regenerate, and then wire the handler. Two rules apply here. The code around them does not show either one:

- **No cross-service import.** If `restock_at` needs data from `orders`, the data arrives through the generated client, never as a Go import, per [ADR-0101](../adr/0101-monorepo.md). `depguard` fails the build on such an import.
- **Errors use the platform envelope**, not a custom shape. Return the RFC 9457 problem type. `libs/go/observability` fills `trace_id` from the active span, so your handler does not, per [ADR-0303](../adr/0303-api-contracts-and-lifecycle.md).

An authz-relevant change belongs in a Temporal workflow, not in a bare store method. An example is a field that decides who can see a resource. The database write and the OpenFGA tuple write must succeed or fail together, per [ADR-0302](../adr/0302-temporal.md) and [ADR-0304](../adr/0304-identity-and-authorization.md).

## 5. Run it

```sh
mise run db:migrate
mise run server                     # terminal 1
mise run service:dev -- catalog     # terminal 2, once
```

Then call it through `https://dev.localtest.me:8443/api/products`, not through the port directly. **A curl to the port sends your service forged identity headers.** A request that works on the port and fails through the edge is the most common local surprise, per [`../dev-loop.md`](../dev-loop.md).

## 6. What the pull request runs

Nine gates, in the order in which they fail:

| Gate | Rejects | Where |
| --- | --- | --- |
| `ci:gen` | generated trees that do not match your spec. This is the drift check | before anything else is worth reading |
| `lint:openapi` | casing, timestamp format, a divergent shared component, a missing `example` on a 2xx response | the spec |
| `lint:service-contract` | a resource prefix that collides with one from another service | the spec |
| `oasdiff` | a breaking change. It **labels** the pull request and does not block it | the spec, against `master` |
| `lint:sql` | a `timestamp` where `timestamptz` belongs, a PII column without a tag | the migration |
| `lint:api-audience` | a route exposed at the wrong audience | the spec and the edge config |
| `ci:lint` | everything else: Go, TypeScript, Markdown, shell | the whole diff |
| `ci:affected` | nothing. It **selects** what the rest of CI runs | the diff |
| `ci:test` | unit and integration tests for the selected services | the selection |

**Understand `ci:affected` above all.** It reads your diff and decides which services CI exercises. Nothing tests a change that it does not select. That is a known and accepted risk, not a bug, per row 8 of [`../reference/risk-register.md`](../reference/risk-register.md). A change can be subtle, for example in a shared library, a chart value, or a generated tree. Then check that the affected output lists the services you expect.

**Add the `e2e` label if your change touches more than one service.** The full browser suite runs nightly. Without the label, a cross-service regression stays in `master` until the morning, per [`../reference/build-path.md`](../reference/build-path.md).

## 7. What review is for

A machine enforces most rules here. Review exists for the rules that no machine checks. A reviewer reads for these four classes:

- **A secret in a committed file.** This is the one defect that survives its own fix. A revert of the file leaves the secret in history, so the fix is a rotation.
- **A missing authorization check**, or an authz-relevant write outside a workflow.
- **A rule enforced at the wrong layer.** An example is a rule in a CI lint that a `kubectl apply` bypasses, per [ADR-0203](../adr/0203-policy-enforcement.md).
- **A comparison that a decision needs and does not have.** If your change adopts a tool, [ADR-0002](../adr/0002-tool-adoption.md) states what the change must include.

A machine already checks everything else.

## What you did not have to do

The dense rules above buy you these savings:

- No version to bump. Releases use CalVer over the repository, computed at release time, per [ADR-0103](../adr/0103-release-and-versioning.md).
- No client to write by hand, in either language, and no admin page to build.
- No chart to edit. The service chart is shared and takes values, per [ADR-0201](../adr/0201-gitops.md).
- No environment to configure. Local, dev, staging, and production use the same chart with different values, per [ADR-0205](../adr/0205-environment-parity.md).
- No deploy step. A merge to `master` is the deploy. Argo CD reconciles it.

## When the change is bigger than a field

| The change | Read first |
| --- | --- |
| A new service | the six decomposition forces of [ADR-0000](../adr/0000-platform-foundations.md). A new service names the force that justifies it |
| A new platform component | the budget rule in [`../operational-surface.md`](../operational-surface.md), then [ADR-0002](../adr/0002-tool-adoption.md) for the comparison it needs |
| A breaking API change | [ADR-0303](../adr/0303-api-contracts-and-lifecycle.md). `oasdiff` labels it, and the ADR states what to do about the label |
| Anything that binds more than one service | an ADR. Start from [`../adr/_template.md`](../adr/_template.md) |
