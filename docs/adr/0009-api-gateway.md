# ADR-0009: API Gateway

- **Status:** Accepted
- **Date:** 2026-05-19
- **Deciders:** Platform team
- **Related:** [ADR-0003](0003-cluster-topology.md), [ADR-0008](0008-api-contracts.md), [ADR-0010](0010-auth.md)

## Context

A single API gateway sits in front of all services exposed to the browser (the Next.js app) and to third-party API consumers. Service-to-service calls inside the cluster bypass the gateway ([ADR-0006](0006-temporal.md)).

The gateway owns:

- **Routing** for `/api/*` from Traefik ([ADR-0003](0003-cluster-topology.md)) to upstream services.
- **Auth at the edge** — JWT validation only. Claims are forwarded as upstream headers. Permission decisions live in services ([ADR-0010](0010-auth.md)).
- **Rate limiting and quotas** — per-key, per-user, per-tier.
- **Schema validation at the edge** — using the same OpenAPI specs that drive [ADR-0008](0008-api-contracts.md) codegen.
- **Observability hooks** — request logging and W3C trace context propagation.

It does **not** own: cluster ingress (Traefik does), mTLS between services, retries/circuit-breaking inside the cluster, API monetisation.

## Decision drivers

1. **OpenAPI-native config.** The gateway consumes our OpenAPI specs directly. No parallel routing config.
2. **Open source.** No paid tiers.
3. **Plugin language fit.** Custom middleware is written in Go.
4. **Operational simplicity.** No separate DBA, no separate cluster.

## Considered options

- **Tyk Gateway OSS** — OpenAPI 3.x is a first-class input; Go plugins via gRPC plugin server; mature JWT and rate-limit features; Kubernetes operator with `ApiDefinition` and `SecurityPolicy` CRDs; Redis as the only external dependency.
- **Kong Gateway OSS** — large plugin ecosystem; Lua-first plugin model; OpenAPI is not a first-class input; heavier ops (Postgres or reduced-feature DB-less).
- **Apache APISIX** — etcd-backed, Lua core; Go plugins are out-of-process; OpenAPI import is a plugin.
- **Traefik** — already our cluster ingress ([ADR-0003](0003-cluster-topology.md)); OpenAPI is documentation-only; rate-limit and quota features are far less rich than Tyk.
- **Envoy Gateway / Gateway API** — bare Envoy is an L7 proxy, not an API management gateway. Out of proportion for our team.
- **KrakenD** — Go-native and OpenAPI-aware, but primarily an aggregator; JWT and rate limiting less mature.
- **Gravitee OSS** — only OSS candidate with a built-in developer portal; JVM-based, ruled out by [ADR-0001](0001-language-and-runtime.md).

## Decision

**Tyk Gateway OSS is the API gateway** for all external traffic.

### Responsibilities

- TLS termination is upstream at Traefik; Tyk receives plaintext over the cluster network.
- **Auth: JWT validation only.** Tyk verifies the token, extracts claims, and forwards them as upstream headers (`X-User-Id`, `X-Org-Id`, `X-Roles`). It does **not** call the authz engine.
- **Rate limiting and quotas** — per API key for third-party traffic; per user (from JWT `sub`) for first-party.
- **Schema validation** — from the OpenAPI spec at `services/<service>/openapi.yaml` ([ADR-0008](0008-api-contracts.md)). Same artifact, two enforcement points, zero duplicated work.
- **Trace context propagation** — Tyk preserves W3C `traceparent` and adds its own span as a child.

### Configuration

- Tyk API definitions are **generated** from `services/<service>/openapi.yaml` by `tools/codegen/tyk-gen`. They land in `infra/gateway/apis/` as generated artifacts and are committed per [ADR-0002](0002-monorepo.md).
- Hand-edited Tyk API definitions are forbidden.
- Security policies live in `infra/gateway/policies/` as hand-written declarative YAML — one file per logical tier (anonymous, authenticated user, partner, internal-admin).
- Deployed via the Tyk Kubernetes operator with CRDs in `infra/helm/platform/tyk/`.

### Plugins

- Plugins are written in **Go** via Tyk's gRPC plugin server. Lua plugins are not used.
- Plugin source lives under `libs/go/tyk-plugins/`. Each plugin's `README.md` explains why the work belongs at the gateway and not in the service.

### Developer portal

The developer portal is **not part of Tyk in this deployment.** It is a route group in the frontend application: `apps/frontend/src/app/(devportal)/`. The route group:

- Renders OpenAPI specs via Scalar or Redoc embedded in Next.js pages.
- Calls the Tyk admin API to issue and rotate API keys for authenticated developers.
- Matches the product's visual design.

The route group is implemented when the first third-party consumer is on the roadmap. Until then, the route group exists as a placeholder serving "documentation coming soon" — no separate component to operate.

### Authz boundary

Settled here and inherited by [ADR-0010](0010-auth.md):

- The gateway validates tokens and forwards claims.
- The gateway does **not** call the authz engine.
- Services receive claim headers and use a shared Go authz client (`libs/go/authz/`) to make permission decisions.
- Service-to-service calls bypass the gateway and authorise themselves the same way using a service-to-service token.

## Consequences

### Positive

- The OpenAPI spec is the single source of truth for routing, validation, codegen, and gateway behaviour. One PR updates them all.
- Go-only plugin surface keeps the operational language footprint consistent with [ADR-0001](0001-language-and-runtime.md).
- OSS-only stance keeps licensing cost at zero and avoids paid-control-plane lock-in.
- The dev portal as a frontend route group keeps visual consistency and removes a separate stateful component.

### Negative / Risks

- **No admin UI in OSS.** All ops via API/CRDs. Mitigated by GitOps + runbook documentation in `docs/gateway/runbook.md`.
- **Smaller plugin ecosystem than Kong.** We write more middleware ourselves. Acceptable given the Go plugin model fits.
- **Tyk's roadmap may push features into paid tiers.** Mitigated by the OSS license and reviewed annually.
- **Double schema validation (gateway + service)** has a CPU cost. Accepted per [ADR-0008](0008-api-contracts.md).

### Follow-ups

- `infra/helm/platform/tyk/` deployment with the Tyk operator and Redis.
- `tools/codegen/tyk-gen` for OpenAPI → Tyk API definition emission.
- `infra/gateway/policies/` initial policy set (anonymous, user, partner, internal-admin).
- `apps/frontend/src/app/(devportal)/` placeholder route group.
- `libs/go/tyk-plugins/` skeleton with one example plugin (claim enrichment).
- `docs/gateway/runbook.md` covering route changes, policy updates, key issuance.

## Rules

- Tyk Gateway OSS is the API gateway for all external traffic. No alternate gateway is used at the same edge.
- Tyk API definitions are generated from `services/<service>/openapi.yaml` and committed under `infra/gateway/apis/`. Hand-edits are forbidden.
- Tyk validates JWTs, extracts claims, and forwards them as `X-User-Id`, `X-Org-Id`, `X-Roles` headers. It does not call the authz engine.
- Tyk enforces request-schema validation at the edge. The service re-validates the same schema; both come from the same OpenAPI artifact.
- Rate limits and quotas are configured in `infra/gateway/policies/` per logical tier.
- Gateway plugins are written in Go via Tyk's gRPC plugin server. Lua plugins are forbidden.
- The developer portal is a route group in `apps/frontend/`, not a separate application or Tyk-paid feature.
- Service-to-service calls inside the cluster bypass Tyk; they validate JWTs in the service's auth middleware ([ADR-0010](0010-auth.md)).
- A new public endpoint is delivered by: spec change in OpenAPI → `mise run gen:all` → PR with regenerated Tyk definition. No manual Tyk dashboard step.
