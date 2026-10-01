# Threat Model

The controls are decided and enforced. No document states **who they are against**. Without a named adversary, only the designer of a control set can review it. Everyone else guesses the assumption behind each control.

This is STRIDE-lite over the three boundaries that matter here. It decides nothing. Every control links to its ADR, and every accepted gap links to [`risk-register.md`](risk-register.md).

## Adversaries

| Adversary | Capability assumed | What they want |
| --- | --- | --- |
| **Unauthenticated internet** | can reach every published origin, at any rate, forever | credentials, data, a foothold, or to use up the platform's capacity |
| **Authenticated user** | a valid session in one organisation | another organisation's data, or authority that nobody granted them |
| **Compromised first-party pod** | code execution inside a workload that the platform runs, with that pod's network allowances | lateral movement to the data tier, cloud credentials, persistence |
| **Compromised build path** | can land a commit, or influence a dependency | a malicious image that runs in production |
| **Stolen operator session** | a browser that holds an operator's session | the ops tier, which is the cluster's control surface |
| **Provider or physical access** | the infrastructure below the platform | data at rest, and the machines |

**Not modelled.** These adversaries are outside the model:

- a nation-state adversary with supply-chain and hardware capability
- an insider with the SOPS recovery key
- a compromised upstream image publisher whose signature verifies

Each would defeat controls here, and each is excluded on purpose, not by oversight. [ADR-0000](../adr/0000-platform-foundations.md) makes the same exclusion when it declines TUF.

## Boundary 1: the internet and the edge

| Threat | Control | Owner |
| --- | --- | --- |
| **Spoofing** identity by supplying identity headers | Oathkeeper removes every identity header that the client sends before it injects the authoritative ones | [ADR-0305](../adr/0305-edge-auth-and-traffic-policy.md) |
| **Spoofing** a session by forging or replaying a token | the edge validates tokens once, with the algorithm pinned and `iss`, `aud`, and `exp` checked. Sessions are `Secure`, `HttpOnly`, and `SameSite=Lax` | [ADR-0304](../adr/0304-identity-and-authorization.md) |
| **Tampering** with a request in transit | TLS at the edge, verified in every environment | [ADR-0205](../adr/0205-environment-parity.md) |
| **Repudiation** of an authorization decision | per-decision events from the authorization service into the log store | [ADR-0304](../adr/0304-identity-and-authorization.md) |
| **Denial of service** by brute force or volume | rate limiting at the edge, per route, with a tighter limit on the authentication paths | [ADR-0305](../adr/0305-edge-auth-and-traffic-policy.md) |
| **Elevation** through a cross-origin or cross-site request | a strict per-request nonce CSP, `frame-ancestors 'none'`, an origin check on server actions, and Kratos's own anti-CSRF token on self-service flows | [ADR-0400](../adr/0400-frontend.md), [ADR-0304](../adr/0304-identity-and-authorization.md) |
| **Elevation** from a product session into the ops tier | the ops coarse gate requires an `operator` claim and AAL2. A product session alone reaches nothing | [ADR-0306](../adr/0306-trust-tiers-and-urls.md) |
| **Information disclosure** through a stolen operator session that uses an XSS | the product-origin CSP, and nothing else. **Accepted risk 1** | [risk 1](risk-register.md) |

## Boundary 2: inside the cluster

| Threat | Control | Owner |
| --- | --- | --- |
| **Spoofing** identity between services | no cryptographic control. A service trusts `X-User-Id` because default-deny controls who can reach its port. **Accepted risk 2** | [risk 2](risk-register.md) |
| **Elevation** by a compromised pod that reaches the data tier | default-deny east-west, so reachability is an allowance and not a default | [ADR-0206](../adr/0206-cluster-networking.md) |
| **Information disclosure** by capture of east-west traffic | WireGuard encryption of all pod traffic | [ADR-0206](../adr/0206-cluster-networking.md) |
| **Elevation** from a pod to the node | Pod Security Admission `restricted` in every namespace, with a pinned enforce-version. The node is immutable, with no shell and no package manager | [ADR-0206](../adr/0206-cluster-networking.md) |
| **Information disclosure** of cloud credentials through the metadata endpoint | egress policy denies the metadata address by name | [ADR-0206](../adr/0206-cluster-networking.md) |
| **Elevation** across tenants in one database | one logical database per service, per-service credentials, and no service reaches the data of another | [ADR-0300](../adr/0300-data.md) |
| **Elevation** by an authenticated user who reaches another organisation's resources | `Checker` authorizes every read and every mutation as if the identifier were public | [ADR-0304](../adr/0304-identity-and-authorization.md), [ADR-0003](../adr/0003-naming-and-identifiers.md) |
| **Tampering** with the authorization store through a side channel | writes that affect authz are dual-written inside a workflow, never by an ad-hoc path | [ADR-0302](../adr/0302-temporal.md), [ADR-0401](../adr/0401-internal-admin.md) |

## Boundary 3: the build and deploy path

| Threat | Control | Owner |
| --- | --- | --- |
| **Tampering** with an image between build and run | admission verifies the cosign signature and the required attestations. Every reference is digest-pinned | [ADR-0104](../adr/0104-supply-chain-security.md), [ADR-0203](../adr/0203-policy-enforcement.md) |
| **Spoofing** the origin of an image | SOPS holds the signing key, and no person holds it. The public key is committed, and the admission policy names it | [ADR-0104](../adr/0104-supply-chain-security.md) |
| **Tampering** with cluster state outside the repository | Argo CD is the only deploy mechanism, and production does not self-heal. So drift is shown and not silently corrected | [ADR-0201](../adr/0201-gitops.md) |
| **Elevation** through a dependency with a known vulnerability | scanning as a merge gate. The finding blocks before anything ships | [ADR-0104](../adr/0104-supply-chain-security.md) |
| **Information disclosure** of secrets in the repository | SOPS with age recipients. Plaintext is never committed, and the local key decrypts only throwaway values | [ADR-0202](../adr/0202-secrets.md) |
| **Denial of service** by the gate itself | Kyverno's webhook fails closed for the whole cluster. **Accepted risk 5**, with a documented break-glass | [risk 5](risk-register.md) |

## What the model shows

**The strongest boundary is the outermost one, and the weakest is the middle one.** The edge validates, strips, and injects. Inside the cluster, a service believes an identity header because of where it came from. [ADR-0305](../adr/0305-edge-auth-and-traffic-policy.md) makes this trade on purpose. So read the *compromised first-party pod* adversary first. The design depends most on this adversary's capability being rare.

**Every gap in these tables is a row in the register, and every register row has a trigger.** Nobody reads a threat model twice if it ends in a list of unmanaged worries.
