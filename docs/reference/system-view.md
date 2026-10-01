# System View

The ADR set records every decision and describes nothing. It records why each part is what it is, but nothing shows the shape. This document is the description. It decides nothing, and every element traces back to the ADR that chose it.

It has three views, in the order that a newcomer needs them:

1. what runs
2. how a request moves
3. how identity reaches a handler

## Containers

Argo CD reconciles everything inside the cluster boundary from this repository, per [ADR-0201](../adr/0201-gitops.md). Everything outside the boundary is there on purpose: the two rows that must survive the cluster.

```text
                     ┌─────────────────────────────────────────────────────────┐
   browser ── TLS ──▶ │ Traefik            edge: routing, TLS, rate limiting    │
                     │   └─▶ Oathkeeper   forward-auth: validate, strip, inject │
                     └───────────────┬─────────────────────────────────────────┘
                                     │  X-User-Id / X-Org-Id / X-Roles
        ┌────────────────────────────┼────────────────────────────┐
        ▼                            ▼                            ▼
  ┌───────────┐             ┌─────────────────┐          ┌─────────────────┐
  │ frontend  │             │ services/*      │◀────────▶│ authz + OpenFGA │
  │ Next.js   │────HTTP────▶│ Go: server      │  Checker └─────────────────┘
  │ one app   │             │     worker      │
  └───────────┘             └────────┬────────┘
                                     │
        ┌────────────────┬───────────┴───────────┬──────────────────┐
        ▼                ▼                       ▼                  ▼
  ┌───────────┐   ┌─────────────┐        ┌──────────────┐   ┌──────────────┐
  │ Postgres  │   │ Temporal    │        │ OTel         │   │ Kratos       │
  │ CNPG      │   │ server      │        │ Collector    │   │ identity     │
  │ one DB    │   │ + workers   │        │ DaemonSet    │   └──────────────┘
  │ per svc   │   └─────────────┘        └──────┬───────┘
  └───────────┘                                 │
                                    ┌───────────┴────────────┐
                                    ▼                        ▼
                          ┌──────────────────┐     ┌──────────────────┐
                          │ Loki  Tempo      │     │ Prometheus       │
                          │ Pyroscope        │     │ + Alertmanager   │
                          └────────┬─────────┘     └──────────────────┘
                                   │                        │
                                   └────────┬───────────────┘
                                            ▼
                                      ┌──────────┐
                                      │ Grafana  │  one UI, four signals
                                      └──────────┘
  ═══════════════════════════ cluster boundary ═══════════════════════════
        ▼                                              ▼
  ┌───────────────────┐                        ┌──────────────────┐
  │ object storage    │  backups, log/trace/   │ forge + registry │  images,
  │ off-cluster       │  profile data, images  │ Forgejo + zot    │  pipelines
  └───────────────────┘                        └──────────────────┘
```

**Two things sit outside on purpose.** Production object storage holds the backups that a cluster rebuild reads. So it cannot live in the failure domain that it protects, per [ADR-0200](../adr/0200-cluster-topology.md). Pods pull from the registry. So a cluster that cannot start pods cannot serve its own images, per [ADR-0105](../adr/0105-image-registry.md).

**What is not here.** Kyverno and Pod Security Admission sit in the API server's admission path, not in any request path. CiliumNetworkPolicy is in the datapath between every pair of boxes above. Neither appears as a box, because neither is a hop, per [ADR-0203](../adr/0203-policy-enforcement.md).

## A request, end to end

This view shows the checkout saga. It is the one path that uses every mechanism, per [ADR-0302](../adr/0302-temporal.md).

```text
browser         Traefik      Oathkeeper     orders svc     Temporal      catalog/payment
   │                │             │              │             │                │
   │──POST /api/orders───────────▶│              │             │                │
   │                │─forward-auth▶│             │             │                │
   │                │             │─validate session (Kratos)  │                │
   │                │             │─strip client headers       │                │
   │                │◀─200 + X-User-Id / X-Org-Id / X-Roles    │                │
   │                │────────────────────────────▶│            │                │
   │                │             │              │─Checker ▶ OpenFGA             │
   │                │             │              │─start workflow ─────▶│        │
   │◀────────────────202 + workflow handle ───────│             │                │
   │                │             │              │             │─activity ──────▶│
   │                │             │              │             │  HTTP + same headers
   │                │             │              │             │◀─result ────────│
   │                │             │              │             │─compensate on failure
   │──GET /api/orders/{id} ──────▶│──────────────▶│            │                │
   │◀───────────────── state, read from Postgres ─│             │                │
```

**This view shows three properties:**

- The edge establishes identity once and forwards it. No hop validates it again.
- The synchronous request returns a handle. It does not wait for the saga.
- A cross-service call is HTTP through a generated client. So the workflow's steps cross the same boundary as any caller, per [ADR-0000](../adr/0000-platform-foundations.md) principle 10.

## Identity and authorization

This view shows where the platform decides *who* the caller is. It also shows where a separate decision sets *what they may do*.

```text
  ┌─────────┐   session cookie    ┌────────────┐    who is this?    ┌──────────┐
  │ browser │────────────────────▶│ Oathkeeper │───────────────────▶│  Kratos  │
  └─────────┘                     └─────┬──────┘                    └──────────┘
                                        │ authoritative headers
                                        ▼
                                  ┌────────────┐   may they do it?  ┌──────────┐
                                  │  service   │───────────────────▶│ OpenFGA  │
                                  │  handler   │      Checker       │  tuples  │
                                  └─────┬──────┘                    └──────────┘
                                        │ authorized mutation
                                        ▼
                                  ┌────────────┐  dual write, in one workflow
                                  │  Postgres  │  ── authz-relevant change ──▶ OpenFGA
                                  └────────────┘
```

| Question | Answered by | Where |
| --- | --- | --- |
| Who the caller is | Kratos, through Oathkeeper | once, at the edge, per [ADR-0305](../adr/0305-edge-auth-and-traffic-policy.md) |
| Whether they may do this | OpenFGA, through `Checker` | in the handler, per request and per resource, per [ADR-0304](../adr/0304-identity-and-authorization.md) |
| Whether they may reach this port | CiliumNetworkPolicy | in the datapath, independent of both, per [ADR-0206](../adr/0206-cluster-networking.md) |
| Whether this operator may open a dashboard | the ops coarse gate: the `operator` claim plus AAL2, on purpose with **no** OpenFGA call | at the edge. So an authorization outage cannot lock operators out of the dashboards that diagnose it |

**The load-bearing asymmetry.** Between the edge and a service, identity is a header that is trusted because of network position, per [ADR-0305](../adr/0305-edge-auth-and-traffic-policy.md). Authorization is never positional. A request that has arrived is authorized as if it came from anywhere. The seam that makes identity cryptographic is recorded with its trigger. Authorization needs no seam, because it never made the assumption.
