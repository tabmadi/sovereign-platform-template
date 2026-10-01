# ADR-0304: Identity and Authorization

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0100](0100-language-and-runtime.md), [ADR-0104](0104-supply-chain-security.md), [ADR-0200](0200-cluster-topology.md), [ADR-0202](0202-secrets.md), [ADR-0205](0205-environment-parity.md), [ADR-0301](0301-data-lifecycle-privacy.md), [ADR-0302](0302-temporal.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0305](0305-edge-auth-and-traffic-policy.md), [ADR-0306](0306-trust-tiers-and-urls.md), [ADR-0400](0400-frontend.md), [ADR-0401](0401-internal-admin.md), [ADR-0500](0500-observability.md), [ADR-0501](0501-operator-uis-and-dashboards.md)
- **Decides:** Ory Kratos authenticates, OpenFGA authorizes every protected call through `Checker`, and organisations are relationships, not roles.

## Context

The platform serves four kinds of principal:

| Principal | Needs |
| --- | --- |
| B2C users | public sign-up, email and password, social login, MFA, recovery |
| B2B organisations | multi-tenant orgs, SSO, per-org roles, SCIM provisioning |
| Services calling services | identity forwarded as headers and trusted by network policy, per [ADR-0206](0206-cluster-networking.md). No per-call token |
| Third-party API consumers | tokens to call public APIs |

Earlier ADRs set these constraints:

- The platform is self-hosted only.
- The footprint of each service matters, per [ADR-0100](0100-language-and-runtime.md).
- The edge validates tokens, and services decide permissions, per [ADR-0305](0305-edge-auth-and-traffic-policy.md).

**Hard requirement on the UI.** The login UI is a custom Next.js surface on the platform's own design system, per [ADR-0400](0400-frontend.md). It is not the provider's hosted pages, themed templates, or a forked vendor UI. The provider must expose a headless, API-first identity flow that Next.js drives end to end.

**Authorization shape.** The day-one features already need more than flat RBAC: resource ownership across orgs, shared resources, and a role per org per resource. Temporal is available, per [ADR-0302](0302-temporal.md). So the dual write between the application database and the authz store is a routine workflow.

The decision has three parts: the identity provider, the OAuth2 authorization server, and the authorization engine.

## Decision drivers

1. **Configuration lives in the repository**, per principle 1 of [ADR-0000](0000-platform-foundations.md). Identity schemas, OAuth2 clients, and authz models are files, not database state.
2. **Headless identity provider.** The UI constraint requires it.
3. **Integration contracts that any language can meet.** Auth is a *protocol* contract: token format, header names, and validation rules. Any language can express it.
4. **No new runtime and no new datastore** on the always-on floor for this concern, per [ADR-0100](0100-language-and-runtime.md) and [ADR-0300](0300-data.md).

## Considered options

### Identity provider

| Option | Headless flow | Config source of truth | Verdict |
| --- | --- | --- | --- |
| **Ory Kratos** | fully headless self-service flows | **JSON Schema identity files and YAML in git** | **Chosen.** Go, Apache-2.0, and the reference implementation of the headless pattern *(documented)* |
| Zitadel | a real headless Session API that covers password, MFA, passkeys, and external IdPs | **its own event-sourced database**, despite its Terraform provider | Rejected on driver 1. The same driver rejected Coroot, per [ADR-0501](0501-operator-uis-and-dashboards.md). A second reason: its own guide makes hosted login the default. The guide says it was `designed with security in mind, which limits the customization capabilities`. Its main customization story is to fork a beta Next.js app, and the UI constraint excludes that by name |
| Keycloak | themes, or the Admin and Account REST APIs. It has no first-class headless self-service flow | realm import and export, with drift back to the database | The most mature OSS provider. Its JVM footprint does not fit [ADR-0100](0100-language-and-runtime.md), and extension work is in Java |
| Authentik | flow-based | database | Python, Django, Celery, and Redis add a third runtime and three components. Its B2C self-service flows are less mature |
| SuperTokens | fully headless. The recipe model is API-first, and the caller owns all of the UI | **its own core service and database**. Configuration is partly in code and partly in that store | The closest competitor to Kratos on driver 2. It splits configuration between the SDK's initialisation code and the core's state. So no single committed file describes the identity setup |
| Logto | headless Management and Experience APIs | its own database, with a Terraform provider over the management API | Fails driver 1 in the same way as Zitadel: the API is the source of truth, and git holds a script that talks to it |
| Casdoor | a headless API, but the UI is the primary surface | database, with configuration objects | Broad protocol coverage across a wide feature surface. It has the same database-as-truth problem |

### OAuth2 and OIDC server

The platform needs this server only when a third-party client gets its own credentials. First-party browsers use Kratos sessions.

| Option | Added runtime and datastore | Consent flow integrates with the chosen IdP | Config source of truth | Verdict |
| --- | --- | --- | --- | --- |
| **Ory Hydra** | none: Go on the existing Postgres | **yes, first-party with Kratos** | YAML plus committed client definitions | **Chosen.** The only option that adds an OAuth2 server and does not also add a second identity system *(reasoned)* |
| Keycloak | a JVM, and its own store | it *is* the IdP, so the question goes away, and so does Kratos | realm import, with drift to the database | To adopt it here decides the row above again, and [ADR-0100](0100-language-and-runtime.md) bars the runtime |
| Zitadel | its own event-sourced store | as above, it replaces Kratos | its own database | Same: it is an IdP that also does OAuth2. It is not an OAuth2 server for an IdP it does not own |
| Authentik | Python, Django, Celery, Redis | as above | database | Same shape, heavier |
| Dex | none: Go, and it can run with no storage | **no**. Dex federates *upstream* identity providers. It issues tokens for users it does not own | committed YAML, the best of the field on driver 1 | By far the thinnest. It is a federating proxy, not an authorization server with its own consent and client management |
| Authelia | Go, plus a session store | no: it has its own identity model | committed YAML | An access-control portal that gained an OIDC provider. Its user model is not the Kratos model |
| Build our own | none | does not apply | ours | Excluded by [ADR-0000](0000-platform-foundations.md): the platform does not hand-roll security-critical infrastructure |
| Ship no OAuth2 server, the honest baseline | none | does not apply | does not apply | Correct until a third party needs credentials. This is why Hydra is flag-gated Opt-in and not Core, per [`operational-surface.md`](../operational-surface.md) |

### Authorization engine

The day-one requirements are ReBAC, not flat RBAC. They include cross-org sharing, a role per org per resource, and reverse-index questions such as `which resources can this user see`. That limits the field to Zanzibar-style engines.

| Engine | Model and capability | Governance | Fit | Verdict |
| --- | --- | --- | --- | --- |
| **OpenFGA** | Zanzibar ReBAC. ABAC through CEL conditions and contextual tuples. Reverse index through `ListObjects` and `ListUsers` | **CNCF**: vendor-neutral, with contributors from many vendors | a single Go binary on Postgres. `.fga` DSL, `fga model test` in CI, and the official Go SDK behind a seam | **Chosen.** It matches SpiceDB on capability and operational shape, and wins on governance. Contextual tuples also let a check read data at request time. This eases the sync that the dual write carries *(reasoned)* |
| SpiceDB | Zanzibar ReBAC. ABAC through CEL caveats. The strongest reverse-index and `Watch` APIs. `ZedToken` consistency | single-vendor | a single Go binary on Postgres | The credible fallback, equal on capability. It loses only on governance. Its consistency advantage matters only at large scale |
| Ory Keto | Zanzibar ReBAC. ABAC only through OPL. No conditions, no `Watch`, and no batch | single-vendor, with some features source-available | fits the existing Ory stack | The thinnest feature set of the mature engines. It has licence-gated extras and no advantage that offsets them |
| Permify | ReBAC plus first-class ABAC. Native multi-tenancy | single-vendor, under corporate ownership. A smaller community | Go on Postgres | Capable. Its adoption is narrower than a vendor-neutral option of equal capability, so it is the weaker long-term bet |
| Topaz | a ReBAC directory **plus full OPA with Rego**, the most expressive. Weak reverse-index and large-scale query APIs | community-maintained, with no sponsoring vendor. Pre-1.0 | edge or sidecar with an embedded directory, so authz data must be replicated to every instance | The richest policy language, and the worst data-sync story of the field |
| Casbin | a PERM-model **library** with role inheritance and implicit-permission queries. **No relationship-graph traversal and no reverse index over resources** | Apache, vendor-neutral | in-process. Ports in other languages must agree on matcher semantics | Not a Zanzibar engine. It answers `what may this user do` well. It answers `which resources can this user see` only by enumeration, and that is the day-one requirement |
| Oso | policy-as-code in Polar, with relationship rules evaluated over the application's own data | single-vendor. [The open-source library is deprecated](https://www.osohq.com/docs/oss/any/getting-started/deprecation.html) in favour of the hosted Oso Cloud | in-process as a library, or a call to that service | The maintained path is a third party's service, and principle 3 excludes that. The self-hosted part that is left is a library that its author no longer develops |
| In-process RBAC per service | hand-rolled | ours | differs per service | The complex cases exist from day one. A later move to a Zanzibar engine is a data migration per feature |

Any two Zanzibar engines are interchangeable at the architecture level. The `Checker` seam in `libs/go/authz/` is engine-agnostic. So a change of engine touches one library, the model file, and the chart. It does not touch the services.

### Why ReBAC from day one, not RBAC with a later migration

The template creates many products, and only some need ReBAC. So the obvious alternative is to ship flat RBAC and migrate later. This ADR rejects it. The switching cost is three separate costs, and they differ greatly.

| Cost | Difficulty | Why |
| --- | --- | --- |
| **Check sites** | almost free | `Checker.Allowed(ctx, action, resource)` is already the only authz seam, and inline role checks are already forbidden. The platform pays this cost with any engine |
| **Data model** | hard, and it grows as data accumulates | RBAC stores `subject → role`. ReBAC stores `subject → relation → object`. A switch needs a backfill of one tuple per existing relationship. This is trivial while the store holds only `alice is org-admin`. It is costly once per-resource ACL tables exist |
| **Dual-write discipline** | hard and invasive | RBAC in one database is one transaction. ReBAC keeps two stores in sync. To add that late to every authz-relevant mutation path is the truly difficult part |

The deciding difference is the **shape of the question**. RBAC answers a *subject-shaped* question: what role does this user have. ReBAC also answers an *object-shaped* question: may this user act on *this specific* resource. That question covers sharing, per-resource roles, and cross-org ownership. So:

- A role-shaped product **never needs to switch**. RBAC serves it forever.
- RBAC **cannot serve a per-resource product at all**. That product needed ReBAC from the start, not later.
- So `start with RBAC, migrate later` serves only products that never migrate, or that should never have started on RBAC. The rare true middle case pays the **maximum** accumulated cost of both hard rows. The approach optimises for the worst path.

**The honest tax:** even at L1 below, this adds the dual-write habit. It also adds one extra Postgres-backed binary that RBAC in the database does not need. The platform accepts this for one tool, one mental model, and no worst-path migration.

## Decision

### Identity provider: Ory Kratos

Kratos handles registration, login, MFA, recovery, settings, and social login. Identity schemas are JSON Schema files at `infra/auth/kratos/identity-schemas/`. All other configuration is YAML at `infra/auth/kratos/`.

The Next.js login UI lives at `apps/frontend/src/app/(landing)/auth/` and drives Kratos self-service flows directly.

The session cookie is `SameSite=Lax`, `Secure`, and `HttpOnly`, with the meaning that [RFC 6265bis](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-rfc6265bis) gives those attributes. This is the first line of CSRF defence. The built-in anti-CSRF token of Kratos covers the self-service flows. The edge Origin check backs up other cookie-authenticated mutations, per [ADR-0305](0305-edge-auth-and-traffic-policy.md). Browser-side CSP and Server-Actions handling belong to [ADR-0400](0400-frontend.md).

### Password policy

Two local controls are on in every environment, with no dependency outside the pod:

- **`min_password_length: 12`**
- **`identifier_similarity_check_enabled: true`**, which rejects a password that resembles the email or username

The shape follows [NIST SP 800-63B](https://pages.nist.gov/800-63-3/sp800-63b.html):

- Length carries the strength.
- Composition rules and forced rotation are absent, because they push users toward predictable patterns.
- The breach check below is the compromised-credential screening of 800-63B.

That document also defines the **AAL** levels that this ADR uses.

**The HaveIBeenPwned breach check is off by default.** It is a real control. It catches the one class that a length rule cannot catch: a long passphrase that is already in a breach corpus. Its cost is not the network policy:

- **It needs world egress on every password operation.** Each registration, password login, and password change does a k-anonymity range lookup over HTTPS. Some deployments run on a closed network with no route to the internet. There, the control cannot work, whatever the manifest says.
- **It fails open, silently.** `ignore_network_errors` defaults to true. So an unreachable endpoint does not fail the flow and does not log an error. Measured on a default-deny cluster, each registration had about 160 dropped SYNs over 20 seconds of retries. This added 20 seconds of latency, and Kratos accepted the breached password anyway.

A control that looks enabled in the manifest but does nothing on the wire is worse than a control that is honestly off. It invites the reviewer to stop looking.

The check is most useful in the B2C tier, whose users are AAL1 with no forced second factor. Operators carry [TOTP](https://www.rfc-editor.org/rfc/rfc6238) or [WebAuthn](https://www.w3.org/TR/webauthn-3/) in any case.

An environment with the egress enables the check in three steps:

- It sets `haveibeenpwned_enabled` with `max_breaches: 0`.
- It restores the `toFQDNs` allow rule.
- It restores the companion L7 DNS rule. The network policy keeps both rules as a comment.

A closed network can instead point `haveibeenpwned_host` at a self-hosted k-anonymity API. Kratos has no setting for a custom CA chain. So that host must serve a certificate that the container already trusts.

This is a per-environment security posture, not a parity violation. The policy is identical in every environment that can enforce it. [ADR-0205](0205-environment-parity.md) forbids the opposite pattern: a control enabled in production and quietly disabled locally. Local then enforces a weaker policy and looks the same.

### OAuth2 server: Ory Hydra, when a public API exists

Hydra is deployed behind the `hydra_thirdparty` flag when a project exposes a public API or external machine clients. It issues authorization-code and client-credentials tokens for third parties and external machines. The edge validates those tokens and converts them to the standard identity headers. So **the internal request shape is identical whether or not Hydra is deployed**.

Hydra is not used for internal service-to-service calls, which carry no token. When Hydra is deployed, it is the only issuer of external tokens. No service mints its own. Configuration lives at `infra/auth/hydra/`. Third-party clients are declared in YAML that a post-sync hook applies.

**The specifications decide token shape and validation, not this platform.** A third-party integrator brings a library, not a reading of our documentation. Every local variation here is a bug that someone else has to discover.

| Concern | Decision |
| --- | --- |
| Access-token format | JWT per [RFC 9068](https://www.rfc-editor.org/rfc/rfc9068): `typ: at+jwt` and the required claims of the profile. The platform does not use opaque tokens with introspection. With them, the edge calls Hydra on every request |
| Validation | [RFC 8725](https://www.rfc-editor.org/rfc/rfc8725) JWT best practice. The edge rule pins the signing algorithm, so `alg: none` and algorithm-confusion attacks fail by construction. The edge checks `iss`, `aud`, and `exp`. A token minted for one audience is not accepted for another |
| Grants | authorization code with [PKCE](https://www.rfc-editor.org/rfc/rfc7636) for **every** client, public and confidential alike. Client credentials for machine callers. Implicit and resource-owner-password grants are disabled. This is the OAuth 2.1 posture, and Hydra does not impose this configuration on its own |
| Discovery | the [OpenID Connect Core](https://openid.net/specs/openid-connect-core-1_0.html) provider metadata document. A third party configures its client from that endpoint, not from prose that we maintain |

### B2B organisations: an `orgs` service on top of Kratos

Kratos stores identities, not organisations. A first-party `services/orgs/` gives multi-tenancy. It owns:

- organisations and memberships
- the active organisation for a session
- org-level invitations and SSO connection records

The service exists whether or not a B2B feature exists. Without it, a later change adds an organisation boundary through every table and tuple. The service avoids that migration.

**The organisation is the unit of authorization.** Every protected resource in the model belongs to an `org`. A user only ever acts through a role in some org. A user with zero orgs is an account that can own nothing.

So membership is a day-one invariant: **when Kratos creates an identity, the identity gets a personal organisation in which it is `admin`.** The post-registration webhook starts the `RegisterUser` workflow. Its two activities are the same dual write as any authz mutation: the `orgs` rows and the OpenFGA tuple.

Membership is many-to-many, so a user can create more orgs and be invited into others. The personal org is a first tenant, not a limit.

| Model | Tenant created | Gain over eager | Cost |
| --- | --- | --- | --- |
| **Personal org, eager** | automatically, at registration | **Chosen.** No org-less branching. It is a superset of the others, so a sales-led flow adds on top with no change | one-person-org clutter *(reasoned)* |
| Lazy tenant | on the first action that needs one | less clutter | every caller must handle the org-less user. So `identities with no org` becomes normal, not an edge case |
| Owner-creates-first | manually, as a deliberate step | cleanest for pure B2B | a newly signed-up user is stuck with no tenant |
| Invite-only or SCIM | by an admin or an external IdP | fits regulated environments | no self-serve growth, and the provisioning path must exist from the start |
| No org, pure B2C | never: the user is the boundary | simplest if teams never arrive | to add tenancy later is a data migration, and it reworks the ownership relations of the model |
| A single shared default org | at bootstrap | the fewest orgs | **Rejected.** It puts unrelated users in one tenant and breaks isolation |

The default name of the personal org is a **generic constant**, not the user's email. An org can later hold a whole team, and every member invited into it sees its name. So an email there leaks PII into a shared display field, per [ADR-0301](0301-data-lifecycle-privacy.md). It also goes stale when the mutable email changes. The stable identity is the org id.

A change of model edits the registration webhook path. For the B2C case, it also edits the ownership relations of the model. The `Checker` seam and the authz calls of every service do not change.

### Directory provisioning is deferred

[SCIM](https://www.rfc-editor.org/rfc/rfc7644) lets the IdP of an enterprise customer drive joiners and leavers directly. It is plumbing per customer, so it waits.

| Field | Value |
| --- | --- |
| **Trigger** | the first contract that makes directory-driven provisioning a condition of purchase |
| **Seam** | ✓ mostly. `orgs` already owns memberships, invitations, and SSO connection records. `RegisterUser` already does the membership dual write. SCIM is an authenticated endpoint that drives that path. The gap is deprovisioning. A Kratos identity state change must also revoke sessions and tuples, and no flow does this |
| **Cost if adopted late** | joiners and leavers stay manual. A leaver who keeps access is the audit finding that shows the gap. Adoption then reconciles existing memberships against the directory once per customer |

### Authorization engine: OpenFGA

Services access OpenFGA only through the `authz.Checker` interface in `libs/go/authz/`. A depguard rule confines the SDK to that library.

One engine serves every project at the complexity it needs. **The schema grows, never the tool.**

| Level | Model | Typical instance |
| --- | --- | --- |
| **L1, role per org** | members and admins of an organisation. This *is* flat RBAC | about 15 lines of DSL. Most instances stay here |
| **L2, resource ownership** | `owner`, `editor`, `viewer` on single resources | adds relations to the same file |
| **L3, sharing and hierarchy** | groups, folders, inheritance, cross-org sharing | adds relations to the same file |

The `Checker` interface is identical at every level. So **L1 is the first-class default, not a fallback**:

```fga
type user

type organization
  relations
    define admin: [user]
    define member: [user]
    define view: admin or member
    define manage: admin
```

That is flat RBAC on the engine that also does L2 and L3, so nobody ever migrates tools. Role-shaped usage keeps the tuple set small. Only membership changes write tuples, and they are already an `orgs` operation. So the dual-write surface scales down with it.

| Concern | Decision |
| --- | --- |
| Model authoring | the OpenFGA **DSL** at `infra/auth/openfga/model.fga` is the single source of truth. `mise run gen:authz-model` transforms it to JSON for the API |
| Scope | **one global model**, not one per service, because authz relationships often cross service boundaries |
| Tests | check assertions at `infra/auth/openfga/fga.yaml`. CI runs `fga model test` and asserts that the JSON matches the DSL |
| Deployment | Helm, on the shared platform Postgres, as a plain Deployment and Service with an `openfga migrate` initContainer. Our own services use the same pattern. OpenFGA ships no first-party operator |
| Bootstrap | OpenFGA needs a **store** and an immutable, versioned **authorization model**, both created in-cluster. A seed Job makes sure that a store named `platform` exists. The Job writes the model and applies the static ops grants. Services resolve the store by name at first use, so no store-ID plumbing is needed. The ids are opaque deploy-time values, not secrets |

### Accepted limitation: no consistency token

SpiceDB's `ZedToken` gives read-after-write consistency per request. OpenFGA has no equivalent, per [openfga/roadmap#67]. It offers only a coarse `HIGHER_CONSISTENCY` flag.

This is not a day-one concern. It matters only at large, heavily replicated scale, and nothing here depends on it. The `Checker` runs at default consistency, and the dual write passes no token.

| Field | Value |
| --- | --- |
| **Trigger** | a read-after-write staleness bug appears in production: a user completes a mutation and is then denied the resource it granted |
| **Seam** | ✓ every read goes through `Checker`. So higher consistency is an argument per call site inside one library, not a change in any service |
| **Cost if adopted late** | the failure has already reached users as an intermittent permission error. That is the hardest class of authz bug to attribute |

[openfga/roadmap#67]: https://github.com/openfga/roadmap/issues/67

### Dual-write discipline

Every authz-relevant mutation runs in a Temporal workflow, per [ADR-0302](0302-temporal.md). These mutations are create, share, transfer, and delete on a protected resource. The workflow holds the database write and the OpenFGA write as activities, so the pair cannot half-apply.

A direct database write to an authz-relevant table outside a workflow blocks review. A depguard-style rule against the relevant store methods enforces this.

### Identity is validated at the edge and carried as headers

The edge validates tokens once. **Past the edge there are no tokens.** Identity travels as a fixed set of trusted headers, with the same shape for every request.

| Stage | Behaviour |
| --- | --- |
| Edge validation | Oathkeeper validates the Kratos session cookie or the Hydra-issued JWT. JWTs are RS256, with keys at a JWKS endpoint. Validation requires issuer, audience, expiry, signature, and `nbf` with a 30s skew tolerance. `docs/reference/jwt-validation.md` defines these rules once |
| Header injection | Oathkeeper **strips any identity headers that the client supplies** and injects authoritative `X-User-Id`, `X-Org-Id`, and `X-Roles` |
| Service read | `libs/go/authmw/` reads the headers into a typed principal. Services never fetch JWKS or parse a JWT |
| Service to service | no token. The same headers are forwarded, gated by Cilium NetworkPolicy. This is network identity, not a machine token per call |

A conformance suite at `libs/go/authmw/conformance/` ships with the repo. It holds identity-header fixtures with expected principals and authorization outcomes. Any non-Go service passes it.

### Authorizing operator tooling at the edge

The rule `the edge validates, services decide` assumes that a first-party service exists to decide. Operator dashboards are third-party and cannot call `Checker`. So their authorization happens at the edge in two layers, per [ADR-0306](0306-trust-tiers-and-urls.md).

| Layer | Mechanism |
| --- | --- |
| **Coarse gate, mandatory** | The ops-tier Oathkeeper requires `X-Roles` to contain `operator`, plus an **AAL2** session. It reads only the session and its claims, and makes **no OpenFGA call**. This is deliberate: the debugging surface does not share fate with the product authorization plane. An OpenFGA outage must not lock every operator out of the dashboards they need to diagnose it. See [`docs/guide/break-glass.md`](../guide/break-glass.md) |
| **Fine gate, optional** | The route adds the `remote_json` authorizer, which calls `Checker` and models each tool as a `dashboard` resource. It is deferred until an operator should reach some tools and not others. Until then, the coarse gate expresses the same policy. The seam is the authorizer field on one route. The cost of the wait: until that point, every operator has access to every tool |

This is the only sanctioned permission decision at the edge. Product surfaces decide inside the service through `Checker`.

### Security verification: ASVS Level 2

**The application security bar is [OWASP ASVS](https://owasp.org/www-project-application-security-verification-standard/) Level 2**, pinned to version 5.0. ASVS describes L2 as right for an application that handles significant transactions and personal data. That is the default posture of this platform.

The neighbouring levels do not fit:

- L1 is a floor that a team can reach without design support, and it asserts little.
- L3 targets systems where a breach is a safety event. Its demands reshape decisions made deliberately elsewhere in this set. They include per-transaction reauthentication, full segregation of duties, and an exhaustive access audit.

The version is pinned, so an upstream revision is a reviewed bump and not a goal that moves silently. [ADR-0200](0200-cluster-topology.md) applies the same discipline to the Pod Security Standards version.

**Many ADRs meet the claim together, not this ADR alone.** ASVS is much broader than identity. So this ADR states the bar and names the owner of each part:

| Concern | Owner |
| --- | --- |
| Authentication, session management | this ADR: Kratos sessions, the NIST 800-63B password policy, AAL levels |
| Access control | this ADR: OpenFGA through `Checker`, never inline |
| Input validation and encoding | [ADR-0303](0303-api-contracts-and-lifecycle.md): validators are generated from the spec, so coverage does not depend on diligence |
| Error handling and logging | the error envelope of [ADR-0303](0303-api-contracts-and-lifecycle.md), and the structured logs and PII rule of [ADR-0500](0500-observability.md) |
| Data protection and privacy | [ADR-0301](0301-data-lifecycle-privacy.md) |
| Communications security | WireGuard east-west, per [ADR-0206](0206-cluster-networking.md), and verified TLS everywhere, per [ADR-0205](0205-environment-parity.md) |
| Configuration and secrets | [ADR-0202](0202-secrets.md) |
| Malicious-code and supply chain | [ADR-0104](0104-supply-chain-security.md) |

**The bar covers first-party surfaces.** Vendored operator tooling is outside it: Lowdefy, Grafana, and pgweb, per [ADR-0401](0401-internal-admin.md) and [ADR-0501](0501-operator-uis-and-dashboards.md). [ADR-0400](0400-frontend.md) draws the same boundary for accessibility, for the same reason. A claim over software we do not write is a claim we cannot keep.

**A named holder verifies the claim on a cadence.** L2 is a design claim, not a test result. A claim that nobody examines becomes false over time. So the examination is scheduled, not only intended:

| Field | Value |
| --- | --- |
| Owner | the platform team, as a whole. For each row of the table above, the owner of the ADR that the row names verifies it |
| Cadence | once per ASVS release, and on any change to the ADR that owns a row |
| Artefact | a verdict per row in [`docs/reference/asvs-verification.md`](../reference/asvs-verification.md): met, met with a stated exception, or unmet. The file is live state and carries the date of the last examination of each row |
| Failure | a row that stays unexamined for a full cadence is stated as unverified, not as met. The bar stays the target and stops being a claim |

### Day-one component cost

| Component | Role |
| --- | --- |
| Kratos | human login |
| Oathkeeper | edge validation and identity-header injection, per [ADR-0305](0305-edge-auth-and-traffic-policy.md) |
| OpenFGA | authorization |
| `services/orgs/` | organisations and memberships |
| `libs/go/authmw/` and `libs/go/authz/` | header reader and `Checker` |

Hydra is deployed only when a project exposes a public API. There is no service-to-service token. All components share the platform Postgres and the observability stack.

## Consequences

### Positive

- Login UI freedom: the sign-in surface is the product's own, and there is no fight against vendor templates.
- One way to get a token for human or machine identity.
- Authz is a single coherent model from day one. There is no deferred migration and no per-service RBAC table.
- Schema in files, tests in files, a CLI for debugging, and GitOps for everything.
- Safe for services in other languages: auth integration is a protocol contract, so escape-hatch services take part on equal terms.
- Authz-relevant mutations go through Temporal, so the structure contains the dual-write risk.

### Negative and Risks

- **Three platform components on day one** for internal-only projects, plus the `orgs` service. Accepted. The constraints are headless login and ReBAC, both from day one, and they make consolidation impossible without compromise. NetworkPolicy replaces the service-to-service token, and this removes a validation path from every service.
- **To build B2B organisations on Kratos is real work.** Accepted. The alternative costs the UI requirement.
- **Dual-write discipline must be enforced.** A direct write that skips the workflow is a silent authz bug. Lint, a review checklist, and integration tests mitigate it. The tests assert the OpenFGA state after every workflow.
- **ASVS L2 is a design claim, not a test result.** No job proves it. It holds by construction, and review checks it. Its value: a reviewer has a named checklist instead of a private sense of what secure means. Its risk: a claim that nobody examines becomes false over time. The quarterly review schedule assigns the examination. A row with no examination for a full cadence is marked unverified.
- **L2 is not the bar that every deployment needs.** A regulated project raises it and records the delta in its own ADR. It does not edit this one.
- **The coarse ops gate is a claim, not a policy check.** An operator whose access should end keeps it until their session expires or someone removes the flag. This is accepted deliberately, so the dashboards survive an authz outage.

## Rules

- The application security bar is OWASP ASVS 5.0 Level 2 for first-party surfaces. Vendored operator tooling is out of scope, and the exclusion is stated, not assumed. `(ref: OWASP ASVS 5.0 L2)`
- Ory Kratos owns human identity. There is no alternate user store.
- Ory Hydra issues external tokens, and it is deployed only for projects that expose a public API. No service issues its own tokens. Access tokens are `at+jwt`. The authorization-code grant requires PKCE for every client. Implicit and resource-owner-password grants are disabled. `(ref: RFC 9068, RFC 7636, OIDC Core)`
- The login UI is the Next.js app that drives Kratos self-service flows. Hosted pages are not used.
- The password policy is `min_password_length: 12` plus `identifier_similarity_check_enabled: true` in every environment. The breach check is off by default and enabled per environment where the egress exists. It is never enabled where the egress does not exist, because it then fails open silently. `(ref: NIST SP 800-63B)`
- The session cookie is `SameSite=Lax`, `Secure`, `HttpOnly`. `(ref: RFC 6265bis)`
- `services/orgs/` owns B2B organisations. Other services consult its HTTP API. `(CI: ci:lint)`
- Every protected resource belongs to an `org`, and a user acts only through a role in an org. Every identity gets a personal org at registration through the `RegisterUser` dual write. A single shared default org is not used.
- A change to the tenancy model is confined to the registration webhook path. It is a deliberate decision per project.
- Directory provisioning ships only after the documented contract trigger fires. Until then, membership changes go through invitations.
- Authorization is OpenFGA, accessed only through the `Checker` interface. Direct SDK use elsewhere is not permitted. `(CI: ci:lint)`
- The OpenFGA schema is one global file. Per-service schemas are not used. `(CI: lint:authz)`
- Authz-relevant mutations run inside a Temporal workflow, with the database write and the OpenFGA write as separate activities. `(CI: lint:authz-dual-write)`
- Inline role checks in handlers are not used. Every permission decision goes through `Checker`. `(CI: lint:authz)`
- The edge gates operator dashboards by the coarse claim plus AAL2, with no OpenFGA call. Optional refinement per tool adds the `remote_json` authorizer.
- The coarse operator claim is `metadata_public.operator`, written only through the Kratos admin API. It is never an identity trait. Self-service registration and settings write traits, so any visitor can grant a trait claim to themselves.
- An operator is a registered user promoted in the admin console. The console toggle runs one workflow that writes the claim and the `group:operator` grant together. The platform has no operator-creation endpoint. `mise run ops:grant` is the one path outside the console. It needs cluster credentials, and it exists for the first operator and for a console outage.
- A simple instance uses an L1 schema, which is the first-class default. L2 and L3 grow the same schema on the same engine.
- The edge validates tokens once, with the algorithm pinned and `iss`, `aud`, and `exp` checked. Services do not validate tokens. `(CI: lint:auth-inline; ref: RFC 8725)`
- Identity is carried as `X-User-Id`, `X-Org-Id`, and `X-Roles`. The edge injects these headers, and internal calls forward them unchanged. Services read identity only from these headers. `(CI: lint:authz)`
- Service-to-service calls carry no token. Shared secrets, HMAC schemes, and per-call machine tokens are not used.
- A non-Go service reads the identity headers through the same contract, and it passes `libs/go/authmw/conformance/` before it merges.
- Auth configuration is canonical only at `infra/auth/*`. File injection delivers it to charts. It is never hand-copied inline into the values of a chart. `(CI: ci:gen)`
