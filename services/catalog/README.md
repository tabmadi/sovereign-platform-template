# catalog

The simplest shop service. It is pure CRUD over a single `products` table, with no workflows.

It shows the generated-code path, in this order:

1. The OpenAPI spec.
2. The ogen server in `libs/go/sdks/catalog`.
3. `internal/handlers`, which implements the generated `Handler`.
4. The sqlc queries.
5. The dbmate migrations.
6. The observability middleware.

```sh
cd services/catalog
mise run migrate    # apply migrations to $DATABASE_URL
mise run server     # http://localhost:8081, its registered port. In the cluster it is :8080
```
