# Operator Panels

This page lists every web panel that an operator of this project can open, and what gates each one. [ADR-0306](../adr/0306-trust-tiers-and-urls.md) decides the hostnames. [ADR-0501](../adr/0501-operator-uis-and-dashboards.md) decides which panel answers which question.

`<host>` is the environment host. On the local tier it is `dev.localtest.me:8443`. In a deployed environment it is the `envHost` of that environment's values file.

**A generated project fills in the last table.** The ops tier is the same in every project. The panels outside it belong to the project's own forge and infrastructure.

## The ops tier

One gate covers every panel in this table: an operator session at AAL2, per [ADR-0304](../adr/0304-identity-and-authorization.md). Log in once at `https://<host>/auth/login`, and every panel opens. A panel answers `401` without that session. [break-glass](../guide/break-glass.md) describes the first operator of an environment.

| Panel | URL | Use it to | Runs in |
| --- | --- | --- | --- |
| Grafana | `https://grafana.ops.<host>/` | see whether anything is wrong, and where | every environment |
| Argo CD | `https://argocd.ops.<host>/` | see what is deployed, and whether it synced | every environment |
| Hubble UI | `https://hubble.ops.<host>/` | see what talks to what, and which flow the network denies | every environment |
| Headlamp | `https://headlamp.ops.<host>/` | read pods, their descriptions, and their logs | every environment |
| Temporal UI | `https://temporal.ops.<host>/` | read workflow histories and schedules | every environment |
| Admin console | `https://lowdefy.ops.<host>/` | manage users, operators, and product data, per [ADR-0401](../adr/0401-internal-admin.md) | every environment |
| pgweb | `https://pgweb.ops.<host>/` | read the databases. It is read-only | every environment |
| zot console | `https://zot.ops.<host>/` | browse the image catalogue and its tags | every environment |
| SeaweedFS admin | `https://seaweedfs.ops.<host>/` | inspect object storage | non-production |
| Mailpit | `https://mailpit.ops.<host>/` | read the mail that the sink caught | where the environment sinks mail |

The route of a panel exists in every environment. It answers `404` where the panel's chart is off.

## Outside the ops tier

These panels do not use the operator session. Each one has its own login, and [credential-register](credential-register.md) records where that login is kept.

| Panel | URL | Gate |
| --- | --- | --- |
| Registry | `https://registry.<host>/` | the registry's push or pull credential, per [ADR-0105](../adr/0105-image-registry.md) |
| Forge | the origin of the project's forge | the forge's own login, per [ADR-0102](../adr/0102-source-control-and-ci.md) |
| Infrastructure console | the provider's console, or the hypervisor's panel | its own login. It is a break-glass credential |
