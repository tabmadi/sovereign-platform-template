# Local environment reference

These are lookup tables for the local cluster: ports, URLs, and the environment contract. [dev-loop](../dev-loop.md) explains how to *use* them. [ADR-0600](../adr/0600-local-development-loop.md) and [ADR-0306](../adr/0306-trust-tiers-and-urls.md) hold the decisions behind them.

## Service ports on the host

`scripts/lib/ports.sh` assigns the ports, and each service's `.mise.toml` sets its port as `PORT`. `lint:ports` enforces that the two agree and that no two services collide.

| Service | Host port |
| --- | --- |
| catalog | 8081 |
| orders | 8082 |
| orgs | 8083 |
| payment | 8084 |
| authz | 8085 |

`:8080` is unassigned, because the host maps it to the edge. This changes nothing in the cluster: pods still bind `:8080`.

To override the port for a single run, set `PORT=` in that service's `.env`. It wins over the registry. Prefer an edit to the registry, so that the `<SVC>_URL` defaults of callers stay correct.

## Forwarded dependencies

`mise run dev:forward` exposes the in-cluster dependencies to the host process and to tools such as `psql`.

| Dependency | Host address |
| --- | --- |
| Postgres | `localhost:5432` |
| Temporal gRPC | `localhost:7233` |
| Temporal UI | `localhost:8233` |
| OpenFGA | `localhost:18080` |

OpenFGA is forwarded to `18080` and not to its own `8080`, because the host maps `8080` to the edge. So `OPENFGA_API_URL` in every `.env.example` points at `18080`.

## Product URLs

Everything is served from one origin, `https://dev.localtest.me:8443`. The hostname is real public DNS that resolves to `127.0.0.1`. A locally issued wildcard certificate covers it. The edge matches the longest prefix, so the specific routes win over the `/` catch-all.

Deployed environments terminate on `443` and leave out the port.

| Path | Serves | Auth | Defined in |
| --- | --- | --- | --- |
| `/` | landing page, from the host dev server | public | `infra/local/edge-auth.yaml` |
| `/panel`, `/devportal` | authenticated frontend areas | session | `apps/frontend/src/proxy.ts` |
| `/auth/login`, `/auth/registration`, and the other Kratos UI pages | Kratos UI pages, from the host dev server | public | `infra/local/edge-auth.yaml` |
| `/auth/self-service`, `/auth/.well-known`, `/auth/sessions` | Kratos public API | public | `infra/local/edge-auth.yaml` |
| `/api/<resource>` | service APIs in a flat namespace, per [ADR-0306](../adr/0306-trust-tiers-and-urls.md) | Oathkeeper | `infra/helm/service/templates/ingressroute.yaml` |
| `/api/rum` | browser-telemetry ingest | public | `infra/gateway/frontend-observability.yaml` |

## Ops URLs

Each tool has one origin under `*.ops.<host>`, never a product path. `infra/gateway/ingressroutes.yaml` defines every route. The route of an opt-in tool resolves to a backend only when its chart is enabled.

The **Auth** column is the coarse gate, which is always on. It requires the `operator` claim plus an AAL2 session, with no authz call, per [ADR-0304](../adr/0304-identity-and-authorization.md). The optional per-tool `dashboard:<tool>#view` layer is off by default.

| URL | Tool | Extra login |
| --- | --- | --- |
| `grafana.ops.dev.localtest.me:8443` | Grafana: metrics, logs, traces, RUM, policy drops | none |
| `hubble.ops.dev.localtest.me:8443` | Hubble UI: live service map, flows, drop verdicts | none |
| `temporal.ops.dev.localtest.me:8443` | Temporal Web UI | none |
| `argocd.ops.dev.localtest.me:8443` | Argo CD | none |
| `lowdefy.ops.dev.localtest.me:8443` | Lowdefy admin console | none |
| `headlamp.ops.dev.localtest.me:8443` | Headlamp: Kubernetes debug UI, read-only | none |
| `pgweb.ops.dev.localtest.me:8443` | pgweb: read-only database inspector | none |
| `mailpit.ops.dev.localtest.me:8443` | Mailpit: the viewer of the mail sink, non-prod only | none |
| `seaweedfs.ops.dev.localtest.me:8443` | SeaweedFS admin UI, non-prod only | none |
| `zot.ops.dev.localtest.me:8443` | zot console: the registry catalogue, the tags, and what the mirror has cached | none |

Every tool above trusts the edge and serves anonymously. So an operator who passes the gate lands directly on the tool. **The zot console cannot serve anonymously.** Its access policy is one configuration for one process. To open the console would also open `registry.dev.localtest.me:8443` to anonymous pulls, per [ADR-0105](../adr/0105-image-registry.md). So the platform presents the credential for the browser. A small reverse proxy in the zot pod adds the registry's `cluster` pull user on the `zot.ops` origin only. The operator sees no second prompt. The `registry.<host>` origin still asks for that credential. Read it with `kubectl -n platform get secret zot-credentials -o jsonpath='{.data.htpasswd}' | base64 -d`. The password of the local bundle is the committed throwaway one.

**Two zots run locally, and each answers a different question:**

- `zot.ops` above is the platform's own registry. It runs in the cluster, uses the object store, and is the component that a deployed environment runs.
- The **nodes pull from** the host container at `http://registry.localhost:5000`. It mirrors the upstream registries and holds the repo's own images. It serves its console at that address with no login. So you can check on a page whether an image is cached, with no `curl`.

The split is not redundancy. A `*.localtest.me` name does not resolve inside a node. So locally the in-cluster registry cannot be the node pull source, per [ADR-0105](../adr/0105-image-registry.md). The host container is the pull source. The in-cluster instance is still deployed, so that the full tier exercises its chart. After bring-up, `cluster:up full` mirrors the first-party images into it. So its `zot.ops` catalogue shows the same images that CI pushes in a deployed environment, and it is not empty. If `zot.ops` is empty, the mirror step has not run. `mise run cluster:populate-zot` fills it.

**Why the node registry is not on `localtest.me`.** A browser on the host reaches every origin in the table above. On the host, `*.localtest.me` resolves to `127.0.0.1`, and the edge answers. But a **node's containerd** reaches the registry. Inside a node container, `127.0.0.1` is the node itself. So a `localtest.me` name would send every image pull to the wrong place. `registry.localhost` is the registry container's own name. Docker's embedded DNS resolves it to the container's address from any container on the network. The registry also cannot go through the edge: Traefik's own image must be pulled before Traefik can route anything.

SeaweedFS's master and filer UIs are also not routed, per [ADR-0306](../adr/0306-trust-tiers-and-urls.md). Reach them by port-forward.

Mailpit holds every message that the Kratos courier submits. So you read a verification or recovery mail there. Production keeps no such store, per [ADR-0307](../adr/0307-outbound-email.md).

Without the edge, you can still reach Grafana with `kubectl -n platform port-forward svc/grafana 3000:80`. You can reach Mailpit with `kubectl -n platform port-forward svc/mailpit 8025:8025`.

## Frontend environment contract

`mise run dev:frontend` sets these variables. Another way to start the dev server needs the same values, for example an IDE run configuration or a debugger. For this, copy `apps/frontend/.env.example` to `.env.local`. Next loads it before it evaluates its config.

| Variable | Why it exists |
| --- | --- |
| `EDGE_PUBLIC_ORIGIN` | The edge origin of the **browser**, so it carries the port. The server-action CSRF allowlist comes from it. Server components fall back to it when the internal origin is unset. This is correct on the host, where the two are the same. When it is unset, the first server-side fetch throws |
| `EDGE_INTERNAL_ORIGIN` | Where **this process** dials the edge. In the cluster, this is the edge's `:443`, not the browser's `:8443`. One variable cannot be both, so there are two. Set only in the cluster |
| `NODE_TLS_REJECT_UNAUTHORIZED` | Local only. See the note below |
| `NEXT_PUBLIC_FIXTURES` | `1` serves every seam in `src/lib/data/` from its committed fixture instead of the service. This way a screen is designed before its API exists, per [ADR-0701](../adr/0701-product-design-and-discovery.md). Unset by default. A production build with it set fails during prerender |

Browser-side calls need none of this. The client uses a relative `/api`, which is same-origin by construction. A server-side fetch has no document to resolve a relative URL against, so the origin is named once. The origin must be configuration and not the request's `Host` header. The client controls that header, and this fetcher forwards the user's session cookie.

`NODE_TLS_REJECT_UNAUTHORIZED` exists only while the local issuer mints a self-signed **leaf**. Under the local **CA** of [ADR-0600](../adr/0600-local-development-loop.md), the certificate is trusted correctly and the variable is not set. Deployed environments never set either TLS variable.

## Task index

| Task | Does |
| --- | --- |
| `mise run setup` | install the git hooks. Once per clone |
| `mise run server`, `mise run worker` | run a service natively. Resolves the floor plus its declared dependencies |
| `mise run dev:forward` | port-forward the dependencies to the host. Leave it running |
| `mise run dev:frontend` | run the frontend dev server against the edge |
| `mise run db:migrate` | apply the migrations of every service to the local database |
| `mise run auth:seed` | seed the committed test identities |
| `mise run cluster:up` | the local floor |
| `mise run cluster:up -- full` | the real charts at single replica, through Argo CD |
| `mise run cluster:add -- <name>` | build, import, and deploy one service or platform chart |
| `mise run cluster:remove -- <name>` | uninstall **and restore Argo auto-sync** |
| `mise run cluster:stop`, `mise run cluster:down` | stop and keep the image cache, or delete. Both take the tier: `-- full` |
| `mise run cluster:heal` | recover a cluster that is stuck after a host reboot |
| `mise run e2e`, `mise run e2e:smoke` | browser acceptance suites, per [ADR-0601](../adr/0601-testing-strategy.md) |
| `mise run perf`, `perf:smoke`, `perf:stress`, `perf:seed` | load suites, per the [perf runbook](../guide/performance-runbook.md) |
| `mise run lint`, `mise run format` | every language, including Markdown |
