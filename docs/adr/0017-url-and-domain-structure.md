# ADR-0017: URL & Domain Structure (Trust Tiers)

- **Status:** Accepted
- **Date:** 2026-07-06
- **Deciders:** Platform team
- **Related:** [ADR-0003](0003-cluster-topology.md), [ADR-0008](0008-api-contracts.md), [ADR-0009](0009-api-gateway.md), [ADR-0010](0010-auth.md), [ADR-0011](0011-observability.md), [ADR-0012](0012-internal-admin.md), [ADR-0014](0014-frontend.md), [ADR-0015](0015-naming-and-identifiers.md), [ADR-0022](0022-api-lifecycle.md)

## Context

Every environment exposes two very different kinds of HTTP surface behind the same Traefik edge
([ADR-0003](0003-cluster-topology.md), [ADR-0009](0009-api-gateway.md)):

1. **Product** — the user-facing Next.js app (landing, auth UI, the `panel`/`devportal` route groups,
   [ADR-0014](0014-frontend.md)), the service APIs (flat `/api/<resource>`, [ADR-0008](0008-api-contracts.md)), and browser
   telemetry ingest.
2. **Operations tooling** — third-party operator dashboards we deploy but do not author: Hubble UI
   ([ADR-0025](0025-service-map-apm-ui.md)), Grafana ([ADR-0011](0011-observability.md)), the Lowdefy internal-admin
   console ([ADR-0012](0012-internal-admin.md)), Argo CD ([ADR-0004](0004-gitops.md)), the Temporal Web UI
   ([ADR-0006](0006-temporal.md)), and the MinIO console (non-prod).

Serving both tiers as URL paths on one shared origin (`<env-host>/grafana`, `/internal/admin`, `/api/*`) has two
disqualifying problems:

- **No browser-level isolation between tiers.** Path segments on one origin share cookies, `localStorage`, and the DOM.
  A flaw in code we do not control (a Hubble-UI/Grafana XSS, a dangling-subdomain takeover) executes in the **same origin**
  as the product app and its session. The browser's same-origin policy provides *zero* separation between a path and its
  siblings.
- **Some tools cannot be served under a path at all.** Hubble UI's React Router is hardwired to basename `/`
  and 404s under any path prefix; it must be served at the root of its own origin — a common SPA
  constraint. Grafana needs `serve_from_sub_path`, Argo CD and the
  Temporal UI have their own base-path quirks. Path hosting is a per-tool fight.

The web consensus is that **separate origins (subdomains) are the right boundary for internal/higher-risk tooling**:
browsers treat each subdomain as a distinct origin, so cookies, storage, CSP, and rate-limit/WAF scope are isolated by
construction. Subpaths are the default only when everything on the origin is one trusted application. Trust-tier
segmentation by subdomain (`admin.api.example.com` vs `public.api.example.com`) is an established pattern.

We need one deliberate URL/origin scheme that (a) isolates the product tier from the ops tier at the browser level,
(b) still lets a single operator login flow cover all the ops tools, and (c) gives every tool a predictable hostname
that fits a wildcard certificate.

## Decision drivers

1. **Browser-enforced origin isolation between tiers.** A flaw in one origin must not be able to read or script another
   (DOM, storage) — the boundary is the same-origin policy, not path discipline. Credential-level isolation is layered on
   top via per-tool authorization (and, optionally, OIDC), not assumed from the cookie alone.
2. **One operator session across ops tools.** Operators use several dashboards in a sitting; they should log in once for
   the whole ops tier (the tools are the same trust level), with that login carrying a second factor (AAL2).
3. **Least authority, not least cookie.** A logged-in session must not by itself grant any ops tool; access is an
   explicit per-tool grant ([ADR-0010](0010-auth.md)).
4. **Predictable, wildcard-friendly names** ([ADR-0015](0015-naming-and-identifiers.md)): lowercase, hyphen-within-
   segment, every tier under a single parent label so one wildcard cert covers it.
5. **Env parity** ([ADR-0016](0016-environment-parity.md)). The same scheme, host-parameterised, in local and every
   deployed environment.

## Decisions

### Two trust tiers under one registrable host

Let `<host>` be the environment host (e.g. `dev.localtest.me` locally, `dev.example.com` in a deployed env). Surfaces
split into exactly two tiers:

| Tier        | Origin                 | What lives there                                                                 |
|-------------|------------------------|----------------------------------------------------------------------------------|
| **Product** | `<host>` (apex)        | Next.js app — landing, `/auth/*`, `panel`/`devportal`; `/api/<resource>/*`; `/api/rum` (browser RUM ingest) |
| **Ops**     | `*.ops.<host>`         | one origin per operator tool (table below)                                       |

The Next.js app is the **whole product origin**: it serves the public landing page and the authenticated route groups,
and the service APIs stay **same-origin** under the flat `<host>/api/<resource>/*` (the browser app is their only client,
so same-origin avoids CORS and keeps the session cookie naturally scoped). The ops tier nests every tool one level under a
shared `ops.` label.

### Ops-tier hostnames

| Tool                       | Hostname                  | Notes                                              |
|----------------------------|---------------------------|----------------------------------------------------|
| Hubble UI (service map)    | `hubble.ops.<host>`           | served at root (SPA can't run under a path)        |
| Grafana                    | `grafana.ops.<host>`      | drop `serve_from_sub_path`; served at root         |
| Argo CD                    | `argocd.ops.<host>`         | replaces port-forward access                       |
| Temporal Web UI            | `temporal.ops.<host>`     | replaces port-forward access                       |
| Lowdefy internal admin     | `lowdefy.ops.<host>`        | the sole admin surface; the product frontend has no `/admin` route group |
| Headlamp (k8s debug UI)    | `headlamp.ops.<host>`          | Core, read-only by default ([ADR-0024](0024-kubernetes-debug-ui.md))      |
| pgweb (DB inspector)       | `pgweb.ops.<host>`           | Core, read-only break-glass ([ADR-0012](0012-internal-admin.md))          |
| MinIO console              | `minio.ops.<host>`        | **non-prod only** ([ADR-0016](0016-environment-parity.md))         |

Names follow [ADR-0015](0015-naming-and-identifiers.md)'s charset (`^[a-z][a-z0-9-]*$`, hyphen within a segment, never
underscore). The grammar is `{tool}.{tier}.{env-host}`; the product tier carries **no** tier label (it is the apex).

**Origins are named after the tool, lowercased — with no exceptions.** `grafana`, `hubble`, `temporal`, `minio`,
`argocd`, `pgweb`, `headlamp`, `lowdefy`. The rule is one sentence with no judgement calls, which is the point.

The alternative — naming origins after the *concept* (`o11y`, `map`, `workflows`, `s3`, `deploy`, `db`, `k8s`,
`admin`) — was considered and rejected. Its theory is that a concept name is a stable seam which survives swapping the
tool behind it. It does not hold in practice: tools rarely map one-to-one onto a stable concept. Swapping a
network-flow UI for an APM suite changes the concept along with the tool (`network` would have to become `map`
anyway), and a single tool's concept drifts as it grows features — a "map" tool that also serves profiling, database
monitoring, and SLOs fits no concept label. Concept naming produces renames on tool changes *and* naming debates in
between, while promising to prevent exactly those.

Tool naming also removes a category of argument that has no right answer: whether a map tool is "map" or "apm", whether
Headlamp is "k8s" or "cluster". And it stops hostnames from staking territorial claims — `o11y.ops` implicitly asserted
that one tool owned observability, which framed a second, complementary tool as a rival for the name rather than a
different question-answerer (see [ADR-0025](0025-service-map-apm-ui.md)).

Two costs, accepted deliberately:

- **Legibility.** `pgweb.ops` and `headlamp.ops` are less self-evident to a newcomer than `db.ops` and `k8s.ops`. The
  table above is where a newcomer looks, and it names the concern next to every host.
- **The URL moves when the tool does.** Accepted, because per the reasoning above the concept name would have moved anyway.

The counter-argument that tool names leak the stack to an attacker is real but weak here: the wildcard `*.ops.<host>`
certificate keeps individual subdomains out of Certificate Transparency logs, and every origin is gated on an AAL2
operator session plus a per-tool `Checker` call. The `ops.` label already announces that operator tooling exists.

### Why the `ops.` label is load-bearing, not cosmetic

Cookies are sent to a domain and its **descendants** only, never to siblings or a higher ancestor's other children.
That single rule forces the nesting:

- If ops tools were flat (`hubble.<host>`, `grafana.<host>`), the only domain that covers all of them is the common
  parent `<host>` — which **is the product origin**. A cookie shared across flat ops tools would therefore also reach the
  product, re-merging the tiers.
- Nesting under `ops.<host>` lets the ops session cookie be scoped `Domain=ops.<host>`: it covers every `*.ops.<host>`
  tool but **not** the apex `<host>`. Shared across ops, invisible to product.

So the `ops.` segment is the mechanism that makes "one operator login, isolated from product" expressible on a single
registrable host.

### Cookie & session mechanics

**Default model — one parent-scoped session cookie.** A single Kratos `ory_kratos_session` cookie scoped to the parent
`<host>` (`Domain=<host>`) is shared across the product apex and every `*.ops.<host>` origin. This is accepted because
every origin under `<host>` is **first-party and edge-gated**: tier isolation is enforced by **per-tool authorization**
(next section) and by requiring **AAL2 — operator MFA ([ADR-0010](0010-auth.md))** on the ops tier, *not* by cookie
scope. A compromised non-operator product session that reaches an ops origin is still denied by the dashboard
authorizer. The cookie keeps `Secure` + `HttpOnly` + `SameSite=Lax` ([ADR-0010](0010-auth.md)).

The one property deliberately traded away is *token*-level isolation between tiers: the session token is sent across the
whole `<host>` subtree, so an XSS on the high-surface product origin could ride an **operator's** session into the ops
tools. This is acceptable while every subtree origin is first-party; product-origin CSP ([ADR-0014](0014-frontend.md)) is
the compensating control.

**Hardening upgrade (optional).** To also isolate the token, split the cookie: keep the product cookie host-only on the
apex, and have the ops tier mint an `ops.<host>`-scoped session via **OIDC against the central IdP** — Hydra
(`hydra_thirdparty`, [ADR-0009](0009-api-gateway.md)) behind one ops-tier auth proxy (per-tier, not per-tool). One Kratos
instance cannot issue two differently-scoped cookies, and the apex cannot set a cookie on the sibling `ops.` subtree, so
OIDC is the mechanism if token isolation is wanted. This upgrade becomes **mandatory** if any non-first-party origin is
ever hosted under `<host>`.

### Authorization: who may reach which surface

Authentication only proves *who* the operator is; it does not entitle them to every tool. Access is authorized per
surface, at one of two enforcement points split by **who owns the code**:

- **Product surfaces are our code → the app/service decides.** The `/admin`, `/panel`, `/devportal` route groups and the
  `/api/<svc>` endpoints authorize with OpenFGA through `libs/go/authz`'s `Checker` ([ADR-0010](0010-auth.md)); the edge
  only authenticates. Page-level access to `/admin` is a `Checker.Allowed` call in the RSC layer, not a bare session
  check.
- **Ops dashboards are third-party → the edge decides.** Hubble UI, Grafana, Argo CD, Temporal, the MinIO console, and the
  Lowdefy console cannot run a permission check themselves, so authorization moves to the ops-tier Oathkeeper, in two
  layers:

  - **Coarse gate (mandatory) — a claim, not a `Checker` call.** The whole ops tier is gated on the operator's identity:
    the ops-tier forward-auth requires `X-Roles` to contain `operator` (the `operator` trait on the Kratos identity,
    injected as a header per [ADR-0010](0010-auth.md)) **and** an **AAL2 session** (operator MFA). This decision reads
    only the authenticated session and its claims — it makes **no OpenFGA call**. That is deliberate: the ops dashboards
    are how an operator debugs an outage, so their coarse gate must not share fate with the product authorization plane.
    An OpenFGA or authz-endpoint outage must not lock every operator out of Grafana/Hubble/Argo. Losing OpenFGA degrades
    the ops tier to "any operator reaches any tool," not "nobody reaches anything."

  - **Fine gate (optional) — per-tool `remote_json` → OpenFGA `Checker`.** When per-tool grants are wanted (`alice: Grafana
    but not Hubble UI`), each ops route adds the `remote_json` authorizer calling the OpenFGA `Checker`, modelling each tool
    as a resource:

        type dashboard
          relations
            define viewer: [user, group#member]
            define view: viewer

    A request to `grafana.ops.<host>` then also checks `view` on `dashboard:grafana`. For 3–8 operators this fine layer
    is typically deferrable, so the `dashboard` resource and its `remote_json` wiring are optional day-one, not required.

The coarse claim gate is the load-bearing one; the fine per-tool layer refines within it when a project needs it. Product
surfaces are unaffected: they authorize in-app/in-service through the OpenFGA `Checker` ([ADR-0010](0010-auth.md)), so
"every product permission decision goes through `Checker`" still holds — only the ops tier's coarse gate is intentionally
a claim, for break-glass independence.

### Certificates & DNS

- Two wildcard certs per environment: `*.<host>` (covers the apex's siblings and `ops.<host>` itself) and
  `*.ops.<host>` (covers the ops tools, which are two labels deep). Both via cert-manager DNS-01 in deployed envs
  ([ADR-0005](0005-secrets.md)); both as SANs on the locally-generated wildcard for local.
- DNS: `*.<host>` and `*.ops.<host>` resolve to the edge. Locally this is free (`*.localtest.me` → 127.0.0.1).

### Routing

- Product: Traefik `Host(\<host>\)` routes (the per-resource `/api/<resource>` IngressRoutes and the frontend catch-all
  already match on `Host`, [ADR-0009](0009-api-gateway.md)).
- Ops: one `Host(\{tool}.ops.<host>\)` IngressRoute per tool, each behind the ops forward-auth middleware. Host-
  parameterised so local and deployed envs share the manifests ([ADR-0016](0016-environment-parity.md)).

### Content & the public developer surface: SEO axis vs trust axis

Two independent axes decide where a surface lives, and conflating them is the mistake this rule prevents:

- **SEO / link-equity consolidation** favours an **apex subdirectory**: Google treats a subdomain as a separate site
  whose authority is not shared with the root, so anonymous, indexable content compounds domain authority only when
  served under `<host>/…`.
- **Trust isolation** favours a **separate origin** — the boundary this ADR already draws for the ops tier.

They conflict only for anonymous content, and one rule resolves it: **the SEO axis applies only to surfaces that are both
anonymous and indexable; anything behind a login is `noindex` and is therefore placed on trust-isolation grounds alone.**

| Surface                                                       | Placement                                | Deciding axis                                                     |
|---------------------------------------------------------------|------------------------------------------|-------------------------------------------------------------------|
| Product docs, blog, guides, changelog                         | `<host>/docs`, `<host>/blog`, … (subdir) | anonymous + indexable → SEO                                       |
| Public API reference (`x-audience: public` operations only, [ADR-0008](0008-api-contracts.md)) | `<host>/developers` (subdir) | anonymous + indexable → SEO; first-party read-only, like the landing page |
| Dev portal (edge surface — audience `>= internal`, [ADR-0009](0009-api-gateway.md)) | `<host>/devportal` (subdir)           | behind app session + `Checker`; same-origin with `/api`, so "try it" needs no CORS |
| Partner credential dashboard (issue/rotate Hydra OAuth2 keys)  | its own subdomain, separate auth realm  | behind login → `noindex`; a non-Kratos (Hydra) realm must not share the apex session cookie |

The public docs portal is **anonymous — no login** ([ADR-0009](0009-api-gateway.md)); only *credential management* is
authenticated, on the separate dashboard origin above. This is a **deferred, external third tier**: internal-only
projects (the default) have exactly the product and ops tiers; a project shipping a public API adds this external tier,
scoped by the same two axes.

### The API endpoint path: flat `/api/<resource>`, service topology hidden

The service API is exposed as a **flat resource namespace on one shared prefix — `<host>/api/<resource>`** (e.g.
`/api/products`, `/api/orders`, `/api/charges`), **not** per-service (`/api/<svc>/...`). The URL names the *resource*,
not the service that happens to own it today. This is the Stripe/GitHub facade: a caller sees one coherent API surface,
and which service serves a route is an internal detail that can change (a resource can move between services, or a service
split in two) **without breaking a single URL**. The edge maps each resource prefix to its backing service; the mapping
is infrastructure, invisible to consumers. Specs already declare resource-noun paths (`/products`, `/charges`), so the
service segment was only ever leaking topology.

**Collision governance.** One flat namespace means two services cannot both own `/api/orders`. That is a *feature*, not a
limitation — a name collision is a genuine domain-modelling conflict — and it is enforced, not left to chance: a CI lint
fails if two `x-audience`-exposed specs claim the same top-level resource prefix. The edge route table (per-resource
`PathPrefix`, [ADR-0009](0009-api-gateway.md)) is the single registry of who owns what.

**East-west endpoints are not on this surface.** Internal service-to-service endpoints (`x-audience: cluster`, no `/api`
route) bypass the edge entirely ([ADR-0006](0006-temporal.md), [ADR-0009](0009-api-gateway.md)) and are reached in-cluster,
gated by Cilium NetworkPolicy — they are never `/api/<resource>` edge routes, and appear in neither docs portal.

A **path, not its own origin** — and that holds **even for a public/partner API**. The origin-isolation argument that puts
ops dashboards on `*.ops.<host>` does **not** carry over to a JSON API: there is no DOM, JS, or browser storage to isolate,
so a separate origin protects nothing an API has. The reasons a subdomain *sounds* right mostly evaporate here:

- **CORS is a cost, not a benefit.** Same-origin `<host>/api` needs none; a subdomain would manufacture a cross-origin
  problem. (A third-party's own browser app needs CORS to call us regardless of where our API sits.)
- **WAF and rate-limits are path-scoped already.** Traefik attaches middleware per `PathPrefix` router — the per-resource
  `/api/<resource>` IngressRoutes do ([ADR-0009](0009-api-gateway.md)).
- **Infra separation already exists.** The edge routes `/api/*` to service pods and `/` to the frontend; a subdomain adds
  nothing until traffic is routed to genuinely different edge/CDN infrastructure.
- **Versioning is not in the URL.** The default API is single-live-version ([ADR-0022](0022-api-lifecycle.md)), so there is
  no version segment at all; when external consumers force online versioning on, the version rides an `Api-Version` header,
  not the path — which is *why* the flat resource URL stays stable across versions. Auth realm is a path-scoped Oathkeeper
  rule (session *and* JWT on the same `/api` prefix), not a host.

A distinct origin is warranted in only two narrow cases, neither the template default: **hard credential isolation** —
guaranteeing the app session cookie never reaches the API — which requires a **separate registrable domain**, not merely a
subdomain (a parent-scoped `Domain=<host>` cookie is sent to `api.<host>` too); or **separate edge/CDN infrastructure at
scale**. Absent those, the public API is another `<host>/api/<resource>` route, distinguished from the internal one by its
`x-audience: public` contract ([ADR-0008](0008-api-contracts.md)) and Hydra-JWT auth, not by its origin.

## Consequences

### Positive

- Each tier is a **separate origin**: an ops dashboard cannot read or script the product app's DOM/storage, and a
  product-side XSS cannot read or script an ops tool — browser-enforced same-origin policy, not convention. (Credential-
  level isolation is handled by per-tool authz + operator AAL2 in the default model, or fully by the OIDC upgrade.)
- Each ops tool is also isolated from the *other* ops tools (separate origins): per-origin CSP, security headers, rate
  limits, and storage.
- Tools that resist path hosting (Hubble UI, Grafana, Argo, Temporal) are each served at a clean root — no `base-path`
  fights.
- A logged-in session no longer implies tool access: every ops surface is per-tool authorized and AAL2-gated.
- Argo CD, Temporal, and the MinIO console get first-class auth-gated URLs instead of port-forwarding.

### Negative / Risks

- **A second wildcard cert and deeper DNS** (`*.ops.<host>`, four labels deep in prod). cert-manager handles it, but it
  is more moving parts.
- **No token-level tier isolation in the default model.** The parent-scoped cookie sends the session token across the
  whole `<host>` subtree, so a product-origin XSS could ride an *operator's* session into ops. Accepted while every
  origin is first-party; per-tool authz + operator AAL2 + product CSP are the compensating controls, and the OIDC
  upgrade closes it if needed.
- **Subdomain-takeover hygiene** matters more: dangling `*.ops.<host>` DNS must not be left claimable.

### Follow-ups

- The product/ops split lives in `infra/gateway` (host-parameterised ops IngressRoutes), the per-tool chart values
  (Grafana/Argo/Temporal base-path off; Hubble UI root), and the cert-manager Certificate (two wildcards).
- The ops-tier forward-auth enforces the coarse **`operator` claim + AAL2** gate (no OpenFGA call). The `operator` trait
  is declared on the Kratos identity schema and injected as `X-Roles` ([ADR-0010](0010-auth.md)). The optional fine
  per-tool layer adds `remote_json` → OpenFGA `Checker` with a `dashboard` resource in `infra/auth/openfga/model.fga`.
- The default session cookie is parent-scoped. *Optional hardening:* an ops-tier OIDC proxy (Hydra) for token isolation,
  required only if a non-first-party origin is ever hosted under `<host>`.
- Break-glass recovery for a full auth-plane outage is `docs/ops/break-glass.md` (`kubectl port-forward` with an
  independently-obtained kubeconfig), cross-linked from the `scripts/cluster-full.sh` banner.

## Rules

- Surfaces belong to exactly one tier: **product** on the apex `<host>`, **ops tooling** on `*.ops.<host>`. No operator
  dashboard is served from a product path, and no product surface is served from an `ops.` subdomain. A project that ships
  a public API adds a deferred **external** tier (public docs at `<host>/developers` and the partner credential dashboard
  subdomain); internal-only projects have only the product and ops tiers.
- Anonymous, indexable, first-party content — product docs, blog, guides, changelog, and the public read-only API
  reference — is served from an **apex subdirectory** for link-equity consolidation. A subdomain is used only for a
  distinct trust boundary (third-party code or a separate auth realm), never merely because a surface is public.
- The public API docs portal is anonymous; only credential management (Hydra keys) is authenticated, on its own origin
  ([ADR-0009](0009-api-gateway.md)).
- The service API is a **flat resource namespace** on the path `<host>/api/<resource>` (`/api/products`, `/api/orders`,
  …), never per-service (`/api/<svc>/...`) — the URL names the resource, and which service serves it is a hidden,
  movable edge-routing detail. A CI lint fails if two `x-audience`-exposed specs claim the same top-level resource
  prefix; the edge route table is the ownership registry. East-west endpoints (`x-audience: cluster`, no `/api` route) bypass the edge and
  are not on this surface.
- The path holds **including the public/partner API** — a JSON API has no DOM/storage to origin-isolate, and
  CORS/WAF/rate-limits are path-scoped; the API is not versioned in the URL at all (single-live-version by default, an
  `Api-Version` header when online versioning is flagged on — [ADR-0022](0022-api-lifecycle.md)). The public API is a
  `<host>/api/<resource>` route distinguished by its `x-audience: public` contract ([ADR-0008](0008-api-contracts.md))
  and Hydra-JWT auth, not by its origin. A distinct origin is used only for **hard credential isolation** (which needs a
  *separate registrable domain*, since a `Domain=<host>` cookie reaches `api.<host>`) or **separate edge/CDN
  infrastructure at scale** — never for CORS/WAF, which do not require it.
- Ops-tier hostnames are `{tool}.ops.<host>`, lowercase, matching `^[a-z][a-z0-9-]*$`
  ([ADR-0015](0015-naming-and-identifiers.md)).
- The default is one session cookie scoped to the parent `<host>`, shared across tiers; tier isolation is enforced by
  per-tool authorization and an **AAL2 (operator MFA)** requirement on the ops tier, not by cookie scope. This is
  permitted **only** while every origin under `<host>` is first-party and edge-gated.
- Splitting the cookie (product host-only on the apex + an `ops.<host>` cookie minted via OIDC) is the optional token-
  isolation upgrade, and is **mandatory** if any non-first-party origin is hosted under `<host>`.
- Each environment provisions both `*.<host>` and `*.ops.<host>` certificates.
- The ops tier's coarse gate is a **claim, not a `Checker` call**: the ops-tier forward-auth requires `X-Roles` to
  contain `operator` plus an **AAL2** session, and makes no OpenFGA call — so the debugging surface does not share fate
  with the product authorization plane. Optional per-tool refinement adds Oathkeeper's `remote_json` authorizer against
  the OpenFGA `Checker` (`dashboard:<tool>#view`). Product surfaces authorize in-app/in-service through `libs/go/authz`
  ([ADR-0010](0010-auth.md)); a bare authenticated session never grants ops-tool access.
