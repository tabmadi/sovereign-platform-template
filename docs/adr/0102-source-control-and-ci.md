# ADR-0102: Source Control and CI Platform

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0101](0101-monorepo.md), [ADR-0103](0103-release-and-versioning.md), [ADR-0104](0104-supply-chain-security.md)
- **Decides:** Forgejo is the forge and Forgejo Actions the pipeline runner, entered through `mise run ci:*` so the forge stays cheap to leave.

## Context

Principle 3 of [ADR-0000](0000-platform-foundations.md) makes source control and CI a first-class decision, not a signup. A forge bundles four concerns that a managed provider hides:

- the repository
- the review record
- the pipeline
- the identity that signs artefacts

The pipeline builds and signs artefacts, per [ADR-0104](0104-supply-chain-security.md). So whoever runs it decides what the platform can prove that it built.

A managed forge is the one dependency that pinning or a contract cannot reconcile with principle 3. The reason is that the trust root is the thing that is outsourced.

## Decision drivers

1. **Operational sovereignty**, per principle 3 of [ADR-0000](0000-platform-foundations.md). Source, review, and build run on infrastructure that the organisation controls.
2. **Thinnest viable platform**, per principle 2. A forge is one component. A suite that arrives with its own datastore fleet is a different purchase.
3. **Exit cost stays low**, per principle 4. The pipeline definition must not become the place where build logic lives. If it does, leaving means rewriting the pipeline, not re-pointing it.
4. **One primitive per concern**, per principle 5. Source, review, and pipelines are one purchase or several. Each additional system is operational surface that the platform team carries.
5. **The build environment is part of the supply chain**, per [ADR-0104](0104-supply-chain-security.md). Whoever runs the pipeline can change what is built, whatever is signed after it.

## Considered options

| Option | Component weight | Pipelines | Governance | Verdict |
| --- | --- | --- | --- | --- |
| **Forgejo with Forgejo Actions** | one Go binary, plus a Postgres on the forge host | built in, with GitHub-Actions workflow syntax. Runners are self-hosted by definition | a non-profit umbrella, [Codeberg e.V.](https://forgejo.org/), under [GPLv3+](https://lwn.net/Articles/986998/) | **Chosen.** The only option that meets drivers 1 to 4 together *(reasoned)* |
| Gitea with Gitea Actions | identical | identical | company-controlled | Functionally equivalent. Provenance is *recorded evidence about exit cost*, per principle 4. The governing body is the only thing that separates these two otherwise equal choices |
| Gogs | one Go binary | **none.** No built-in CI | maintainer-led | Both rows above forked from it, and the pipelines went with the forks. Adopting it lands on the row for a separate CI engine below |
| GitLab CE | a suite: Gitaly, Redis, Sidekiq, its own Postgres, and several web services | mature and complete | company-controlled, open-core | Rejected by principle 2, as [ADR-0000](0000-platform-foundations.md) already records. It replaces one component with a platform |
| Self-hosted forge with a separate CI engine | two components | Woodpecker, Tekton, or Argo Workflows | varies | Rejected by principle 5, as [ADR-0000](0000-platform-foundations.md) already records. It is a second system beside the forge |
| A managed forge, the do-nothing baseline | none | hosted runners | third-party | Fails driver 1 outright. Axis B is only asserted, not held. The identity that signs artefacts stays under the control of a third party |

Forgejo and Gitea come from the same software lineage, and they score the same on every technical row. Principle 4 says that provenance does not veto a choice, but is recorded. Here it is the only evidence that separates them, so it decides.

### The two tools the pipeline runs on

Both are Tier 2, per [ADR-0002](0002-tool-adoption.md). Both follow from the runner shape. They are not independent preferences.

| Concern | Chosen | Picked over | Why |
| --- | --- | --- | --- |
| Image builds | **BuildKit**, through buildx on the Docker of the runner | Buildah, Kaniko | A runner is a dedicated machine with Docker, as described below, because the jobs that start kind need one. The builder uses the daemon that is already there *(reasoned)*. The `Dockerfile` syntax is defined against BuildKit, so cache mounts and multi-stage behaviour need no translation. Buildah is the runner-up, and its exit is a task change |
| Running a workflow locally | **act** | pushing to a branch, or running a self-hosted runner on the workstation | Workflow YAML is a thin caller of `mise run ci:*`, so most local checks run the task directly. `act` covers the remaining case, the workflow wiring itself, without a push |

## Decision

| Concern | Decision |
| --- | --- |
| Forge | **Forgejo**, self-hosted on its own host, with its Postgres on that same host |
| Pipelines | **Forgejo Actions**, with runners on infrastructure we control |
| Workflow content | checkout, toolchain setup, then `mise run ci:*`. Logic does not live in YAML |
| Review record | pull requests on the forge. Branch protection and required checks are configuration in the repository, per principle 1 of [ADR-0000](0000-platform-foundations.md) |
| Registry | **not** the package registry of the forge. [ADR-0105](0105-image-registry.md) decides it separately |

**Workflow YAML is a portable subset.** Its steps are `actions/checkout`, the own composite setup action of the repository, and `mise run` calls. That subset runs on Forgejo Actions and on the provider-hosted workflows that the template ships. This makes the forge cheap to leave in either direction.

**A runner gives `ubuntu-latest` a machine, not a container.** The portable subset assumes what a provider-hosted job gets: a host with Docker, whose loopback and filesystem the job owns. A job that starts kind publishes its API and a registry on loopback, and bind-mounts its checkout. Inside a job container, neither the loopback nor the filesystem belongs to the host. So a Forgejo runner executes jobs on a dedicated machine that holds nothing else. It never uses a workload-cluster node, because a job controls the Docker of that machine, which is root on it. A machine that runs two jobs at once has one registry port and one set of edge ports. So in CI, `cluster:up` waits while another job holds them, and `cluster:down` removes only its own.

### The template ships provider-hosted workflows

A generated project needs CI from its first commit. At that point, no cluster exists to run a forge on. So the workflows under `.github/workflows/` are the bootstrap path, not a competing decision.

| Field | Value |
| --- | --- |
| **Trigger** | the platform cluster serves its first environment |
| **Seam** | ✓ the thin-YAML rule above. A move re-targets the same `mise run ci:*` calls, and does not rewrite pipeline logic |
| **Cost if adopted late** | the pipeline migration is flat, because the thin-YAML rule makes it a re-target, not a rewrite. **The review record is not flat.** Pull requests, review comments, and issues are native to the forge and do not travel with a `git push`. So that body grows for as long as the decision waits. Until the move lands, sovereignty is also only asserted, not held |

### Signing identity

[ADR-0104](0104-supply-chain-security.md) signs with a key pair held in SOPS, not against a third-party certificate authority. The purpose is that the signing identity does not depend on which forge runs the pipeline. A forge move re-targets the workflow and leaves the trust root untouched.

Forgejo does mint [per-job OIDC tokens for Actions](https://forgejo.org/docs/latest/user/actions/security-openid-connect/), together with ephemeral runners. That capability is available for anything that wants a short-lived workload identity. It does not sign images.

## Where the forge runs

**The forge runs outside the workload cluster, on its own host.** [ADR-0207](0207-cluster-storage.md) makes the same decision for the production object store, for the same reason. A component that exists to recover a cluster must not share the failure domain of that cluster.

The forcing argument is circularity:

- Argo CD reconciles the platform from git.
- git lives in the forge.
- In the cluster, Argo would deploy the forge.

So a full-cluster loss leaves nothing to reconcile *from*. Recovery would start with a manual rebuild of the forge from a backup. Only then could the automation that depends on it run. Nobody should find that recovery procedure during an incident.

Running the forge outside removes the cycle. It does not only order the steps: Argo syncs from a forge that Argo never deployed.

**Its database goes with it.** Take a forge on its own host whose Postgres is the CNPG of the workload cluster. It has moved the binary and left the state behind. The same cluster loss still takes the repositories, the pull requests, and the review record. The recovery still starts with a database restore from a backup, before anything can reconcile. The forge host has its own Postgres for the same reason that the forge has its own host.

| | In the workload cluster | Outside it |
| --- | --- | --- |
| Recovery from full-cluster loss | rebuild the forge first, by hand, from a backup | the source is already there, and Argo reconciles |
| Bootstrap order | the forge must be installed imperatively before Argo, like Argo itself | no ordering constraint at all |
| Operational cost | one fewer host | one more host, patched and backed up separately |
| Blast radius of a cluster mistake | takes the source of truth with it | does not |

The cost is real, and it is a host. Someone patches it, backs it up, and monitors it outside the own observability of the platform. That is the price of the property. The platform already pays the same price for the object store.

**zot is the same question with a different answer.** The registry is on the critical path for every pod start. So during a cold start, an in-cluster registry cannot serve the cluster it lives in. Unlike the forge, it holds no source of truth. It is backed by object storage, and a redeploy rebuilds its contents, per [ADR-0105](0105-image-registry.md). It needs its **bucket** to be outside the cluster. [ADR-0207](0207-cluster-storage.md) already requires this in production. The registry itself stays in-cluster.

## Consequences

### Positive

- Source, review, pipelines, and the build identity run on controlled infrastructure. Axis B is held, not only asserted.
- Forgejo Actions reuses the workflow syntax that is already in the repository. So the migration re-targets, and does not rewrite.
- There is no second CI engine. The database of the forge is a single Postgres on the forge host. That is the one place where it does not re-enter the failure domain of the cluster.

### Negative and Risks

- **The forge joins Core.** A forge outage blocks merges and builds. Argo CD keeps reconciling from the last synced commit, so a forge outage does not stop the running system.
- **Self-hosted runners are compute that the platform team owns**, including their cache and their isolation. Execution of untrusted PRs is a policy question. A public repository must answer it before it enables such execution.
- **The pipeline feature set of Forgejo is behind the provider it imitates.** The thin-YAML rule limits the exposure: the surface in use is checkout, setup, and a task call.

## Rules

- The forge is Forgejo, self-hosted on a host outside the workload cluster, with its Postgres on that host.
- **The forge runs outside the workload cluster it serves.** *Where the forge runs* gives the reason.
- Pipelines run on Forgejo Actions, with runners on controlled infrastructure. No second CI engine is introduced, per principle 5 of [ADR-0000](0000-platform-foundations.md).
- A runner executes `ubuntu-latest` jobs on a dedicated machine. It never runs them inside a job container or on a workload-cluster node.
- The repository lives at `forge.<apex>/platform/<project>`. An organisation owns it, never a person, and Argo CD reconciles from that URL.
- Workflow YAML checks out, sets up the toolchain, and calls `mise run ci:*`. Pipeline logic is not written in YAML.
- Branch protection and required checks are configuration in the repository, never set through the forge UI, per principle 1 of [ADR-0000](0000-platform-foundations.md).
- The default branch takes a direct push from one identity only: the `ci` machine user. Its `PROMOTE_TOKEN` pushes the dev and staging promotion commit, per [ADR-0201](0201-gitops.md). Every other change reaches the branch through a reviewed pull request.
- Container images are published to the registry in [ADR-0105](0105-image-registry.md), not to the package registry of the forge.
