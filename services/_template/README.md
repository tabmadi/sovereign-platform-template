# `_template` service

The starting skeleton for every backend service. **Do not edit this directory to add features.** Copy it to `services/<your-name>/` and strip the build tags. `scripts/new-service.sh <name>` does this for you.

## Contents

| Path | Purpose |
| --- | --- |
| `openapi.yaml` | The service contract, per ADR-0303. It is the source of truth. |
| `cmd/server/main.go` | HTTP server entry point. It calls `obs.Init`, `dbmw`, and the other wiring. |
| `cmd/worker/main.go` | Temporal worker entry point, per ADR-0302 |
| `internal/handlers/` | Implements the ogen-generated `Handler`. It reads and writes through the sqlc store |
| `internal/workflows/` | Owned Temporal workflows, per ADR-0302 |
| `internal/activities/` | Owned Temporal activities |
| `internal/store/queries/` | sqlc input: SQL files, per ADR-0300 |
| `internal/store/` | Generated sqlc output: typed Go |
| `migrations/` | dbmate migrations, per ADR-0300 |
| `sqlc.yaml` | sqlc config for this service |
| `.mise.toml` | Service-local tasks: `server`, `worker`, `test`, `lint`, `migrate`, `generate`, and `build` |
| `Dockerfile` | Multi-stage build with a `CMD` build arg, per ADR-0101 |

## Checklist for a new service

`scripts/new-service.sh` copies the skeleton. It cannot decide the items below for you. The service contract in [ADR-0205](../../docs/adr/0205-environment-parity.md) gives the full reasons. `mise run lint:service-contract` fails on any item you miss.

1. **Register a local port** in `scripts/lib/ports.sh`. Set the same `PORT` in your `.mise.toml`. The skeleton ships `80XX`, so the lint fails until you do. Ports must be unique, and `:8080` is reserved for the local edge mapping.
2. **Trim `dep:*`** to what the service reads. Drop `dep:temporal` if there is no worker, and `dep:postgres` if there is no database.
3. **Add `svc:*`** for every other service that you call over HTTP. If you miss one, the service starts cleanly and then fails on the first outbound call.
4. **Write `.env.example`** with every variable that you read. It creates a fresh clone's `.env`, so an unlisted variable gets a default with no warning.
5. **Add a values file per environment** under `infra/gitops/services/<env>/values/`. This step deploys the service. The ApplicationSet generates one Argo Application *per values file*. If you skip an environment, the service is absent there and nothing reports it. If that is on purpose, declare `# platform/not-deployed: <env>` in your `.mise.toml` instead.
6. **Decide your edge exposure** in those values: `ingress.enabled`, `ingress.resources`, and `networkPolicy.allowFrom` for east-west callers. An internal service must set `networkPolicy.allowFromGateway: false`. `services/authz` is a worked example.
7. **Replace this README** with one that describes the purpose of the service.

## Standard tasks

```sh
mise run server     # HTTP server
mise run worker     # Temporal worker
mise run test
mise run lint
mise run migrate    # dbmate up
mise run generate   # sqlc and openapi codegen
mise run build      # go build
```

## Build tags

Every `*.go` file in this directory has `//go:build _template`. This keeps the template out of the repo-wide `go build ./...`. When you scaffold a new service, `scripts/new-service.sh` strips these tags.
