# The Build Path

[`detection-latency.md`](detection-latency.md) composes the run-time path: per failure class, how long a fault runs before anyone notices. This document composes the other one. **Per class of defect, what stops it between a keystroke and production, and what reaches production unchecked.**

Every gate below is decided in an ADR, and each ADR is complete about its own gate. What no ADR can state is the total, because the total is a property of the sequence rather than of any layer in it.

**A defect class with no row here is one nobody has classified**, which is the same failure the run-time table's unbounded rows name.

## The four positions that set these numbers

| Position | Effect on the merge path | Owning decision |
| --- | --- | --- |
| CI lints fail open by construction | an unrun check is a passed check, so every repository-property gate is advisory against a path that skips CI | [ADR-0203](../adr/0203-policy-enforcement.md) |
| Affected-detection selects what CI runs | a selection bug produces a green run against something it did not select | [ADR-0101](../adr/0101-monorepo.md), register row 8 |
| Per-PR e2e is label-gated; the full suite is nightly | a cross-service defect passes the merge gate and is caught by a scheduled run | [ADR-0601](../adr/0601-testing-strategy.md), register row 6 |
| Admission is the only layer a manual apply cannot route around | anything checked solely in CI is unenforced against the incident path | [ADR-0203](../adr/0203-policy-enforcement.md) |

## The path

A change passes through six positions. The first four are advisory in the strict sense — they constrain a cooperating author — and the last two constrain the cluster.

| # | Position | Constrains | Bypassed by |
| --- | --- | --- | --- |
| 1 | Local hooks | the author, before the push | not pushing through them |
| 2 | CI lints and codegen drift | the pull request | a CI outage, a skipped run, affected-detection not selecting the change |
| 3 | Tests — unit, integration, e2e | the pull request | the same, plus e2e being label-gated |
| 4 | Review | the pull request | approval |
| 5 | Argo CD reconciliation | what the cluster converges to | a manual `kubectl apply` |
| 6 | Admission — PSA and Kyverno | what the cluster runs | nothing available to a deploying party |

**Positions 1 to 4 share one bypass**, and it is not malice: a CI outage, a misconfigured path filter, or a change affected-detection did not select produces the same result as skipping them deliberately. That is why [ADR-0203](../adr/0203-policy-enforcement.md) assigns runtime properties to positions 5 and 6 rather than to 2.

## Per class of defect

**Caught by** names the earliest position that rejects the defect. **Reaches production if** names what has to be true for it to get past every position.

| Defect class | Caught by | Reaches production if | Residual |
| --- | --- | --- | --- |
| Layout, naming, prose, generated-code drift | 2 — CI lints ([ADR-0101](../adr/0101-monorepo.md), [ADR-0001](../adr/0001-documentation-and-output-conventions.md)) | CI does not run, or affected-detection does not select the change | **bounded.** The subject is a file. A repository property that reaches production is a cosmetic defect, which is why this class is assigned to a layer that fails open |
| Contract shape — spec validity, audience, breaking change | 2 — vacuum and oasdiff ([ADR-0303](../adr/0303-api-contracts-and-lifecycle.md)) | as above | **bounded.** The generated client is committed and drift-checked, so a spec change that skipped the gate still has to pass the drift check to merge |
| A single service's logic | 3 — unit and integration tests | the service was not selected by affected-detection | **register row 8.** This is the class that row is about, and its reach is one merge plus everything downstream |
| A cross-service regression | 3 — e2e, **label-gated per PR**, nightly in full | the pull request carried no e2e label | **register row 6, up to a day.** The largest routine hole in this table, and the one bought down by a policy change rather than a component |
| An operator dashboard broken | 3 — the nightly suite only | always, until the nightly run | **up to a day**, and it is a day of exposure on the surface used *during* an incident |
| A known-vulnerable dependency or base image | 2 — Trivy at the merge gate ([ADR-0104](../adr/0104-supply-chain-security.md)) | the CVE is published after the merge | **the pull side is unbounded.** Trivy is push-shaped: it sees what is being built, not what is already running. Nothing on the floor notices that a CVE published today affects an image built in March, which is what [`../operational-surface.md`](../operational-surface.md)'s Dependency-Track row would answer |
| An unsigned or floating-tag image | **6 — Kyverno at admission** ([ADR-0104](../adr/0104-supply-chain-security.md)) | it does not. Admission is not bypassable by a deploying party | **none, by construction.** This class is why position 6 exists |
| A privileged or non-conforming workload | **6 — Pod Security Admission** ([ADR-0200](../adr/0200-cluster-topology.md)) | it does not | **none.** In-tree, so it fails with the API server rather than separately |
| An unreachable or over-reachable workload | **6 — CiliumNetworkPolicy** in the datapath ([ADR-0206](../adr/0206-cluster-networking.md)) | it does not, for traffic. A missing policy is a different defect | **none for enforcement; the gap is a policy nobody wrote**, which position 4 is the only check on |
| A resource-governance defect — no request, wrong priority | **6 — in-tree API objects** ([ADR-0204](../adr/0204-resource-management.md)) | it does not | **none.** `LimitRange` defaults it or `ResourceQuota` rejects it |
| A plaintext secret in a committed file | 1 and 2 — gitleaks over the tree at commit and in CI, and over the whole history in CI (`lint:secrets`, `lint:secrets-history`, [ADR-0202](../adr/0202-secrets.md)) | its shape is one the rules do not recognise | **bounded by the rule set, and the sharpest row here.** Unlike the classes above, the defect is permanent once merged: git history holds it after the file is fixed |
| An authorization defect — a check omitted, or a dual write outside a workflow | 2 — `lint:authz-dual-write` and `lint:authz` for the static shapes; 3 — the authorization and privilege-escalation specs; 4 — review for an omitted `Checker` call ([ADR-0304](../adr/0304-identity-and-authorization.md), [ADR-0302](../adr/0302-temporal.md)) | a handler omits a check no spec exercises | **bounded for the static shapes, unbounded for an omitted check.** A missing call leaves nothing for a linter to read |
| Cluster state diverging from the repository | 5 — Argo CD, with `selfHeal=false` in production ([ADR-0201](../adr/0201-gitops.md)) | a human applies it and nobody reads the drift notification | **hours to next working day.** Detection, not enforcement — production reverts nothing on its own, deliberately |

## The machinery

Every task a workflow or a git hook reaches, and the failure class it owns (ADR-0000 principle 2). Generated from the
tasks' descriptions by `mise run gen`; a task that owns no class, or one another row already owns, is a deletion.

<!-- machinery:begin -->

| Task | Owns | Reached from |
| --- | --- | --- |
| `acceptance` | Generate a project from the working tree and prove it reaches a serving cluster (ADR-0106). Needs Docker; runs nightly and on the acceptance label, never in check. | template.yml |
| `build` | Every Go module compiles, the tools included (ADR-0101). | ci.yml |
| `ci:affected-adversarial` | Test affected-detection from the other side (ADR-0101, ADR-0601): break each service in a scratch worktree and assert the manifest names it. | ci.yml |
| `ci:affected-matrix` | The affected manifest split into the two arrays publish.yml's matrices need, as forge step-output assignments (ADR-0102). | publish.yml |
| `ci:build-context` | An app's Docker build context, as a forge step-output assignment (ADR-0102). | publish.yml |
| `ci:e2e-gate` | Whether a pull request pays for the smoke suite, as a forge step-output assignment (ADR-0102, ADR-0601). | e2e.yml |
| `ci:gen` | The single definition behind ci.yml's drift job and the lefthook gen-drift hook: run it locally to reproduce that CI job exactly. | .lefthook.yml, ci.yml |
| `ci:nightly-gate` | Whether tonight's cluster:up full suite should run, as a forge step-output assignment (ADR-0102, ADR-0601). | _nightly-gate.yml |
| `ci:preview` | The pull-request preview environment (ADR-0205): the full tier at one pull request's images and manifests, destroyed with the run that made it. | preview.yml |
| `ci:prune-registry` | Delete the first-party image tags no environment pins and the last PRUNE_KEEP commits do not name (ADR-0105). | publish.yml |
| `ci:push-promotion` | Commit a promotion's values changes and push them to the default branch (ADR-0201). | publish.yml |
| `ci:release-info` | A CalVer release tag resolved to version + commit, as forge step-output assignments (ADR-0102, ADR-0103). | promote-on-release.yml |
| `ci:release-pr` | Open the prod pin as a pull request the forge merges once its checks pass (ADR-0201). | promote-on-release.yml |
| `ci:release-publish` | Publish the forge release for $VER (ADR-0103). | promote-on-release.yml |
| `ci:scan` | The vulnerability merge gate (ADR-0104). | ci.yml |
| `ci:sign` | Sign a published image and attach its SBOM and provenance (ADR-0104). | publish.yml |
| `cluster:add` | One verb for "put this in the cluster" (ADR-0600). | lighthouse.yml |
| `cluster:down` | Delete the tier's cluster and its image cache. | e2e.yml, lighthouse.yml, perf.yml |
| `cluster:up` | Create, resume or repair a tier. | e2e.yml, lighthouse.yml, perf.yml |
| `e2e` | The full browser suite against a running full tier: acceptance, visual and accessibility (ADR-0601). | e2e.yml |
| `e2e:install` | The e2e island's Node dependencies and its browser (ADR-0601). | e2e.yml, lighthouse.yml, preview.yml |
| `e2e:smoke` | The @smoke subset of the browser suite, for a labelled pull request (ADR-0601). | e2e.yml, preview.yml |
| `format:go` | Go formatting, golangci-lint's formatters in place (ADR-0100). | .lefthook.yml |
| `format:md` | rumdl is the only Markdown formatter — never the IDE's. | .lefthook.yml |
| `format:shell` | shfmt (mvdan/sh) is the shell formatter, over the same file set lint:shell reads (scripts/lib/sh-files.sh). | .lefthook.yml |
| `format:ts` | TypeScript, JSON and CSS formatting, biome in place (ADR-0100). | .lefthook.yml |
| `gen:admin` | Scaffold the Lowdefy admin pages from the OpenAPI specs (ADR-0401). | .lefthook.yml |
| `gen:adr-rules` | Two documents are views over the ADR set's Rules sections: the rules index and the security baseline (ADR-0203). | .lefthook.yml |
| `gen:build-path` | The machinery table in docs/reference/build-path.md, from the tasks a workflow or hook reaches (ADR-0000). | .lefthook.yml |
| `gen:data-classes` | The data-class and retention registry (ADR-0301) — the checklist a new service is reviewed against. | .lefthook.yml |
| `gen:image-allowlist` | The third-party image allow-list (ADR-0104), derived from the charts themselves: every repository the platform's own charts pull from. | .lefthook.yml |
| `gen:openapi` | The Go and TypeScript clients and servers generated from each service's OpenAPI spec (ADR-0303). | .lefthook.yml |
| `gen:openapi-public` | Filtered OpenAPI projections for the Scalar developer portals (ADR-0303/0009/0014). | .lefthook.yml |
| `gen:shared-components` | Writes the canonical error envelope, money, and timestamp components into every spec from tools/codegen/shared-components.yaml (ADR-0303). | .lefthook.yml |
| `gen:sqlc` | The typed Go database access generated from each service's queries (ADR-0300). | .lefthook.yml |
| `gen:zod` | The runtime validation schemas generated from the OpenAPI specs for the TypeScript apps (ADR-0303). | .lefthook.yml |
| `lighthouse` | Web vitals and the per-route bundle budgets, as merge gates (ADR-0400): LCP < 2.5s, CLS < 0.1, and Total Blocking Time < 200ms on the mobile profile. | lighthouse.yml |
| `lint:activity-register` | Temporal registration gate (ADR-0302): every activity a workflow names as a string is registered on its service's worker. | .lefthook.yml, ci.yml |
| `lint:adr-xref` | The ADR set's internal wiring: references resolve, Related names documents that exist, every ADR carries a Decides line and an index row, the two adoption documents name the same components. | .lefthook.yml, ci.yml |
| `lint:alert-severity` | The alert-severity gate (ADR-0502). | .lefthook.yml, ci.yml |
| `lint:api-audience` | Audience↔exposure gate (ADR-0303): a spec's info.x-audience must match whether the service is edge-exposed (public ⇔ has an /api route). | .lefthook.yml, ci.yml |
| `lint:api-breaking` | oasdiff labels breaking contract changes for review; it is NOT a version gate (ADR-0303). | ci.yml |
| `lint:auth-inline` | Auth single-source guard (ADR-0305/0010/0029): fails if kratos/oathkeeper config is re-inlined into the Ory chart values instead of living in infra/auth/*, or if the frontend grows developme. | .lefthook.yml, ci.yml |
| `lint:authz` | Edge-auth policy gates (ADR-0304/0305/0306): - OpenFGA model + assertions (fga model test) + model.json in-sync check - ops dashboards authorize via remote_json → Checker, never `allow` - th. | .lefthook.yml, ci.yml |
| `lint:authz-dual-write` | ADR-0304's dual-write rule, statically: a tuple is written from an activity, never from a handler. | .lefthook.yml, ci.yml |
| `lint:comments` | The half of ADR-0001's comment table a machine can read, over the Go and TypeScript this repository owns. | .lefthook.yml, ci.yml |
| `lint:commits` | Conventional Commits over the pull request's commit RANGE (ADR-0103). | ci.yml |
| `lint:contrast` | Colour contrast against the design-token file rather than per component (ADR-0400): a token change moves every surface at once, so the token file is where a regression is introduced. | .lefthook.yml, ci.yml |
| `lint:data-classes` | Drift check for it. | .lefthook.yml, ci.yml |
| `lint:determinism` | Temporal workflow determinism (ADR-0302). | .lefthook.yml, ci.yml |
| `lint:floating-tags` | Image references pin a digest or an explicit version, never a moving tag (ADR-0101, ADR-0104). | .lefthook.yml, ci.yml |
| `lint:gitops-env-scope` | ADR-0201 gate: an environment's bootstrap directory names that environment alone. | .lefthook.yml, ci.yml |
| `lint:go` | Go correctness and style: golangci-lint's configured analysers over every module (ADR-0100). | .lefthook.yml, ci.yml |
| `lint:gostyle` | Custom layout-based Go style analyzers. | .lefthook.yml, ci.yml |
| `lint:helm-deps` | `helm dependency build` needs the repo registered in the caller's helm config; `update` resolves it from Chart.yaml. | .lefthook.yml, ci.yml |
| `lint:i18n` | Localisation, enforced rather than intended (ADR-0400). | .lefthook.yml, ci.yml |
| `lint:image-allowlist` | Drift check for it. | .lefthook.yml, ci.yml |
| `lint:log-vocab` | Human-output vocabulary gate (ADR-0001): scripts use →/✓/✗/⚠ via scripts/lib/log.sh, not bare WARN/ERROR/FAIL prose. | .lefthook.yml, ci.yml |
| `lint:md` | Markdown structure and formatting, rumdl over every document (ADR-0001). | .lefthook.yml, ci.yml |
| `lint:money` | The monetary-value gate (ADR-0100, ADR-0300): a money-ish OpenAPI property is the shared `Money` component, no Go field or variable with a money-ish name is a float, and no TypeScript money. | .lefthook.yml, ci.yml |
| `lint:naming` | The resource-name grammar (ADR-0003): `{project}-{env}-{role}[-{n}]` across the Talos inventory, the sops recipients, and the GitOps overlays, with the role vocabulary read from the ADR's ow. | .lefthook.yml, ci.yml |
| `lint:node-scope` | Node confinement guard (ADR-0100/ADR-0601): Node/npm may appear ONLY in the repo-root test/e2e/ workspace. | .lefthook.yml, ci.yml |
| `lint:openapi` | OpenAPI contracts: every spec against the platform ruleset, and resource-prefix ownership across the set (ADR-0303). | .lefthook.yml, ci.yml |
| `lint:parity` | ADR-0205 gate: every key a deployed environment's values carry exists in the local overlay, or is allowlisted with its sanctioned reason. | .lefthook.yml, ci.yml |
| `lint:ports` | Local port registry gate (ADR-0205): ports unique, every service registered, and each service's .mise.toml binding what the registry assigns it. | .lefthook.yml, ci.yml |
| `lint:project-identity` | ADR-0106 gate: a project created from this template must own its own name before it pushes. | .lefthook.yml, ci.yml |
| `lint:prose` | ADR-0001's banned-constructs table, enforced. | .lefthook.yml, ci.yml |
| `lint:readme-drift` | Principle 9 applied to the one document that is not generated. | .lefthook.yml, ci.yml |
| `lint:resource-governance` | ADR-0204 gate: renders every chart (each service separately) and checks the declared resources against the guardrails in infra/helm/platform/resource-governance BEFORE they reach a cluster. | .lefthook.yml, ci.yml |
| `lint:rules-index` | Drift check for the generated rule documents. | .lefthook.yml, ci.yml |
| `lint:secrets` | ADR-0202: plaintext secret values do not appear in any committed file. | .lefthook.yml, ci.yml |
| `lint:secrets-history` | The history scope of lint:secrets. | ci.yml |
| `lint:service-contract` | ADR-0205 gate: every service provides the same artifacts, because the platform DISCOVERS services through those artifacts. | .lefthook.yml, ci.yml |
| `lint:service-databases` | ADR-0300: a service that ships migrations has a database to run them against. | .lefthook.yml, ci.yml |
| `lint:service-deps` | The inner loop's dependency graph, checked against the code (ADR-0600, ADR-0205). | .lefthook.yml, ci.yml |
| `lint:shell` | shellcheck over every tracked *.sh (ADR-0101). | .lefthook.yml, ci.yml |
| `lint:sql` | SQL: sqruff over every migration and sqlc query, and a column holding personal data carries its pii class (ADR-0300, ADR-0301). | .lefthook.yml, ci.yml |
| `lint:template-build` | `go build ./...` cannot see services/_template: every hand-written file there carries a //go:build _template constraint, which scripts/new-service.sh strips when it copies the tree. | .lefthook.yml, ci.yml |
| `lint:thin-workflows` | ADR-0102: workflow YAML checks out, sets up the toolchain, and calls a mise task. | .lefthook.yml, ci.yml |
| `lint:tool-register` | ADR-0002's four register Rules: every Tier 1/2 row names an owning ADR that exists, that ADR carries the comparison its tier owes, a Tier 1 row names a runner-up, and every alternative a row. | .lefthook.yml, ci.yml |
| `lint:ts` | TypeScript, JSON and CSS: biome lint and format, warnings as errors (ADR-0100). | .lefthook.yml, ci.yml |
| `lint:workspace-copies` | A TS workspace member missing from the frontend image build fails `bun install` with "Workspace not found" — and only when the image is BUILT, which on the full tier is minutes into a cluste. | .lefthook.yml, ci.yml |
| `mock:start` | The API mock for UI work (ADR-0600): Prism serving the committed `internal.json` projection, behind the real edge and its real middleware chain. | lighthouse.yml |
| `perf` | The steady baseline: nightly + pre-release. | perf.yml |
| `perf:seed` | Bulk catalog data so the read path is measured against a realistic table. | perf.yml |
| `perf:smoke` | ~30s. | perf.yml |
| `promote:dev-staging` | Pin dev + staging values for the components in $SERVICES and $APPS to $SHA by digest. | publish.yml |
| `promote:prod` | Pin every prod values file to $SHA by digest and label the images $VER. | promote-on-release.yml |
| `promote:verify` | Gate a release on prod converging on $SHA. | promote-on-release.yml |
| `release` | Cut a repo-wide CalVer release: compute the version, stamp the fields a build tool requires, regenerate CHANGELOG.md, commit, tag, and push (ADR-0103). | promote-on-release.yml |
| `secrets:age` | Idempotent; also writes .sops.yaml (ADR-0202). | e2e.yml, perf.yml, preview.yml |
| `setup` | The git hooks, installed from .lefthook.yml. | .lefthook.yml |
| `setup:node` | The workspace's node_modules. | .lefthook.yml, ci.yml |
| `supply-chain:inventory` | Verify the SBOM attestation of every image pinned in committed values and file what is in it (ADR-0104). | supply-chain.yml |
| `test:go` | Every Go package's tests, the tools included (ADR-0601). | ci.yml |
| `test:template` | The repository's own generation (ADR-0106): a fixture matrix through `copier copy`, the refusals its validators owe, and the equality between the two adoption paths that `copier update`'s merge relies on. | template.yml |
| `test:ts` | The shared TypeScript libraries under libs/ts/ — not the frontend, whose browser behaviour is covered by the e2e suite (ADR-0601). | ci.yml |

<!-- machinery:end -->

## Reading the table

**Two residuals are unbounded, and they are not the same kind of thing.**

- An **omitted authorization check** is unbounded because review is the only position holding it: an absence gives a linter nothing to read, and a spec catches it only on the paths it walks.
- The **CVE pull side** is unbounded because the gate is push-shaped by design. No amount of CI closes it; it is closed by a component, and the component is priced out of Core by the operational budget ([`../operational-surface.md`](../operational-surface.md)).

**The plaintext-secret row is the one to read first.** It is the only class here where the defect survives the fix: reverting the file does not remove it from history, so the remediation is a credential rotation rather than a revert. Every other row on this table is repaired by shipping a correction.

**The path is sound where it is unbypassable and advisory where it is not, and the assignment is deliberate.** Reading the *Caught by* column, every class assigned to position 6 has no residual, and every class with an unbounded residual is assigned to position 4. That is [ADR-0203](../adr/0203-policy-enforcement.md)'s rule producing exactly what it promises — and the cost of the rule stated in one place: **enforcement strength on this platform tracks whether a machine can see the property, not how much the defect costs.** An omitted authorization check is more expensive than a floating tag and is checked by a person, because one is an absence and the other is a field.

**Two rows are a scheduling choice, not a capability gap.** The cross-service regression and the broken operator dashboard both have a suite that catches them; the suite runs nightly rather than on the pull request. Affected-detection already knows which pull requests touch more than one service, so moving the first is a policy change in the workflow.

**Compare the two composites.** The run-time path's dominant term is human attention ([`detection-latency.md`](detection-latency.md)); the build path's is whether a property is machine-visible. They fail differently, and a project reducing the floor should read both: [`../adoption-path.md`](../adoption-path.md)'s managed swaps change the first and leave the second untouched.
