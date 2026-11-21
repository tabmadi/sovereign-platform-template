# ADR-0111: Monorepo Structure and Build

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0100](0100-toolchain.md), [ADR-0103](0103-tasks.md), [ADR-0110](0110-language-and-runtime.md), [ADR-0112](0112-release-and-versioning.md), [ADR-0200](0200-cluster-topology.md), [ADR-0201](0201-gitops.md), [ADR-0401](0401-internal-admin.md), [ADR-0601](0601-testing-strategy.md)
- **Decides:** One repository, one Go module, the recipe names of the platform, and affected-detection deciding what the image jobs build.

## Context

These parts need a home:

- a fleet of backend services
- one frontend application
- shared Go and TypeScript libraries
- generated API clients
- infrastructure-as-code
- tooling

This ADR decides whether that home is one repository or many. Everything after it follows from that answer.

This ADR answers seven questions in one place: repository topology, layout, recipe names, workspace tooling, CI, codegen, and frontend topology. [ADR-0100](0100-toolchain.md) pins every tool through Nix, and [ADR-0103](0103-tasks.md) makes `just` the task runner. This ADR builds on both.

## Decision drivers

1. **One task entry point per concern.** The same command does the right thing in any directory and any language. A developer finds it without reading the CI configuration.
2. **Native caches first.** These are the Go build and test cache, Docker BuildKit, and the Bun install cache. Higher-level orchestration is added only when these are not enough.
3. **CI cost tracks what changed, not what exists.** In a repository that holds the whole fleet, every pull request can run the whole fleet unless something scopes it. That cost grows with the repository, and the value of the run does not.
4. **Local and CI run the same commands.** There are no CI-only shell scripts.
5. **Orchestration is bought with measured need.** The value of a build-graph tool scales with the number of teams and applications. Here the binding constraint is platform-engineering capacity, per [ADR-0000](0000-platform-foundations.md). The cost of the tool comes out of that budget from day one.
6. **A change across services is one reviewed change.** A contract change and every consumer that it breaks land in one pull request.
7. **One binary per tool, with no ambient runtime**, per principle 6 of [ADR-0000](0000-platform-foundations.md).

## Considered options

### Repository topology

| Option | 3 CI cost tracks the change | 6 A change across services is one change | Dependency drift | Verdict |
| --- | --- | --- | --- | --- |
| **One repository, one Go module** | **Only with affected detection, which this ADR builds** | **Yes. One pull request compiles and tests every consumer** | **None. One version of each dependency** | **Chosen** |
| Repository per service | Yes, by construction | No. N pull requests in N queues, merged in an order that nothing enforces | Each service drifts | Rejected on driver 6 |
| Hybrid: a platform repo, with services split out | Partly | No, for the split parts | Partly | Rejected on driver 6 |
| One repo of submodules | Partly | No. A bump per repo and one in the superproject | Each submodule drifts | Rejected on driver 6 |

Sources:

- The trade of a monorepo: [Google, Why Google stores billions of lines of code in a single repository](https://research.google/pubs/why-google-stores-billions-of-lines-of-code-in-a-single-repository/).

**The generated client is the deciding property.** Every service publishes a contract. The contract generates clients that other services compile in, per [ADR-0303](0303-api-contracts-and-lifecycle.md). Across a repository boundary, that generation is a publish-and-consume cycle. A breaking contract change then becomes a version negotiation between queues. In one repository, it is a compile error in the pull request that caused it. At axis A high, the number of those boundaries is the thing that grows.

The choice is reversible in one direction only. Adding a repository is easy. Extracting a service from this one is a migration. *Consequences* prices that asymmetry.

### Go module strategy

| Option | 6 A change across services is one change | Dependency drift | Verdict |
| --- | --- | --- | --- |
| **Single repo-wide `go.mod`** | **Yes** | **None** | **Chosen** |
| Module per service | No. A shared bump lands in N modules one by one | Each module drifts | Rejected on driver 6 |
| A `go.work` overlay of many modules | Yes | Partly | Rejected for the product. Taken for `tools/` alone, where the isolation keeps the pins of Go tools out of the product graph |

Sources:

- Workspaces and their scope: [Go docs, workspaces](https://go.dev/ref/mod#workspaces).

### JavaScript workspace orchestration

[ADR-0110](0110-language-and-runtime.md) settles the runtime and package manager: Bun alone, for install and workspaces. This section decides whether a separate orchestrator sits above it.

| Option | 1 One entry point | 5 Bought with measured need | Verdict |
| --- | --- | --- | --- |
| **Bun workspaces alone** | **Yes. `just` runs every task** | **Yes. Nothing to add** | **Chosen** |
| Turborepo | No. A second task runner for JavaScript | No. Its caching pays off with several frontend apps, and there is one | Rejected on drivers 1 and 5 |
| Nx for JavaScript only | No | No | Rejected on drivers 1 and 5 |

Sources:

- [Bun docs, workspaces](https://bun.com/docs/install/workspaces), [Turborepo](https://turborepo.com/), [Nx](https://nx.dev/).

### The lint and format toolchain

There is one tool per language. Each is a single binary from the dev shell of [ADR-0100](0100-toolchain.md), with no ambient runtime, per principle 6 of [ADR-0000](0000-platform-foundations.md). [ADR-0104](0104-formatters-and-linters.md) decides the formatters of Markdown, Nix, and the data formats. This table adds the languages of the platform. Each is Tier 2, per [ADR-0002](0002-tool-adoption.md). A swap is a configuration file and a task, and the code it judges does not change.

| Surface | Option | 7 One binary, no runtime | Coverage | Verdict |
| --- | --- | --- | --- | --- |
| Go | **golangci-lint** | **Yes** | **Runs vet, staticcheck, revive, and about a hundred more as one pass** | **Chosen** |
| Go | `go vet`, staticcheck, or revive alone | Yes | One analyser each, and several to reconcile | Rejected on coverage |
| TypeScript and CSS | **Biome** | **Yes** | **Lint and format in one config** | **Chosen** |
| TypeScript and CSS | ESLint with Prettier | No. Node.js and a plugin tree | The widest rule set, and two configs | Rejected on driver 7 |
| TypeScript and CSS | oxlint with oxfmt | Yes | Lint mature, format younger | Rejected. It is the runner-up |
| Shell | **shellcheck and shfmt** | **Yes, two binaries** | **No single binary both lints and formats shell** | **Chosen** |
| SQL | **sqruff** | **Yes** | **The sqlfluff rules, in Rust** | **Chosen** |
| SQL | sqlfluff | No. Python | The reference rule set | Rejected on driver 7 |
| Prose, comments, and the ADR set | **tabrules** | **Yes** | **The profile of [ADR-0001](0001-documentation-conventions.md) and the requirement trace of [ADR-0602](0602-behaviour-requirements.md)** | **Chosen** |
| Prose, comments, and the ADR set | Vale with Conftest | Yes, two binaries | Two rule languages to write the same rules | Rejected. It matched the old Go linters only with two rule languages *(measured)* |

Sources:

- [golangci-lint linters](https://golangci-lint.run/docs/linters/), [Biome](https://biomejs.dev/), [oxc, oxlint and oxfmt](https://oxc.rs/), [ESLint](https://eslint.org/), [shellcheck](https://www.shellcheck.net/), [shfmt](https://github.com/mvdan/sh), [sqruff](https://github.com/quarylabs/sqruff), [sqlfluff](https://sqlfluff.com/), [Vale](https://vale.sh/). `tablint rules` in the dev shell lists the rules of tablint.

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
└── justfile                  # the recipes of the service

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
├── opentofu/                 # cluster + DNS + LB provisioning
├── helm/                     # Helm charts (ours + values for upstream)
├── gitops/                   # ArgoCD ApplicationSets + per-env values
├── talos/                    # node machine configs (ADR-0200)
├── auth/                     # Kratos, Hydra, OpenFGA config
├── gateway/                  # Traefik routing + rate limits
└── observability/            # dashboards and alerts as code

tools/                        # the module that pins the Go tools
scripts/                      # shell entered through just recipes

test/                         # external harnesses driving an assembled system
├── e2e/                      # Playwright suites and fixtures (ADR-0601)
└── perf/                     # k6 scenarios and seed data (ADR-0601)

docs/                         # genre decides the directory (ADR-0001)
├── adr/                      # the decisions
├── guide/                    # procedures
├── reference/                # lookups, registries, live state
└── *.md                      # entry documents, and registries an ADR names as canonical

.github/workflows/            # CI definitions, or .forgejo/workflows/ in a project that chose the forgejo mode
```

| Choice | Reason |
| --- | --- |
| `services/` and `apps/` are siblings | Services are headless, horizontally-scaled, internally-addressed backends. `apps/` holds first-party deployable applications. The slot stays open for partner portals, CLIs, or mobile apps with no layout migration. A new entry under `apps/` requires its own ADR |
| `services/` stays spelled out | `svc` already means a Kubernetes Service here. It is also the per-service metavariable in docs. A directory name is short only when the short form is not ambiguous |
| `infra/` holds both IaC and the configuration of what it deploys | One top-level directory removes the recurring question of `infra` or `ops` |
| `tools/` holds only the module that pins Go tools | It holds no program. The own module of `tools/` keeps `ogen`, `workflowcheck`, and the ruleguard DSL out of the graph that every service image builds from. Custom rules and generators come from tabrules, per [ADR-0104](0104-formatters-and-linters.md) |
| `scripts/` holds shell, and shell only | This is the other side of the row above, so the split is a language boundary, not a habit. When the work of a script is a program, it is not a script: the recipe calls the program directly. A wrapper that only changes directory and shells out puts one name in two trees |
| `test/` holds external harnesses, and is singular for that reason | Each suite drives an assembled, running system from outside it, so no suite belongs to one service, per [ADR-0601](0601-testing-strategy.md). It is not where the tests live. A Go test of an `internal/` package **cannot** move here. Only the subtree under the parent of `internal/` can import it, so the compiler rejects the import. Unit tests sit beside their code. This also lets `ci-affected` map a changed package to the tests that cover it |
| Each Node island has its own dev shell | `test/e2e/` runs in `nix develop .#e2e`, and `apps/admin/` runs in `nix develop .#admin`. `test/` has no `package.json`, no lockfile, and no tool pin of its own. `(CI: lint-node-scope)` |

### Recipe names

[ADR-0103](0103-tasks.md) makes `just` the task runner and fixes the six recipes of the contract. This section fixes the rest of the names. The root `justfile` holds the recipes of the repo, and `services/<name>/justfile` holds the recipes of one service. `just --list` lists them in each folder.

The convention of normalized entrypoints comes from GitHub's [Scripts to Rule Them All](https://github.blog/engineering/engineering-principles/scripts-to-rule-them-all/). There, the normalized names *are* the scripts. Here, they are `just` recipes, and `scripts/` is the shell that those recipes enter. `lint-service-contract` checks the recipe set of each service.

| Scope | Standard recipe names |
| --- | --- |
| Every service | `build`, `test`, `lint`, `generate`, `migrate`, `server`, `worker`. This is the closed set that every service exposes |
| Repo root | the six recipes of [ADR-0103](0103-tasks.md), and fleet-wide work grouped by its axis: `ci-*` for what CI calls, `cluster-*` for the local environment, `gen-*` for codegen, `lint-*` and `format-*` for the checks |

The two long-running service recipes are named for the process type they start. The names match `cmd/{server,worker}/`, the `<service>-{server,worker}` images, and the in-cluster DNS names. This gives one vocabulary from end to end.

A service recipe brings up the root recipes it needs with `just --justfile ../../justfile dep-postgres`. A root recipe that another root recipe needs is a dependency, so `just` runs it once.

**Recipe naming.** A recipe name is `group-member`. The group is the axis that you list and run together. Two shapes are correct. The axis worth aggregating by decides which one applies:

| Shape | Use when | Examples |
| --- | --- | --- |
| `activity-target` | one activity fans out across many targets, with an umbrella recipe | `lint-go`, `lint-ts`, `lint-md` under `lint`. `format-*`. `gen-openapi`, `gen-sqlc` under `gen` |
| `resource-operation` | a stateful thing has a lifecycle worth grouping | `cluster-up`, `cluster-stop`, `cluster-down`, `cluster-add`, `cluster-remove`, `db-migrate`, `ops-grant` |

**A recipe name spells its script.** The two shapes map onto `scripts/`. So a developer finds the implementation of a recipe without reading `justfile`:

- `activity-target` is `scripts/activity-target.sh`. Examples are `gen-openapi`, `lint-ports`, and `promote-prod`.
- `resource-operation` is `scripts/resource.sh operation`: one entrypoint that takes the verb as an argument. Examples are `cluster-up`, `argo-pause`, and `mock-start`.

When all members of a family share one implementation, the script is named for the family, not for a member. `dep-*` and `svc-*` enter `dep-apply.sh` and `svc-apply.sh`.

One shape for both cases scatters a family. `stop-cluster` and `delete-cluster` split the cluster lifecycle, and `ts-format` breaks the `format` umbrella. Use `activity-` only where a real umbrella exists. A recipe that exists only as a dependency is `[private]`.

**What a task acts on is an argument.** An environment variable carries the environment of the machine, such as a proxy address or a kubeconfig path. That is the same for every invocation from that shell. The thing that one invocation acts on is an operand, and it belongs in the argument list. `just cluster-down full` names its target on the line that ran it. `TIER=full just cluster-down` puts the target in shell state that outlives the command. The next destructive verb then aims at the wrong cluster. A script can export a variable to pass context to a subprocess it starts. That is internal plumbing, not the interface.

A recipe validates each operand against a closed set, and an unknown operand is fatal. A silent fallback to the default lets a typo delete a tier that the operator did not name.

### Every executable is pinned, in one of two places

| Kind | Pinned in |
| --- | --- |
| Developer and CI tools: Go, Bun, `sqlc`, `sqruff`, `vacuum`, `helm`, `kubectl`, `age`, and `sops` | the dev shell of `flake.nix` and `flake.lock`, per [ADR-0100](0100-toolchain.md) |
| Go tools that generate or check code: `ogen` and `workflowcheck` | a `tool` line in `tools/go.mod`, so the generator and its runtime library share one version |
| Runtime services: Postgres, Temporal, Kratos, Oathkeeper, OpenFGA, SeaweedFS, the observability stack, Argo CD, and the CNPG operator | the Helm chart `appVersion`, plus an explicit `image.tag` in `infra/helm/.../values.yaml` |

The `appVersion` of a chart names the release that it deploys. Renovate moves an image tag or a subchart, and nothing moves `appVersion`, so it goes stale with each update. The `app-version-from` annotation of each chart names the source of its version. A check compares the two, so a stale `appVersion` fails CI.

| Annotation | The version is |
| --- | --- |
| `dependency:<name>` | the `appVersion` of that subchart, in the archive of its locked version |
| `yaml:<file>:<expression>` | a `yq` expression on a file, with the path from the repo root |
| `arg:<file>:<name>` | the default of an `ARG` in a Dockerfile |
| `none` | absent, because the chart is our own and has no upstream release |

Floating tags are forbidden in Dockerfiles, Helm values, and workflows. A floating tag is `latest`, `stable`, `main`, or an unpinned major. A tool-version change is a normal PR. So anyone who clones at any SHA reproduces the exact toolchain that built it.

### One Go module for the product, one for the gates

One `go.mod` at the repo root covers every service, library, and generated client. There is no per-service module and no `replace` directive. Services and libraries are plain packages, imported by the module path of the repo.

`tools/` is the single exception: a second module, joined by a committed `go.work`. The pins of a generator or a gate, such as `ogen`, `workflowcheck`, and the ruleguard DSL, are not a dependency of anything that ships. In the product graph, they would put linter code in the module that every service resolves against. The tool tree needs exactly the isolation that the product does not need. A service image never sees the workspace. Its Dockerfile copies `go.mod`, `go.sum`, `libs/go`, and one service directory, so `go.work` is not in the build context.

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
| `check.yml` | the merge gate of [ADR-0101](0101-source-control-and-ci.md): `just ci`, which builds every check of `flake.nix` in the Nix sandbox. The checks build, test, lint, and regenerate the whole repo |
| `history.yml` | the checks that need the git history or the network: `just ci-lint`, `ci-affected-adversarial`, and `ci-scan` |
| `publish.yml` | builds and pushes images on merges to `master` |
| `e2e.yml` | the full suite nightly and before a release, plus a label-gated smoke job, per [ADR-0601](0601-testing-strategy.md) |

Lint, test, and build run over **the whole repo and both modules**. They are not affected-scoped. The linters have no per-service subset to take, and the Go build cache keeps the repeat cost small. `ci-affected` scopes what is built and promoted, not what is analysed.

Every workflow but the shared gate takes its toolchain from the `./.github/actions/setup` composite action, which installs Nix. Each step then runs `nix develop --command just <recipe>`. [ADR-0116](0116-forge-and-pipelines.md) decides which forge runs these workflows, and on whose runners. Its thin-YAML rule keeps that choice reversible.

### Affected detection

`tabrules affected` reads `git diff --name-only origin/master...HEAD` and maps changes to scopes:

| Change under | Affects |
| --- | --- |
| `services/<X>/` | service `<X>` |
| `libs/go/<L>/` | every Go consumer of `<L>`, through `go list -deps` |
| `libs/go/sdks/<S>/` | every Go consumer of the client of service `<S>` |
| `apps/frontend/` | the frontend |
| `infra/`, `tools/`, `go.mod`, `go.sum`, `package.json` | **global**: everything runs |

`just ci-affected` produces a JSON manifest that the workflows consume. As the fleet grows, this is the most load-bearing part of the tooling, and tabrules tests it.

### Codegen is committed and drift-checked

Principle 9 of [ADR-0000](0000-platform-foundations.md) states that generated code is committed and drift-checked. This ADR fixes where it lands and how the check runs:

- OpenAPI clients land in `libs/{go,ts}/sdks/<service>/`.
- sqlc output lands in `services/<service>/internal/store/`.

`just ci-gen` regenerates and formats everything, and fails on a diff. The `gen` check of `flake.nix` runs it in the sandbox, so `just ci` fails on drift.

### Caching

| Cache | Keyed on |
| --- | --- |
| Go modules in the Nix sandbox | the `outputHash` of `goProxy` in `flake.nix`, from `go.sum` |
| Go build and test, on a workstation | the root `go.sum` |
| Docker BuildKit layers | the registry |
| Bun install | [`bun.lock`](https://bun.com/blog/bun-lock-text-lockfile), and `bun.nix` in the sandbox |

**Deferred:** a remote Go build cache, such as `GOCACHEPROG` or `sccache`. **Trigger:** CI time stays above 15 minutes on the median affected pull request. **Seam:** it is a `GOCACHEPROG` environment variable, so adoption is configuration. **Cost if adopted late:** the CI minutes already spent, and nothing structural. The cache is cold on adoption at any time.

### Container images

Each service has one multi-stage `Dockerfile`. Stage 1 builds with the workspace `go build`. Stage 2 is the runtime base below. The frontend has one Dockerfile that uses standalone output. There is no shared base image.

| Runtime base | Escalation path in the image | CA bundle, users, and tzdata | Pinned by digest | Verdict |
| --- | --- | --- | --- | --- |
| **`gcr.io/distroless/static-debian13`** | **None. No shell and no package manager** | **Kept by upstream** | **Yes, by digest** | **Chosen** |
| `scratch` | None | Copied by hand, and refreshed by hand when roots rotate | Yes | Rejected. It moves the CA refresh to this repo |
| Alpine | A shell and a package manager | Yes | Yes | Rejected on the escalation path |
| Chainguard or Wolfi | None | Yes | No. Its free tags track `latest` | Rejected. The floating-tag rule forbids it |

Sources:

- [distroless images](https://github.com/GoogleContainerTools/distroless), [Chainguard images, free tier](https://www.chainguard.dev/chainguard-images).

**This base is not related to the host operating system.** It gives no kernel and no init. It is a few megabytes of files that come from a Debian release. A change to what the nodes run changes nothing here, per [ADR-0200](0200-cluster-topology.md).

**Server and worker are separate images from the same Dockerfile.** A `CMD` build arg selects which `cmd/` binary the build stage compiles. The result is `<service>-server:<sha>` and `<service>-worker:<sha>`. They scale independently and have different resource profiles. Neither should carry the code surface of the other. One Dockerfile keeps the build stage and base layers shared and cache-friendly.

Images are tagged `<service>:<git-sha>`, and the same SHA goes through every environment, per [ADR-0201](0201-gitops.md).

### Upgrade path

Each step is its own ADR when its trigger fires.

| Step | Trigger | Seam | Cost if adopted late |
| --- | --- | --- | --- |
| Split the Go module | a service or library needs its own dependency line: external publication, a different upgrade cadence, or isolated security review | present. Packages already sit at import paths that become module paths with no change | grows with the number of cross-package imports that must become versioned dependencies. The later it happens, the more of the repository it touches |
| Adopt Nx or moon as a task orchestrator with caching and a project graph | the recipe graph outgrows `just`, or hand-written affected detection is no longer trustworthy | present. Recipes are declarative and already named `group-member`. Both tools wrap them and do not replace them | low. It is proportional to package count and does not compound. Each wrap is mechanical, and nothing builds up that makes the next one harder |
| Adopt Pants, Bazel, or Nix | hermetic reproducible builds become a compliance requirement. The ADR written at that time picks one of the three | **none. This is a bet**, per [ADR-0000](0000-platform-foundations.md). Each tool replaces the build and does not wrap it. So every Dockerfile, task, and codegen step is rewritten | **grows with the fleet.** Every build target, Dockerfile, and codegen step must be described to the new system. So the migration is proportional to a repository that is expected to grow. The trigger is a compliance requirement, and those come with dates. The risk of waiting is a fleet-sized migration to the deadline of someone else. The delay buys this: the platform never pays for a build system that the trigger may never demand |

## Consequences

### Positive

- `just <recipe>` is the universal interface across languages and services.
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
- The product is a single Go module rooted at `go.mod`, with no per-service or per-library `go.mod`. `tools/` is the one exception: a second module joined by `go.work`. The dependencies of a gate are not a dependency of anything that ships. `(CI: ci-lint)`
- A service image build copies only `go.mod`, `go.sum`, `libs/go`, and its own service directory, so `go.work` never enters the build context.
- Every backend service lives at `services/<name>/`. Every shared Go package lives under `libs/go/<name>/`. Every shared TypeScript library lives under `libs/ts/<name>/`. `(CI: lint-service-contract)`
- Generated API clients live at `libs/{go,ts}/sdks/<service>/` and are committed. `(CI: ci-gen)`
- The frontend is one application at `apps/frontend/`. A new frontend or a new entry under `apps/` requires an ADR.
- A task is a `just` recipe, per [ADR-0103](0103-tasks.md). Every service exposes `build`, `test`, `lint`, `generate`, `migrate`, `server`, and `worker`. `(CI: lint-service-contract)`
- A recipe name is `group-member`, grouped by the axis worth listing together, and it spells its script. `activity-target` is `scripts/activity-target.sh`, and `resource-operation` is `scripts/resource.sh operation`.
- What a recipe acts on is an argument, never an environment variable: `just cluster-down full`. Environment variables carry the environment of the machine. A variable that a script exports for its own subprocesses is not an interface. `(ref: clig.dev, POSIX Utility Conventions)`
- A recipe validates its operand against a closed set and fails on an unknown operand. It never falls back to a default.
- Every external tool is pinned. Developer and CI tools are pinned in `flake.lock`, Go code tools in `tools/go.mod`, and runtime services as an explicit `image.tag` in Helm values. Floating tags are not used anywhere. `(CI: lint-floating-tags)`
- The `appVersion` of each chart equals the version at the source that its `app-version-from` annotation names. A chart with no upstream release sets the annotation to `none`. `(CI: lint-app-versions)`
- A PR that changes a spec, a SQL query, or any codegen input includes the regenerated artifacts. `(CI: ci-gen)`
- A change to `go.mod`, `go.sum`, root `package.json`, `infra/`, or `tools/` triggers a full-repo CI run. `(CI: ci-affected)`
- Container images are tagged `<service>:<git-sha>`, and the same SHA goes through every environment. `(CI: lint-floating-tags)`
- `services/<X>/` does not import `services/<Y>/`. Sharing goes through `libs/` or generated clients. `(CI: lint-go, lint-service-contract)`
- Route groups inside `apps/frontend/` do not import from each other. `(CI: lint-ts)`
- `tools/` holds only the module that pins Go tools. `scripts/` holds shell. A recipe calls a program directly. A shell script that only shells out to one is not written.
- `test/` holds the external harnesses that drive an assembled system: `test/e2e/` and `test/perf/`. A test of the code in one package lives beside that package.
- Each Node island runs in its own dev shell of `flake.nix`. `test/` itself has no package manifest or lockfile. `(CI: lint-node-scope)`
- Build-graph tools are not used on day one. These are Nx, moon, Pants, and Bazel. Adoption requires its own ADR.
