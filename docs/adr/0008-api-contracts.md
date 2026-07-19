# ADR-0008: API Contracts & Codegen

- **Status:** Accepted
- **Date:** 2026-07-06
- **Deciders:** Platform team
- **Related:** [ADR-0001](0001-language-and-runtime.md), [ADR-0009](0009-api-gateway.md), [ADR-0017](0017-url-and-domain-structure.md), [ADR-0022](0022-api-lifecycle.md)

## Context

Services expose APIs to three consumer groups:

1. **The Next.js frontend** ([ADR-0002](0002-monorepo.md)) — browser-side.
2. **Other internal services** — service-to-service via HTTP ([ADR-0006](0006-temporal.md)).
3. **Third-party / public API consumers** — external developers who require stable, documented contracts.

Identity is validated at the edge by Ory Oathkeeper ([ADR-0009](0009-api-gateway.md)) and workflow orchestration is Temporal ([ADR-0006](0006-temporal.md)).

We need:

- A single **source of truth** for every API surface.
- **Generated code** in both Go (server stubs and internal clients) and TypeScript (frontend client). No hand-written request/response types on either side.
- **Schema validation in the service**, generated from the same artifact — no hand-maintained validators.
- A workflow strict enough that contract drift cannot survive code review or CI.
- Coverage for streaming use cases (SSE common; bidirectional rare but possible).

Wire efficiency for internal calls is explicitly **not** a priority. JSON over HTTP everywhere. Operational simplicity, browser-friendliness, gateway-friendliness, and human-debuggability win over binary-protocol throughput at our scale.

## Decision drivers

1. **One contract, two languages.** Go server + TS client from the same artifact.
2. **Single validation surface.** One generated validator in the service, driven by the spec — no parallel edge-validation config to keep in sync.
3. **Public API readiness.** Third-party consumers expect OpenAPI docs and SDKs.
4. **Browser fit.** No special proxies, no Envoy sidecars, no `grpc-web`.
5. **Spec-first, enforced.** The spec leads. CI fails if generated code is stale or hand-written types shadow generated ones.

## Considered options

- **OpenAPI 3.1 + `ogen` + `openapi-typescript` + `openapi-fetch`** — one spec drives Go server, Go client, TS client, public docs, downloadable SDKs.
- **gRPC + `grpc-web`** — browsers need an Envoy/Connect proxy and lose streaming semantics; public consumers expect OpenAPI anyway.
- **Connect-RPC (Buf)** — speaks HTTP/JSON and gRPC simultaneously, but adds an RPC framework where plain OpenAPI/JSON already satisfies our browser, service, and public consumers. Revisit only if a binary-protocol need emerges.
- **GraphQL** — wrong fit for service-to-service and public-API consumers; gateway features are harder; adds a query planner an 8-person team cannot afford.
- **tRPC** — TS-only; our backend is Go.

## Decision

**The API contract source of truth is OpenAPI 3.1.** One spec per **HTTP service** at `services/<service>/openapi.yaml` — every service that serves HTTP is spec-first and generates its server with ogen, with no per-service opt-out. Each spec is **fully self-contained**: cross-service shapes (the error envelope, common ID/time types, the workflow handle from [ADR-0006](0006-temporal.md)) are declared in the spec's own `components` rather than imported from a shared `api/shared/` namespace by cross-file `$ref`. Keeping each spec self-contained (no external file references) makes specs portable across the codegen and linting tools and removes any cross-file resolution step, so these shapes are duplicated by convention and kept identical across services.

**The rule is mandatory and scoped to HTTP surfaces — no per-service exemptions.** Every service that serves HTTP ships an `openapi.yaml` and implements the ogen-generated `Handler`, including east-west control-plane services. The `authz` service ([ADR-0010](0010-auth.md)) owns no database and sits behind Oathkeeper rather than the `/api` edge, yet it is spec-first like any other: its `/authorize` decision endpoint (a policy decision point — 200 allow, 403 deny, modelled as a two-variant response) and its `/operators` action are ogen operations. OpenFGA remains the source of truth for the *authorization model* (which relations exist); the spec is the source of truth for authz's *HTTP contract* (the request/response shapes over the wire) — the two describe different things and do not compete. This uniformity is deliberately worth more than the few unused artifacts it produces — ogen also emits an authz Go/TS client that no caller imports — because it buys one mental model, one toolchain, and tooling (admin-gen, linters, drift-check) that can assume a spec always exists. The only services without a spec are those with no HTTP surface at all (pure workers); `mise run gen` discovers specs by glob (`services/*/openapi.yaml`).

### Server URL & paths: flat resource namespace

Each spec's `servers` entry is the **shared flat prefix — `url: /api`** — and its paths are **globally-unique resource
nouns** (`/products`, `/orders`, `/charges`), so the exposed URL is `<host>/api/<resource>` with no service segment
([ADR-0017](0017-url-and-domain-structure.md)). The service that owns a resource is a hidden edge-routing detail, not part
of the URL. Because all specs share one `/api` namespace, two `x-audience`-exposed specs must not claim the same top-level
resource prefix; the vacuum lint fails on a collision. East-west, service-to-service endpoints (declared under
`servers: /`) bypass the edge ([ADR-0009](0009-api-gateway.md)) and are not part of the `/api` surface.

The API is **not versioned in the URL**: single-live-version by default, an `Api-Version` header only when online
versioning is flagged on ([ADR-0022](0022-api-lifecycle.md)) — which is precisely why the flat resource URL is stable.

### Codegen

| Output                      | Tool                                                   | Location                                               |
|-----------------------------|--------------------------------------------------------|--------------------------------------------------------|
| Go server + client + types  | `ogen` (type-safe, OpenTelemetry-instrumented)         | `libs/go/sdks/<service>/`                              |
| TS client                   | `openapi-typescript` + `openapi-fetch` (~6 KB runtime) | `libs/ts/sdks/<service>/`                              |
| Public SDKs                 | OpenAPI Generator                                      | published per-language as third-party consumers arrive |

All generated artifacts are committed to the repo and drift-checked in CI per [ADR-0002](0002-monorepo.md).

### Workflow

1. API change is a PR to `services/<service>/openapi.yaml`.
2. CI runs **vacuum** lint with the repo ruleset at `tools/codegen/openapi-ruleset.yaml` (style + breaking-change detection).
3. `mise run gen` regenerates Go server, Go client, and TS client.
4. CI fails if generated files are out of date (`git diff --exit-code`).
5. Hand-written code imports generated types and never declares parallel ones.

### Validation

- **The service** validates request schemas via `ogen`'s generated server, which decodes and validates every request into typed Go values. The validator is generated from the same spec; it costs nothing to maintain.
- **The service** owns all **business-rule** validation (ownership, limits, state transitions, idempotency).

Schema validation is **service-side only.** The edge ([ADR-0009](0009-api-gateway.md)) does not validate request bodies — internal service-to-service calls bypass it anyway, so the service is the one place that sees every request. `ogen`'s generated validator makes a second edge-validation layer redundant rather than defense-in-depth.

### Streaming

- **Server-Sent Events (SSE)** is the default for server→client push. Declared in OpenAPI as `text/event-stream` responses; Traefik passes through.
- **Server-streaming over HTTP/2** is used only when SSE is awkward (binary frames, very high throughput). Declared with a chunked-transfer response, documented per-endpoint.
- **WebSockets** for bidirectional streaming. Documented in `services/<service>/README.md` with a JSON-Schema for message envelopes. Treated as a deliberate exception: each WS endpoint needs a one-line justification in the README.
- Traefik handles WS upgrades. gRPC and Connect are not introduced for streaming.

### Authoring layer

OpenAPI YAML is hand-written. **TypeSpec is not used.** If a service's spec grows unwieldy, the response is to split the service or factor shapes into more `components` within the same file (possibly splitting the service), not to introduce a second authoring tool.

### API audience & visibility

The one spec per service is the source of truth, but not every service or operation is meant for every consumer group (the three from *Context*). A single label — `x-audience` — classifies the surface so the developer portals ([ADR-0009](0009-api-gateway.md)) render **filtered projections** of the same specs rather than separate hand-maintained documents.

**`x-audience` is one ordered ladder** — a widening audience boundary, *service-to-service → first-party edge → third-party edge*:

| value | meaning | edge-reachable? |
|---|---|---|
| `cluster` | east-west, service-to-service, in-cluster only (gated by NetworkPolicy) | no — bypasses the edge |
| `internal` | first-party edge surface — our own frontend/admin/tools, curated out of public docs | yes, `/api` |
| `public` | third-party edge surface — the contract outsiders may see | yes, `/api` |

The label is set on `info` as the **service default** and may be **overridden per operation** (an operation's `x-audience` wins, else the service default, else the fail-closed `cluster`). So a mostly-`public` service can mark one write op `internal` (edge-reachable, kept out of public docs), and an otherwise-edge service can mark an east-west webhook `cluster`. It **defaults to `cluster`** — fail-closed: a spec is never treated as edge-reachable, let alone public, unless it says so. (An east-west control-plane service like `authz` still carries a spec — see *Decision* — but with an all-`cluster` audience, so it appears in no portal and claims no `/api` surface.)

The field follows Zalando's `x-audience` convention; the three values are our own simplification of Zalando's enum, and folding operation-level visibility onto the *same* axis replaces the separate Redocly-style `x-internal` flag — one ladder, no second label to reconcile.

**`x-audience` is documentation scoping, not access control.** Withholding an operation from a rendered spec does not protect it: exposure is decided solely by the edge route and Oathkeeper ([ADR-0009](0009-api-gateway.md)) — a service with no IngressRoute (`ingress.enabled: false`) is unreachable from the internet whatever its spec says. The two must not drift, so a CI check ties the ladder to real exposure: a service is edge-exposed **iff** it has at least one `internal`/`public` operation, and a `cluster`-only service must have no `/api` route. That pair — `x-audience: cluster` plus no `/api` edge route — defines an east-west endpoint ([ADR-0017](0017-url-and-domain-structure.md)); such endpoints never appear in either portal.

## Consequences

### Positive

- One artifact powers server, internal client, frontend client, docs, and public SDKs. Per-service contract cost is roughly fixed regardless of how many consumers exist.
- Browser, third-party, and service-to-service consumers all see the same API shape; no protocol-translation layer.
- Schema-level validation is generated, not written — one validator per service, no hand-maintained duplication.
- Public API readiness is a CI artifact, not a project.

### Negative / Risks

- OpenAPI is awkward for complex discriminated unions and conditional schemas. Mitigated by vacuum ruleset rules enforcing flat schemas; complex polymorphism is a hint that the API surface is too coupled.
- Streaming story is pragmatic, not unified. Mitigated by per-WS-endpoint justification and acceptance that gRPC/Connect are not adopted for this alone.
- Cross-service shapes (error envelope, workflow handle) are duplicated across specs because each spec is kept self-contained (no external `$ref`s). Mitigated by their small, stable surface; a future bundler step could restore a single source if drift becomes a problem.

### Follow-ups

- The `mise run gen:*` task family (wrapping the `scripts/gen-*.sh` generators).
- `tools/codegen/openapi-ruleset.yaml` ruleset.
- Shared shapes (error envelope, workflow handle) declared inline in each `services/<service>/openapi.yaml` `components` block.
- A CI lint (`mise run lint:api-resources`) enforcing the flat-namespace invariant: no two `x-audience`-exposed specs
  claim the same top-level resource prefix, and each exposed prefix has a matching `ingress.resources` entry
  ([ADR-0017](0017-url-and-domain-structure.md)).
- A `mise run gen:openapi-public` projection task emitting the merged docs bundles the Scalar-rendered portals consume
  ([ADR-0009](0009-api-gateway.md), [ADR-0014](0014-frontend.md)): the dev-portal bundle keeps operations at audience
  `>= internal`, the public-docs bundle keeps only `public` — a threshold on the ladder, resolved per operation.
- **Implemented:** `mise run lint:api-audience` (`tools/lint-api-audience`) enforces the audience↔exposure invariant —
  a service is edge-exposed iff it has an `internal`/`public` operation (resolving each op's audience against the service
  default), and a `cluster`-only service has no `/api` route (`ingress.resources`, read from the canonical dev values);
  an all-`cluster` service like authz satisfies this trivially — it has a spec but no edge-exposed operation.
- Lefthook pre-commit hook running the affected generator slice.
- CI drift-check job per [ADR-0002](0002-monorepo.md).

## Rules

- The contract source of truth is OpenAPI 3.1, one file per **HTTP service** at `services/<service>/openapi.yaml`, and every HTTP service generates its server with ogen — no per-service opt-out. East-west control-plane services are included (e.g. `authz`, [ADR-0010](0010-auth.md)): OpenFGA defines its authorization model, the spec defines its HTTP contract. Only a service with no HTTP surface ships no spec.
- An edge-exposed spec's `servers` url is the shared flat `/api`, and paths are globally-unique resource nouns — the exposed URL is
  `<host>/api/<resource>` with no service segment ([ADR-0017](0017-url-and-domain-structure.md)). Vacuum lint fails if two
  `x-audience`-exposed specs claim the same top-level resource prefix. An all-`cluster` east-west service (e.g. `authz`) instead
  uses `servers: /` and never joins the `/api` namespace. The API carries no version segment
  ([ADR-0022](0022-api-lifecycle.md)).
- Each spec is self-contained: cross-service shapes (error envelope, workflow handle) are declared inline in the spec's `components` and kept identical across services. Cross-file `$ref` is avoided to keep specs portable across the codegen and linting tools.
- Every spec declares `info.x-audience` on the ordered ladder `cluster` | `internal` | `public` (default `cluster`); an operation may override it. It is documentation scoping, not access control.
- Exposure is enforced independently by the edge route + Oathkeeper ([ADR-0009](0009-api-gateway.md)); a CI check (`lint:api-audience`) ties the ladder to reality — a service is edge-exposed iff it has an `internal`/`public` operation, and a `cluster`-only service has no `/api` route.
- All clients and server stubs are generated from the spec and committed. CI fails on drift.
- Hand-written code imports generated types. Parallel hand-written request/response types are forbidden.
- The service validates request schemas from the OpenAPI artifact via the generated `ogen` server. There is no separate edge validation.
- Business-rule validation lives only in the service, never at the edge.
- Server-Sent Events is the default streaming mechanism. WebSockets require a per-endpoint justification in the service README.
- gRPC, Connect-RPC, GraphQL, and tRPC are not used.
- OpenAPI YAML is hand-written. TypeSpec and equivalent authoring layers are not used.
- A spec change is a PR; merging is blocked on vacuum lint passing and on `mise run gen` producing no diff.
