# ADR-0303: API Contracts, Codegen and Lifecycle

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0003](0003-naming-and-identifiers.md), [ADR-0100](0100-language-and-runtime.md), [ADR-0101](0101-monorepo.md), [ADR-0103](0103-release-and-versioning.md), [ADR-0302](0302-temporal.md), [ADR-0305](0305-edge-auth-and-traffic-policy.md), [ADR-0306](0306-trust-tiers-and-urls.md), [ADR-0400](0400-frontend.md), [ADR-0500](0500-observability.md)
- **Decides:** Hand-written OpenAPI 3.1 is the contract source of truth, and every HTTP service implements the handler generated from it.

## Context

Services expose APIs to three consumer groups:

| Consumer | Transport | Upgrade coupling |
| --- | --- | --- |
| The Next.js frontend, per [ADR-0400](0400-frontend.md) | browser to edge | ships in the same commit and release |
| Other services | in-cluster HTTP | ships in the same release |
| Third parties | edge, when a public API is flagged on | cannot be forced to upgrade |

The platform needs these things:

- one source of truth per API surface
- generated code in Go and TypeScript
- generated request validation
- a workflow in which contract drift cannot pass CI
- coverage for streaming
- a rule for how a live contract changes

Wire efficiency for internal calls is not a priority. JSON over HTTP is used everywhere. Operational simplicity, browser support, gateway support, and human debugging rank above binary-protocol throughput.

## Decision drivers

1. **One contract, two languages.** The Go server and the TS client come from the same artifact.
2. **A request is validated once.** Two validators disagree at some point, and the disagreement is the bug.
3. **Public API readiness.** Third-party consumers expect OpenAPI docs and SDKs.
4. **A browser is a first-class client.** It reaches the API without an intermediary that translates the protocol.
5. **The spec and the running code cannot disagree.** Whatever is generated is derivable, so drift is detected, not discovered by accident.
6. **Version machinery matches the real consumers.** A co-shipped consumer needs none. A consumer outside the project's control needs it.

## Considered options

### Contract format

| Option | Browser | Public consumers | Cost |
| --- | --- | --- | --- |
| **OpenAPI 3.1, ogen, and openapi-typescript** | native `fetch` | docs and SDKs generated | **Chosen.** One spec drives the server, both clients, docs, and SDKs *(reasoned)* |
| gRPC and `grpc-web` | needs an Envoy or Connect proxy, and loses streaming semantics | expect OpenAPI anyway | a proxy tier plus a second IDL |
| Connect-RPC by Buf | speaks HTTP and JSON | workable | an RPC framework, where OpenAPI and JSON already satisfy every consumer. Its advantage is a binary wire format, and the Context above rules that out as a priority |
| GraphQL | good | a poor fit for service-to-service | a query planner is a platform component that the budget does not hold, per [ADR-0000](0000-platform-foundations.md) |
| tRPC | good | none | TypeScript-only, and the backend is Go |

### Version scheme, for when online versioning is flagged on

| Option | URL stability | Why not |
| --- | --- | --- |
| **Date in a request header**: `Api-Version: 2026-07-01` | flat resource URL kept | **Chosen.** REST APIs that change continuously converge on this convention. Examples are Stripe's `Stripe-Version` and GitHub's `X-GitHub-Api-Version`. One calendar covers release and contract. Azure also pins a version, but as a query parameter, not a header. That forks the URL for a caching layer and keeps the path *(documented)* |
| SemVer major in the path: `/api/v2/...` | forks the URL | It conflicts with the flat URL that hides the topology, per [ADR-0306](0306-trust-tiers-and-urls.md). Its value is the breaking signal to an independent pinner, and pin-and-sunset already gives that |
| Google AIP path-major | forks the URL | It exposes only the major and serves both from one backend. It is the same idea with a coarser label |
| Query parameter: `?api-version=` | path kept, cache key forked | Azure's shape. A version in the query string is part of the cache key and of every logged URL. A caller can easily omit it, so the default version becomes load-bearing |
| `Accept` header content negotiation | flat resource URL kept | The canonical REST answer. It overloads a header whose job is representation. Media-type versioning also works badly with generated clients: they set `Accept` for content type, not for contract age |

### Go code generation

| Option | Direction | What it generates | Where request validation lives | Verdict |
| --- | --- | --- | --- | --- |
| **ogen** | spec-first | the server itself, with typed handlers | **in the generated decoder**, from the same spec | **Chosen.** Drivers 2 and 5 follow from the design. Nothing enforces them on top of it *(reasoned)* |
| oapi-codegen | spec-first | stubs *into* chi, echo, gin, or `net/http` | an optional middleware that reads the spec at runtime | The incumbent and the closest alternative. With validation as runtime middleware, a second copy of the contract is read at request time. It is not compiled into the types |
| huma | **code-first**: the spec is emitted from Go types | the spec | struct tags | It reverses driver 5: the code becomes the source and the contract the artefact. It is right for an API with one co-shipped consumer. It is wrong when a third party pins the API |
| OpenAPI Generator | spec-first | stubs in many languages | varies by generator | A JVM toolchain, per [ADR-0100](0100-language-and-runtime.md), and its Go output is among its weakest targets. It is kept below for public SDKs, where the range of languages is the whole point |
| Hand-written handlers plus a runtime spec validator | neither | nothing | a runtime check | Nothing forces the spec and the handlers to agree, which fails driver 5 |

### The rest of the spec toolchain

Four tools read the same OpenAPI files. Each is Tier 2, per [ADR-0002](0002-tool-adoption.md): a swap changes a task, and the specs stay as they are.

| Concern | Chosen | Picked over | Why |
| --- | --- | --- | --- |
| TypeScript client | **`openapi-typescript` with `openapi-fetch`** | Kubb, orval, Hey API, a hand-written `fetch` wrapper | It emits types plus a thin typed `fetch`, and nothing else. The alternatives emit framework-specific hooks. These couple the published SDK to the frontend's data-fetching choice, so a new choice means a new client, per [ADR-0400](0400-frontend.md) *(reasoned)* |
| Spec linting | **vacuum** | Spectral, Redocly CLI, no spec lint | Spectral's rule model as a Go binary, not a Node program, per [ADR-0100](0100-language-and-runtime.md). Rules are portable between the two, so the exit is one ruleset file |
| Breaking-change detection | **oasdiff** | openapi-diff, Optic, review alone | The only option that classifies a diff as breaking or not against a rule set. The others render the diff for a human to judge. Optic covers the same ground inside a hosted workflow |
| Reference rendering | **Scalar** | Redoc, Swagger UI, Stoplight Elements | Its request console is in the open distribution, and Redoc's console is paid. A console on a different origin from the API loses the session that the developer portal exists to test, per [ADR-0306](0306-trust-tiers-and-urls.md) *(documented)* |

## Decision

The contract source of truth is **OpenAPI 3.1**, one spec per HTTP service at `services/<service>/openapi.yaml`.

### Scope: mandatory, no per-service exemption

Every service that serves HTTP ships a spec and implements the ogen-generated `Handler`. This includes east-west control-plane services. Only a service with no HTTP surface, a pure worker, ships no spec. `mise run gen` finds specs by glob.

The `authz` service of [ADR-0304](0304-identity-and-authorization.md) owns no database, and it sits behind Oathkeeper, not the `/api` edge. It is still spec-first: its `/authorize` decision endpoint and `/operators` action are ogen operations. OpenFGA is the source of truth for the authorization *model*. The spec is the source of truth for the *HTTP contract* of authz. The two describe different things.

Uniformity gives one mental model and one toolchain. It also gives tooling that assumes a spec always exists: admin-gen, linters, and the drift check. It costs a few unused artifacts: ogen emits an authz client that no caller imports. The trade favours uniformity.

### Specs are self-contained

Each spec declares the cross-service shapes in its own `components`. These shapes are the error envelope, common ID and time types, and the workflow handle of [ADR-0302](0302-temporal.md). A spec does not import them by cross-file `$ref`. With no external file reference, no resolution step is needed, and every spec stays portable across the codegen and lint tools. The shapes are duplicated across specs, and a check keeps them identical, as described below.

### The shared shapes

Each of these appears in every spec, so this ADR fixes it once. No service decides it again.

**Errors are [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457) problem details**, served as `application/problem+json`.

| Member | Value |
| --- | --- |
| `type` | `about:blank`, except where two errors share a status code and a client handles them differently. That case takes a URN, `urn:problem-type:<service>:<slug>`, never an `https` URL. A dereferenceable type puts an error taxonomy into the public URL namespace, which [ADR-0306](0306-trust-tiers-and-urls.md) keeps flat |
| `title` | a stable, human-readable summary. It does not change with the instance |
| `status` | the HTTP status, repeated in the body |
| `detail` | specific to the instance, and safe to show a user. Never a stack trace, a query, or an internal hostname |
| `instance` | omitted. `trace_id` identifies the occurrence |
| `trace_id`, an extension | the [Trace Context](https://www.w3.org/TR/trace-context/) trace-id of the failing request, per [ADR-0500](0500-observability.md). So an error that a user reports leads to its trace |
| `errors`, an extension | field-level validation failures, each a JSON Pointer and a message. The ogen-generated validator fills it |

The edge also produces errors: Oathkeeper denies a request before a handler runs, per [ADR-0305](0305-edge-auth-and-traffic-policy.md). The edge emits the same media type and the same members. So a generated client has one error branch, not two.

**Timestamps are [RFC 3339](https://www.rfc-editor.org/rfc/rfc3339) with a literal `Z`.** The wire uses `format: date-time`, always in UTC. An offset other than `Z` is rejected, not converted. Columns are Postgres `timestamptz`. A duration is an integer field named for its unit, such as `timeout_seconds`. It is not an ISO 8601 duration string, because no generator maps that string to a useful type.

**Entity identifiers are the type-prefixed UUIDv7 of [ADR-0003](0003-naming-and-identifiers.md).** Each is a `string`, and the schema declares the prefix pattern. A bare UUID on the wire is a lint failure.

The canonical fragment that keeps these identical is `tools/codegen/shared-components.yaml`. It is the source, and the copy in a spec is only a copy. `lint:openapi` fails when the two differ. The duplication is deliberate, and it is not trusted. The check makes the shapes identical as a fact, not as a habit.

### URL shape: flat resource namespace

| Property | Value |
| --- | --- |
| `servers` url, edge-exposed | `/api` |
| `servers` url, east-west only | `/` |
| Paths | globally unique resource nouns: `/products`, `/orders`, `/charges` |
| Exposed URL | `<host>/api/<resource>`, with no service segment, per [ADR-0306](0306-trust-tiers-and-urls.md) |
| Version segment | none |

The service that owns a resource is a hidden edge-routing detail. All specs share one `/api` namespace. So two edge-exposed specs must not claim the same top-level resource prefix, and vacuum lint fails on a collision.

### Codegen

| Output | Tool | Location |
| --- | --- | --- |
| Go server, client, types | `ogen`: type-safe and instrumented with OpenTelemetry | `libs/go/sdks/<service>/` |
| TS client | `openapi-typescript` with `openapi-fetch` | `libs/ts/sdks/<service>/` |
| Public SDKs | OpenAPI Generator | published per language for a consumer outside this repository |

All generated artifacts are committed and drift-checked in CI, per [ADR-0101](0101-monorepo.md).

OpenAPI YAML is hand-written. TypeSpec and equal authoring layers are not used. A spec that grows too large is a signal to split the service or to move shapes into more `components`. It is not a reason to add a second authoring tool.

### Workflow

1. An API change is a PR to `services/<service>/openapi.yaml`.
2. CI runs **vacuum** with the repo ruleset at `tools/codegen/openapi-ruleset.yaml`. It holds style and structural rules, including the resource-prefix collision check below.
3. `mise run gen` regenerates the Go server, Go client, and TS client.
4. CI fails if generated files are stale, through `git diff --exit-code`.
5. Hand-written code imports generated types and declares no parallel ones.

### Validation

Schema validation is **service-side only**. The server that `ogen` generates decodes and validates every request into typed Go values. The validator is generated from the same spec, and it costs nothing to maintain. The service also owns all business-rule validation: ownership, limits, state transitions, and idempotency.

The edge does not validate request bodies. Internal service-to-service calls bypass the edge, so the service is the only place that sees every request. A second validator at the edge is redundant, not defence in depth.

### Streaming

| Mechanism | When | Declaration |
| --- | --- | --- |
| Server-Sent Events | the default for push from server to client | a `text/event-stream` response. Traefik passes it through |
| Server-streaming over HTTP/2 | binary frames or high throughput | a chunked-transfer response, documented per endpoint |
| WebSockets | bidirectional | `services/<service>/README.md`, with a JSON Schema for message envelopes and a one-line justification per endpoint |

Traefik handles WebSocket upgrades. gRPC and Connect are not introduced for streaming.

### Audience and visibility

`x-audience` classifies each surface. The developer portals of [ADR-0400](0400-frontend.md) then render filtered views of the same specs, not separate documents maintained by hand. It is **one ordered ladder**, where each step widens the audience.

| Value | Meaning | Edge-reachable |
| --- | --- | --- |
| `cluster` | east-west, in-cluster only, gated by NetworkPolicy | no |
| `internal` | first-party edge surface, left out of public docs | yes, `/api` |
| `public` | third-party edge surface | yes, `/api` |

The value resolves in this order: the operation's `x-audience`, then the service default on `info`, then `cluster`. This default fails closed, so a spec is never treated as edge-reachable unless it says so. A mostly `public` service can mark one write operation `internal`. An otherwise edge-exposed service can mark an east-west webhook `cluster`.

The field follows Zalando's `x-audience` convention. The three values simplify Zalando's enum. Operation-level visibility uses the same axis, which replaces a separate `x-internal` flag in the Redocly style. So there is one ladder and no second label to keep in step.

**`x-audience` scopes documentation. It is not access control.** The edge route and Oathkeeper decide exposure, per [ADR-0305](0305-edge-auth-and-traffic-policy.md). A service with `ingress.enabled: false` is unreachable, whatever its spec says. A CI check ties the ladder to reality. A service is edge-exposed if it has at least one `internal` or `public` operation, and only then. A service with only `cluster` operations has no `/api` route. That pair defines an east-west endpoint, per [ADR-0306](0306-trust-tiers-and-urls.md). No portal shows such endpoints.

### Lifecycle default: one live version

The live API is whatever the current production release serves, per [ADR-0103](0103-release-and-versioning.md). There is no version in the path, no version header, and no support window.

- **A breaking change is a normal PR.** The only consumer is the co-shipped frontend. So a breaking change updates its caller in the same commit, and the two deploy together. The previous shape is not kept alive.
- **The contract diff is a review signal, not a gate.** `oasdiff` labels a change as breaking, so the break is intentional and visible in review. It does not require a version bump or a second live surface.
- **No `Deprecation` or `Sunset` machinery, no transformation layer, and no N-1.** Those belong to the deferred path.

Versioning schemes protect consumers who cannot be forced to upgrade. With one in-tree consumer, that cost buys nothing.

### Lifecycle upgrade: online versioning, flagged off

- **Trigger:** a consumer that the project cannot deploy in lockstep. Examples are a third party, a partner, or a first-party mobile app on its own release cycle.
- **Seam:** the edge reads the header, and the compat layer wraps the handler. So adoption is additive.
- **Cost if adopted late:** the first consumer outside lockstep is unsupported until the flag flips.

Nothing below is built or operated until then.

| Element | Rule |
| --- | --- |
| Version label | a date header, `Api-Version: 2026-07-01` |
| Where dates come from | the subset of release dates on which the public contract changed visibly, per [ADR-0103](0103-release-and-versioning.md). Most releases create no API version |
| Missing header | resolves to the latest version, and the response echoes the resolved date. Clients are advised to pin |
| Support window | N-1. At most two versions are live. The previous one is sunset on a documented date |
| Deprecation signalling | `Deprecation`, per RFC 9745, plus `Sunset`, per RFC 8594, plus a `Link` to migration notes |
| Compatibility | by transformation, bounded to N-1. Handlers produce only the latest shape. A thin response layer maps it back one version |

## Consequences

### Positive

- One artifact powers the server, the internal client, the frontend client, the docs, and the public SDKs. The contract cost per service is fixed, whatever the consumer count.
- Every consumer sees the same API shape, with no protocol-translation layer.
- Schema validation is generated, not written.
- Public API readiness is a CI artifact, not a project.
- The default runs no version machinery. The upgrade path is designed in advance, not improvised under pressure.

### Negative and Risks

- OpenAPI is awkward for discriminated unions and conditional schemas. Vacuum rules that enforce flat schemas reduce this. Complex polymorphism is a sign of an over-coupled API surface.
- The streaming design is practical, not unified. A justification for each WebSocket reduces this.
- Cross-service shapes are duplicated across self-contained specs. Their small, stable surface and the equality check against the canonical fragment reduce this. If the duplication outgrows them, a bundler step restores a single source.
- **A shared fragment is a coupling point.** A change to the error envelope or a common type regenerates every client at once. That is the price of one error branch, not one per service.
- The default cannot serve a consumer outside lockstep. Accepted: that consumer is the documented trigger.

## Rules

- The contract source of truth is OpenAPI 3.1, one file per HTTP service at `services/<service>/openapi.yaml`. Every HTTP service generates its server with ogen. East-west control-plane services are included. Only a service with no HTTP surface ships no spec. `(CI: lint:openapi; ref: OpenAPI 3.1)`
- Each spec is self-contained: cross-service shapes are declared inline in `components` and kept identical across services. Cross-file `$ref` is not used. `(CI: lint:openapi)`
- Cross-service shapes come from `tools/codegen/shared-components.yaml`, and a spec's copy is checked against it. The fragment changes first. A spec's copy is never edited on its own. `(CI: lint:openapi)`
- Errors are RFC 9457 problem details served as `application/problem+json`, by services and by the edge alike. `type` is `about:blank`, except where two errors share a status code and a client handles them differently. That case takes a `urn:problem-type:` URN. Every error carries `trace_id`. `detail` contains no stack trace, query, or internal hostname. `(CI: lint:openapi; ref: RFC 9457)`
- Timestamps on the wire are RFC 3339 in UTC with a literal `Z`, and a non-`Z` offset is rejected. A duration is an integer field named for its unit. Entity identifiers are the type-prefixed UUIDv7 of [ADR-0003](0003-naming-and-identifiers.md), and a bare UUID is a lint failure. `(CI: lint:openapi; ref: RFC 3339, RFC 9562)`
- An edge-exposed spec's `servers` url is `/api`, and its paths are globally unique resource nouns. The exposed URL carries no service segment and no version segment. A service with only `cluster` operations uses `servers: /`. `(CI: lint:service-contract)`
- Every spec declares `info.x-audience` on the ladder `cluster`, `internal`, `public`, with `cluster` as the default. An operation can override it. It scopes documentation and is not access control. `(CI: lint:api-audience)`
- A service is edge-exposed if it has an `internal` or `public` operation, and only then. A service with only `cluster` operations has no `/api` route. `(CI: lint:api-audience)`
- All clients and server stubs are generated from the spec and committed. `(CI: ci:gen)`
- Hand-written code imports generated types. Parallel hand-written request and response types are not declared. `(CI: lint:authz)`
- The service validates request schemas through the generated ogen server. The edge performs no schema validation and no business-rule validation.
- Server-Sent Events is the default streaming mechanism. A WebSocket endpoint carries a justification in the service README.
- gRPC, Connect-RPC, GraphQL, and tRPC are not used.
- OpenAPI YAML is hand-written. TypeSpec and equal authoring layers are not used.
- A spec change is a PR. Merge is blocked until vacuum passes and `mise run gen` produces no diff. `(CI: ci:lint, ci:gen)`
- The API serves a single live version: the current production release. There is no version in the path or in a header, and no support window.
- A breaking contract change ships in one PR with its co-shipped caller. The previous shape is not kept alive.
- `oasdiff` labels breaking changes for review. It is not a version gate. `(CI: ci:lint)`
- Online versioning is deferred behind the trigger of a consumer outside lockstep, and the default does not operate it. It consists of a date `Api-Version` header, an N-1 window, `Deprecation`, `Sunset`, and `Link` headers, and a response-transformation layer bounded to N-1.
