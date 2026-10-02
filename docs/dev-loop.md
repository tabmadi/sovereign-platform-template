# The local development loop

This page is how to use [ADR-0600](adr/0600-local-development-loop.md). There are two tiers. In either tier, a service runs native or in-cluster. This page tells you:

- which tier and mode to pick
- how to be logged in
- what each tier cannot tell you, by design

## Pick a tier

| You are | Run | Cost |
| --- | --- | --- |
| writing service code | `mise run cluster:up`, then the task of the service | seconds to start, no image build |
| working on the UI | `cluster:up` and `mise run mock:start` | the same, plus a mock that serves the committed contract |
| changing charts, sync waves, or anything Argo delivers | `mise run cluster:up -- full` | minutes. It is the whole platform |
| about to open a PR | `mise run cluster:up -- full`, then `mise run e2e` | the configuration that CI runs |

`cluster:up` is the floor. It always runs, and it is cheap. It brings up:

- Cilium, Traefik, and cert-manager
- a stand-in Postgres
- Kratos and Oathkeeper
- the seeded test identities

Everything else is opt-in. **The service that needs a dependency declares it.** There are no profiles to pick from, and no table to keep correct.

```sh
mise run cluster:up                 # the floor
mise run -C services/orders server    # starts dep:postgres, dep:openfga, and dep:temporal first
mise run -C services/orders worker    # also starts svc:catalog and svc:payment, which the saga calls
```

`lint:service-deps` checks those `depends` lists against the code. So a dependency that the code has and the list does not have fails in CI. It does not cause a confusing failure at run time.

## Native or in-cluster

| Mode | Command | Use it when | It cannot |
| --- | --- | --- | --- |
| **native** | `mise run service:dev -- <svc>`, then `mise run -C services/<svc> server` | you want a debugger, or a change every second | see the env or files of the pod. NetworkPolicy does not apply to it |
| **in-cluster** | `mise run cluster:add -- <svc>` | you need the real pod: its env, its mounts, and its policy | attach a debugger. It also costs one image build for each change |

Both modes sit behind the real edge. Native mode stamps an IngressRoute and an EndpointSlice that point at the host. So Traefik routes to your process, and your process gets **real Oathkeeper identity headers**. These are the same headers that the pod would get.

Any number of services can run native at the same time. Each one binds its own registered port from `scripts/lib/ports.sh`. No service has `:8080`, because the host maps it to the edge. To debug a flow across three services, run all three native with breakpoints. Everything they call stays in the cluster.

`cluster:add` pauses the Argo auto-sync of that app, so Argo does not revert the working-tree image. `mise run cluster:remove -- <svc>` turns the auto-sync on again. While it stays paused, the cluster stops tracking `master`, and nothing warns you.

## Be logged in

There is no bypass. Adding one blocks review, per `lint:auth-inline`. Both tiers run the real Kratos. Both tiers seed the committed test identities when they start:

| Identity | Credentials | Level | Gives you |
| --- | --- | --- | --- |
| admin | `admin@localtest.me`, password `1st Password!` | AAL2: password and TOTP | the ops hosts. This is the everyday full-tier account |
| operator | `operator@e2e.localtest.me`, password `0perator-e2e-Sessi0n!` | AAL2: password and TOTP | the same ops hosts. This is the e2e fixture, created again for each suite run |
| user | `user@e2e.localtest.me`, password `Pr0duct-e2e-Sessi0n!` | AAL1: password | the product surface |

`admin` is created once, and nothing changes it after that. On the full tier it is also the first operator that every environment seeds, per [ADR-0304](adr/0304-identity-and-authorization.md). Every e2e run creates `operator` and `user` again, so the runs are deterministic. So do not build a workflow around their session. Log in at `https://dev.localtest.me:8443/auth/login`. The ops hosts are `https://<name>.ops.dev.localtest.me:8443`. They answer `401` until you log in.

The second factor is enrolled at run time, not imported, because Kratos cannot import a TOTP credential. The first login with an operator account takes you to the settings flow once, to enrol it. If a login stops working, `mise run auth:seed` runs the whole provisioning again.

## HTTP proxies

No cluster command handles the proxy. `mise run cluster:up` is the same command on a direct network and on a network behind a firewall. Behind a proxy, run `mise run proxy:setup` once, first. It sets up what the cluster commands then expect:

- the proxy of the Docker daemon. Through it, the local zot reaches upstream registries for every node, per ADR-0105.
- the proxy of the build container.
- a `NO_PROXY` that covers `.localtest.me`, `localhost`, and `127.0.0.1`. Without it, every local request goes to a proxy that cannot resolve it. The symptom is then a timeout, not a refusal.

Images need nothing more than this first step. `cluster:up` fills the local registry before it creates the cluster, and the nodes pull only from there. So a pull that fails for lack of egress fails during the warm-up, and the error names the image. It does not fail as an `ImagePullBackOff` twenty minutes later. [guide/http-proxy.md](guide/http-proxy.md) has the full setup, with the values for the environment of the Docker daemon.

## After a reboot

The inner loop routes to native services through an EndpointSlice. The EndpointSlice points at the docker-bridge gateway, which is the only host address that a pod can reach. The bring-up stamps it. When the bridge is created again, the address is wrong, and a reboot does this. Then the cluster comes back and the pods are Ready, but every native route returns 502.

`mise run cluster:heal` restarts the node, which clears a half-restored Cilium datapath. Then it stamps the edge glue again. It is idempotent. Run it each time the cluster survives an event on the host.

## UI work: the mock

```sh
mise run mock:start     # Prism, serving apps/frontend/public/devportal/openapi/internal.json
mise run mock:logs      # the useful part: unmatched routes, and bodies that fail the spec
mise run mock:stop
```

The mock takes over `/api` at a priority that no service route can reach. So it works whether a service runs or not. It sits **behind the real edge** and the real middleware chain. So the request path is the production path: TLS, identity-header stripping, forward-auth, and security headers.

By design, the mock does not:

- **serve identity.** It returns no `401`, knows no session, and sends no identity headers. Auth behaviour comes from Kratos and Oathkeeper, which are already in the floor.
- **keep state.** Two POSTs return the same thing. Nothing persists, and nothing moves forward. The `status` of a workflow stays at the value in the example.
- **act as a test fixture.** It is forbidden in `test`, `ci:affected`, and the e2e and visual suites. A suite that passes against a mock has only tested the mock.

Its only input is the committed projection. So if a response is wrong, fix it in `services/<svc>/openapi.yaml` and regenerate. This is the purpose: the accuracy comes from the contract, and the whole team gets it there.

## What each tier cannot tell you

**`cluster:up` cannot tell you:**

- whether it works on the real datastores. Its Postgres is a plain ephemeral image, not CNPG. It has no pooler, no failover, and no backups, and the database is empty after every restart. Its stand-ins for Temporal and OpenFGA make the same trade.
- whether the delivery works. Nothing here reconciles from git. So sync waves, ApplicationSet generators, and secret materialisation stay untested.
- whether a native service obeys its NetworkPolicy. The host process is not in the mesh, so nothing enforces a policy against it.

**`cluster:up full` cannot tell you:**

- whether your uncommitted change works, unless you put it there. Argo reconciles the committed `master`, not your working tree. Use `cluster:add` or a branch `targetRevision`, per [guide/gitops-local.md](guide/gitops-local.md).
- whether it survives scale. Everything runs at one replica through the `local` values overlay. So a bug that needs two of something does not appear.

**Neither tier tells you about node count or the multi-node failure modes.** Neither tier is a performance measurement: everything shares the CPU of one machine with your compiler. For load tests, run `mise run perf` against the full tier. Even that gives only a relative number.

## When it breaks

| Symptom | Try |
| --- | --- |
| a pod is stuck pulling | `mise run cluster:up`. It warms the registry again, then converges |
| native routing is dead after a reboot, with 502 at `/`, because the bridge IP changed | `mise run cluster:heal` |
| everything acts strangely and you want the time back | `mise run cluster:down`, then bring the tier up again |
| the edge answers 404 for a service you deployed | check that Argo did not revert it: `kubectl -n argocd get app` |

Disk is the usual cause when a full tier half-works. The node evicts pods and garbage-collects images that it cannot pull again, because the inner-loop images exist only on the node. Run `docker system prune`, then rebuild, in that order.

## Where the rules are

[ADR-0600](adr/0600-local-development-loop.md) holds the decision and its consequences. This page is how to use it. [guide/gitops-local.md](guide/gitops-local.md) covers tests of uncommitted infrastructure. [guide/first-change.md](guide/first-change.md) is the end-to-end walk through adding something.
