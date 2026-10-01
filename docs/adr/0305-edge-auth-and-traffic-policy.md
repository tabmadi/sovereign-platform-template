# ADR-0305: Edge Authentication and Traffic Policy

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0101](0101-monorepo.md), [ADR-0200](0200-cluster-topology.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0304](0304-identity-and-authorization.md), [ADR-0306](0306-trust-tiers-and-urls.md), [ADR-0400](0400-frontend.md)
- **Decides:** Traefik fronting Ory Oathkeeper validates identity once at the edge and injects the headers that every service downstream trusts.

## Context

Traefik is the cluster ingress, per [ADR-0200](0200-cluster-topology.md). It handles TLS, routing, load balancing, and static assets. This ADR covers what happens **after Traefik and before a service**:

- who validates the identity of the caller
- how that identity travels onward
- what traffic policy applies at the edge

Service-to-service calls bypass the edge entirely. Cilium NetworkPolicy gates them, not a token.

| The edge owns | The edge does not own |
| --- | --- |
| Identity validation of the Kratos session or Hydra JWT, once | Cluster ingress and TLS, owned by Traefik |
| Identity propagation as trusted headers, in one shape for every request | Permission decisions, owned by services through `Checker`, per [ADR-0304](0304-identity-and-authorization.md) |
| Rate limiting on auth-sensitive endpoints | Request-schema validation, owned by services through ogen, per [ADR-0303](0303-api-contracts-and-lifecycle.md) |
| Static browser-security headers and the CSRF Origin check | The per-request CSP nonce, owned by the frontend, per [ADR-0400](0400-frontend.md) |

## Decision drivers

1. **One identity shape for every request.** A handler reads identity in the same way, whether the call came from a browser or from another service. There is no split between JWTs in one place and headers in another.
2. **Services are auth-free in their handlers.** Identity arrives already validated.
3. **The edge reads the credential that the identity provider issues**, with no translation layer between them. [ADR-0304](0304-identity-and-authorization.md) decides what that credential is.
4. **The edge adds no state.** Everything here is on the path of every request. So a datastore behind the edge is a datastore in front of everything.
5. **Authorization lives in one place.** A policy language at the edge is a second place to write a permission decision.

## Considered options

### The ingress controller

Traefik is Tier 1, per [ADR-0002](0002-tool-adoption.md). Every inbound request crosses it. Its middleware model expresses the forward-auth chain. The routes are CRDs that the GitOps tree owns. The table compares the two properties that decide this position: how routing is authored, and whether the forward-auth seam is first-class.

| Option | Routing authored as | Forward-auth | Data plane | Verdict |
| --- | --- | --- | --- | --- |
| **Traefik** | `IngressRoute` CRDs, with middleware as separate composable resources | **first-class middleware**, and the chained shape that the next table needs | its own, in Go | **Chosen.** Middleware is a resource, not an annotation. So a reviewer reads the auth chain of a route as a list of objects, not as a string *(reasoned)* |
| Envoy Gateway | Gateway API resources, with policy attachment | through `ext_authz`, the native and more expressive mechanism of Envoy | Envoy | **The runner-up**, and the better data plane. It loses on weight: Envoy plus a control plane is two components, and Traefik is one. `ext_authz` buys expressiveness that this platform spends at the application layer instead |
| ingress-nginx | `Ingress` with annotations, plus snippets | `auth-url` annotations | nginx | The most widely deployed. The annotation model puts routing logic in strings that nothing validates until reload. Configuration-snippet injection is a recurring class of issue |
| HAProxy Ingress | `Ingress` with annotations, or a ConfigMap | `auth-url` | HAProxy | The strongest data plane on raw throughput. Its configuration surface is authored outside the resource model |
| Contour | `HTTPProxy` CRDs, or Gateway API | `ext_authz`, delegated to Envoy | Envoy | The shape of Envoy Gateway, with a longer history and a narrower feature set. Envoy Gateway supersedes it |
| Gateway API on any implementation, no controller chosen | portable resources | implementation-defined | varies | The portability is real, but the forward-auth chain is not portable. So the property it buys does not cover the property that decides the row |

**Throughput is not the deciding axis here, and this ADR records that.** At the shape of this platform, every option in this table saturates the network before it saturates itself. So the deciding property is how a reviewer reads an auth chain in a diff.

### Certificate lifecycle

TLS terminates at the ingress above. So this section decides what issues and renews the certificate.

| Option | Renewal | Configuration | Added components | Verdict |
| --- | --- | --- | --- | --- |
| **[cert-manager](https://cert-manager.io/docs/)** | a controller reconciles `Certificate` resources and renews them before expiry | CRDs in the repository | one controller | **Chosen.** The certificate is a Kubernetes object. So a renewal failure is a resource condition that an alert already reads, not a log line in a cron job *(reasoned)* |
| certbot in a `CronJob` | the schedule, and what it writes | a shell script and a mounted secret | one Job and a script to own | A renewal failure is silent until TLS breaks. That is the slowest-arriving failure on the floor. Nothing about this option is cheaper |
| A private CA | we issue it, on our own schedule | ours | a CA to run, plus trust-anchor distribution to every client | The exit if the public ACME dependency becomes unacceptable, per [ADR-0000](0000-platform-foundations.md). It costs a trust anchor on every browser and every client |
| Manual issuance | a person, once a year | none | none | The honest baseline. It fails on the wildcard-per-environment shape: a certificate whose renewal is a calendar entry of one person expires in the end |

Each environment has one wildcard certificate, issued over ACME DNS-01. [ADR-0206](0206-cluster-networking.md) holds the record shape and the provider requirement that it implies.

### The forward-auth mechanism

| Option | Added components | Reads a Kratos browser session | Identity passed onward as | Verdict |
| --- | --- | --- | --- | --- |
| **Ory Oathkeeper as ForwardAuth** | **none beyond one Go binary**, no datastore | **yes**, and Hydra JWTs through the same rule set | mutated trusted headers, one shape for every route | **Chosen.** Declarative YAML access rules in git. It is the only option that reads both credential formats of this platform with no hop between them *(reasoned)* |
| Plain Traefik `ForwardAuth` to Kratos `/sessions/whoami` | **none at all** | yes | nothing: `whoami` authenticates but does not mutate the request | The zero-component baseline, and the row that prices the chosen option. Without mutation, every service must strip client-supplied identity headers itself. There is also no rule language to mark a route public |
| oauth2-proxy | one | **no: it speaks OIDC**, and Kratos issues browser sessions, not OIDC tokens | OIDC claims as headers | The usual first answer to this problem. It needs Hydra in front of Kratos before it has anything to validate. That adds an OAuth2 round trip to first-party browser traffic to satisfy a proxy, not a requirement |
| Authelia | one, plus a session store | no: it carries its own identity model | headers | An identity provider with a forward-auth front-end. To adopt it decides [ADR-0304](0304-identity-and-authorization.md) again instead of serving it |
| Pomerium | one, plus its own state | no: OIDC | headers, with per-route policy | The strongest alternative on expressiveness. It has the same OIDC mismatch. Its policy language is a second home for authorization, against driver 5 |
| Envoy `ext_authz` | Envoy at the edge, beside Traefik or instead of it | through a service we write | whatever that service sets | A mechanism, not a product. It turns the question into *what runs behind it*. A change of ingress is a bigger change than this decision |
| Tyk or Kong | a control plane, a datastore, a plugin runtime | through a plugin | plugin-defined | Rich API management. Its one unique value here is edge OpenAPI validation, and in-service validation already does that, per [ADR-0303](0303-api-contracts-and-lifecycle.md) |
| Traefik's commercial OIDC middleware | none | no: OIDC | headers | It closes the JWT gap in the open distribution of Traefik. It is a paid tier, against principle 3 of [ADR-0000](0000-platform-foundations.md) |
| A DIY ForwardAuth service | one first-party service | yes, once written | ours | Viable. It puts auth-critical validation under our ownership. Oathkeeper has the same shape, is declarative, and someone else maintains it |

**The OIDC mismatch removes most of the field.** Kratos issues browser sessions, not OIDC tokens. Hydra issues OAuth2 tokens for third-party clients, per [ADR-0304](0304-identity-and-authorization.md). So every proxy above that expects an OIDC provider needs Hydra in the first-party browser path. That adds an OAuth2 flow that serves the proxy and no consumer.

## Decision

The edge is **Traefik fronting Ory Oathkeeper**. No full API-management gateway is deployed by default.

### Validate once, headers everywhere after

```text
Internet
  → Traefik       TLS, routing, load balancing, rate limiting
  → Oathkeeper    validate Kratos session or Hydra JWT → strip → inject X-User-Id / X-Org-Id / X-Roles
  → service       reads identity headers only; Checker authorises

service → service forwards the same headers; NetworkPolicy gates reachability; no token on the path
```

Oathkeeper **strips any client-supplied identity headers** before it sets the authoritative ones. Services read identity only from those headers and never parse a JWT. `authmw` is a trusted-header reader, per [ADR-0304](0304-identity-and-authorization.md).

This is the single request shape: every service, edge-origin or internal, reads identity in the same way.

**A denial at the edge looks like a denial from a service.** Oathkeeper rejects a request before any handler runs, so it is the other error producer of the platform. Its `401` and `403` responses carry `application/problem+json` in the shape that [ADR-0303](0303-api-contracts-and-lifecycle.md) fixes. They have the same members and the same `trace_id` extension. So a generated client has one error branch, not one per producer. The error handlers of Oathkeeper are configured for this and are not left at their default body.

### Where this sits against zero trust

A reader who knows [NIST SP 800-207](https://csrc.nist.gov/pubs/sp/800/207/final) stops at the diagram above. A service that trusts a header is the thing that zero trust exists to remove. The position is deliberate: **this platform takes the authorization model of 800-207 and declines its transport model.**

| Tenet | Here |
| --- | --- |
| Access is granted per request and per resource, and evaluated dynamically | **held.** Every protected call goes through `Checker` against OpenFGA, per [ADR-0304](0304-identity-and-authorization.md). Nothing is authorised only because it reached the service |
| All communication is secured, whatever the network location | **held.** WireGuard encrypts all east-west pod traffic, per [ADR-0206](0206-cluster-networking.md) |
| No implicit trust comes from network position | **declined.** A service trusts `X-User-Id` for two reasons. Cilium default-deny guarantees that only sanctioned callers reach its port. Oathkeeper strips client-supplied headers at the edge. That is positional trust, and it is exactly the assumption that 800-207 removes |

The concession buys these properties:

- handlers with no auth code
- one identity shape for every caller
- no token minting or verification per hop
- no sidecar on the hot path

It costs this: code that runs inside a sanctioned caller can forge identity to a downstream service. The blast radius is the egress allowances of that caller. The `restricted` profile bounds it further, because it limits what a compromised pod can do at all, per [ADR-0200](0200-cluster-topology.md).

**The seam is built, and this platform owns its trigger, not an auditor.** [ADR-0206](0206-cluster-networking.md) makes per-workload certificate identity a Cilium mutual-auth and SPIFFE upgrade. It fires on any of three conditions:

| Trigger | Why it is the right threshold |
| --- | --- |
| A service performs a **monetary mutation** | The cost of the concession is a forged identity that a downstream service accepts. Where that buys money and not data, egress allowances no longer bound the blast radius |
| A **second team** owns a service in this cluster | Positional trust assumes that every sanctioned caller is code that this team reviewed. With a second owner, `sanctioned` becomes a claim about the review of another team |
| Compliance requires an **auditable CA chain** | The external reason, and the weakest of the three. It fires on the calendar of another party, not on the risk of this platform |

The upgrade converts positional trust into cryptographic trust, and it changes only the transport. The authorization half already follows 800-207, so nothing above it moves.

This platform can observe the first two conditions in its own repository. So its largest accepted risk does not depend on an external party to notice it. The example `payment` service does not fire the first condition: it moves no money and holds no processor credential, per [ADR-0302](0302-temporal.md). A service that moves money makes a different claim, and that claim fires the trigger.

### Rate limiting

From day one, Traefik's middleware throttles auth-sensitive routes per source: login, signup, and password reset. This is a security control, independent of any public API.

**Per-API-key tiered quotas are deferred.** They are a feature of full API management, and the platform wants nothing else from such a gateway.

| Field | Value |
| --- | --- |
| **Trigger** | a project bills for API access, so the quota of a caller differs by contract, not by route |
| **Seam** | ✓ the public API is already a distinct audience with its own routes, per [ADR-0303](0303-api-contracts-and-lifecycle.md). So a gateway goes in front of those routes only, behind a per-project flag. First-party browser traffic keeps the path above |
| **Cost if adopted late** | the API is already billed against counters kept somewhere else, usually in a service. Those counters become the migration, not the gateway |

### Security headers and Origin policy

Every route passes through the edge, so blanket headers live here.

| Control | Where |
| --- | --- |
| `frame-ancestors 'none'`, `X-Content-Type-Options: nosniff`, `Referrer-Policy`, HSTS | a Traefik `Middleware` on all responses. These directives never vary per request |
| The nonce-bearing `script-src` directive | the frontend, per [ADR-0400](0400-frontend.md) |
| **CSRF Origin check** | an Oathkeeper rule that rejects cookie-authenticated state-changing requests whose `Origin` is not the project's own domain. The browser does not attach bearer tokens, so bearer-token traffic is exempt |

The Origin check backs up the `SameSite=Lax` cookie of [ADR-0304](0304-identity-and-authorization.md) and the Next.js Server-Actions check of [ADR-0400](0400-frontend.md).

### Configuration and routing

| Concern | Location |
| --- | --- |
| Oathkeeper access rules | `infra/auth/oathkeeper/` as declarative YAML, deployed beside Kratos and Hydra |
| Traefik routing, rate limits, middleware | `infra/gateway/` as committed Traefik CRDs, per [ADR-0101](0101-monorepo.md) |

**Flat resource routing.** The API is a flat namespace, per [ADR-0306](0306-trust-tiers-and-urls.md). So the edge routes each resource prefix to its backing service through a `PathPrefix` rule per resource. Service topology stays hidden, and a resource can move between services with no URL change.

**The route table is the single registry of resource ownership.** A CI lint fails if two edge-exposed specs claim the same prefix, per [ADR-0303](0303-api-contracts-and-lifecycle.md). Oathkeeper matches one rule on the whole `/api/` prefix and does not list services.

There is no gateway-specific API-definition codegen. The spec drives service codegen, and the edge does not consume it.

### Hydra is a public-API flag

Hydra issues OAuth2 tokens for third-party and external machine clients. **Internal-only projects do not deploy it.** Kratos, Oathkeeper, and OpenFGA are the internal stack. A project that exposes a public API sets `hydra_thirdparty: on`. Oathkeeper then validates those JWTs and converts them to the same identity headers. So **the internal request shape does not change**.

### Authz boundary

- The edge validates identity and injects headers. It does **not** call the authz engine.
- Services receive the headers and decide permissions through the shared client.
- Service-to-service calls bypass the edge and authorise the forwarded identity in the same way. NetworkPolicy decides which services may reach which.

The one sanctioned exception is operator tooling, which is third-party and cannot call `Checker`. [ADR-0304](0304-identity-and-authorization.md) owns that gate.

### Developer portals

Both portals render the specs as **filtered projections on the `x-audience` ladder**, never as separately maintained documents. Both render the edge `/api` surface. East-west operations appear in neither, and service READMEs document them.

Scalar's request console is the reason that the dev portal is same-origin with `/api`, per [ADR-0306](0306-trust-tiers-and-urls.md). Its `try it` action hits the real edge with the caller's session and needs no CORS. [ADR-0400](0400-frontend.md) owns the renderer, the route group, and the rejected alternatives. [ADR-0303](0303-api-contracts-and-lifecycle.md) owns the projections.

## Consequences

### Positive

- One identity shape across the platform, and service handlers are auth-free.
- The edge validator is one Go binary from a family that the team already operates. There is no Redis, no plugin runtime, and no gateway codegen.
- JWT validation lives at exactly one hardened chokepoint. It is not duplicated into every service.

### Negative and Risks

- **Internal header trust rests on NetworkPolicy.** A misconfigured policy lets a pod spoof `X-User-Id`. Default-deny in the service template mitigates this, and Hubble flows are the audit surface, per [ADR-0200](0200-cluster-topology.md). This is the recorded deviation from NIST SP 800-207 above, not an unexamined gap. The SPIFFE seam exists to convert this one property.
- **No edge schema validation.** Generated in-service validation from the same spec mitigates this. Internal calls bypass the edge anyway, so the service is the only point that sees every request.
- **Per-API-key quotas are not available on day one.** Accepted. A project adds them when a monetised public API is real.
- **Oathkeeper is one more component to operate.** Accepted. It shares the Ory operational model.

## Rules

- Ingress is Traefik with TLS from cert-manager over ACME DNS-01. Oathkeeper sits behind it as the edge identity filter. There is no API-management gateway. `(ref: RFC 8555)`
- The edge is Traefik fronting Ory Oathkeeper. No full API-management gateway is deployed by default.
- Oathkeeper validates the Kratos session or Hydra JWT, strips client-supplied identity headers, and injects the authoritative ones. It does not call the authz engine. `(CI: lint:authz)`
- Every request carries identity in the same header shape. Services read identity from headers and never parse a token. `(CI: lint:auth-inline)`
- Service-to-service calls bypass the edge and forward the identity headers. NetworkPolicy gates them. No token is on the internal path.
- Request-schema validation is service-side. There is no edge schema validation.
- Edge denials return `application/problem+json` in the shape that [ADR-0303](0303-api-contracts-and-lifecycle.md) fixes, and carry `trace_id`. The default error body of Oathkeeper is not shipped. `(ref: RFC 9457)`
- Rate limiting on auth-sensitive routes is Traefik middleware in `infra/gateway/`.
- Static browser-security headers are a Traefik middleware on all responses. The per-request CSP nonce belongs to the frontend.
- An Oathkeeper rule checks the Origin of every cookie-authenticated state-changing request. Bearer-token traffic is exempt.
- The edge routes each resource prefix to its backing service, and the route table is the single registry of resource ownership. `(CI: lint:service-contract)`
- Hydra is deployed only for projects that expose a public API or external machine clients.
- A project that needs tiered per-API-key quotas adds a full gateway for its own routes by its own decision. It is not the platform default.
