# ADR-0103: Release, Tagging and Versioning

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0101](0101-monorepo.md), [ADR-0201](0201-gitops.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0500](0500-observability.md)
- **Decides:** One repository-wide CalVer line derived from Conventional Commits, with SemVer reserved for anything published for an external pinner.

## Context

The monorepo produces these artifacts:

- service container images
- Go and TypeScript libraries
- generated API clients
- Helm charts
- two applications

[ADR-0101](0101-monorepo.md) tags images `<service>:<git-sha>`, and the same SHA goes through every environment. That covers deployment identity. It leaves three questions open:

- How humans name what is in production, in a changelog or a release note.
- When a version number changes, and who changes it.
- How the identity of the running build is confirmed, not assumed.

**The decisive fact is that this repo ships as a single unit.** GitOps rolls one SHA through every environment. Production moves as a whole when a release is cut. No component has an external consumer that pins it independently:

- Go libraries are in-tree packages of one module.
- TypeScript libraries resolve through `workspace:*`.
- Service-to-service calls use the in-repo generated SDK at HEAD.

So a per-component SemVer line would encode a compatibility promise that **no external consumer is there to read**.

## Decision drivers

1. **The unit of versioning is the unit of shipping.** GitOps rolls one SHA through every environment, and production moves as a whole. A finer version line describes a boundary that the system does not have.
2. **A version signals something to someone, or it signals nothing.** Whatever the number promises, some consumer must be able to read it and act on it.
3. **Commit history is an input, not only a record.** The changelog and the breaking-change signal come from it. So its format must be machine-readable and enforced at write time, not cleaned up later.
4. **Deploy identity stays SHA-based**, per [ADR-0101](0101-monorepo.md). This is inherited, not decided here. Any release label adds to the image identity and never replaces it.
5. **The promotion boundary is a choice, not a default.** Dev and staging deploy continuously from `master`, per [ADR-0201](0201-gitops.md). This ADR decides whether production follows automatically.
6. **The identity of the running build is provable.** It is not inferred from a successful pipeline.

## Considered options

### The version line

| Option | What the number signals | Human judgement per release | Verdict |
| --- | --- | --- | --- |
| **[CalVer](https://calver.org/) `vYYYY.0M.MICRO`, one repo-wide line** | when it shipped | none, because it is the date | **Chosen.** It answers the only question asked of a release version *(reasoned)* |
| [SemVer](https://semver.org/), one repo-wide line | a compatibility contract | bump level, every release | The contract has no independent pinner. So the signal goes to nobody, and the judgement call is pure cost |
| SemVer per component, prefixed tag namespaces | per-component compatibility | one judgement per component | Multiplies the same unread promise by the component count, plus tag bookkeeping |
| Git SHA only, no human version | nothing | none | Deploy identity is already the SHA. A changelog and a release note need a label that a human can say aloud |

Driver 2 decides this table. The number of SemVer is addressed to a pinner, and there is none.

**Escape hatch.** A library, SDK, or service can be extracted and published for external consumers to pin. Then *that artifact* adopts SemVer with its own prefixed tag, because an external pinner does need the breaking signal.

| Field | Value |
| --- | --- |
| **Trigger** | an artifact is published for a consumer outside this repository to pin |
| **Seam** | present. The repo-wide line has no prefix, so a namespaced tag coexists with it and does not replace it. The chosen tooling supports per-package tagging as configuration |
| **Cost if adopted late** | the first external consumer pays it. That consumer pins a CalVer tag that promises nothing. The retrofit cannot honestly start at `v1.0.0`, because versions that the consumer already depends on exist |

### Commit convention

| Option | Machine-readable | How a breaking change is marked | Verdict |
| --- | --- | --- | --- |
| **Conventional Commits** | **a specified grammar, with parsers in every ecosystem** | `!` after the type or scope, or a `BREAKING CHANGE:` footer | **Chosen.** Driver 3: the changelog and the breaking signal are derived, not curated *(reasoned)* |
| Free-form messages, with a changelog written by hand | no | by whoever remembers | Makes the changelog a writing task at release time, and the breaking signal a matter of memory |
| gitmoji | a prefix set, with no grammar behind it | no defined marker | Expressive and popular. A gate has nothing to key off |
| A house prefix scheme | as far as we build it | as far as we build it | The same grammar, written and maintained here, with no third-party parser to inherit |

### Release tooling

| Option | Computes the version | Enforces the grammar | Verdict |
| --- | --- | --- | --- |
| **cocogitto, changelog-only** | not used, because CalVer comes from the date | **yes, at `commit-msg` and in CI** | **Chosen.** One binary covers enforcement and changelog rendering. The version it could compute is not wanted *(reasoned)* |
| commitlint | no | yes | The same enforcement as a Node program. [ADR-0100](0100-language-and-runtime.md) bars Node for authored tooling |
| release-please | yes, by inferring SemVer bumps from commit history | no | Its whole value is bump inference. The version-line decision above makes that irrelevant |
| changesets | yes, per package, from intent files that authors write | no | Built for independently published packages. The same decision rules those out |

## Decision

### Conventional Commits, enforced

Every commit on `master` follows the [Conventional Commits](https://www.conventionalcommits.org/) spec.

| Element | Value |
| --- | --- |
| Types | `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `chore`, `build`, `ci`, `revert` |
| Scope | the component path slug, such as `gateway`, `frontend`, `libs/go/observability`, or `helm/postgres`. The valid set is generated from the repo layout and lint-enforced |
| Breaking change | `!` after the type or scope, or a `BREAKING CHANGE:` footer |

Under CalVer, a breaking marker computes no version bump. It does three things:

- It heads the changelog.
- It flags the change for review.
- For the API surface, it is the signal that [ADR-0303](0303-api-contracts-and-lifecycle.md) keys off.

`cocogitto` enforces the format through a lefthook `commit-msg` hook. CI runs `cog check` again over the commit range of the pull request, as part of `mise run ci:lint`. [ADR-0102](0102-source-control-and-ci.md) keeps CI logic in tasks, not in workflow steps. A squash-merge produces one commit whose title is a valid Conventional Commit. Merge commits are not used.

### One repo-wide CalVer line

The repository has one release version: **`vYYYY.0M.MICRO`**. For example: `v2026.07.0`, then `v2026.07.1` for a second release in the same month, then `v2026.08.0` in August. It is the human-readable alias for the state of the whole repo at that release.

Services, apps, and charts have no version of their own. Where a build tool requires a version field, the release stamps it with the current CalVer. Nobody maintains it independently.

**One calendar covers release and API contract.** By default, [ADR-0303](0303-api-contracts-and-lifecycle.md) keeps a single live version of the API. Only when an external consumer exists does it mint date-based API versions, from this same calendar. The API version is the subsequence of release dates on which the public contract changed.

### Image tags: SHA and digest for machines, CalVer for humans

| Tag | Purpose | Where it is referenced |
| --- | --- | --- |
| `<service>:<git-sha>` | deploy identity | GitOps manifests in dev and staging |
| `repo@sha256:<digest>` digest | the strongest identity, because a digest cannot be pushed again | GitOps manifests in prod, through `image.digest`, which takes precedence over `image.tag` |
| `<service>:v<YYYY.0M.MICRO>` | reference for humans and external documentation | never referenced by GitOps |

A release-tag push pushes the CalVer label once per image, and the label is immutable. Moving tags are never published, and CI rejects them.

### Proving which build is running

The question of whether the pod runs the new code hides two different problems:

- **actual drift**: old code under a new tag
- the **observability gap**: no way to confirm it without trusting the pipeline

**The structure prevents drift.** Deploys use immutable SHA tags. GitOps references a SHA or a digest only. Moving tags are never published. So a node cannot silently serve a stale image under a reused tag. Two hardenings belong to the promotion workflow of [ADR-0201](0201-gitops.md):

- Pin production by digest.
- **Gate on rollout completion.** Argo reporting Healthy is not the same as rolled out. So the workflow waits until the new ReplicaSet is available.

**One build identity is compiled into the artifact.** It is never read from a runtime environment variable or a ConfigMap. The point is to prove which build runs, and a runtime value can change independently of the code it describes.

| Artifact | Mechanism |
| --- | --- |
| Go services | `-ldflags -X` injects the git SHA, release version, and build time into `libs/go/buildinfo`. A local build falls back to the Go VCS stamp |
| Frontend | the same values, inlined into `NEXT_PUBLIC_SERVICE_VERSION` at build |

Build scripts and CI pass these as `--build-arg GIT_SHA=<sha> BUILD_VERSION=<version> BUILD_TIME=<time>`.

That one value shows in three places:

| Surface | Form | Answers |
| --- | --- | --- |
| Telemetry attribute | `obs.Init` sets OTel `service.version` and `service.build.sha`, per [ADR-0500](0500-observability.md) | what serves production now, as a Grafana query with no endpoint involved |
| Endpoint | `GET /version` on the admin port, beside `/livez` and `/readyz`. It returns `{version, sha, builtAt}` | scriptable per-pod checks, such as a CI smoke test or an operator's `curl` |
| Response header | `X-App-Version` and `X-App-Revision` from the shared `httpmw`. The frontend also stamps `X-App-Version` | inspect any response in devtools. A comparison of the bundle version in the browser with the backend header also catches a **stale cached bundle**. The backend alone cannot show that |

### The release process

A release is repo-wide, and it **is** the production deploy. Dev and staging deploy continuously from `master`, limited by Argo sync windows, per [ADR-0201](0201-gitops.md). Production moves only when someone cuts a release.

`mise run release` does these steps:

1. It computes the next CalVer from the date and the last release tag. The same month bumps `MICRO`, and a new month resets it.
2. It stamps version fields where a build tool needs one.
3. It regenerates `CHANGELOG.md` with `cog changelog` for the commit range since the last release.
4. It commits as `chore(release): v<YYYY.0M.MICRO>` and creates the tag.
5. It pushes the commit and the tag.

The release commit goes through the standard build path on `master`, which produces `<service>:<sha>`. The tag push then triggers the production promotion workflow. That workflow attaches the CalVer image labels and creates the release from the generated changelog.

`cocogitto` is **changelog-only**. It does not compute the version. It does enforce the commit format, and it renders notes grouped by type, with breaking changes at the top.

### Changelog, pre-release, hotfix

| Concern | Rule |
| --- | --- |
| Changelog | one top-level `CHANGELOG.md`, regenerated on every release and **committed**. So reviewers see the text of the release in the release PR, and it survives a shallow clone or a mirror |
| Pre-release tags | `-rc.<N>` is valid and does **not** trigger a production deploy. It is reserved for when an external consumer needs a named pre-release artifact |
| Hotfix | branch from the commit of the release tag, not from `master`, as `hotfix/v<YYYY.0M.MICRO+1>`. Cherry-pick, and run `mise run release` from the branch. The tag drives the same promotion workflow. The branch is deleted after the tag exists |

### How consumers resolve

| Consumer | Resolution |
| --- | --- |
| Go code that consumes `libs/go/*` | packages of the single root module, so always on-disk source |
| TypeScript that consumes `libs/ts/*` | `workspace:*`, so always on-disk source |
| Generated API clients | the workspace version. They are not versioned independently |
| An external pinner | does not exist. It comes only through the SemVer escape hatch, at publication time |

## Consequences

### Positive

- There is one version to reason about. What is in production is one date, the human alias of the deployed SHA.
- No human picks bump levels, and there is no per-component tag bookkeeping.
- Deploy identity and release identity stay decoupled, so the GitOps invariants hold.
- One calendar covers release versions and API-contract versions, so there is no second versioning vocabulary.
- The running build reports itself through telemetry, an endpoint, and a header. All three come from one compiled-in value.

### Negative and Risks

- **CalVer carries no compatibility signal.** This is accepted. Nothing internal is pinned externally. The compatibility story of the API lives in [ADR-0303](0303-api-contracts-and-lifecycle.md). The escape hatch covers later publication.
- **An unrelated change shares the same release number.** This is accepted. The repo ships as a unit, so the number should mean everything as of this date.
- **The platform uses a fraction of the capability of `cocogitto`.** This is accepted. If external publishing grows, each artifact can opt into bump mode.

## Rules

- Every commit on `master` is a valid Conventional Commit. Breaking markers head the changelog and flag review. Under CalVer, they compute no version bump. `(CI: ci:lint; ref: Conventional Commits)`
- The repository has one release version, CalVer `vYYYY.0M.MICRO`. There are no per-component version lines and no prefixed tag namespaces. `(ref: CalVer)`
- In addition to the build tag of [ADR-0101](0101-monorepo.md), production pins by digest. Each release publishes exactly one immutable CalVer label for human reference. Moving tags are never published. `(CI: lint:floating-tags)`
- `mise run release` cuts releases. There is no auto-release on merge. A release tag triggers the production deploy. Dev and staging deploy continuously from `master`.
- The repo owns one committed top-level `CHANGELOG.md`. cocogitto regenerates it in changelog-only mode, grouped by change type, newest first. `(ref: Keep a Changelog)`
- Hotfixes branch from the release tag, not from `master`.
- Anything extracted or published for external consumers to pin adopts SemVer with its own tag at that point. `(ref: SemVer)`
- The identity of the running build is compiled into the artifact and never read from a runtime environment. It shows as OTel `service.version` and `service.build.sha`, a `GET /version` admin endpoint, and the `X-App-Version` and `X-App-Revision` response headers.
- The promotion workflow gates on rollout completion, not on Argo reporting Healthy.
