# The Build Path

[`detection-latency.md`](detection-latency.md) puts together the run-time path. For each failure class, it states how long a fault runs before anyone notices. This document puts together the other path. **For each class of defect, it states what stops the defect between a keystroke and production, and what reaches production unchecked.**

An ADR decides each gate below, and each ADR is complete about its own gate. No ADR can state the total, because the total belongs to the sequence and not to any layer in it.

**A defect class with no row here is a class that nobody has classified.** This is the same failure that the unbounded rows of the run-time table name.

## The four positions that set these numbers

| Position | Effect on the merge path | Owning decision |
| --- | --- | --- |
| CI lints fail open by construction | a check that does not run counts as a passed check. So every gate on a repository property is advisory against a path that skips CI | [ADR-0203](../adr/0203-policy-enforcement.md) |
| Affected-detection selects what CI runs | a selection bug gives a green run that does not select the broken change | [ADR-0111](../adr/0111-monorepo.md), register row 8 |
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
| Layout, naming, prose, generated-code drift | 2: CI lints, per [ADR-0111](../adr/0111-monorepo.md) and [ADR-0001](../adr/0001-documentation-conventions.md) | CI does not run, or affected-detection does not select the change | **bounded.** The subject is a file. A repository property that reaches production is a cosmetic defect. So this class goes to a layer that fails open |
| Contract shape: spec validity, audience, breaking change | 2: vacuum and oasdiff, per [ADR-0303](../adr/0303-api-contracts-and-lifecycle.md) | as above | **bounded.** The generated client is committed and drift-checked. So a spec change that skipped the gate must still pass the drift check to merge |
| A single service's logic | 3: unit and integration tests | affected-detection did not select the service | **register row 8.** That row is about this class. Its reach is one merge plus everything downstream |
| Behaviour with no test, or a test that cites a retired requirement | 2: `lint-requirements`, per [ADR-0602](../adr/0602-behaviour-requirements.md) | CI does not run | **bounded for the trace, unbounded for meaning.** The lint sees that a test names an ID, not that its assertion proves the requirement. Position 4 is the only check on that |
| A cross-service regression | 3: e2e, **per PR only with a label**, nightly in full | the pull request had no e2e label | **register row 6, up to a day.** This is the largest routine hole in this table. A policy change closes it, not a component |
| An operator dashboard broken | 3: the nightly suite only | always, until the nightly run | **up to a day.** It is a day of exposure on the surface that operators use *during* an incident |
| A known-vulnerable dependency or base image | 2: Trivy at the merge gate, per [ADR-0113](../adr/0113-supply-chain-security.md) | the CVE is published after the merge | **the pull side is unbounded.** Trivy is push-shaped: it sees what is being built, not what already runs. Nothing on the floor notices that a CVE published today affects an image built in March. The Dependency-Track row in [`../operational-surface.md`](../operational-surface.md) would answer this |
| An unsigned or floating-tag image | **6: Kyverno at admission**, per [ADR-0113](../adr/0113-supply-chain-security.md) | it does not. A deploying party cannot bypass admission | **none, by construction.** Position 6 exists because of this class |
| A privileged or non-conforming workload | **6: Pod Security Admission**, per [ADR-0200](../adr/0200-cluster-topology.md) | it does not | **none.** It is in-tree, so it fails with the API server and not separately |
| An unreachable or over-reachable workload | **6: CiliumNetworkPolicy** in the datapath, per [ADR-0206](../adr/0206-cluster-networking.md) | it does not, for traffic. A missing policy is a different defect | **none for enforcement. The gap is a policy that nobody wrote.** Position 4 is the only check on it |
| A resource-governance defect: no request, wrong priority | **6: in-tree API objects**, per [ADR-0204](../adr/0204-resource-management.md) | it does not | **none.** `LimitRange` defaults it, or `ResourceQuota` rejects it |
| A plaintext secret in a committed file | 1 and 2: gitleaks over the tree at commit and in CI, and over the whole history in CI. The tasks are `lint-secrets` and `lint-secrets-history`, per [ADR-0202](../adr/0202-secrets.md) | the rules do not recognise its shape | **bounded by the rule set, and the sharpest row here.** Unlike the classes above, the defect is permanent after a merge: git history holds it after the file is fixed |
| An authorization defect: an omitted check, or a dual write outside a workflow | 2: `lint-authz-dual-write` and `lint-authz` for the static shapes. 3: the authorization and privilege-escalation specs. 4: review for an omitted `Checker` call. Per [ADR-0304](../adr/0304-identity-and-authorization.md) and [ADR-0302](../adr/0302-temporal.md) | a handler omits a check that no spec exercises | **bounded for the static shapes, unbounded for an omitted check.** A missing call leaves nothing for a linter to read |
| Cluster state diverging from the repository | 5: Argo CD, with `selfHeal=false` in production, per [ADR-0201](../adr/0201-gitops.md) | a human applies it, and nobody reads the drift notification | **hours to the next working day.** This is detection, not enforcement. On purpose, production reverts nothing on its own |

## The machinery

This table lists every task that a workflow or a git hook reaches, and the failure class that the task owns, per ADR-0000 principle 2. `just gen` generates it from the task descriptions. Delete a task that owns no class, or a task whose class another row already owns.

<!-- machinery:begin -->

| Recipe | Owns | Reached from |
| --- | --- | --- |
| `build` | Compile every Go module, the tools included, per ADR-0111 | flake.nix |
| `cache-push` | Push what CI built to the binary cache, per ADR-0101. Without NIX_CACHE_URL it does nothing | check.yml |
| `ci` | Run exactly what CI runs: every check of flake.nix in the Nix sandbox | check.yml, git hooks |
| `ci-affected-adversarial` | Break each service in a scratch worktree and check that affected detection names it | history.yml |
| `ci-affected-matrix` | The affected manifest, split into the arrays of the image jobs, per ADR-0116 | publish.yml |
| `ci-build-images` | Build, push, and sign every affected image: services or apps | publish.yml |
| `ci-design-preview` | The design preview of a pull request, per ADR-0701: build or comment | design-preview.yml |
| `ci-e2e-gate` | Whether a pull request runs the smoke suite, per ADR-0601 | e2e.yml |
| `ci-gen` | Generate and format everything, and fail on a change, per ADR-0111 and ADR-0303 | flake.nix |
| `ci-lighthouse-gate` | Whether a pull request runs Lighthouse, per ADR-0400 | lighthouse.yml |
| `ci-nightly-gate` | Whether the nightly suite runs tonight, per ADR-0601 | _nightly-gate.yml |
| `ci-preview` | The preview environment of a pull request, per ADR-0205 | preview.yml |
| `ci-prune-registry` | Delete the first-party image tags that nothing pins, per ADR-0114 | publish.yml |
| `ci-push-promotion` | Commit the values of a promotion and push them, per ADR-0201 | publish.yml |
| `ci-release-info` | A release tag as a version and a commit, per ADR-0112 | promote-on-release.yml |
| `ci-release-pr` | Open the prod pin as a pull request, per ADR-0201 | promote-on-release.yml |
| `ci-release-publish` | Publish the forge release for $VER, per ADR-0112 | promote-on-release.yml |
| `ci-renovate` | Run Renovate over this repository, per ADR-0117 | renovate.yml |
| `ci-scan` | The vulnerability gate, per ADR-0113 | history.yml |
| `cluster-down` | Delete the cluster of the tier and its image cache | e2e.yml, perf.yml |
| `cluster-up` | Create, resume, or repair a local tier. The argument `full` selects the full tier | e2e.yml, perf.yml |
| `dns-apply` | Make the zones of the provider match infra/dns/dnsconfig.js, per ADR-0206 | dns.yml |
| `dns-check` | Report how the zones of the provider differ from infra/dns/dnsconfig.js, per ADR-0206 | dns.yml |
| `e2e` | The full browser suite against a running full tier, per ADR-0601 | e2e.yml |
| `e2e-diagnose` | Print the errors of the workloads on the path of an ops route, after a failed e2e run | e2e.yml |
| `e2e-install` | The Node.js dependencies of the e2e island, per ADR-0601. The browsers come from nixpkgs | e2e.yml, lighthouse.yml, preview.yml, publish.yml |
| `e2e-smoke` | The @smoke subset of the browser suite, per ADR-0601 | e2e.yml, preview.yml |
| `lighthouse` | Web vitals and the bundle budget of each route, per ADR-0400 | lighthouse.yml, publish.yml |
| `lighthouse-down` | Remove the containers and the network of lighthouse-up | lighthouse.yml, publish.yml |
| `lighthouse-up` | The Lighthouse origin with no cluster, per ADR-0400 | lighthouse.yml, publish.yml |
| `lint-activity-register` | Every activity that a workflow names is registered on its worker, per ADR-0302 | flake.nix |
| `lint-adr-xref` | The cross references that tablint has no rule for | flake.nix |
| `lint-alert-severity` | The severity of every alert, per ADR-0502 | flake.nix |
| `lint-api-audience` | The audience of a spec matches its route at the edge, per ADR-0303 | flake.nix |
| `lint-api-breaking` | Label the breaking contract changes for review, per ADR-0303 | history.yml |
| `lint-app-versions` | Each chart's appVersion names the release that the chart deploys, per ADR-0111 | flake.nix |
| `lint-auth-inline` | The auth config has one source, per ADR-0305 | flake.nix |
| `lint-authz` | The OpenFGA model, its assertions, and the access rules of the edge, per ADR-0304, ADR-0305, and ADR-0306 | flake.nix |
| `lint-authz-dual-write` | An authorization tuple is written from an activity, never from a handler, per ADR-0304 | flake.nix |
| `lint-commits` | Conventional Commits over the commit range of a pull request, per ADR-0101 | history.yml |
| `lint-contrast` | The contrast of the design tokens, per ADR-0400 | flake.nix |
| `lint-data-classes` | The drift check of the data-class registry | flake.nix |
| `lint-determinism` | Temporal workflow determinism, per ADR-0302 | flake.nix |
| `lint-dns` | infra/dns/dnsconfig.js is a valid zone, per ADR-0206 | flake.nix |
| `lint-fixtures` | Every fixture is typed against a generated SDK, per ADR-0701 | flake.nix |
| `lint-floating-tags` | An image reference pins a digest or an exact version, per ADR-0111 and ADR-0113 | flake.nix |
| `lint-gitops-env-scope` | An environment's bootstrap folder names only that environment, per ADR-0201 | flake.nix |
| `lint-go` | Go correctness and style with golangci-lint, per ADR-0110 | flake.nix |
| `lint-gostyle` | The custom Go style analyzers | flake.nix |
| `lint-helm-deps` | Helm dependency calls resolve from Chart.yaml alone, per ADR-0111 | flake.nix |
| `lint-i18n` | Every string is in the message catalogues, per ADR-0400 | flake.nix |
| `lint-image-allowlist` | The drift check of the image allow-list | flake.nix |
| `lint-l7-routes` | A caller limited to some routes uses only the cluster operations of the spec, per ADR-0305 | flake.nix |
| `lint-log-vocab` | Scripts use the log vocabulary of ADR-0001 | flake.nix |
| `lint-money` | A money value is the shared Money component and never a float, per ADR-0110 and ADR-0300 | flake.nix |
| `lint-naming` | The resource name grammar of ADR-0003 | flake.nix |
| `lint-node-scope` | Node.js and npm stay in their islands, per ADR-0110 and ADR-0601 | flake.nix |
| `lint-openapi` | Every spec against the platform ruleset, and the owner of each resource prefix, per ADR-0303 | flake.nix |
| `lint-parity` | Every key of a deployed environment exists in the local overlay, per ADR-0205 | flake.nix |
| `lint-ports` | The local ports are unique and registered, per ADR-0205 | flake.nix |
| `lint-readme-drift` | The README matches the decisions it summarizes | flake.nix |
| `lint-resource-governance` | Render every chart and check its resources against the guardrails, per ADR-0204 | flake.nix |
| `lint-rules-index` | The drift check of the generated rule documents | flake.nix |
| `lint-secrets-history` | The secret scan over the whole git history, per ADR-0202 | history.yml |
| `lint-service-contract` | Every service provides the same artifacts, per ADR-0205 | flake.nix |
| `lint-service-databases` | A service with migrations has a database, per ADR-0300 | flake.nix |
| `lint-service-deps` | The dependency graph of the inner loop matches the code, per ADR-0600 and ADR-0205 | flake.nix |
| `lint-shell` | shellcheck over every shell file, per ADR-0111 | flake.nix |
| `lint-sql` | SQL with sqruff, and the pii class of each column with personal data, per ADR-0300 and ADR-0301 | flake.nix |
| `lint-template-build` | Vet services/_template, which `go build ./...` cannot see behind its build tag | flake.nix |
| `lint-thin-workflows` | Workflow YAML checks out, sets up the toolchain, and calls a recipe, per ADR-0116 | flake.nix |
| `lint-tool-register` | The register rules of ADR-0002 | flake.nix |
| `lint-ts` | TypeScript, JavaScript, and CSS with Biome, with warnings as errors, per ADR-0110 | flake.nix |
| `lint-workarounds` | Every workaround matches the version its file pins, per ADR-0001 | flake.nix |
| `lint-workspace-copies` | The frontend image build copies every TypeScript workspace member | flake.nix |
| `perf` | The steady load baseline, per ADR-0601. It needs the full tier | perf.yml |
| `perf-seed` | Seed bulk catalog products, 5000 by default. --clean removes them | perf.yml |
| `perf-smoke` | Both scenarios with one virtual user for a few seconds | perf.yml |
| `promote-dev-staging` | Pin the dev and staging values of $SERVICES and $APPS to $SHA | publish.yml |
| `promote-prod` | Pin every prod values file to $SHA, and label the images $VER | promote-on-release.yml |
| `promote-verify` | Wait until prod runs $SHA | promote-on-release.yml |
| `release` | Cut a CalVer release of the repo, per ADR-0112 | promote-on-release.yml |
| `secrets-age` | Create your age key and write .sops.yaml, per ADR-0202. It runs again safely | e2e.yml, perf.yml, preview.yml |
| `supply-chain-inventory` | Verify the SBOM of every pinned image and record its contents, per ADR-0113 | supply-chain.yml |
| `test-frontend` | The frontend tests, with a coverage floor for each route group, per ADR-0400 | flake.nix |
| `test-go` | Every Go test, the tools included, per ADR-0601 | flake.nix |
| `test-ts` | The tests of the shared TypeScript libraries | flake.nix |

<!-- machinery:end -->

## Reading the table

**Two residuals are unbounded, and they are not the same kind of thing.**

- An **omitted authorization check** is unbounded, because review is the only position that holds it. An absence gives a linter nothing to read. A spec catches it only on the paths that the spec walks.
- The **CVE pull side** is unbounded, because the gate is push-shaped by design. No amount of CI closes it. Only a component closes it, and the operational budget prices that component out of Core, per [`../operational-surface.md`](../operational-surface.md).

**Read the plaintext-secret row first.** It is the only class here where the defect survives the fix. A revert of the file does not remove the secret from history. So the fix is a credential rotation, not a revert. For every other row in this table, a shipped correction repairs the defect.

**The path is sound where nobody can bypass it, and advisory elsewhere. This assignment is on purpose.** In the *Caught by* column, every class at position 6 has no residual. Every class with an unbounded residual is at position 4. This is the rule of [ADR-0203](../adr/0203-policy-enforcement.md), and it gives exactly what it promises. It also states the cost of the rule in one place: **on this platform, enforcement strength follows whether a machine can see the property, not how much the defect costs.** An omitted authorization check costs more than a floating tag, but a person checks it. The reason is that one is an absence and the other is a field.

**Two rows are a scheduling choice, not a capability gap.** A suite catches both the cross-service regression and the broken operator dashboard. The suite runs nightly and not on the pull request. Affected-detection already knows which pull requests touch more than one service. So a move of the first row is a policy change in the workflow.

**Compare the two composites.** The dominant term of the run-time path is human attention, per [`detection-latency.md`](detection-latency.md). The dominant term of the build path is whether a machine can see a property. They fail in different ways. A project that reduces the floor reads both. The managed swaps in [`../adoption-path.md`](../adoption-path.md) change the first and leave the second as it is.
