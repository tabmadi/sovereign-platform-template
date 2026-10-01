# authz

The edge authorizer. Oathkeeper's `remote_json` authorizer calls it on every gated request, as `infra/auth/oathkeeper/values.yaml` configures. It answers by checking the relationship tuples in OpenFGA through `libs/go/authz`.

Unlike the shop services, it is **internal**. It has no `/api` edge route, no database, and no OpenAPI spec. It is not a public API, so `lint:api-audience` exempts it. Its two callers both reach it east-west on the server port:

- Oathkeeper.
- The `authz-admin` connection of the Lowdefy admin console in `apps/admin/lowdefy.yaml`. It POSTs to `/operators` from backend to backend and does not go back through the edge.

```sh
cd services/authz
mise run server     # http://localhost:8085
```

`:8085` is this service's registered local port in `scripts/lib/ports.sh`. In the cluster, it binds `:8080` like every other service.

It also owns one workflow. Creating an operator is a dual write: a Kratos identity, then a `group:operator` tuple. ADR-0304 puts an authz-relevant pair in a Temporal workflow. So `POST /operators` returns `202` and a handle, not the operator. The worker in `cmd/worker` serves the `authz-queue`. It is the only worker on the platform that opens no database pool, because this service owns no schema.

It has no database, so it declares only `dep:openfga`. It needs an OpenFGA preshared key at startup, even though the client dials on first use. Locally, that is the fixed dev key in `.env.example`. In the cluster, it comes from the SOPS-managed `openfga-creds` secret.
