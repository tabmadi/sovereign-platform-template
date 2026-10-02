# The Build Path

[`detection-latency.md`](detection-latency.md) puts together the run-time path. For each failure class, it states how long a fault runs before anyone notices. This document puts together the other path. **For each class of defect, it states what stops the defect between a keystroke and production, and what reaches production unchecked.**

An ADR decides each gate below, and each ADR is complete about its own gate. No ADR can state the total, because the total belongs to the sequence and not to any layer in it.

**A defect class with no row here is a class that nobody has classified.** This is the same failure that the unbounded rows of the run-time table name.

## The four positions that set these numbers

| Position | Effect on the merge path | Owning decision |
| --- | --- | --- |
| CI lints fail open by construction | a check that does not run counts as a passed check. So every gate on a repository property is advisory against a path that skips CI | [ADR-0203](../adr/0203-policy-enforcement.md) |
| Affected-detection selects what CI runs | a selection bug gives a green run that does not select the broken change | [ADR-0101](../adr/0101-monorepo.md), register row 8 |
| Per-PR e2e runs only with a label, and the full suite runs nightly | a cross-service defect passes the merge gate, and a scheduled run catches it | [ADR-0601](../adr/0601-testing-strategy.md), register row 6 |
| Admission is the only layer that a manual apply cannot go around | anything that only CI checks is unenforced against the incident path | [ADR-0203](../adr/0203-policy-enforcement.md) |

## The path

A change passes through six positions. The first four are advisory in the strict sense: they constrain an author who cooperates. The last two constrain the cluster.

| # | Position | Constrains | Bypassed by |
| --- | --- | --- | --- |
| 1 | Local hooks | the author, before the push | a push that does not go through them |
| 2 | CI lints and codegen drift | the pull request | a CI outage, a skipped run, or affected-detection that does not select the change |
| 3 | Tests: unit, integration, e2e | the pull request | the same, plus e2e that runs only with a label |
| 4 | Review | the pull request | approval |
| 5 | Argo CD reconciliation | what the cluster converges to | a manual `kubectl apply` |
| 6 | Admission: PSA and Kyverno | what the cluster runs | nothing that a deploying party can use |

**Positions 1 to 4 share one bypass, and it is not malice.** A CI outage, a misconfigured path filter, or a change that affected-detection did not select has the same result as a skip on purpose. So [ADR-0203](../adr/0203-policy-enforcement.md) assigns runtime properties to positions 5 and 6, not to position 2.

## Per class of defect

**Caught by** names the earliest position that rejects the defect. **Reaches production if** names what must be true for the defect to get past every position.

| Defect class | Caught by | Reaches production if | Residual |
| --- | --- | --- | --- |
| Layout, naming, prose, generated-code drift | 2: CI lints, per [ADR-0101](../adr/0101-monorepo.md) and [ADR-0001](../adr/0001-documentation-and-output-conventions.md) | CI does not run, or affected-detection does not select the change | **bounded.** The subject is a file. A repository property that reaches production is a cosmetic defect. So this class goes to a layer that fails open |
| Contract shape: spec validity, audience, breaking change | 2: vacuum and oasdiff, per [ADR-0303](../adr/0303-api-contracts-and-lifecycle.md) | as above | **bounded.** The generated client is committed and drift-checked. So a spec change that skipped the gate must still pass the drift check to merge |
| A single service's logic | 3: unit and integration tests | affected-detection did not select the service | **register row 8.** That row is about this class. Its reach is one merge plus everything downstream |
| A cross-service regression | 3: e2e, **per PR only with a label**, nightly in full | the pull request had no e2e label | **register row 6, up to a day.** This is the largest routine hole in this table. A policy change closes it, not a component |
| An operator dashboard broken | 3: the nightly suite only | always, until the nightly run | **up to a day.** It is a day of exposure on the surface that operators use *during* an incident |
| A known-vulnerable dependency or base image | 2: Trivy at the merge gate, per [ADR-0104](../adr/0104-supply-chain-security.md) | the CVE is published after the merge | **the pull side is unbounded.** Trivy is push-shaped: it sees what is being built, not what already runs. Nothing on the floor notices that a CVE published today affects an image built in March. The Dependency-Track row in [`../operational-surface.md`](../operational-surface.md) would answer this |
| An unsigned or floating-tag image | **6: Kyverno at admission**, per [ADR-0104](../adr/0104-supply-chain-security.md) | it does not. A deploying party cannot bypass admission | **none, by construction.** Position 6 exists because of this class |
| A privileged or non-conforming workload | **6: Pod Security Admission**, per [ADR-0200](../adr/0200-cluster-topology.md) | it does not | **none.** It is in-tree, so it fails with the API server and not separately |
| An unreachable or over-reachable workload | **6: CiliumNetworkPolicy** in the datapath, per [ADR-0206](../adr/0206-cluster-networking.md) | it does not, for traffic. A missing policy is a different defect | **none for enforcement. The gap is a policy that nobody wrote.** Position 4 is the only check on it |
| A resource-governance defect: no request, wrong priority | **6: in-tree API objects**, per [ADR-0204](../adr/0204-resource-management.md) | it does not | **none.** `LimitRange` defaults it, or `ResourceQuota` rejects it |
| A plaintext secret in a committed file | 1 and 2: gitleaks over the tree at commit and in CI, and over the whole history in CI. The tasks are `lint:secrets` and `lint:secrets-history`, per [ADR-0202](../adr/0202-secrets.md) | the rules do not recognise its shape | **bounded by the rule set, and the sharpest row here.** Unlike the classes above, the defect is permanent after a merge: git history holds it after the file is fixed |
| An authorization defect: an omitted check, or a dual write outside a workflow | 2: `lint:authz-dual-write` and `lint:authz` for the static shapes. 3: the authorization and privilege-escalation specs. 4: review for an omitted `Checker` call. Per [ADR-0304](../adr/0304-identity-and-authorization.md) and [ADR-0302](../adr/0302-temporal.md) | a handler omits a check that no spec exercises | **bounded for the static shapes, unbounded for an omitted check.** A missing call leaves nothing for a linter to read |
| Cluster state diverging from the repository | 5: Argo CD, with `selfHeal=false` in production, per [ADR-0201](../adr/0201-gitops.md) | a human applies it, and nobody reads the drift notification | **hours to the next working day.** This is detection, not enforcement. On purpose, production reverts nothing on its own |

## The machinery

This table lists every task that a workflow or a git hook reaches, and the failure class that the task owns, per ADR-0000 principle 2. `mise run gen` generates it from the task descriptions. Delete a task that owns no class, or a task whose class another row already owns.

<!-- machinery:begin -->

| Task | Owns | Reached from |
| --- | --- | --- |
| `acceptance` | Generate a project from the working tree and prove that it reaches a serving cluster, per ADR-0106. It needs Docker. It runs nightly and on the acceptance label, never in check. | template.yml |
| `build` | Every Go module compiles, including the tools, per ADR-0101. | ci.yml |
| `ci:affected-adversarial` | Test affected-detection from the other side, per ADR-0101 and ADR-0601. Break each service in a scratch worktree and check that the manifest names it. | ci.yml |
| `ci:affected-matrix` | The affected manifest, split into the two arrays that publish.yml's matrices need, as forge step-output assignments, per ADR-0102. | publish.yml |
| `ci:build-context` | An app's Docker build context, as a forge step-output assignment, per ADR-0102. | publish.yml |
| `ci:e2e-gate` | Whether a pull request runs the smoke suite, as a forge step-output assignment, per ADR-0102 and ADR-0601. | e2e.yml |
| `ci:gen` | The one definition behind ci.yml's drift job and the lefthook gen-drift hook. Run it locally to repeat that CI job exactly. | .lefthook.yml, ci.yml |
| `ci:nightly-gate` | Whether tonight's cluster:up full suite runs, as a forge step-output assignment, per ADR-0102 and ADR-0601. | _nightly-gate.yml |
| `ci:preview` | The pull-request preview environment, per ADR-0205: the full tier at one pull request's images and manifests. The run that creates it also destroys it. | preview.yml |
| `ci:prune-registry` | Delete the first-party image tags that no environment pins and the last PRUNE_KEEP commits do not name, per ADR-0105. | publish.yml |
| `ci:push-promotion` | Commit a promotion's values changes and push them to the default branch, per ADR-0201. | publish.yml |
| `ci:release-info` | A CalVer release tag resolved to a version and a commit, as forge step-output assignments, per ADR-0102 and ADR-0103. | promote-on-release.yml |
| `ci:release-pr` | Open the prod pin as a pull request. The forge merges it when its checks pass, per ADR-0201. | promote-on-release.yml |
| `ci:release-publish` | Publish the forge release for $VER, per ADR-0103. | promote-on-release.yml |
| `ci:scan` | The vulnerability merge gate, per ADR-0104. | ci.yml |
| `ci:sign` | Sign a published image and attach its SBOM and provenance, per ADR-0104. | publish.yml |
| `cluster:add` | One verb to put something in the cluster, per ADR-0600. | lighthouse.yml |
| `cluster:down` | Delete the tier's cluster and its image cache. | e2e.yml, lighthouse.yml, perf.yml |
| `cluster:up` | Create, resume, or repair a tier. | e2e.yml, lighthouse.yml, perf.yml |
| `e2e` | The full browser suite against a running full tier: acceptance, visual, and accessibility, per ADR-0601. | e2e.yml |
| `e2e:install` | The e2e island's Node dependencies and its browser, per ADR-0601. | e2e.yml, lighthouse.yml, preview.yml |
| `e2e:smoke` | The @smoke subset of the browser suite, for a labelled pull request, per ADR-0601. | e2e.yml, preview.yml |
| `gen:admin` | Scaffold the Lowdefy admin pages from the OpenAPI specs, per ADR-0401. | .lefthook.yml |
| `gen:adr-rules` | Two documents are views over the Rules sections of the ADR set: the rules index and the security baseline, per ADR-0203. | .lefthook.yml |
| `gen:build-path` | The machinery table in docs/reference/build-path.md, from the tasks that a workflow or hook reaches, per ADR-0000. | .lefthook.yml |
| `gen:data-classes` | The data-class and retention registry, per ADR-0301. A new service is reviewed against this checklist. | .lefthook.yml |
| `gen:image-allowlist` | The third-party image allow-list, per ADR-0104. It comes from the charts: every repository that the platform's own charts pull from. | .lefthook.yml |
| `gen:openapi` | The Go and TypeScript clients and servers, generated from each service's OpenAPI spec, per ADR-0303. | .lefthook.yml |
| `gen:openapi-public` | Filtered OpenAPI projections for the Scalar developer portals, per ADR-0303. | .lefthook.yml |
| `gen:shared-components` | Writes the canonical error envelope, money, and timestamp components from tools/codegen/shared-components.yaml into every spec, per ADR-0303. | .lefthook.yml |
| `gen:sqlc` | The typed Go database access, generated from each service's queries, per ADR-0300. | .lefthook.yml |
| `gen:zod` | The runtime validation schemas for the TypeScript apps, generated from the OpenAPI specs, per ADR-0303. | .lefthook.yml |
| `lighthouse` | Web vitals and the bundle budget for each route, as merge gates, per ADR-0400: LCP < 2.5s, CLS < 0.1, and Total Blocking Time < 200ms on the mobile profile. | lighthouse.yml |
| `lint:activity-register` | The Temporal registration gate, per ADR-0302: every activity that a workflow names as a string is registered on its service's worker. | .lefthook.yml, ci.yml |
| `lint:adr-xref` | The internal links of the ADR set. References resolve, and Related names documents that exist. Every ADR has a Decides line and an index row. The two adoption documents name the same components. | .lefthook.yml, ci.yml |
| `lint:alert-severity` | The alert-severity gate, per ADR-0502. | .lefthook.yml, ci.yml |
| `lint:api-audience` | The audience and exposure gate, per ADR-0303. A spec's info.x-audience is public only when the service has an /api route at the edge. | .lefthook.yml, ci.yml |
| `lint:api-breaking` | oasdiff labels breaking contract changes for review. It is not a version gate, per ADR-0303. | ci.yml |
| `lint:auth-inline` | The single-source guard for auth config, per ADR-0305. It fails if kratos or oathkeeper config is put inline in the Ory chart values instead of infra/auth/*, or if the frontend adds development auth. | .lefthook.yml, ci.yml |
| `lint:authz` | The edge-auth policy gates, per ADR-0304, ADR-0305, and ADR-0306. They check the OpenFGA model, its assertions, and model.json sync. Ops dashboards authorize through remote_json to the Checker, never `allow`. | .lefthook.yml, ci.yml |
| `lint:authz-dual-write` | The ADR-0304 dual-write rule, checked statically: a tuple is written from an activity, never from a handler. | .lefthook.yml, ci.yml |
| `lint:comments` | The part of the ADR-0001 comment rules that a machine can check, over the comments this repository owns. | .lefthook.yml, ci.yml |
| `lint:commits` | Conventional Commits over the commit range of the pull request, per ADR-0103. | ci.yml |
| `lint:contrast` | Colour contrast, checked against the design-token file and not for each component, per ADR-0400. A token change moves every surface, so the token file is where a regression starts. | .lefthook.yml, ci.yml |
| `lint:data-classes` | The drift check for the data-class registry. | .lefthook.yml, ci.yml |
| `lint:determinism` | Temporal workflow determinism, per ADR-0302. | .lefthook.yml, ci.yml |
| `lint:dns` | ADR-0206: infra/dns/dnsconfig.js is a valid zone declaration. It needs no credential. | .lefthook.yml, ci.yml |
| `lint:floating-tags` | Image references pin a digest or an explicit version, never a moving tag, per ADR-0101 and ADR-0104. | .lefthook.yml, ci.yml |
| `lint:gitops-env-scope` | ADR-0201 gate: an environment's bootstrap directory names only that environment. | .lefthook.yml, ci.yml |
| `lint:go` | Go correctness and style: golangci-lint's configured analysers over every module, per ADR-0100. | .lefthook.yml, ci.yml |
| `lint:gostyle` | Custom Go style analyzers based on layout. | .lefthook.yml, ci.yml |
| `lint:helm-deps` | `helm dependency build` needs the repo registered in the caller's helm config. `update` resolves it from Chart.yaml. | .lefthook.yml, ci.yml |
| `lint:i18n` | Localisation, enforced, per ADR-0400. | .lefthook.yml, ci.yml |
| `lint:image-allowlist` | The drift check for the image allow-list. | .lefthook.yml, ci.yml |
| `lint:log-vocab` | The vocabulary gate for human output, per ADR-0001. Scripts use → ✓ ✗ ⚠ through scripts/lib/log.sh, not bare WARN, ERROR, or FAIL text. | .lefthook.yml, ci.yml |
| `lint:md` | Markdown structure and formatting: rumdl over every document, per ADR-0001. | .lefthook.yml, ci.yml |
| `lint:money` | The monetary-value gate, per ADR-0100 and ADR-0300. A money-like OpenAPI property is the shared `Money` component. No Go or TypeScript field or variable with a money-like name is a float. | .lefthook.yml, ci.yml |
| `lint:naming` | The resource-name grammar of ADR-0003, `{project}-{env}-{role}[-{n}]`, across the Talos inventory, the sops recipients, and the GitOps overlays. The role vocabulary comes from the ADR. | .lefthook.yml, ci.yml |
| `lint:node-scope` | The Node confinement guard, per ADR-0100 and ADR-0601. Node and npm appear only in the repo-root test/e2e/ workspace. | .lefthook.yml, ci.yml |
| `lint:openapi` | OpenAPI contracts: every spec against the platform ruleset, and resource-prefix ownership across the set, per ADR-0303. | .lefthook.yml, ci.yml |
| `lint:parity` | ADR-0205 gate: every key in a deployed environment's values exists in the local overlay, or is on the allowlist with its approved reason. | .lefthook.yml, ci.yml |
| `lint:ports` | The local port registry gate, per ADR-0205: ports are unique, every service is registered, and each service's .mise.toml uses the port the registry assigns. | .lefthook.yml, ci.yml |
| `lint:project-identity` | ADR-0106 gate: a project created from this template must have its own name before it pushes. | .lefthook.yml, ci.yml |
| `lint:prose` | The Simple English profile and the banned-constructs table of ADR-0001, enforced. | .lefthook.yml, ci.yml |
| `lint:readme-drift` | Principle 9, applied to the one document that is not generated. | .lefthook.yml, ci.yml |
| `lint:resource-governance` | ADR-0204 gate: render every chart, each service separately, and check the declared resources against the guardrails in infra/helm/platform/resource-governance before they reach a cluster. | .lefthook.yml, ci.yml |
| `lint:rules-index` | The drift check for the generated rule documents. | .lefthook.yml, ci.yml |
| `lint:secrets` | ADR-0202: no committed file holds a plaintext secret value. | .lefthook.yml, ci.yml |
| `lint:secrets-history` | The history scope of lint:secrets. | ci.yml |
| `lint:service-contract` | ADR-0205 gate: every service provides the same artifacts, because the platform finds services through those artifacts. | .lefthook.yml, ci.yml |
| `lint:service-databases` | ADR-0300: a service that ships migrations has a database to run them against. | .lefthook.yml, ci.yml |
| `lint:service-deps` | The inner loop's dependency graph, checked against the code, per ADR-0600 and ADR-0205. | .lefthook.yml, ci.yml |
| `lint:shell` | shellcheck over every tracked *.sh, per ADR-0101. | .lefthook.yml, ci.yml |
| `lint:sql` | SQL: sqruff over every migration and sqlc query. A column with personal data has its pii class, per ADR-0300 and ADR-0301. | .lefthook.yml, ci.yml |
| `lint:tasks` | ADR-0600: every mise task has a command or a dependency. | .lefthook.yml, ci.yml |
| `lint:template-build` | `go build ./...` cannot see services/_template. Every hand-written file there has a //go:build _template constraint, and scripts/new-service.sh removes it when it copies the tree. | .lefthook.yml, ci.yml |
| `lint:thin-workflows` | ADR-0102: workflow YAML checks out, sets up the toolchain, and calls a mise task. | .lefthook.yml, ci.yml |
| `lint:tool-register` | The four register Rules of ADR-0002: every Tier 1 or Tier 2 row names an owning ADR that exists, and that ADR has the comparison its tier needs. A Tier 1 row names a runner-up. | .lefthook.yml, ci.yml |
| `lint:ts` | TypeScript, JSON, and CSS: biome lint and format, with warnings as errors, per ADR-0100. | .lefthook.yml, ci.yml |
| `lint:workspace-copies` | A TS workspace member that the frontend image build does not copy fails `bun install` with `Workspace not found`. This happens only at image build, which on the full tier is minutes into a cluster start. | .lefthook.yml, ci.yml |
| `mock:start` | The API mock for UI work, per ADR-0600. Prism serves the committed `internal.json` projection behind the real edge and its real middleware chain. | lighthouse.yml |
| `perf` | The steady baseline: nightly and before a release. | perf.yml |
| `perf:seed` | Bulk catalog data, so the read path is measured against a realistic table. | perf.yml |
| `perf:smoke` | About 30 seconds. | perf.yml |
| `promote:dev-staging` | Pin the dev and staging values for the components in $SERVICES and $APPS to $SHA by digest. | publish.yml |
| `promote:prod` | Pin every prod values file to $SHA by digest, and label the images $VER. | promote-on-release.yml |
| `promote:verify` | Gate a release on prod converging on $SHA. | promote-on-release.yml |
| `release` | Cut a repo-wide CalVer release, per ADR-0103: compute the version, stamp the fields a build tool needs, regenerate CHANGELOG.md, commit, tag, and push. | promote-on-release.yml |
| `secrets:age` | Idempotent. It also writes .sops.yaml, per ADR-0202. | e2e.yml, perf.yml, preview.yml |
| `setup` | The git hooks, installed from .lefthook.yml. | .lefthook.yml |
| `setup:node` | The workspace's node_modules. | .lefthook.yml, ci.yml |
| `supply-chain:inventory` | Verify the SBOM attestation of every image pinned in committed values, and record its contents, per ADR-0104. | supply-chain.yml |
| `test:go` | Every Go package's tests, including the tools, per ADR-0601. | ci.yml |
| `test:template` | The repository's own generation, per ADR-0106: a fixture matrix through `copier copy`, the refusals its validators must give, and the equality of the two adoption paths. The merge of `copier update` depends on that equality. | template.yml |
| `test:ts` | The shared TypeScript libraries under libs/ts/. The e2e suite covers the frontend's browser behaviour, per ADR-0601. | ci.yml |

<!-- machinery:end -->

## Reading the table

**Two residuals are unbounded, and they are not the same kind of thing.**

- An **omitted authorization check** is unbounded, because review is the only position that holds it. An absence gives a linter nothing to read. A spec catches it only on the paths that the spec walks.
- The **CVE pull side** is unbounded, because the gate is push-shaped by design. No amount of CI closes it. Only a component closes it, and the operational budget prices that component out of Core, per [`../operational-surface.md`](../operational-surface.md).

**Read the plaintext-secret row first.** It is the only class here where the defect survives the fix. A revert of the file does not remove the secret from history. So the fix is a credential rotation, not a revert. For every other row in this table, a shipped correction repairs the defect.

**The path is sound where nobody can bypass it, and advisory elsewhere. This assignment is on purpose.** In the *Caught by* column, every class at position 6 has no residual. Every class with an unbounded residual is at position 4. This is the rule of [ADR-0203](../adr/0203-policy-enforcement.md), and it gives exactly what it promises. It also states the cost of the rule in one place: **on this platform, enforcement strength follows whether a machine can see the property, not how much the defect costs.** An omitted authorization check costs more than a floating tag, but a person checks it. The reason is that one is an absence and the other is a field.

**Two rows are a scheduling choice, not a capability gap.** A suite catches both the cross-service regression and the broken operator dashboard. The suite runs nightly and not on the pull request. Affected-detection already knows which pull requests touch more than one service. So a move of the first row is a policy change in the workflow.

**Compare the two composites.** The dominant term of the run-time path is human attention, per [`detection-latency.md`](detection-latency.md). The dominant term of the build path is whether a machine can see a property. They fail in different ways. A project that reduces the floor reads both. The managed swaps in [`../adoption-path.md`](../adoption-path.md) change the first and leave the second as it is.
