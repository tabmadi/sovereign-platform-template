# ADR-0306: Trust Tiers and URL Structure

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0003](0003-naming-and-identifiers.md), [ADR-0200](0200-cluster-topology.md), [ADR-0201](0201-gitops.md), [ADR-0202](0202-secrets.md), [ADR-0205](0205-environment-parity.md), [ADR-0302](0302-temporal.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0304](0304-identity-and-authorization.md), [ADR-0305](0305-edge-auth-and-traffic-policy.md), [ADR-0307](0307-outbound-email.md), [ADR-0400](0400-frontend.md), [ADR-0401](0401-internal-admin.md), [ADR-0500](0500-observability.md), [ADR-0501](0501-operator-uis-and-dashboards.md)
- **Decides:** Product is served from the apex and operator tooling from one origin per tool under `*.ops.<host>`.

## Context

Every environment exposes two kinds of HTTP surface behind one Traefik edge:

| Surface | Contents | Code ownership |
| --- | --- | --- |
| **Product** | the Next.js app, the service APIs, browser telemetry ingest | first-party |
| **Operations tooling** | Hubble UI, Grafana, the Lowdefy console, Argo CD, the Temporal UI, Headlamp, pgweb, the Mailpit viewer, the SeaweedFS admin UI | **third-party: deployed, not authored** |

This ADR fixes three things:

- where each surface lives
- how one operator login covers the ops tier
- what the API path looks like

## Decision drivers

1. **Browser-enforced origin isolation between tiers.** A flaw in one origin must not read or script another. The boundary is the same-origin policy, not path discipline.
2. **Operators pay for logins during an incident.** An investigation crosses several dashboards. So the number of authentications it costs is a property of the layout, not a preference.
3. **Least authority, not least cookie.** A logged-in session grants no ops tool by itself.
4. **Predictable, wildcard-friendly names**, per [ADR-0003](0003-naming-and-identifiers.md).
5. **Parity**, per [ADR-0205](0205-environment-parity.md). The same scheme, host-parameterised, everywhere.

## Considered options

### Where ops tooling lives

| Option | Browser isolation | Per-tool hosting cost | Verdict |
| --- | --- | --- | --- |
| **A subdomain per tool under a shared `ops.` label** | **each origin is distinct**: cookies, storage, CSP, and rate-limit scope are isolated by construction | none: every tool is served at a root | **Chosen** *(reasoned)* |
| Paths on the product origin | **none**. Path segments share cookies, `localStorage`, and the DOM. So a flaw in code we do not control runs in the same origin as the product session | a fight per tool. The router of Hubble UI is hardwired to basename `/` and returns 404 under any prefix. Grafana needs sub-path serving. Argo CD and the Temporal UI have their own quirks | Both problems disqualify it |
| A flat subdomain per tool, no `ops.` label | isolation per tool, and see below | none | The only domain that covers all of them is the product origin itself. So a shared ops cookie reaches product and merges the tiers again |
| Paths on the product origin with `__Host-` cookies per tool | **none between tools**. The prefix binds a cookie to the host, not to a path, so every tool still shares one origin | the same fight per tool | The cheap middle option, and it does not exist. `__Host-` hardens a cookie against subdomain injection and gives no path isolation, because the same-origin policy has no path dimension |
| A separate registrable domain for ops | strongest: no shared parent | none, plus a second certificate authority chain and DNS zone | Justified only where the parent-scoped cookie is itself the threat. Recorded as the hardening path |

### How ops origins are named

| Option | Survives a change of tool | Naming decision per tool | Verdict |
| --- | --- | --- | --- |
| **After the tool, lowercased**: `grafana`, `hubble`, `temporal` | no: the URL moves with the tool | none. The name is already chosen | **Chosen.** One sentence, no judgement calls, and a rename happens only on an event that is already a migration *(reasoned)* |
| After the concept: `o11y`, `map`, `workflows`, `s3` | **claimed, but no** | one debate per tool | The theory is that a concept name outlives the tool. It does not hold. A change from a network-flow UI to an APM suite changes the concept too, and the concept of a tool drifts as it grows features. So concept naming produces renames on tool changes *and* naming debates between them. A hostname can also claim territory. A host that claims `observability` makes a complementary second tool look like a rival for the name, not a tool that answers a different question |

This choice has two accepted costs:

- To a newcomer, `pgweb.ops` is less clear than `db.ops`. The table below answers this, because it names the concern next to every host.
- The URL moves when the tool moves. This happens under concept naming too.

Tool names leak the stack. The objection is real but weak here, for three reasons:

- The wildcard certificate keeps individual subdomains out of Certificate Transparency logs.
- Every origin is gated on an operator session with a second factor.
- The `ops.` label already announces that operator tooling exists.

### Where the service API lives

| Option | CORS | Isolation gained | Verdict |
| --- | --- | --- | --- |
| **A path on the product origin, `<host>/api/<resource>`** | **none needed** | does not apply | **Chosen.** A JSON API has no DOM, JS, or browser storage to isolate. So a separate origin protects nothing that it has *(reasoned)* |
| `api.<host>` | created for our own frontend | **none against the cookie**. A `Domain=<host>` cookie reaches `api.<host>` too | The reasons that make it sound right do not hold. WAF and rate limits already attach per path router. The edge already routes `/api/*` to services and `/` to the frontend |
| A separate registrable domain | required | **hard credential isolation**: the app session cookie cannot reach the API | Justified only for that guarantee, or for separate edge and CDN infrastructure at scale. Not the default |
| Per-service paths, `/api/<svc>/...` | none needed | does not apply | Leaks topology into every URL. So a resource cannot move between services without breaking callers |

## Decision

### Two tiers under one registrable host

`<host>` is the environment host.

| Tier | Origin | Contents |
| --- | --- | --- |
| **Product** | `<host>`, the apex | the Next.js app with landing, auth, `panel`, and `devportal`. `/api/<resource>/*`. The browser telemetry ingest path |
| **Ops** | `*.ops.<host>` | one origin per operator tool |

The service APIs stay **same-origin** under the flat path. The browser app is their only first-party client. So same-origin avoids CORS and keeps the session cookie scoped naturally.

### Ops-tier hostnames

The grammar is `{tool}.{tier}.{env-host}`. The product tier carries no tier label.

| Tool | Hostname | Note |
| --- | --- | --- |
| Hubble UI | `hubble.ops.<host>` | served at root. Its SPA cannot run under a path |
| Grafana | `grafana.ops.<host>` | sub-path serving off |
| Argo CD | `argocd.ops.<host>` | replaces port-forward access |
| Temporal UI | `temporal.ops.<host>` | replaces port-forward access |
| Lowdefy admin | `lowdefy.ops.<host>` | the only admin surface, per [ADR-0401](0401-internal-admin.md) |
| Headlamp | `headlamp.ops.<host>` | read-only by default, per [ADR-0501](0501-operator-uis-and-dashboards.md) |
| pgweb | `pgweb.ops.<host>` | read-only break-glass |
| Mailpit | `mailpit.ops.<host>` | **non-prod only**. The viewer of the mail sink, per [ADR-0307](0307-outbound-email.md) |
| SeaweedFS admin | `seaweedfs.ops.<host>` | **non-prod only**, and the only exposed surface of that component |
| zot console | `zot.ops.<host>` | the catalogue of the registry. It carries its own credential after the edge gate, per [ADR-0105](0105-image-registry.md) |

### The one origin outside both tiers

| Origin | Gate |
| --- | --- |
| `registry.<host>` | the registry's own credentials, per [ADR-0105](0105-image-registry.md), never the operator session |

A registry client is not a browser. `docker login`, containerd, and BuildKit speak the authentication challenge of the OCI distribution spec. They follow no redirect to a login page. So forward-auth in front of this origin fails every push and every pull with a document that the client cannot read. The origin sits outside the `ops.` label for the reason that the label exists. It never sees the operator cookie, so it must not be inside the scope of that cookie.

### The local environment's host name

A local tier fills the `envHost` slot like any other environment, per [ADR-0205](0205-environment-parity.md). So the grammar above holds unchanged, and only the domain differs. That domain is **`dev.localtest.me`**, and the label is load-bearing. It is the environment slot, not a local marker. This keeps the local values file in the same shape as a deployed one. The label also scopes the operator session cookie. A cookie on a bare shared domain goes to every other project that uses that domain.

The field splits into two families, and each buys the same property at a different price.

| Option | Standing | What it costs |
| --- | --- | --- |
| **`localtest.me`**, and also `lvh.me` and `vcap.me` | none: an ordinary registration | **Chosen.** A real public DNS wildcard to `127.0.0.1`. So it resolves identically on every machine and every client, with no setup. The price is a dependency on a domain that someone else owns *(reasoned)* |
| `.test` | RFC 6761 §6.2, reserved for testing | It never collides, and the RFC specifies that it answers **NXDOMAIN**. So it resolves only where a wildcard resolver is installed. That setup is per machine and differs by operating system |
| `.localhost` | RFC 6761 §6.3, the strongest specification of the three: resolvers **SHOULD** return the loopback address | Rejected. The specification is a SHOULD, and implementations disagree. On a developer machine, Go's resolver returned `no such host` for a name under `.localhost`. `getent` answered `::1`, with no IPv4. So a perf suite written in Go cannot reach the edge |
| `nip.io`, `sslip.io` | none | Encodes an IP in the name. That answers a question that a loopback edge does not ask. It is the right answer if the tier moves to a routable address |
| `.internal` | reserved by ICANN and never delegated. No IETF standard | The same resolver requirement as `.test`, with less precedent |

**The property being bought is zero setup.** A name that resolves everywhere makes the domain invisible to a newcomer. An invisible domain is the best onboarding property available. The standing risk is that the domain is a registration, not a reservation. That risk is real. `xip.io` was the most widely adopted member of this family. It was withdrawn after its whole domain was classified as social-engineering content. That is a hazard of the redirect pattern, not of one operator.

**The trigger to move is that class of loss, and the destination is `.test`**, which keeps the grammar. `.localhost` is not a destination. It has the same migration cost and keeps a resolution problem.

**The registry is the exception, and it is not on this surface at all.** `registry.localhost:5000` is a docker container name that the embedded DNS of the container runtime resolves. It is not a host name that a browser resolves. The client makes the difference. Inside a node, `127.0.0.1` is the node. So any name that resolves to loopback sends an image pull to the wrong place. The registry also cannot sit behind the edge, because the edge's own image has to be pulled before the edge exists, per [ADR-0105](0105-image-registry.md). A `.localhost` name is right here for the same reason that it is wrong above. Nothing browses it, and only the resolver of the container runtime has to agree.

**The console is the same backend on the other side of that line.** `zot.ops.<host>` serves the catalogue to a browser and takes the full ops chain. `registry.<host>` serves the distribution API to a client that cannot pass that chain. It is one process with two origins. The kind of client that arrives chooses the gate, not the port that answers.

The browser is not asked for zot's own htpasswd on top of the ops chain. A small reverse proxy in the zot pod presents the pull credential for the browser and serves the console origin. `registry.<host>` reaches zot directly, and its clients authenticate themselves. The alternative is an anonymous read policy. It opens every pull on `registry.<host>` only to make a console page load.

The cluster's own pulls do not use `registry.<host>` at all. A kubelet reaches the Service directly. The origin exists for the pipeline that pushes, and for a person who inspects what was pushed.

**A tool behind the ops gate does not ask for a second password.** Every origin under `ops.<host>` is reached only through Oathkeeper. Oathkeeper has already proved an AAL2 operator who holds the grant for that tool. The port of each tool admits traffic from the gateway only. So the built-in login of a tool guards a door that is already locked. It also adds a credential to generate, rotate, store, and find. So Grafana serves with its anonymous role, and Argo CD serves anonymously with `policy.default: role:admin`.

The SeaweedFS admin UI is served in the same way. `weed` starts without `-admin.password`, so it registers no login route at all. The dashboard answers whoever the edge let through.

This places one real requirement on such a tool: it must be unreachable except through the edge. The network policy does this. A tool whose port admits traffic from anywhere else still needs its own login.

**Where the login of a tool cannot be switched off, a proxy presents its credential for the browser.** The zot console is the case. The login is not that surface's to waive, because the console and the distribution API are one process under one access policy. The only switch that silences the prompt is an anonymous read policy, and it opens every pull on `registry.<host>`, per [ADR-0105](0105-image-registry.md).

So a small reverse proxy runs in the zot pod. It adds the `Authorization` header of the pull identity and serves the `zot.ops.<host>` origin. The operator meets the ops gate and nothing more. The credential stays in the Secret that the proxy reads, not in the memory of a person. The proxy admits traffic from the gateway on its own port. So the requirement `unreachable except through the edge` holds for it as for any other origin.

**A component that exposes several UIs gets one origin, not several.** SeaweedFS ships a master UI, a filer UI, and an admin UI. Only the admin UI is routed. The others are diagnostic surfaces, reached in the same way as any unrouted surface. An origin per internal view multiplies CSP, rate-limit, and session surface, and it adds no operator capability that the admin UI lacks. The production instance runs outside the cluster, per [ADR-0200](0200-cluster-topology.md). So it has no `ops.<host>` origin at all, and its administration is not an edge concern.

### Why the `ops.` label is load-bearing

The browser sends cookies to a domain and its **descendants** only. It never sends them to siblings, or to the other children of a parent.

- Flat ops hostnames have `<host>`, **the product origin**, as their only common parent. So any cookie shared across ops tools also reaches product.
- A nest under `ops.<host>` lets an ops cookie be scoped to that label. It covers every tool and **not** the apex.

The `ops.` segment is the mechanism that makes `one operator login, isolated from product` possible on a single registrable host.

### Cookie and session model

**Default: one parent-scoped session cookie**, shared across the apex and every ops origin. This is accepted because every origin under `<host>` is first-party and edge-gated. **Per-tool authorization and a required second factor on the ops tier enforce tier isolation, not the cookie scope.** A compromised non-operator product session that reaches an ops origin is still denied by the dashboard gate.

**The property traded away deliberately is token-level isolation.** The browser sends the session token across the whole subtree. So an XSS on the high-surface product origin can ride the session of an *operator* into the ops tools. The product-origin CSP of [ADR-0400](0400-frontend.md) is the compensating control.

**This is the highest-severity accepted risk in the set, and this ADR records it as one.** Its properties:

- The impact is every ops tool that an operator can reach, which is the control surface of the cluster.
- The likelihood is the XSS posture of the product origin.
- The compensating control is a header, not a boundary.

[`docs/reference/risk-register.md`](../reference/risk-register.md) carries its severity, not only this list. A risk of this size that a reader sees once in a Consequences section is a risk nobody reads again.

**Isolation of the token too is a deferred hardening.** The product cookie stays host-only on the apex. The ops tier mints its own scoped session through OIDC, behind one ops-tier auth proxy. The proxy is per tier, not per tool. One Kratos instance cannot issue two cookies with different scopes, and the apex cannot set a cookie on the sibling subtree. So OIDC is the mechanism.

| Field | Value |
| --- | --- |
| **Trigger** | any non-first-party origin is hosted under `<host>`, or the product surface renders content that one user supplies to another. The first makes the shared cookie unsound by construction. The second raises the XSS likelihood that the CSP holds alone |
| **Seam** | ✓ every ops route already passes one forward-auth middleware, per [ADR-0305](0305-edge-auth-and-traffic-policy.md). So the change is what that middleware validates. No tool is reconfigured, and no URL moves |
| **Cost if adopted late** | the newly added origin could read the shared parent-scoped cookie for as long as it was hosted. No later scoping takes back a token that the browser already sent |

### Authorization is split by who owns the code

| Surface | Enforcement point |
| --- | --- |
| Product: our code | the app or service decides, through `Checker`, per [ADR-0304](0304-identity-and-authorization.md). The edge only authenticates. Page-level access is a `Checker` call in the render layer, not a bare session check |
| Ops dashboards: third-party | the edge decides, because the tool cannot run a permission check itself |

[ADR-0304](0304-identity-and-authorization.md) owns the two layers of the ops gate, and the reason that the coarse layer deliberately makes no authz call. The consequence for this ADR: a loss of the authz plane degrades the ops tier to `any operator reaches any tool`, never to `nobody reaches anything`.

### Certificates, DNS, and routing

- Each environment has two wildcard certificates. One covers the siblings of the apex, and this includes `ops.<host>` itself. The other covers the ops tools, which sit two labels deep. cert-manager issues both.
- Both wildcards resolve to the edge.
- Product routes match on host. Ops routes are one host-matched IngressRoute per tool behind the ops forward-auth middleware. They are host-parameterised, so every environment shares the manifests.

### Content placement: the SEO axis against the trust axis

Two independent axes decide where a surface lives. This rule prevents the mistake of treating them as one.

- **Discoverability favours an apex subdirectory.** Google states that it treats subdomains and subdirectories the same for ranking, so this is not a ranking claim. A subdirectory keeps one host, one certificate, and one analytics property. It is also same-origin with `/api`, and this lets a `try it` console work without CORS.
- **Trust isolation favours a separate origin.** That is a browser guarantee, not a preference.

They conflict only for anonymous content, and one rule resolves the conflict: **the first axis applies only to surfaces that are both anonymous and indexable. Anything behind a login is `noindex`, and trust alone decides its placement.**

| Surface | Placement | Deciding axis |
| --- | --- | --- |
| Product docs, blog, guides, changelog | apex subdirectory | anonymous and indexable |
| Public API reference, `public` operations only | apex subdirectory | anonymous and indexable. First-party and read-only |
| Dev portal, audience `>= internal` | apex subdirectory | behind the session and `Checker`. Same-origin with `/api`, so `try it` needs no CORS |
| Partner credential dashboard | its own subdomain, separate auth realm | behind login, so `noindex`. A non-Kratos realm must not share the apex session cookie |

**The external third tier is deferred.** An internal-only project has exactly the product and ops tiers. The rows above describe where the third tier goes when it exists.

| Field | Value |
| --- | --- |
| **Trigger** | a party outside the organisation gets credentials for the API |
| **Seam** | ✓ the tier is a third host under the same wildcard and the same edge. Its auth realm is a second Oathkeeper rule set, not a change to the first, per [ADR-0305](0305-edge-auth-and-traffic-policy.md). Nothing in the product or ops tiers moves |
| **Cost if adopted late** | partner credentials were already issued through the surface that existed, usually the product origin. So the separation starts with a migration of live credentials and the sessions that hold them |

### The API path

The service API is a **flat resource namespace**. The URL names the resource, not the service that owns it. This is the Stripe and GitHub facade. A caller sees one coherent surface. Which service serves a route is an internal detail, and it can change without breaking a URL.

**Collision governance.** In one flat namespace, two services cannot both own a resource prefix. That is a feature, because a name collision is a real domain-modelling conflict. CI enforces it, so it is not left to chance. The edge route table is the ownership registry, per [ADR-0305](0305-edge-auth-and-traffic-policy.md).

**East-west endpoints are not on this surface.** They bypass the edge, NetworkPolicy gates them, and they appear in neither docs portal.

**One reserved path sits outside both tiers.** `/.well-known/` on the apex is neither product nor ops surface. The conventions of the web live there, so nothing else claims that prefix. The apex publishes [`security.txt`](https://www.rfc-editor.org/rfc/rfc9116) there, with a contact address and a disclosure policy. A researcher who finds something looks in exactly this one place. Without the file, the report goes to whatever public inbox the researcher can find.

**The path holds for a public or partner API too.** Its `x-audience: public` contract and its JWT auth set it apart, not its origin. Versioning never enters the URL. The default is a single live version, and online versioning uses a header, per [ADR-0303](0303-api-contracts-and-lifecycle.md). This is exactly why the flat resource URL stays stable across versions.

## Single sign-on for the operator consoles

Self-hosting multiplies consoles: Forgejo, zot, Grafana, Argo CD, Headlamp, Hubble, the Temporal UI, and pgweb. The cost lands on offboarding. When someone leaves, the question is whether anyone remembers all eight.

**The answer is the identity stack already here, not a ninth component.** Ory Hydra is already in the tree as the OIDC provider, per [ADR-0305](0305-edge-auth-and-traffic-policy.md). Kratos is already the identity source, and the login UI already exists at `/auth/login`. Consoles that speak OIDC consume it. When one Kratos identity is deactivated, access to all of them ends at once.

| Option | Verdict |
| --- | --- |
| **Hydra and Kratos, already deployed** | **Chosen.** No new component, no second identity source, and one offboarding action. Consent is auto-granted for first-party console clients. This keeps a third-party consent screen from appearing in front of an internal tool *(reasoned)* |
| Authentik | The best admin experience in the field, and the wrong shape here. It is a second identity system beside Kratos. So every person exists twice, and offboarding becomes two actions: the problem stated again, not solved. It also brings its own PostgreSQL and Redis |
| Zitadel | A live candidate for this slot. The objections to it are about custom login UIs and config-as-code for *application* identity, and neither applies to hosted-login OIDC. It still loses on the same count as Authentik: a second source of people |
| Keycloak | The same duplication, on a JVM, with realms and mappers to learn |
| Authelia | A tiny footprint, and a forward-auth model that this platform already has in Oathkeeper. It replaces a component and does not add SSO |

**Consoles that do not speak OIDC stay edge-gated**, as they are now. Oathkeeper's forward-auth in front of `{tool}.ops.<host>` already requires a Kratos session. So access is single sign-on even where the console does not know it. pgweb, the Hubble UI, and the Temporal UI are in this group.

**The remaining risk is local accounts, and it is the one worth naming.** Grafana, Forgejo, and Argo CD each keep an internal admin that bypasses OIDC entirely. So an offboarding that only deactivates the Kratos identity leaves those admins in place. So the local admin of each console is a **break-glass credential in the secret store**, per [ADR-0202](0202-secrets.md), not a per-person account. It is one credential to rotate, and nobody's personal login.

## Consequences

### Positive

- Each tier is a separate origin. So an ops dashboard cannot read or script the product app, and a product-side XSS cannot script an ops tool. The browser enforces this, not a convention.
- Each ops tool is also isolated from the others: CSP, headers, rate limits, and storage are per origin.
- Tools that resist path hosting are each served at a clean root, with no base-path fights.
- A logged-in session does not imply tool access.
- Argo CD, Temporal, and the SeaweedFS admin UI get auth-gated URLs instead of port-forwarding.

### Negative and Risks

- **A second wildcard certificate and deeper DNS.** cert-manager handles it, and it adds moving parts.
- **No token-level tier isolation in the default model.** Accepted while every origin is first-party. Per-tool authorization, operator MFA, and the product CSP are the compensating controls. The OIDC upgrade closes the gap.
- **Subdomain-takeover hygiene matters more.** Dangling ops DNS must not be left open to a claim.
- **The ops tier depends on one edge auth path.** Its failure locks operators out of every dashboard at once. This is why break-glass is a written procedure, not improvisation. See [`docs/guide/break-glass.md`](../guide/break-glass.md).

## Rules

- Each surface belongs to exactly one tier: product on the apex, ops tooling on `*.ops.<host>`. No operator dashboard is served from a product path, and no product surface from an `ops.` subdomain.
- A project that ships a public API adds a deferred external tier: public docs on an apex subdirectory, and the partner credential dashboard on its own subdomain.
- Anonymous, indexable, first-party content is served from an apex subdirectory. A subdomain is used only for a distinct trust boundary, never only because a surface is public.
- The public API docs portal is anonymous. Only credential management is authenticated.
- The service API is a flat resource namespace at `<host>/api/<resource>`, never per-service. `(CI: lint:service-contract)`
- `/.well-known/` on the apex is reserved for web conventions, and no product route claims it. The apex serves `security.txt` with a contact address and a disclosure policy. `(ref: RFC 9116, RFC 8615)`
- The path holds for the public API too. A distinct origin is used only for hard credential isolation, or for separate edge infrastructure at scale. Hard credential isolation needs a separate registrable domain, because a parent-scoped cookie reaches a subdomain.
- Ops-tier hostnames are `{tool}.ops.<host>`, named after the **upstream project**, lowercase, and in the naming charset of [ADR-0003](0003-naming-and-identifiers.md). The name is not the concept the tool serves, not its binary, and not an abbreviation of either.
- The default is one session cookie scoped to the parent host. Per-tool authorization and an AAL2 requirement on the ops tier enforce tier isolation. This is permitted only while every origin under `<host>` is first-party and edge-gated.
- A split of the cookie is the optional token-isolation upgrade. It is mandatory if any non-first-party origin is hosted under `<host>`.
- Each environment provisions both wildcard certificates.
- A bare authenticated session never grants ops-tool access.
