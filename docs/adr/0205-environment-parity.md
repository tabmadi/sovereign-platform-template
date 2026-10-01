# ADR-0205: Environment Parity

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0003](0003-naming-and-identifiers.md), [ADR-0200](0200-cluster-topology.md), [ADR-0201](0201-gitops.md), [ADR-0202](0202-secrets.md), [ADR-0300](0300-data.md), [ADR-0307](0307-outbound-email.md), [ADR-0500](0500-observability.md), [ADR-0600](0600-local-development-loop.md), [ADR-0601](0601-testing-strategy.md)
- **Decides:** Every environment deploys the same charts, and the only sanctioned divergence is a values overlay per environment.

## Context

[ADR-0200](0200-cluster-topology.md) commits to parity at the artifact layer. The same charts and manifests apply everywhere, and the distribution differs only in lifecycle. This ADR fixes the exact boundary: **what may differ between an engineer's laptop and production, and what may never differ.** [ADR-0600](0600-local-development-loop.md) decides how the local tiers are built.

## Decision drivers

1. **The production path is the most-exercised path.** Every other tier must run what production runs. Otherwise the lower tiers validate something that production does not do.
2. **A new environment costs a selection, not a script.**
3. **The divergence surface can be listed.** What may differ is a list, not a judgement for each case.
4. **Drift is visible before it breaks something**, not at the moment an environment diverges in production.

## Considered options

| Option | Divergence expressed as | Exercises the production path elsewhere | Cost of an upstream change | Verdict |
| --- | --- | --- | --- | --- |
| **One chart set, values overlays per environment** | one values file per environment | yes. Every tier renders the same templates | once | **Chosen.** The divergence surface is one file per environment that a diff can show *(reasoned)* |
| Kustomize overlays on a shared base | a base, plus a patch directory per environment | yes | once, plus a new check that each patch still matches the base | A patch matches the base by structure. An upstream change can silently turn a patch into a no-op, and the divergence becomes invisible. [ADR-0201](0201-gitops.md) rejects this templating layer for the same reason |
| Chart forks per environment | separate chart directories | no. Only its own environment exercises each fork | once per fork | Drift is invisible until an environment breaks |
| Chart logic that branches on the environment | `{{ if eq .Values.env "prod" }}` | **no. The production branch is the least-exercised code in the repo** | once, and every branch needs new reasoning | It moves divergence into templates, where it cannot be reviewed as configuration |
| A different stack locally, such as Compose | a parallel definition | no | twice, in two languages | A second definition of the system that drifts silently. The local tier would validate something that production does not run |

## Decision

### One chart set, values per environment

Every environment deploys the same charts under `infra/helm/platform/*` and `infra/helm/service`. The environments are **local, dev, staging, and prod**. The only sanctioned divergence is a values overlay per environment, and local is a first-class member.

A divergence that a value cannot express is permitted **only** in the inner-loop tier, per [ADR-0600](0600-local-development-loop.md), and never silently. Examples are a different chart, or a hand-written Deployment in place of an operator-managed component.

**The contract is the same in every tier.** These are identical everywhere:

- the Kubernetes API
- the service chart
- the service images
- the env contract: `DATABASE_URL`, `TEMPORAL_HOST_PORT`, the OTLP endpoint, and OpenFGA

*Scale* may differ. In the inner loop only, the *implementation behind a contract* may also differ.

### May differ, must not differ

| Concern | May differ | Must not differ |
| --- | --- | --- |
| Kubernetes distribution | Ephemeral locally and persistent when deployed. In the inner loop, the node count, and how that node is configured but not what it runs, per [ADR-0600](0600-local-development-loop.md) | the charts and manifests applied, the distribution and its datastore in every tier, and the machine config from the full tier upward |
| Scale | replicas, storage size, anti-affinity, and HPA | which components the full tier runs |
| Data-tier implementation | inner-loop stand-ins against the real charts | the wire contract, and the Postgres major version |
| Object storage placement | in the cluster in non-prod, outside the cluster in prod | the implementation, and the S3 API contract |
| Outbound mail | the agent in production, and a sink in every environment below it, per [ADR-0307](0307-outbound-email.md) | SMTP submission as the contract that every sender speaks |
| TLS issuer | a local CA, or `Let's Encrypt` | cert-manager as the mechanism, and certificates that are **verified**, never bypassed |
| Secret plaintext | throwaway locally, real when deployed | SOPS as the decrypt mechanism |
| Domain | `*.localtest.me`, or `*.<env>.<project-domain>` | the routing and edge shape |

The **must not differ** column is [12-Factor X](https://12factor.net/dev-prod-parity), made into a list. That factor says a twelve-factor app *resists the urge to use different backing services between development and production*. The **may differ** column is the deliberate scope. The factor says nothing about scale. An inner-loop stand-in behind an identical wire contract is not a different backing service.

### Distribution lifecycle

| Tier | Distribution | Lifecycle |
| --- | --- | --- |
| local inner loop | upstream Kubernetes on etcd, on one node, per [ADR-0600](0600-local-development-loop.md) | per engineer, recreated freely |
| local full platform | as [ADR-0200](0200-cluster-topology.md) decides, from the same machine config, provisioned in containers | per engineer, recreated freely |
| CI e2e and label-gated PR preview | the same as the local full platform | ephemeral, created and destroyed per run |
| dev, staging, prod | as [ADR-0200](0200-cluster-topology.md) decides, provisioned on hosts | persistent |

**Distribution parity is a floor, and the floor is the full tier.** From the full tier upward, the machine config is fixed, and the choice is about lifecycle, not architecture. The inner loop sits one step below. It runs the same Kubernetes on the same datastore with the same datapath. It differs only in node count, and in reaching that state by configuration, not by machine config. It spends its sanctioned divergence on the stand-ins behind a wire contract, not on the cluster under them.

The local full-platform tier and the CI preview tier are the **same configuration**. So work on one is work on the other, and neither is a second chance to catch what the other misses. Deployed environments stay persistent: they survive reboots and hold real storage and backups.

### The ephemeral PR environment

A preview is the full-platform tier from [ADR-0600](0600-local-development-loop.md), brought up in CI against the images of one pull request. It is a lifecycle of a tier that is already decided, not a fourth kind of environment. For this reason it lives here and not in an ADR of its own.

| Concern | Decision |
| --- | --- |
| Trigger | A label on the pull request. Bring-up costs minutes of runner time, so it is opt-in per PR, not per push, per [ADR-0601](0601-testing-strategy.md) |
| Configuration | the same charts and the same `local` values overlay as the full tier, with images from the PR's build |
| Identity | the committed deterministic test identities, never a copy of the data of any deployed environment |
| Lifetime | Destroyed when the run ends or the pull request closes. Nothing survives it, and nothing outside it depends on it |
| Naming | The environment slug comes from the pull request number, per [ADR-0003](0003-naming-and-identifiers.md), so two previews cannot collide |

**A preview holds no real data and no real credential.** It is a throwaway cluster, so it takes the local tier's secret path, not the path of a deployed environment. That path is the committed local age key, per [ADR-0202](0202-secrets.md). An environment that borrowed production data or production secrets to look realistic would be a production system that lives as long as a pull request.

**Previews are not a deployment target.** No preview is promoted, and nothing is released from one. A preview is a test fixture with a URL.

### Object storage

**Here, parity covers the implementation, not only the API.** One store runs in every environment, and the only difference is placement. It runs in the cluster in non-prod and outside the cluster in production, for the failure-domain reason that [ADR-0200](0200-cluster-topology.md) states.

As values, that difference is the S3 endpoint and whether the in-cluster chart is enabled. CNPG backups target the production bucket. In non-prod they target the in-cluster instance, where a backup is a convenience, not a recovery guarantee.

### Secrets

[ADR-0202](0202-secrets.md) requires one secret mechanism in every environment, and local is no exception. Local uses the same SOPS path, with a committed, well-known **local** age key. The key is safe because it decrypts only throwaway credentials. The decrypt mechanism is identical to production. Only the plaintext differs.

### Outbound mail

**Here, parity covers the contract, not the implementation.** Every sender submits over SMTP in every environment, per [ADR-0307](0307-outbound-email.md). Production points that submission at the mail agent. Every environment below production points the same submission at a sink that has no outbound path.

The implementation differs because of production's defining property: it reaches a real recipient. A non-production environment must not have that property. Object storage above takes the opposite shape. There, implementations differ behind an identical S3 API, so parity must reach the implementation. Two SMTP submission endpoints do not differ in that way, because each one accepts or refuses a message. The part that does differ is deliverability, and it has no local equivalent to test against.

## Consequences

### Positive

- The divergence surface is one values file per environment, and a diff can review it.
- The full local tier exercises a chart change before the change reaches a deployed environment.
- New environments are values selections. A new environment is an overlay, not a script.
- The production path is the most-exercised path, because every tier runs it.

### Negative and Risks

- **The inner loop's stand-ins are a sanctioned parity gap.** The gap is limited to the implementation behind an unchanged wire contract. It is a list, not an argument, and it never extends to the full tier.
- **The full tier is the last tier before a deployed environment.** CI and the preview share its configuration, so nothing examines a divergence carried there. This is why distribution parity starts at the full tier and not one tier higher.
- **A single local node is not a production topology.** The shapes of saturation carry over. The absolute ceilings do not, per [ADR-0601](0601-testing-strategy.md).
- **Non-prod backups are not recovery guarantees.** This ADR states it so that nobody mistakes the in-cluster convenience for one.
- **Local secrets are committed.** This is safe only while the local age key decrypts nothing real. A real credential in a local secret file is a leak, not a shortcut.

## Rules

- Every environment deploys the same charts. The only sanctioned divergence is a values overlay per environment, listed in `infra/gitops/parity-allowlist.txt`. A values key that a deployed overlay carries and the local overlay does not carry is a defect, unless the allowlist names the reason. `(CI: lint:parity)`
- Every tier runs the distribution and datastore that [ADR-0200](0200-cluster-topology.md) decides. From the full local platform upward, the machine config is also the same. Such a tier differs from a deployed environment only in lifecycle and in how its nodes are provisioned. The inner loop differs in node count alone, per [ADR-0600](0600-local-development-loop.md).
- Chart templates do not branch on the environment name. Outside the inner-loop tier, a difference that a value cannot express is a defect.
- The Kubernetes API, service chart, service images, and env contract are identical in every tier.
- Object storage is one implementation in every environment, per [ADR-0207](0207-cluster-storage.md). Production runs it outside the cluster, and no store that holds production data runs on the cluster it serves.
- Outbound mail is one contract in every environment, not one implementation. Production submits through the agent that [ADR-0307](0307-outbound-email.md) decides. Every environment below production submits to a sink with no outbound path.
- Backups are off-cluster and mandatory in production, per [ADR-0207](0207-cluster-storage.md). Non-prod backups are a convenience and are never cited as a recovery guarantee.
- SOPS is the secret mechanism in every environment, including local.
- A PR preview is the full-platform tier at the images of one pull request. It is label-gated, and it is destroyed with the run. Its slug comes from the pull request number.
- A preview uses the local secret path and the committed test identities. The data or credentials of a deployed environment are never copied into one.
- Nothing is promoted or released from a preview.
- cert-manager issues certificates over ACME in every environment, and they are verified, never bypassed. `(ref: RFC 8555)`
