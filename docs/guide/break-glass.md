# Break-glass and ops recovery

This guide shows how an operator reaches the debugging surfaces when the auth plane that gates them is down. The surfaces are Grafana, Hubble UI, Argo CD, and the admin console. It goes with [ADR-0306](../adr/0306-trust-tiers-and-urls.md) and [ADR-0304](../adr/0304-identity-and-authorization.md).

## Principle: no shared fate in the recovery path

The tools and credentials that recover a system must not depend on that system. A recovery path that shares fate with the failed plane is a circular dependency. It passes every drill and fails in the one real outage. Every mechanism below gives the ops tier an **independent trust root**.

This guide uses two methods:

- **Logical decoupling.** The stack stays the same, and the fragile link is removed. The ops tier's coarse gate is an `operator` **claim plus AAL2**, not an OpenFGA `Checker` call, per [ADR-0304](../adr/0304-identity-and-authorization.md). So an OpenFGA outage does not lock operators out. This method is cheap, but Kratos and Oathkeeper are still in the path.
- **Physical decoupling, or break-glass.** This is a separate path with its own credentials. It bypasses the plane completely. It is the path that helps you when auth is fully down.

## The ladder for this stack

The ladder fits a small platform team. It has no separate operator IdP or PKI. Those bring back the cost of two auth systems that [ADR-0304](../adr/0304-identity-and-authorization.md) avoids.

1. **Everyday:** use the SSO ops gate. This is the Oathkeeper `operator` claim plus AAL2 at `*.ops.<host>`, per [ADR-0306](../adr/0306-trust-tiers-and-urls.md).
2. **Reduce the need for break-glass:** use the claim-based coarse gate above. Only a full Kratos or Oathkeeper outage then locks operators out. An OpenFGA outage does not.
3. **True break-glass, when auth is fully down:** use `kubectl port-forward` with a kubeconfig that you got through a separate channel. The kubeconfig authenticates to the API server with a client cert or token. That trust root is independent of Kratos and OpenFGA. It reaches any tool directly and bypasses Traefik, Oathkeeper, and OpenFGA:

   ```sh
   kubectl -n platform port-forward svc/grafana 3000:80       # then http://localhost:3000
   kubectl -n kube-system port-forward svc/hubble-ui 8080:80
   kubectl -n argocd   port-forward svc/argocd-server 8081:80
   ```

   The `scripts/cluster.sh` banner prints this procedure as the diagnose path. It is the approved break-glass path.

## The first operator

The admin console promotes operators, and only an operator can reach it. So a new environment's first operator follows these steps:

1. Register on the storefront like any user.
2. Enrol TOTP.
3. Get promoted from a workstation that holds the cluster's kubeconfig:

   ```sh
   mise run ops:grant -- first.operator@example.com
   ```

Every later promotion and demotion happens in the console, per [ADR-0304](../adr/0304-identity-and-authorization.md).

## Requirements on the break-glass path

- **Provisioned in advance.** An operator must be able to get the kubeconfig *before* an outage. It **must not sit behind the product SSO**. Otherwise it shares fate with the plane it recovers.
- **Fail secure, not fail open.** The ops gate never opens when auth is unreachable. Recovery is a separate strong path, never a weaker gate.
- **Visible and audited.** Every use of break-glass is logged and reviewed afterwards.
- **Tested.** Rehearse it in a game day or DiRT exercise, together with the DR drill, per [ADR-0200](../adr/0200-cluster-topology.md). An untested break-glass path fails when you need it.

## Optional hardening

As a second break-glass path, seal the Grafana and Argo **local-admin** credentials in a SOPS secret, per [ADR-0202](../adr/0202-secrets.md). These credentials do not depend on SSO. Keep them disabled in normal operation. They are not required while the kubeconfig path above is the approved route.
