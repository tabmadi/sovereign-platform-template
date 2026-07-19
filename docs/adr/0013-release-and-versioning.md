# ADR-0013: Release, Tagging & Versioning

- **Status:** Accepted
- **Date:** 2026-07-06
- **Deciders:** Platform team
- **Related:** [ADR-0002](0002-monorepo.md), [ADR-0004](0004-gitops.md), [ADR-0008](0008-api-contracts.md), [ADR-0022](0022-api-lifecycle.md)

## Context

The monorepo produces several distinct kinds of release artifact:

- **Service container images** — built per merge, deployed via GitOps.
- **Go libraries** under `libs/go/` consumed by services as in-repo packages of the single root module.
- **TS libraries** under `libs/ts/` consumed by `apps/frontend/`.
- **Generated API clients** under `libs/{go,ts}/sdks/`.
- **Helm charts** under `infra/helm/` with their own `Chart.yaml` versions.
- **The frontend and admin apps** under `apps/`.

Per [ADR-0002](0002-monorepo.md), container images are tagged `<service>:<git-sha>` and the same SHA flows through every
environment ([ADR-0004](0004-gitops.md)). That covers deployment identity, but it does not answer:

- How do humans refer to "what's in production right now" in a CHANGELOG or release note?
- When does a version number actually change, and who is allowed to change it?
- How is a breaking change to a service's OpenAPI contract ([ADR-0008](0008-api-contracts.md)) handled
  ([ADR-0022](0022-api-lifecycle.md))?

The decisive fact is that **this repo ships as a single unit.** GitOps rolls one SHA through every environment
([ADR-0004](0004-gitops.md)); prod moves as a whole when a release is cut. No component here has an external consumer
that pins it independently: Go libs are in-tree packages of one module, TS libs resolve via `workspace:*`, and
service-to-service calls ride the in-repo generated SDK at HEAD ([ADR-0008](0008-api-contracts.md)). A per-component
SemVer line would therefore encode a compatibility promise **no external consumer is there to read** — ceremony that
signals nothing. The repo already pins `cocogitto` in `mise.toml`, signalling Conventional Commits as the source of
truth for changelogs.

## Decision drivers

1. **One repo-wide release version, because the repo ships as a unit.** A single co-shipped product is versioned by
   *when* it shipped, not by a per-component "what changed" contract that has no independent pinner.
2. **Versions are release labels, not compatibility promises.** Nothing internal is pinned by an outside party
   (see *Context*); breaking-change handling for the API is [ADR-0022](0022-api-lifecycle.md)'s job, not a version
   number's.
3. **Conventional Commits are mandatory.** They drive the changelog and mark breaking changes for review.
4. **Deploy identity stays SHA-based.** The release version is an *additional* human label on the same image, never a
   replacement. GitOps continues to roll forward by SHA ([ADR-0004](0004-gitops.md)).
5. **Releases are explicit acts.** Merging to `master` deploys dev/staging; cutting a release tag promotes prod.

## Decisions

### Commit message format: Conventional Commits, enforced

All commits on `master` follow the [Conventional Commits](https://www.conventionalcommits.org/) spec:

```text
<type>(<scope>): <subject>

[body]

[footer]
```

- **Types** allowed: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `chore`, `build`, `ci`, `revert`.
- **Scope** is the component path slug: `gateway`, `clay`, `libs/go/observability`, `frontend`, `helm/postgres`, etc.
  The set of valid scopes is generated from the repo layout and enforced by lint.
- **Breaking changes** are marked with `!` after the type/scope (`feat(gateway)!: …`) **or** a `BREAKING CHANGE:`
  footer. Under CalVer this does **not** compute a version bump (the version is the date); it headlines the changelog
  and flags the change for review, and for the API surface it is the signal [ADR-0022](0022-api-lifecycle.md) keys off.

`cocogitto` enforces the format via a lefthook `commit-msg` hook. CI re-runs `cog check` on the PR's commit range.

PR squash-merges produce a single commit whose title MUST be a valid Conventional Commit. Merge commits are disallowed.

### Versioning scheme: one repo-wide CalVer line

The repository has **one** release version, calendar-based: **`vYYYY.0M.MICRO`** (e.g. `v2026.07.0`, then `v2026.07.1`
for a second release the same month, `v2026.08.0` in August). It is the human-readable alias for "the state of the whole
repo at this release" — the friendly form of the SHA that GitOps actually deploys.

- **No per-component version lines, no prefixed tag namespaces.** Services, apps, and charts do not carry their own
  SemVer; they are all at the repo version, because they ship together. `Chart.yaml`/`package.json` version fields, where
  a build tool requires one, are stamped to the current CalVer at release, not maintained independently.
- **Why CalVer, not SemVer.** SemVer's major/minor/patch encodes a compatibility contract for an *independent pinner*.
  This repo has none (see *Context*), so there is nothing for a SemVer major to signal; a date answers the only question
  that is actually asked of the release version — *when did this ship* — with no human judgement about bump levels.
- **The one place a compatibility axis still lives** is the external API contract, and it is deliberately *not* this
  version: [ADR-0022](0022-api-lifecycle.md) keeps the default API single-live-version and, only when an external
  consumer exists, mints date-based API versions drawn from this same release calendar. So there remains exactly one
  calendar; the API version is the subsequence of release dates on which the public contract changed.

### Escape hatch: SemVer for anything genuinely published externally

If a library, SDK, or service is ever **extracted or published for external consumers to pin** (a public Go module, an
npm SDK), *that artifact* adopts SemVer with its own prefixed tag at that point — because an external pinner does need
the breaking signal. This is introduced only when a real external consumer exists, not before; in-repo, everything is
the one CalVer line.

### Container image tags: SHA primary, CalVer label

[ADR-0002](0002-monorepo.md) and [ADR-0004](0004-gitops.md) keep `<service>:<git-sha>` as the deploy-identity tag. On a
release-tag push, the release workflow additionally pushes one immutable label per image:

- `<service>:v<YYYY.0M.MICRO>` (the same CalVer across every image in the release)

GitOps manifests never reference the CalVer tag — it exists for human and external-documentation use only. They pin by
**immutable identity**: a SHA tag in dev/staging (bumped by `promote-on-merge`), and an image **digest**
(`repo@sha256:…`, the strongest form — a digest cannot be re-pushed) in prod (resolved and written by
`promote-on-release`; the chart's `image.digest` takes precedence over `image.tag`). CI rejects moving tags
(`latest`, `vYYYY.0M`), which are never pushed.

### Verifying what's deployed

A recurring doubt — "the new tag is in Argo, but is the pod actually running the new code?" — is really two
problems: **actual drift** (old code under a new tag) and the **observability gap** (no way to confirm without
trusting the pipeline). Both are addressed, in layers.

**Prevent the drift (structural).** Deploys are by immutable `<service>:<git-sha>` (this ADR); GitOps references
SHA only, and moving tags are never published — so a node cannot silently serve a stale image under a reused
tag. Two hardenings belong to the promotion workflow ([ADR-0004](0004-gitops.md)): pin by image **digest**
(`@sha256:…`, the true identity), and **gate on rollout completion** — "Argo Healthy" is not "rolled out", so
the workflow waits for the new ReplicaSet to become available before declaring success.

**Bake one build identity into the artifact.** The identity is compiled **into the binary/bundle**, never read
from a runtime env or ConfigMap — the whole point is to prove *which build* is running, and a runtime value can
be changed independently of the code it claims to describe. Go services inject `git SHA`, release version, and
build time via `-ldflags -X` into `libs/go/buildinfo` (falling back to the Go VCS stamp for local `go build`);
the frontend inlines the same into `NEXT_PUBLIC_SERVICE_VERSION` at build. The build scripts and CI pass these
as `--build-arg GIT_SHA=… BUILD_VERSION=… BUILD_TIME=…`.

**Surface it three ways, from that one value:**

- **Attribute** — `obs.Init` sets OTel resource attributes `service.version` (release) and `service.build.sha`
  (precise, always-unique) from `buildinfo` ([ADR-0011](0011-observability.md)), so every trace/log/metric
  self-reports which binary emitted it. "What is serving prod right now" is a Grafana query, no endpoint needed.
- **Endpoint** — `GET /version` on the admin port (next to `/livez`,`/readyz`) returns `{version, sha, builtAt}`
  for per-pod, scriptable checks (CI smoke, an operator's `curl`).
- **Header** — every service response carries `X-App-Version` (release) + `X-App-Revision` (SHA) via the shared
  `httpmw`; the frontend stamps `X-App-Version` on every response too. This is what closes the frontend's doubt
  directly — inspect any response in devtools — and comparing the browser's bundle version against the backend's
  header also catches a **stale cached bundle**, a variant the backend alone would not reveal.

### Release process: `mise run release`

A release is repo-wide and **is** the prod deploy. Dev and staging deploy continuously from `master` (throttled by
ArgoCD sync windows — see [ADR-0004](0004-gitops.md)); prod only moves when someone cuts a release.

A maintainer runs:

```text
mise run release
```

The task:

1. Computes the next CalVer from the date and the last release tag (same month → bump `MICRO`; new month → reset).
2. Stamps version fields where a build tool needs one (`Chart.yaml`, `package.json`) to the new CalVer.
3. Regenerates `CHANGELOG.md` via `cog changelog` for the commit range since the last release.
4. Commits with `chore(release): v<YYYY.0M.MICRO>` and creates the tag.
5. Pushes the commit and tag.

The release commit goes through the standard build path on `master`, producing `<service>:<sha>`. The tag push then
triggers the prod promotion workflow ([ADR-0004](0004-gitops.md)), which also attaches the CalVer image labels and
creates the GitHub Release from the cocogitto changelog.

`cocogitto` here is **changelog-only**: it does not compute the version (the date does), but it still enforces commit
format and renders the release notes grouped by type, with breaking changes surfaced at the top.

### Changelog: one repo-wide, generated, committed

A single top-level `CHANGELOG.md`, regenerated by `cog changelog` on every release, is the human-readable artifact
attached to the GitHub Release. It is committed so reviewers see what the release will say *in the release PR*, and so it
survives loss of git history (mirrors, shallow clones). Cocogitto's Keep-a-Changelog format is used unmodified; entries
are grouped by Conventional-Commit type and scope.

### Pre-release and hotfix

- **Pre-release tags** (`-rc.<N>`) are valid and **do not trigger prod deploys**. Reserved for the rare case an external
  consumer needs a named pre-release artifact; not the default path.
- **Hotfixes** branch from the release tag's commit, not from `master`: `hotfix/v<YYYY.0M.MICRO+1>`, cherry-pick the fix,
  run `mise run release` from the hotfix branch. The hotfix tag drives the same prod-promotion workflow. Hotfix branches
  are deleted after the tag exists.

### Pinning consumers

- Go consumers resolve `libs/go/*` as packages of the single root module ([ADR-0002](0002-monorepo.md)) — always on-disk
  source. There is no external Go consumer.
- TS consumers resolve `libs/ts/*` via `workspace:*` — always on-disk source.
- Generated API clients are not versioned independently; in-repo consumers use the workspace version.
- External pinning is introduced only via the SemVer escape hatch above, at extraction/publication time.

## Consequences

### Positive

- One version to reason about: "what's in prod" is one date, the human alias of the deployed SHA.
- No human picks bump levels and no per-component tag bookkeeping; the version is just the release date.
- Deploy identity (SHA) and release identity (CalVer) stay decoupled, preserving the GitOps invariants
  ([ADR-0004](0004-gitops.md)).
- One calendar spans release and (eventual) API-contract versions ([ADR-0022](0022-api-lifecycle.md)) — no second
  versioning vocabulary.

### Negative / Risks

- CalVer carries no compatibility signal. Accepted: nothing internal is externally pinned, and the API's compatibility
  story lives in [ADR-0022](0022-api-lifecycle.md); the SemVer escape hatch covers anything later published for external
  pinning.
- A repo-wide version means an unrelated change still rides the same release number. Accepted — the repo ships as a
  unit, so "everything as of this date" is exactly what the number should mean.
- `cocogitto` is used for changelog/commit-format only, not bump computation. Accepted; if per-artifact external
  publishing grows, the SemVer escape hatch (and cocogitto's bump mode for that artifact) is opted in per artifact.

### Follow-ups

- `cog.toml` at repo root: configured scopes, hooks, changelog template (bump computation disabled).
- `mise run release` task wiring (delegates to `scripts/release.sh`) computing the next CalVer.
- Lefthook `commit-msg` hook running `cog verify`.
- `.github/workflows/promote-on-release.yml`: on tag push, label images with CalVer, bump prod values, create GitHub
  Release.
- Lint rule rejecting non-SHA image tags in Helm values and GitOps manifests.

## Rules

- Every commit on `master` is a valid Conventional Commit; CI fails otherwise. Breaking markers headline the changelog
  and flag review; under CalVer they do not compute a version bump.
- The repository has one release version, CalVer `vYYYY.0M.MICRO`. There are no per-component version lines or prefixed
  tag namespaces; components ship at the repo version.
- Container images are deployed by `<service>:<git-sha>`. A single immutable `<service>:v<YYYY.0M.MICRO>` label is
  published on release-tag push for human reference. Moving tags are never published. GitOps manifests pin by immutable
  identity only: a SHA tag in dev/staging, an image **digest** (`repo@sha256:…`) in prod (`image.digest`, written by
  `promote-on-release`).
- Releases are cut by `mise run release`; there is no auto-release on merge to `master`. A release tag triggers the prod
  deploy; dev and staging deploy continuously from `master`, throttled by ArgoCD sync windows ([ADR-0004](0004-gitops.md)).
- The repo owns one committed top-level `CHANGELOG.md`, regenerated by cocogitto (changelog-only; it does not compute the
  version).
- Hotfixes branch from the release tag, not from `master`.
- Anything extracted or published for external consumers to pin adopts SemVer with its own tag at that point; in-repo,
  everything is the one CalVer line.
- The running build's identity (git SHA + version + build time) is compiled into the artifact via `-ldflags -X` /
  `NEXT_PUBLIC_SERVICE_VERSION` — never read from a runtime env — and surfaced as OTel `service.version` +
  `service.build.sha` ([ADR-0011](0011-observability.md)), a `GET /version` admin endpoint, and `X-App-Version` /
  `X-App-Revision` response headers. Deploys stay SHA/digest-immutable and the promotion workflow gates on rollout
  completion ([ADR-0004](0004-gitops.md)).
