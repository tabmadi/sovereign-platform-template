# authz

The edge authorizer. Oathkeeper's `remote_json` authorizer calls it on every gated request, as `infra/auth/oathkeeper/values.yaml` configures. It answers by checking the relationship tuples in OpenFGA through `libs/go/authz`.

Unlike the shop services, it is **internal**. It has no `/api` edge route and no database. Its `openapi.yaml` declares `x-audience: cluster`, so the developer portals do not show it, per ADR-0303. Its three callers all reach it east-west on the server port:

- Oathkeeper, on `POST /authorize`.
- The frontend server, on `POST /authorize/relation`, in `apps/frontend/src/lib/auth/panel-access.ts`.
- The `authz` connection of the Lowdefy admin console in `apps/admin/lowdefy.yaml`, on `/identities`. This is the console's Users page.

```sh
cd services/authz
mise run server     # http://localhost:8085
```

`:8085` is this service's registered local port in `scripts/lib/ports.sh`. In the cluster, it binds `:8080` like every other service.

It also owns one workflow. The operator role is a dual write: the `operator` flag in the Kratos identity metadata, then a `group:operator` tuple in OpenFGA. ADR-0304 puts an authz-relevant pair in a Temporal workflow. `PUT /identities/{id}` with a changed `operator` value runs the `SetOperator` workflow to completion, then returns the updated identity. That update is the only way to promote or demote an operator. The worker in `cmd/worker` serves the `authz-queue`. It is the only worker on the platform that opens no database pool, because this service owns no schema.

It has no database, so it declares only `dep:openfga`. It needs an OpenFGA preshared key at startup, even though the client dials on first use. Locally, that is the fixed dev key in `.env.example`. In the cluster, it comes from the SOPS-managed `openfga-creds` secret.
