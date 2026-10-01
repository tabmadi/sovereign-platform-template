# JWT validation

This document is the single definition of how the edge validates a JWT that Hydra issues. [ADR-0304](../adr/0304-identity-and-authorization.md) and [ADR-0305](../adr/0305-edge-auth-and-traffic-policy.md) refer to it. Browser callers use the Kratos session cookie instead. This document covers the JWT path for third-party clients and machine clients. That path exists only when Hydra is enabled with `hydra_thirdparty`.

## Validation contract

Ory Oathkeeper validates every JWT at the edge before it injects any identity header. It accepts a token only if all of these checks pass:

| Check | Requirement |
| --- | --- |
| Algorithm | RS256, which is asymmetric. `none` and HMAC are rejected |
| Signature | verifies against the issuer's JWKS |
| `iss`, the issuer | matches the configured Hydra issuer URL for the environment |
| `aud`, the audience | contains the expected API audience |
| `exp`, the expiry | in the future |
| `nbf`, not-before | in the past |
| Clock skew | 30 s tolerance on `exp` and `nbf` |

The edge fetches keys from the issuer's JWKS endpoint and caches them. No service fetches the JWKS itself, because only the edge validates, per [ADR-0304](../adr/0304-identity-and-authorization.md).

## After validation

On success, Oathkeeper removes any identity headers that the client sent. It then injects the authoritative `X-User-Id`, `X-Org-Id`, and `X-Roles` headers from the token claims `sub`, `org_id`, and `roles`. After the edge there are no tokens. Services read identity only from these headers through `libs/go/authmw/`, per [ADR-0304](../adr/0304-identity-and-authorization.md).

On failure, the edge rejects the request with `401`. The request never reaches a backend.
