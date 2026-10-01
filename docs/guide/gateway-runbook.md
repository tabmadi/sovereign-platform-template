# Gateway and edge runbook

This guide shows how to operate the edge: Traefik and Oathkeeper. [ADR-0305](../adr/0305-edge-auth-and-traffic-policy.md) holds the decision: Traefik ingress, the Oathkeeper identity filter, and no API-management gateway. [ADR-0306](../adr/0306-trust-tiers-and-urls.md) holds the trust tiers and hostnames.

## Model

- **Traefik** is the only ingress. It does TLS with cert-manager, host and path routing, load balancing, and rate limiting.
- **Oathkeeper** sits behind Traefik as the identity filter, per [ADR-0305](../adr/0305-edge-auth-and-traffic-policy.md) and [ADR-0304](../adr/0304-identity-and-authorization.md). It first strips any identity headers from the client. It then authenticates and injects `X-User-Id`, `X-Org-Id`, and `X-Roles`.
- Edge config lives in `infra/gateway/` and `infra/auth/oathkeeper/`. It is not inlined into chart values. `mise run lint:auth-inline` checks this.

## Add a route

**For a product API resource:**

1. Declare the resource in the service's `ingress.resources`. The edge routes `/api/<resource>` on the apex host and strips the `/api` prefix.
2. Check that no other service owns that resource name. `mise run lint:openapi` rejects the collision, but a manual check is faster, per [ADR-0303](../adr/0303-api-contracts-and-lifecycle.md).
3. Apply `strip-identity-headers` **before** forward-auth in the middleware chain. In the wrong order, a client can inject its own `X-User-Id`. `mise run lint:authz` fails the build on the wrong order.

**For an ops tool:**

1. Add a `Host({tool}.ops.<host>)` IngressRoute behind the ops forward-auth. Its coarse gate is the `operator` claim plus AAL2, per [ADR-0306](../adr/0306-trust-tiers-and-urls.md).
2. Add the Oathkeeper access rule in `infra/auth/oathkeeper/access-rules.json`. Use `remote_json`. `mise run lint:authz` rejects `allow`. An `allow` rule on the ops tier is an unauthenticated origin on the cluster's control surface.

## Certificates and DNS

- Each environment has two wildcard certs: `*.<host>` and `*.ops.<host>`. cert-manager issues them with DNS-01, per [ADR-0202](../adr/0202-secrets.md) and [ADR-0306](../adr/0306-trust-tiers-and-urls.md).
- `*.<host>` and `*.ops.<host>` resolve to the edge. Locally, `*.localtest.me` resolves to `127.0.0.1`.

## Diagnose

- A 401 at the edge means Oathkeeper rejects the session or the JWT. See [jwt-validation](../reference/jwt-validation.md).
- A 403 on an ops origin comes from one of two checks:
  - the coarse claim gate, when the `operator` claim or AAL2 is missing
  - the optional OpenFGA check for each tool
- If the auth plane itself is down, follow [break-glass](break-glass.md).
- Inspect live routing in the Traefik dashboard. Or read the edge and Oathkeeper logs with `kubectl -n platform logs`.
