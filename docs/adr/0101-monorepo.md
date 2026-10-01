# ADR-0101: Monorepo Structure and Build

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0100](0100-language-and-runtime.md), [ADR-0103](0103-release-and-versioning.md), [ADR-0200](0200-cluster-topology.md), [ADR-0201](0201-gitops.md), [ADR-0401](0401-internal-admin.md), [ADR-0601](0601-testing-strategy.md)
- **Decides:** One repository, one Go module, `mise` as the task runner, and affected-detection deciding what CI runs.

## Context

These parts need a home:

- a fleet of backend services
- one frontend application
- shared Go and TypeScript libraries
- generated API clients
- infrastructure-as-code
- tooling

This ADR decides whether that home is one repository or many. Everything after it follows from that answer.

This ADR answers seven questions in one place: repository topology, layout, task invocation, workspace tooling, CI, codegen, and frontend topology.

## Decision drivers

1. **One task entry point per concern.** The same command does the right thing in any directory and any language. A developer finds it without reading the CI configuration.
2. **Native caches first.** These are the Go build and test cache, Docker BuildKit, and the Bun install cache. Higher-level orchestration is added only when these are not enough.
3. **CI cost tracks what changed, not what exists.** In a repository that holds the whole fleet, every pull request can run the whole fleet unless something scopes it. That cost grows with the repository, and the value of the run does not.
4. **Local and CI run the same commands.** There are no CI-only shell scripts.
5. **Orchestration is bought with measured need.** The value of a build-graph tool scales with the number of teams and applications. Here the binding constraint is platform-engineering capacity, per [ADR-0000](0000-platform-foundations.md). The cost of the tool comes out of that budget from day one.

## Considered options

### Repository topology

| Option | A change crossing a service boundary | Dependency drift | CI blast radius | Verdict |
| --- | --- | --- | --- | --- |
| **One repository, one Go module** | **one pull request that compiles and tests every consumer** | **structurally impossible** | every change can reach everything, so scoping is mandatory, not optional | **Chosen** *(reasoned)* |
| Repository per service | N pull requests across N review queues, merged in an order that nothing enforces | the default state. Each service pins its own versions, and they diverge | naturally scoped | The honest baseline, and the result when nobody decides. The isolation is real. It is the wrong purchase at axis A high with one platform team |
| Hybrid: a platform repository, with services split out | as repository-per-service for the split parts | as repository-per-service for the split parts | mixed | Two toolchains, two CI shapes, and two release paths. The boundary is argued again for each service |
| One repository of submodules | a submodule bump per repository, plus a superproject bump | as repository-per-service | mixed | The coordination cost of many repositories, with the review surface of one |

**The generated client is the deciding property.** Every service publishes a contract. The contract generates clients that other services compile in, per [ADR-0303](0303-api-contracts-and-lifecycle.md). Across a repository boundary, that generation is a publish-and-consume cycle. A breaking contract change then becomes a version negotiation between queues. In one repository, it is a compile error in the pull request that caused it. At axis A high, the number of those boundaries is the thing that grows.

The choice is reversible in one direction only. Adding a repository is easy. Extracting a service from this one is a migration. *Consequences* prices that asymmetry.

### Task runner

Two questions are bundled here: **running tasks**, and **pinning the toolchain those tasks need**. Most candidates answer only one of them, and that separates the options.

| Option | Runs tasks | Pins tool versions | Verdict |
| --- | --- | --- | --- |
| **mise** | **yes** | **yes, in the same file** | **Chosen.** One tool does both, so a task and its toolchain cannot drift apart *(reasoned)* |
| Make | yes | no | Present everywhere. The toolchain becomes a separate unpinned problem |
| `just` | yes | no | Better ergonomics than Make, with the same gap |
| asdf | no | yes | The version manager whose plugin ecosystem mise is compatible with. It needs a task runner beside it |
| direnv | no | environment variables only | Solves neither question. It composes with whatever does |
| Nix: flakes, `devenv`, `devbox` | through flake apps, or a runner beside it | **yes, hermetically, down to system libraries** | The strongest reproducibility on offer. This repository has already answered most of its question. See below |
| Nx | yes | no | A build graph with caching. Its value needs more applications than this repo has. A documented upgrade path |
| moon, with `proto` | yes | through `proto`, a second binary that resolves from a curated registry | The closest direct competitor. It is the only candidate that ships affected detection, so nobody has to write it. See below. A documented upgrade path |
| Pants | yes | yes, hermetically | In the Bazel family. It has [dependency inference](https://www.pantsbuild.org/blog/2022/10/27/why-dependency-inference) in place of hand-written build files, and a real Go backend. Held against the same compliance trigger, where it is a more likely answer than Bazel |
| Bazel | yes | yes, hermetically | Reserved for the compliance trigger below, together with Pants and Nix |

**On moon.** It answers both questions. It also ships the one capability that this ADR otherwise builds by hand: a project graph with affected detection and task caching. *Consequences* records that custom affected detection is the most load-bearing tooling in this repository. A bug in it gives a green run against a broken service. moon would retire that code.

Three things decide against it now:

- **Two binaries where mise is one file.** Tool pinning lives in `proto`, beside it.
- **Its depth is in the JavaScript ecosystem.** [Other languages arrive as WASM toolchain plugins](https://moonrepo.dev/docs/how-it-works/languages). Bun came later than the Node package managers. This repository is the reverse: Go-primary, with one JavaScript application.
- **The two tools pin by different architectures.** `proto` resolves from a curated registry. Its own [documentation](https://moonrepo.dev/docs/proto/plugins) states that proto cannot support every tool in core directly. So a tool outside the core toolchain and the community registry is a plugin written here. mise resolves a tool from its GitHub releases, with no plugin and no per-tool entry. The difference is invisible for Go and Bun. It is decisive for the rest of the pinned set, which is mostly single-binary Go releases.

Driver 5 applies here as it does to Nx. The graph is bought when the need is measured. The seam is that tasks are already declarative and named `group:member`.

**On Nix.** It pins system libraries, not only tool versions. Nothing else here has that capability. Three things weigh against it:

- **It is not a task runner.** So a runner sits beside it, and driver 1 forbids splitting task invocation across two tools.
- **It puts a second language and a daemon** on every workstation and every CI runner. That cost comes from the platform-engineering budget, which is the binding constraint, per [ADR-0000](0000-platform-foundations.md).
- **The gap it closes is the system-library layer.** A statically linked Go binary on a distroless base has almost none of that surface. So the payoff here is a fraction of the payoff for a dynamically linked polyglot fleet.

It returns as a candidate when hermeticity becomes a requirement. Bazel is held against the same trigger.

### Go module strategy

| Option | Dependency consistency | Cross-cutting refactor | Verdict |
| --- | --- | --- | --- |
| **Single repo-wide `go.mod`** | **structural: drift is impossible** | one PR | **Chosen** *(reasoned)* |
| Module per service | isolated | staggered bumps across N modules | Buys isolation that the platform does not need, and costs consistency that it does need |
| `go.work` overlay | partial | workspace-mode ceremony | Rejected for the product. Taken for `tools/` alone, where the isolation is the point |

### JavaScript workspace orchestration

[ADR-0100](0100-language-and-runtime.md) settles the runtime and package manager: Bun alone, for install and workspaces. This section decides whether a separate orchestrator sits above it.

| Option | Verdict |
| --- | --- |
| **Bun workspaces alone** | **Chosen.** The selected tool already has the workspace protocol, so the repository adds no JavaScript component *(reasoned)* |
| Turborepo | Task orchestration and remote caching for JavaScript. Its value needs several frontend applications, and there is one |
| Nx for JavaScript only | Splits task invocation across two tools, which driver 1 forbids. The table above considers it as the repo-wide runner instead |

### The lint and format toolchain

There is one tool per language. Each is a single pinned binary with no ambient runtime, per principle 6 of [ADR-0000](0000-platform-foundations.md). Each is Tier 2, per [ADR-0002](0002-tool-adoption.md). A swap is a configuration file and a task, and the code it judges does not change.

| Surface | Chosen | Picked over | Why |
| --- | --- | --- | --- |
| Go | **golangci-lint** | `go vet` alone, revive, staticcheck standalone | It is the aggregator that runs the others. The alternative is running several of them and reconciling their output *(reasoned)* |
| TypeScript | **Biome** | ESLint with Prettier, oxlint, dprint | One binary for lint and format. The incumbent pair is two tool ecosystems, two configuration languages, and a plugin resolution model. The cost is the small set of framework-specific rules that only the incumbent has |
| Markdown | **rumdl** | markdownlint, Vale, Prettier | One binary for lint and format. It holds the compact-table rule that the diffs of this repository depend on, per [ADR-0001](0001-documentation-and-output-conventions.md). markdownlint needs Node. Vale judges prose style, not structure, so it would add to rumdl and not replace it |
| Shell | **shellcheck and shfmt** | no shell lint, shellharden | The two-tool exception. It is the only pairing in the field: no single binary formats and lints shell |
| SQL | **sqruff** | sqlfluff, no SQL lint | The rule set that the incumbent established, reimplemented without the Python runtime that principle 6 bars *(reasoned)* |
| Git hooks | **lefthook** | husky, pre-commit, a committed `.githooks` directory | One binary that reads one committed YAML file. husky needs Node in every clone. `pre-commit` needs Python. A hooks directory has no parallelism and no staged-file filtering |

**The pattern is one property, repeated.** Every row picks a single static binary over a runtime plus a dependency tree, and accepts a narrower rule set for it. That trade lost for shell. There the ADR pays for two binaries and does not pretend that one covers it.

## Decision

### Repository layout

```text
go.work                       # the product module and the tool module
go.mod                        # the product module: services, libs, apps
go.sum

services/<name>/              # one backend service (package, not a module)
├── openapi.yaml
├── cmd/{server,worker}/
├── internal/{handlers,workflows,activities,domain,store}/
├── migrations/
├── Dockerfile
└── .mise.toml

apps/
├── frontend/                 # one frontend app, route groups inside (ADR-0400)
│   └── src/app/(landing|panel|devportal)/
└── admin/                    # Lowdefy config for internal admin (ADR-0401)
    ├── lowdefy.yaml
    ├── _generated/<service>/ # codegen from OpenAPI, drift-checked
    └── custom/<service>/     # hand-written pages

libs/
├── go/                       # all shared Go (single go.mod, no per-library module)
│   ├── <name>/
│   └── sdks/<service>/       # generated Go server + client
└── ts/                       # all shared TS (workspace root)
    ├── <name>/
    └── sdks/<service>/       # generated TS client

infra/
├── terraform/                # cluster + DNS + LB provisioning
├── helm/                     # Helm charts (ours + values for upstream)
├── gitops/                   # ArgoCD ApplicationSets + per-env values
├── talos/                    # node machine configs (ADR-0200)
├── auth/                     # Kratos, Hydra, OpenFGA config
├── gateway/                  # Traefik routing + rate limits
└── observability/            # dashboards and alerts as code

tools/                        # repo-local Go programs
scripts/                      # shell entered through mise tasks

test/                         # external harnesses driving an assembled system
├── e2e/                      # Playwright suites and fixtures (ADR-0601)
└── perf/                     # k6 scenarios and seed data (ADR-0601)

docs/                         # genre decides the directory (ADR-0001)
├── adr/                      # the decisions
├── guide/                    # procedures
├── reference/                # lookups, registries, live state
└── *.md                      # entry documents, and registries an ADR names as canonical

.github/workflows/            # CI definitions
```

| Choice | Reason |
| --- | --- |
| `services/` and `apps/` are siblings | Services are headless, horizontally-scaled, internally-addressed backends. `apps/` holds first-party deployable applications. The slot stays open for partner portals, CLIs, or mobile apps with no layout migration. A new entry under `apps/` requires its own ADR |
| `services/` stays spelled out | `svc` already means a Kubernetes Service here. It is also the per-service metavariable in docs. A directory name is short only when the short form is not ambiguous |
| `infra/` holds both IaC and the configuration of what it deploys | One top-level directory removes the recurring question of `infra` or `ops` |
| `tools/` holds repo-local Go programs only | It is not a place for shell scripts. mise installs external tools. The own module of `tools/` keeps linter dependencies out of the graph that every generated project ships. `tools/internal/` holds the packages that those programs share |
| `scripts/` holds shell, and shell only | This is the other side of the row above, so the split is a language boundary, not a habit. When the work of a script is a Go program, it is not a script: the task calls the program directly. A wrapper that only changes directory and shells out puts one name in two trees |
| `test/` holds external harnesses, and is singular for that reason | Each suite drives an assembled, running system from outside it, so no suite belongs to one service, per [ADR-0601](0601-testing-strategy.md). It is not where the tests live. A Go test of an `internal/` package **cannot** move here. Only the subtree under the parent of `internal/` can import it, so the compiler rejects the import. Unit tests sit beside their code. This also lets `ci:affected` map a changed package to the tests that cover it |
| Each suite under `test/` pins its own tools | `test/e2e/` is the Node island, and `test/perf/` is the k6 island. They share a parent, not a toolchain. `test/` has no `package.json`, no lockfile, and no tool pin of its own. The containment is per directory, in the same way that `apps/admin/` pins the pnpm of Lowdefy under `apps/`. `(CI: lint:node-scope)` |

### mise is the single entry point

Tasks live in `.mise.toml` files. A root file holds repo-wide tasks, and one file per service holds the tasks local to that service. `mise tasks --list` is the interface for finding them.

The convention of normalized entrypoints comes from GitHub's [Scripts to Rule Them All](https://github.blog/engineering/engineering-principles/scripts-to-rule-them-all/). The difference is the layer. There, the normalized names *are* the scripts. Here, they are mise tasks, because the entrypoint must also pin the toolchain it runs under. `scripts/` is the shell that those tasks enter. The per-service set is closed and enforced by `lint:service-contract`, not only a convention.

| Scope | Standard task names |
| --- | --- |
| Every service | `build`, `test`, `lint`, `generate`, `migrate`, `server`, `worker`. This is the closed set that every service exposes |
| Repo root | fleet-wide work, grouped by its axis: `ci:*` for what CI invokes, `cluster:*` for the local environment, `gen:*` for codegen, `lint:*` and `format:*` for the checks. `mise tasks --list` gives the full list |

The two long-running service tasks are named for the process type they start. The names match `cmd/{server,worker}/`, the `<service>-{server,worker}` images, and the in-cluster DNS names. This gives one vocabulary from end to end. A frontend is not a service and keeps `run`. It has no worker to match, and the task starts a dev server, not a production binary.

**Task naming.** A task name is `group:member`. The group is the axis that you list and run together. Two shapes are correct. The axis worth aggregating by decides which one applies:

| Shape | Use when | Examples |
| --- | --- | --- |
| `activity:target` | one activity fans out across many targets, with an umbrella task | `lint:go`, `lint:ts`, `lint:md` under `lint`. `format:*`. `gen:openapi`, `gen:sqlc` under `gen` |
| `resource:operation` | a stateful thing has a lifecycle worth grouping | `cluster:up`, `cluster:stop`, `cluster:down`, `cluster:add`, `cluster:remove`, `db:migrate`, `ops:grant` |

**A task name spells its script.** The two shapes map onto `scripts/`. So a developer finds the implementation of a task without reading `.mise.toml`:

- `activity:target` is `scripts/activity-target.sh`. Examples are `gen:openapi`, `lint:ports`, and `promote:prod`.
- `resource:operation` is `scripts/resource.sh operation`: one entrypoint that takes the verb as an argument. Examples are `cluster:up`, `argo:pause`, and `mock:start`.

When all members of a family share one implementation, the script is named for the family, not for a member. `dep:*` and `svc:*` enter `dep-apply.sh` and `svc-apply.sh`.

One shape for both cases scatters a family. `stop:cluster` and `delete:cluster` split the cluster lifecycle, and `ts:format` breaks the `format` umbrella. Use `activity:` only where a real umbrella exists. Graph-only plumbing that exists only as a `depends` node is marked `hide = true`.

**What a task acts on is an argument.** An environment variable carries the environment of the machine, such as a proxy address or a kubeconfig path. That is the same for every invocation from that shell. The thing that one invocation acts on is an operand, and it belongs in the argument list. `mise run cluster:down -- full` names its target on the line that ran it. `TIER=full mise run cluster:down` puts the target in shell state that outlives the command. The next destructive verb then aims at the wrong cluster. A script can export a variable to pass context to a subprocess it starts. That is internal plumbing, not the interface.

A task validates each operand against a closed set, and an unknown operand is fatal. A silent fallback to the default lets a typo delete a tier that the operator did not name.

### Every executable is pinned, in one of two places

| Kind | Pinned in |
| --- | --- |
| Developer and CI tools: Go, Bun, `sqlc`, `sqruff`, `ogen`, `vacuum`, `helm`, `kubectl`, `age`, `sops`, and mise itself | the root `.mise.toml`, or a service-local one where a service truly needs a different version |
| Runtime services: Postgres, Temporal, Kratos, Oathkeeper, OpenFGA, SeaweedFS, the observability stack, Argo CD, and the CNPG operator | the Helm chart `appVersion`, plus an explicit `image.tag` in `infra/helm/.../values.yaml` |

Floating tags are forbidden in `.mise.toml`, Dockerfiles, Helm values, and workflows. A floating tag is `latest`, `stable`, `main`, or an unpinned major. A tool-version change is a normal PR. So anyone who clones at any SHA reproduces the exact toolchain that built it.

### One Go module for the product, one for the gates

One `go.mod` at the repo root covers every service, library, and generated client. There is no per-service module and no `replace` directive. Services and libraries are plain packages, imported by the module path of the repo.

`tools/` is the single exception: a second module, joined by a committed `go.work`. The dependencies of a gate, such as a ruleguard DSL or an AST walker, are not a dependency of anything that ships. A generated project inherits this tree as a whole. So in the product graph, they would put linter code in the module that every service resolves against. The tool tree needs exactly the isolation that the product does not need. A service image never sees the workspace. Its Dockerfile copies `go.mod`, `go.sum`, `libs/go`, and one service directory, so `go.work` is not in the build context.

Here, dependency **consistency** is worth more than dependency **isolation**:

- one `go get -u` upgrades the repo
- one `govulncheck` and one `go.sum` describe it
- cross-cutting refactors land in one PR
- the structure forces every service onto the same version of every dependency

*Consequences* lists the accepted costs.

### One frontend app

The frontend is one application, with route groups for `(landing)`, `(panel)`, and `(devportal)`. [ADR-0400](0400-frontend.md) sets its framework. This ADR sets the count.

| Reason | Detail |
| --- | --- |
| Cross-subdomain auth is hostile | Sharing cookies and session across subdomains often causes subtle production bugs, with Safari ITP most of all |
| Bundle size is not the constraint | Route-level code splitting weakens the argument for separate apps |
| One deploy unit | One Traefik routing surface: `/panel/*` as a path, not a hostname |

A truly independent frontend gets its own ADR. Examples are a partner-branded experience and an embedded SDK. Such a frontend is not a reason to split the primary app in advance.

Bun workspaces join the app and the TS libraries:

```jsonc
// package.json (root)
{ "workspaces": ["apps/frontend", "libs/ts/*", "libs/ts/sdks/*"] }
```

### CI

| Workflow | Runs |
| --- | --- |
| `ci.yml` | the merge gates, one job each: `mise run ci:build`, `ci:test`, `ci:gen`, which fails on drift, `ci:lint`, `ci:affected-adversarial`, `ci:scan` |
| `publish.yml` | builds and pushes images on merges to `master` |
| `e2e.yml` | the full suite nightly and before a release, plus a label-gated smoke job, per [ADR-0601](0601-testing-strategy.md) |

Lint, test, and build run over **the whole repo and both modules**. They are not affected-scoped. The linters have no per-service subset to take, and the Go build cache keeps the repeat cost small. `ci:affected` scopes what is built and promoted, not what is analysed.

Every workflow takes its toolchain from the `./.github/actions/setup` composite action. So the mise setup and the Go cache key are defined once. [ADR-0102](0102-source-control-and-ci.md) decides which forge runs these workflows, and on whose runners. Its thin-YAML rule keeps that choice reversible.

### Affected detection

`tools/affected/` reads `git diff --name-only origin/master...HEAD` and maps changes to scopes:

| Change under | Affects |
| --- | --- |
| `services/<X>/` | service `<X>` |
| `libs/go/<L>/` | every Go consumer of `<L>`, through `go list -deps` |
| `libs/go/sdks/<S>/` | every Go consumer of the client of service `<S>` |
| `apps/frontend/` | the frontend |
| `infra/`, `tools/`, `go.mod`, `go.sum`, `package.json` | **global**: everything runs |

`mise run ci:affected` produces a JSON manifest that the workflows consume. As the fleet grows, this is the most load-bearing repo tooling, and it has unit tests.

### Codegen is committed and drift-checked

Principle 9 of [ADR-0000](0000-platform-foundations.md) states that generated code is committed and drift-checked. This ADR fixes where it lands and how the check runs:

- OpenAPI clients land in `libs/{go,ts}/sdks/<service>/`.
- sqlc output lands in `services/<service>/internal/store/`.

`mise run ci:gen` regenerates everything, and CI fails on a diff. A lefthook pre-commit hook runs the relevant part when source files change.

### Caching

| Cache | Keyed on |
| --- | --- |
| Go build and test | the root `go.sum` |
| Docker BuildKit layers | the registry |
| Bun install | [`bun.lock`](https://bun.com/blog/bun-lock-text-lockfile) |

**Deferred:** a remote Go build cache, such as `GOCACHEPROG` or `sccache`. **Trigger:** CI time stays above 15 minutes on the median affected pull request. **Seam:** it is a `GOCACHEPROG` environment variable, so adoption is configuration. **Cost if adopted late:** the CI minutes already spent, and nothing structural. The cache is cold on adoption at any time.

### Container images

Each service has one multi-stage `Dockerfile`. Stage 1 builds with the workspace `go build`. Stage 2 is the runtime base below. The frontend has one Dockerfile that uses standalone output. There is no shared base image.

| Runtime base | Verdict |
| --- | --- |
| **`gcr.io/distroless/static-debian13`** | **Chosen.** No shell and no package manager, so a compromised process has nothing to escalate with. Upstream maintains the CA bundle, `/etc/passwd`, and timezone data that a service with outbound TLS calls needs *(reasoned)* |
| `scratch` | Smaller and truly empty. That means copying the CA bundle, a nonroot passwd entry, and tzdata by hand. It also means owning the CA refresh when roots rotate |
| Alpine | A shell and a package manager in production. Under Go, musl resolves DNS differently from glibc |
| Chainguard or Wolfi | Comparable hardening, with a stronger SBOM story. Its free tags track `latest`, which the floating-tag rule forbids |

**This base is not related to the host operating system.** It gives no kernel and no init. It is a few megabytes of files that come from a Debian release. A change to what the nodes run changes nothing here, per [ADR-0200](0200-cluster-topology.md).

**Server and worker are separate images from the same Dockerfile.** A `CMD` build arg selects which `cmd/` binary the build stage compiles. The result is `<service>-server:<sha>` and `<service>-worker:<sha>`. They scale independently and have different resource profiles. Neither should carry the code surface of the other. One Dockerfile keeps the build stage and base layers shared and cache-friendly.

Images are tagged `<service>:<git-sha>`, and the same SHA goes through every environment, per [ADR-0201](0201-gitops.md).

### Upgrade path

Each step is its own ADR when its trigger fires.

| Step | Trigger | Seam | Cost if adopted late |
| --- | --- | --- | --- |
| Split the Go module | a service or library needs its own dependency line: external publication, a different upgrade cadence, or isolated security review | present. Packages already sit at import paths that become module paths with no change | grows with the number of cross-package imports that must become versioned dependencies. The later it happens, the more of the repository it touches |
| Adopt Nx or moon as a task orchestrator with caching and a project graph | the task graph outgrows mise, or hand-written affected detection is no longer trustworthy | present. Tasks are declarative and already named `group:member`. Both tools wrap them and do not replace them | low. It is proportional to package count and does not compound. Each wrap is mechanical, and nothing builds up that makes the next one harder |
| Adopt Pants, Bazel, or Nix | hermetic reproducible builds become a compliance requirement. The ADR written at that time picks one of the three | **none. This is a bet**, per [ADR-0000](0000-platform-foundations.md). Each tool replaces the build and does not wrap it. So every Dockerfile, task, and codegen step is rewritten | **grows with the fleet.** Every build target, Dockerfile, and codegen step must be described to the new system. So the migration is proportional to a repository that is expected to grow. The trigger is a compliance requirement, and those come with dates. The risk of waiting is a fleet-sized migration to the deadline of someone else. The delay buys this: the platform never pays for a build system that the trigger may never demand |

## Consequences

### Positive

- `mise run <task>` is the universal interface across languages and services.
- Cross-package Go changes land in one PR, with no `replace` directive and no workspace ceremony.
- The structure forces every service onto the same dependency versions. There is no drift and no per-service upgrade backlog. Renovate opens one PR per dependency, not N.
- One frontend app removes the whole class of cross-subdomain auth bugs.
- Committed codegen keeps PR review honest and CI simple.
- Affected detection ties CI runtime to PR size, not repo size.

### Negative and Risks

- **Affected detection is custom code.** A bug in it gives passing tests while the affected service is broken. Three things mitigate this: unit tests, an explicit `--all` fallback, and global-trigger paths that turn any shared-infrastructure change into a full run.
- **A single `go.mod` means a service cannot pin its own version of a shared dependency.** A risky upgrade lands across the repo or not at all. `depguard` rules on sensitive packages and the documented module-split path mitigate this.
- **A single `go.mod` couples the vulnerability blast radius.** A CVE in any transitive dependency flags the whole repo. Treating Go upgrades as routine repo-wide work mitigates this.
- **Extracting a service to its own repo is a real migration**, not a directory move. This is accepted, because this is an internal product, not a library ecosystem.
- **One frontend app risks becoming a god-app.** Lint-enforced route-group boundaries mitigate this, together with the ADR-required path for truly independent frontends.
- **Committed generated code makes the repo larger.** Routine `git gc` and `git repack` mitigate this.
- **A single `go build ./...` compiles more than one service needs.** The native build cache absorbs this, and affected detection keeps CI proportional to PR size.

## Rules

- The fleet lives in one repository. Moving any part of it to a second repository requires its own ADR.
- The product is a single Go module rooted at `go.mod`, with no per-service or per-library `go.mod`. `tools/` is the one exception: a second module joined by `go.work`. The dependencies of a gate are not a dependency of anything that ships. `(CI: ci:lint)`
- A service image build copies only `go.mod`, `go.sum`, `libs/go`, and its own service directory, so `go.work` never enters the build context.
- Every backend service lives at `services/<name>/`. Every shared Go package lives under `libs/go/<name>/`. Every shared TypeScript library lives under `libs/ts/<name>/`. `(CI: lint:service-contract)`
- Generated API clients live at `libs/{go,ts}/sdks/<service>/` and are committed. `(CI: ci:gen)`
- The frontend is one application at `apps/frontend/`. A new frontend or a new entry under `apps/` requires an ADR.
- Tasks are invoked through `mise run <task>`. Every service exposes `build`, `test`, `lint`, `generate`, `migrate`, `server`, and `worker`. `(CI: lint:service-contract)`
- A task name is `group:member`, grouped by the axis worth listing together, and it spells its script. `activity:target` is `scripts/activity-target.sh`, and `resource:operation` is `scripts/resource.sh operation`.
- What a task acts on is an argument, never an environment variable: `mise run cluster:down -- full`. Environment variables carry the environment of the machine. A variable that a script exports for its own subprocesses is not an interface. `(ref: clig.dev, POSIX Utility Conventions)`
- A task validates its operand against a closed set and fails on an unknown operand. It never falls back to a default.
- Every external tool is pinned. Developer and CI tools are pinned in `.mise.toml`, and runtime services as an explicit `image.tag` in Helm values. Floating tags are not used anywhere. `(CI: lint:floating-tags)`
- A PR that changes a spec, a SQL query, or any codegen input includes the regenerated artifacts. `(CI: ci:gen)`
- A change to `go.mod`, `go.sum`, root `package.json`, `infra/`, or `tools/` triggers a full-repo CI run. `(CI: ci:affected)`
- Container images are tagged `<service>:<git-sha>`, and the same SHA goes through every environment. `(CI: lint:floating-tags)`
- `services/<X>/` does not import `services/<Y>/`. Sharing goes through `libs/` or generated clients. `(CI: lint:go, lint:service-contract)`
- Route groups inside `apps/frontend/` do not import from each other. `(CI: lint:ts)`
- `tools/` holds repo-local Go programs and the packages under `tools/internal/` that they share. `scripts/` holds shell. A mise task invokes a Go program directly. A shell script that only shells out to one is not written.
- `test/` holds the external harnesses that drive an assembled system: `test/e2e/` and `test/perf/`. A test of the code in one package lives beside that package.
- Each suite under `test/` pins its own tools. `test/` itself has no toolchain, package manifest, or lockfile. `(CI: lint:node-scope)`
- Build-graph and hermetic-build tools are not used on day one. These are Nx, moon, Pants, Bazel, and Nix. Adoption requires its own ADR.
