# Every task, per ADR-0103 and ADR-0111. A recipe that calls a tool runs only inside the dev shell of flake.nix.
# A recipe name is `group-member`. What a recipe acts on is an argument: `just cluster-up full`.

set shell := ["bash", "-euo", "pipefail", "-c"]
set positional-arguments

import? 'template/justfile'
import? 'infra/hypervisor/justfile'

# List the recipes
default:
    @just --list

# Build the dev shell, install the locked dependencies, and install the git hooks
setup:
    nix develop --command just setup-node

# Install the locked node_modules of the workspace, in the hoisted layout that Next.js and the checks of flake.nix use
setup-node: in-shell
    bun install --frozen-lockfile --linker=hoisted

# Turn this copy into a project: answer the seven questions, rename, and apply the setup modes, per ADR-0117
init *args:
    bash scripts/project-init.sh "$@"

# Set up a fresh checkout: dependencies, .env, and the SOPS keys of a new project. It runs again safely
bootstrap: setup-node
    bash scripts/bootstrap.sh

# Create, resume, or repair a local tier. The argument `full` selects the full tier
cluster-up *args: in-shell
    bash scripts/cluster.sh up "$@"

# Apply the PostgreSQL slice of infra/local/deps.yaml. A service lists its own dependencies
dep-postgres: cluster-up
    bash scripts/dep-apply.sh postgres

# Apply the Temporal slice of infra/local/deps.yaml
dep-temporal: cluster-up
    bash scripts/dep-apply.sh temporal

# Apply the OpenFGA slice of infra/local/deps.yaml
dep-openfga: cluster-up
    bash scripts/dep-apply.sh openfga

# Apply the database secrets of each service, which the service chart mounts through envFrom
dep-db-secrets: cluster-up
    bash scripts/dep-apply.sh db-secrets

# Make the authz service answer on its registered local port
svc-authz: cluster-up
    bash scripts/svc-apply.sh authz

# Make the catalog service answer on its registered local port
svc-catalog: cluster-up
    bash scripts/svc-apply.sh catalog

# Make the orders service answer on its registered local port
svc-orders: cluster-up
    bash scripts/svc-apply.sh orders

# Make the orgs service answer on its registered local port
svc-orgs: cluster-up
    bash scripts/svc-apply.sh orgs

# Make the payment service answer on its registered local port
svc-payment: cluster-up
    bash scripts/svc-apply.sh payment

# Apply the host-only edge glue again: the catch-all route to the host next dev, and the EndpointSlice behind it
[private]
cluster-glue: in-shell
    bash scripts/cluster.sh glue

# Stop the nodes of the tier and keep them, so the next cluster-up resumes with no new pull
cluster-stop *args: in-shell
    bash scripts/cluster.sh stop "$@"

# Delete the cluster of the tier and its image cache
cluster-down *args: in-shell
    bash scripts/cluster.sh down "$@"

# Recover a cluster after a host reboot, when pods cannot reach the API
cluster-heal *args: in-shell
    bash scripts/cluster.sh heal "$@"

# Show what runs in the active tier and how to reach it
cluster-status *args: in-shell
    bash scripts/cluster.sh status "$@"

# Check that a tier is up and serving, per ADR-0600. VERIFY_HOST=<apex> checks a deployed environment
verify: in-shell
    bash scripts/verify.sh

# Copy the first-party images into the zot of the full tier, per ADR-0114
cluster-populate-zot: in-shell
    bash scripts/populate-zot.sh

# Set up this machine once for a network behind a proxy, before the first cluster-up
proxy-setup *args: in-shell
    bash scripts/proxy-setup.sh "$@"

# Pause the Argo CD application controller for a live patch
argo-pause: in-shell
    bash scripts/argo.sh pause

# Give the cluster back to GitOps after a live patch
argo-resume: in-shell
    bash scripts/argo.sh resume

# Port-forward the dependencies of the inner loop, so a native service reaches them
dev-forward *args: in-shell
    bash scripts/dev-forward.sh "$@"

# Run next dev on the host, where the local edge routes `/`, per ADR-0400
dev-frontend: in-shell
    EDGE_PUBLIC_ORIGIN=https://dev.localtest.me:8443 bash scripts/dev-frontend.sh

# Serve the committed internal.json projection with Prism behind the real edge, per ADR-0600
mock-start *args: in-shell
    bash scripts/mock.sh start "$@"

# Stop the API mock
mock-stop: in-shell
    bash scripts/mock.sh stop

# Show the requests that matched no operation and the bodies that failed the spec
mock-logs: in-shell
    bash scripts/mock.sh logs

# Apply the pending migrations of every service
db-migrate *args: in-shell
    bash scripts/db-migrate.sh "$@"

# The release of Lowdefy, from the one place that pins it
lowdefy := `sed -n 's/^ARG LOWDEFY_VERSION=//p' apps/admin/Dockerfile`

# Build the Lowdefy admin console in its island shell, per ADR-0401
admin-build:
    nix develop .#admin --command bash -c 'cd apps/admin && pnpm dlx lowdefy@{{ lowdefy }} build'

# Run the Lowdefy admin console with live reload, per ADR-0401
admin-run:
    nix develop .#admin --command bash -c 'cd apps/admin && pnpm dlx lowdefy@{{ lowdefy }} dev'

# Validate the Lowdefy config, per ADR-0401
admin-lint:
    nix develop .#admin --command bash -c 'cd apps/admin && pnpm dlx lowdefy@{{ lowdefy }} validate'

# Build the frontend for production, per ADR-0400
frontend-build: in-shell
    cd apps/frontend && bun run build

# Seed the committed test identities into a running Kratos, per ADR-0601
auth-seed: in-shell
    bash scripts/identity-seed.sh

# Run every generator, then format the data files they write. The edge reads no OpenAPI spec, so it has no generator, per ADR-0305
gen: gen-shared-components gen-openapi gen-openapi-public gen-zod gen-sqlc gen-admin gen-adr-rules gen-data-classes gen-image-allowlist gen-build-path
    dprint fmt --excludes '**/templates/**' >/dev/null

# Write the rules index and the security baseline from the Rules sections, per ADR-0203
gen-adr-rules: in-shell
    tabrules gen rules-index

# Write the machinery table in docs/reference/build-path.md, per ADR-0000
gen-build-path: in-shell
    tabrules gen build-path

# Write the registry of data classes and retention, per ADR-0301
gen-data-classes: in-shell
    tabrules gen data-classes

# Write the zod schemas of each request body from the OpenAPI specs, per ADR-0303
gen-zod: gen-shared-components
    tabrules gen zod

# Write the shared error, money, and timestamp components into every spec, per ADR-0303
gen-shared-components: in-shell
    tabrules gen shared-components

# Write the Go and TypeScript clients and servers from each OpenAPI spec, per ADR-0303
gen-openapi: gen-shared-components
    bash scripts/gen-openapi.sh

# Write the Lowdefy admin pages from the OpenAPI specs, per ADR-0401
gen-admin: gen-openapi
    bash scripts/gen-admin.sh

# Write the filtered OpenAPI projections for the developer portals, per ADR-0303
gen-openapi-public: in-shell
    bash scripts/gen-openapi-public.sh

# Write infra/auth/openfga/model.json from the model.fga DSL, per ADR-0304
gen-authz-model: in-shell
    fga model transform --file infra/auth/openfga/model.fga --output-format json | jq -S . > infra/auth/openfga/model.json

# Write the typed Go database access from the queries of each service, per ADR-0300
gen-sqlc: in-shell
    bash scripts/gen-sqlc.sh

# Delete the generated SDKs and write them again, which removes orphans
gen-clean: in-shell
    rm -rf libs/go/sdks/* libs/ts/sdks/*
    just gen

# Write the image allow-list from the charts, per ADR-0113
gen-image-allowlist: in-shell
    bash scripts/gen-image-allowlist.sh

# Apply every formatter and every safe lint fix
format: format-go format-ts format-md format-shell format-data
    just --fmt

# Format Go: the gostyle fixes, then the formatters of golangci-lint, per ADR-0110
format-go: in-shell
    tabrules fix
    golangci-lint fmt --config .config/golangci.yml ./...

# Format TypeScript, JavaScript, and CSS with Biome, per ADR-0110
format-ts: in-shell
    biome check --config-path .config --write .

# Format Markdown with rumdl, per ADR-0104
format-md: in-shell
    rumdl check --fix .

# Format shell with shfmt, over the files that lint-shell reads
format-shell: in-shell
    bash scripts/format-shell.sh

# Format JSON, JSONC, TOML, YAML, and Nix, per ADR-0104
format-data: in-shell
    dprint fmt --excludes '**/templates/**'
    nixfmt $(git ls-files --cached --others --exclude-standard '*.nix')

# Run every linter
lint: lint-go lint-gostyle lint-template-build lint-determinism lint-ts lint-prose lint-md lint-data lint-nix lint-just lint-secrets lint-platform

# The gates of the platform that run with no network and no cluster. CI runs them in the sandbox
lint-platform: lint-sql lint-service-deps lint-activity-register lint-authz-dual-write lint-money lint-naming lint-helm-deps lint-app-versions lint-openapi lint-api-audience lint-floating-tags lint-shell lint-node-scope lint-auth-inline lint-authz lint-log-vocab lint-resource-governance lint-ports lint-l7-routes lint-service-databases lint-workspace-copies lint-service-contract lint-adr-xref lint-readme-drift lint-rules-index lint-data-classes lint-image-allowlist lint-thin-workflows lint-workarounds lint-dns lint-contrast lint-i18n lint-fixtures lint-tool-register lint-alert-severity lint-parity lint-gitops-env-scope lint-etcd-addresses

# Go correctness and style with golangci-lint, per ADR-0110
lint-go: in-shell
    golangci-lint run --config .config/golangci.yml ./...

# The custom Go style analyzers
lint-gostyle: in-shell
    tabrules check --only go/call-args

# Vet services/_template, which `go build ./...` cannot see behind its build tag
lint-template-build: in-shell
    go vet -tags _template ./services/_template/cmd/... ./services/_template/internal/...

# Temporal workflow determinism, per ADR-0302
lint-determinism: in-shell
    go tool workflowcheck ./services/...

# TypeScript, JavaScript, and CSS with Biome, with warnings as errors, per ADR-0110
lint-ts: in-shell
    biome ci --config-path .config --error-on-warnings .

# Prose, comments, ADRs, and the requirement trace, per ADR-0001 and ADR-0602
lint-prose: in-shell
    tabrules check

# Markdown structure and format, per ADR-0001
lint-md: in-shell
    rumdl check .

# JSON, JSONC, TOML, and YAML format, per ADR-0104
lint-data: in-shell
    dprint check --excludes '**/templates/**'

# Nix format, per ADR-0104
lint-nix: in-shell
    nixfmt --check $(git ls-files --cached --others --exclude-standard '*.nix')

# justfile format, per ADR-0104
lint-just:
    just --fmt --check

# No committed file holds a plaintext secret, per ADR-0202
lint-secrets: in-shell
    bash scripts/lint-secrets.sh

# The secret scan over the whole git history, per ADR-0202
lint-secrets-history: in-shell
    GITLEAKS_HISTORY=1 bash scripts/lint-secrets.sh

# Helm dependency calls resolve from Chart.yaml alone, per ADR-0111
lint-helm-deps: in-shell
    tabrules check --only helm/dependency-fallback

# Each chart's appVersion names the release that the chart deploys, per ADR-0111
lint-app-versions: in-shell
    tabrules check --only helm/app-version

# SQL with sqruff, and the pii class of each column with personal data, per ADR-0300 and ADR-0301
lint-sql: in-shell
    bash scripts/lint-sql.sh

# Every spec against the platform ruleset, and the owner of each resource prefix, per ADR-0303
lint-openapi: in-shell
    bash scripts/lint-openapi.sh

# Every service provides the same artifacts, per ADR-0205
lint-service-contract: in-shell
    tabrules check --only service/contract

# The frontend image build copies every TypeScript workspace member
lint-workspace-copies: in-shell
    tabrules check --only service/workspace-copies

# A service with migrations has a database, per ADR-0300
lint-service-databases: in-shell
    tabrules check --only service/databases

# The local ports are unique and registered, per ADR-0205
lint-ports: in-shell
    tabrules check --only service/ports

# A caller limited to some routes uses only the cluster operations of the spec, per ADR-0305
lint-l7-routes: in-shell
    tabrules check --only edge/l7-routes

# The audience of a spec matches its route at the edge, per ADR-0303
lint-api-audience: in-shell
    tabrules check --only api/audience

# The dependency graph of the inner loop matches the code, per ADR-0600 and ADR-0205
lint-service-deps: in-shell
    tabrules check --only go/service-deps

# Every activity that a workflow names is registered on its worker, per ADR-0302
lint-activity-register: in-shell
    tabrules check --only go/activity-register

# An authorization tuple is written from an activity, never from a handler, per ADR-0304
lint-authz-dual-write: in-shell
    ast-grep scan --rule .config/ast-grep/authz-dual-write.yml .

# The severity of every alert, per ADR-0502
lint-alert-severity: in-shell
    tabrules check --only alert/severity

# A money value is the shared Money component and never a float, per ADR-0110 and ADR-0300
lint-money: in-shell
    tabrules check --only money

# The resource name grammar of ADR-0003
lint-naming: in-shell
    tabrules check --only naming/resource

# Render every chart and check its resources against the guardrails, per ADR-0204
lint-resource-governance: in-shell
    tabrules check --only kube/resource-governance

# An environment's bootstrap folder names only that environment, per ADR-0201
lint-gitops-env-scope: in-shell
    tabrules check --only gitops/env-scope

# Every key of a deployed environment exists in the local overlay, per ADR-0205
lint-parity: in-shell
    tabrules check --only gitops/parity

# The etcd metric addresses match the node inventory, per ADR-0500
lint-etcd-addresses: in-shell
    bash scripts/lint-etcd-addresses.sh

# An image reference pins a digest or an exact version, per ADR-0111 and ADR-0113
lint-floating-tags: in-shell
    tabrules check --only image

# A project has its own name before it pushes, per ADR-0117
lint-project-identity: in-shell
    tabrules check --only project/identity

# Resolve a tag to the index digest that a pin uses, per ADR-0111 and ADR-0113
image-digest *args: in-shell
    bash scripts/image-digest.sh "$@"

# The adoption documents and the deferral register agree with the ADRs, per ADR-0001
lint-adr-xref: in-shell
    tabrules check --only adr/adoption-components,adr/deferral-register

# The README matches the decisions it summarizes
lint-readme-drift: in-shell
    tabrules check --only docs/stack-table,docs/principles,docs/headcount

# The drift check of the image allow-list
lint-image-allowlist: in-shell
    bash scripts/gen-image-allowlist.sh --check

# The drift check of the data-class registry
lint-data-classes: in-shell
    tabrules gen data-classes --check

# The drift check of the generated rule documents
lint-rules-index: in-shell
    tabrules gen rules-index --check

# shellcheck over every shell file, per ADR-0111
lint-shell: in-shell
    bash scripts/lint-shell.sh

# Scripts use the log vocabulary of ADR-0001
lint-log-vocab: in-shell
    tabrules check --only script/log-vocabulary

# Node.js and npm stay in their islands, per ADR-0110 and ADR-0601
lint-node-scope: in-shell
    tabrules check --only service/node-scope

# The auth config has one source, per ADR-0305
lint-auth-inline: in-shell
    tabrules check --only edge/auth-inline

# The OpenFGA model, its assertions, and the access rules of the edge, per ADR-0304, ADR-0305, and ADR-0306
lint-authz: in-shell
    bash scripts/validate-openfga.sh
    tabrules check --only edge/authorizer,edge/api-wildcard,edge/strip-headers

# The register rules of ADR-0002
lint-tool-register: in-shell
    tabrules check --only adr/tool-register

# Every string is in the message catalogues, per ADR-0400
lint-i18n: in-shell
    tabrules check --only frontend/message-parity,frontend/logical-property

# Every fixture is typed against a generated SDK, per ADR-0701
lint-fixtures: in-shell
    tabrules check --only frontend/fixture

# The contrast of the design tokens, per ADR-0400
lint-contrast: in-shell
    tabrules check --only frontend/contrast

# Every workaround matches the version its file pins, per ADR-0001
lint-workarounds: in-shell
    tabrules check --only comment/workaround

# Workflow YAML checks out, sets up the toolchain, and calls a recipe, per ADR-0116
lint-thin-workflows: in-shell
    tabrules check --only workflow/thin

# infra/dns/dnsconfig.js is a valid zone, per ADR-0206
lint-dns: in-shell
    dnscontrol check --config infra/dns/dnsconfig.js

# Conventional Commits over the commit range of a pull request, per ADR-0101
lint-commits: in-shell
    commit-range

# Label the breaking contract changes for review, per ADR-0303
lint-api-breaking: in-shell
    bash scripts/lint-api-breaking.sh

# Run every test
test: test-go test-ts test-frontend

# Every Go test, per ADR-0601
test-go: in-shell
    go test ./...

# The tests of the shared TypeScript libraries
test-ts: in-shell
    bun test libs/ts/

# The frontend tests, with a coverage floor for each route group, per ADR-0400
test-frontend: in-shell
    bash scripts/test-frontend.sh

# Compile the Go module, per ADR-0111
build: in-shell
    go build ./...

# Format, then run every linter
pre-commit: format lint

# The fast gate: run it before you finish a change
check: lint test build

# Run every check of flake.nix in the Nix sandbox. CI runs it on each push, beside its slower jobs
ci:
    nix flake check --print-build-logs

# Push what CI built to the binary cache, per ADR-0101. Without NIX_CACHE_URL it does nothing
cache-push: in-shell
    nix-cache-push

# The services and apps that a change affects, as JSON, per ADR-0111
ci-affected *args: in-shell
    tabrules affected "$@"

# The checks of a pull request that need the git history: commits, the secret history, and breaking contracts
ci-lint: lint-commits lint-secrets-history lint-api-breaking

# The vulnerability gate, per ADR-0113
ci-scan: in-shell
    bash scripts/scan.sh

# Every finding of every severity, for triage. It is not a gate
scan-report: in-shell
    bash scripts/scan.sh report

# The tests that CI runs
ci-test: test

# The affected manifest, split into the arrays of the image jobs, per ADR-0116
ci-affected-matrix *args: in-shell
    bash scripts/ci-affected-matrix.sh "$@"

# Delete the first-party image tags that nothing pins, per ADR-0114
ci-prune-registry: in-shell
    bash scripts/ci-prune-registry.sh

# Commit the values of a promotion and push them, per ADR-0201
ci-push-promotion *args: in-shell
    bash scripts/ci-push-promotion.sh "$@"

# Run Renovate over this repository, per ADR-0117
ci-renovate: in-shell
    bash scripts/ci-renovate.sh

# Open the prod pin as a pull request, per ADR-0201
ci-release-pr: in-shell
    bash scripts/ci-release-pr.sh

# Publish the forge release for $VER, per ADR-0112
ci-release-publish: in-shell
    bash scripts/ci-release-publish.sh

# Sign an image and attach its SBOM and provenance, per ADR-0113
ci-sign *args: in-shell
    bash scripts/ci-sign.sh "$@"

# Verify the SBOM of every pinned image and record its contents, per ADR-0113
supply-chain-inventory: in-shell
    bash scripts/supply-chain-inventory.sh

# Break each service in a scratch worktree and check that affected detection names it
ci-affected-adversarial: in-shell
    bash scripts/ci-affected-adversarial.sh

# Whether a pull request runs the smoke suite, per ADR-0601
ci-e2e-gate: in-shell
    bash scripts/ci-e2e-gate.sh

# Whether a pull request runs Lighthouse, per ADR-0400
ci-lighthouse-gate: in-shell
    bash scripts/ci-lighthouse-gate.sh

# Whether the nightly suite runs tonight, per ADR-0601
ci-nightly-gate: in-shell
    bash scripts/ci-nightly-gate.sh

# Build, push, and sign every affected image: services or apps
ci-build-images *args: in-shell
    bash scripts/ci-build-images.sh "$@"

# The Docker build context of an app
ci-build-context *args: in-shell
    bash scripts/ci-build-context.sh "$@"

# Cut a CalVer release of the repo, per ADR-0112
release *args: in-shell
    bash scripts/release.sh "$@"

# A release tag as a version and a commit, per ADR-0112
ci-release-info *args: in-shell
    bash scripts/ci-release-info.sh "$@"

# Pin the dev and staging values of $SERVICES and $APPS to $SHA
promote-dev-staging: in-shell
    bash scripts/promote-dev-staging.sh

# Pin every prod values file to $SHA, and label the images $VER
promote-prod: in-shell
    bash scripts/promote-prod.sh

# Wait until prod runs $SHA
promote-verify: in-shell
    bash scripts/promote-verify.sh

# Compile everything, as CI does
ci-build: build

# The preview environment of a pull request, per ADR-0205
ci-preview *args: in-shell
    bash scripts/ci-preview.sh "$@"

# The design preview of a pull request, per ADR-0701: build or comment
ci-design-preview *args: in-shell
    bash scripts/ci-design-preview.sh "$@"

# Apply the committed branch protection, checks, and team access to the forge, per ADR-0116
forge-apply: in-shell
    bash scripts/forge-apply.sh

# Start the sprint of today and move the open issues of ended sprints into it, per ADR-0115
forge-sprint: in-shell
    bash scripts/forge-sprint.sh

# Create or refresh the ci machine user and its tokens, per ADR-0116
forge-ci-user: in-shell
    bash scripts/forge-ci-user.sh

# Generate and format everything, and fail on a change, per ADR-0111 and ADR-0303
ci-gen: in-shell
    bash scripts/ci-gen.sh

# Lay the bootstrap floor of an environment and apply its root Application, per ADR-0200
argocd-bootstrap *args: in-shell
    bash scripts/argocd-bootstrap.sh "$@"

# Put a service, an app, or a chart into the cluster, per ADR-0600
cluster-add *args: in-shell
    bash scripts/cluster.sh add "$@"

# Take a service, an app, or a chart out of the cluster
cluster-remove *args: in-shell
    bash scripts/cluster.sh remove "$@"

# Run a service natively behind the real edge
service-dev *args: in-shell
    bash scripts/service-dev.sh "$@"

# Create a Kratos session token for local calls. It needs the full tier
auth-token *args: in-shell
    bash scripts/auth-token.sh "$@"

# Erase a subject in every store, per ADR-0301: just privacy-erase <identity-id>
privacy-erase *args: in-shell
    bash scripts/privacy.sh erase "$@"

# Export the data of a subject as JSON, per ADR-0301: just privacy-export <identity-id>
privacy-export *args: in-shell
    bash scripts/privacy.sh export "$@"

# Grant an operator role while the admin console is down, per ADR-0304
ops-grant *args: in-shell
    bash scripts/ops-grant.sh "$@"

# Generate the key pair that signs images, per ADR-0113
secrets-cosign: in-shell
    bash scripts/secrets-cosign.sh

# Generate the commit signing keys of the forge and the ci user, per ADR-0116
secrets-gpg: in-shell
    bash scripts/secrets-gpg.sh

# Import the signing key of the forge into its Forgejo user, per ADR-0116
forge-signing: in-shell
    bash infra/forge-host/forge.sh signing

# Create your age key and write .sops.yaml, per ADR-0202. It runs again safely
secrets-age: in-shell
    bash scripts/secrets-age.sh

# Encrypt every SOPS file again to the recipients in .sops.yaml, per ADR-0202
secrets-updatekeys: in-shell
    bash scripts/secrets-updatekeys.sh

# The Node.js dependencies of the e2e island, per ADR-0601. The browsers come from nixpkgs
e2e-install:
    nix develop .#e2e --command bash -c 'cd test/e2e && npm ci'

# The full browser suite against a running full tier, per ADR-0601
e2e *args:
    nix develop .#e2e --command bash scripts/e2e.sh test "$@"

# Print the errors of the workloads on the path of an ops route, after a failed e2e run
e2e-diagnose: in-shell
    bash scripts/e2e-diagnose.sh

# The @smoke subset of the browser suite, per ADR-0601
e2e-smoke *args:
    nix develop .#e2e --command bash scripts/e2e.sh test:smoke "$@"

# Only the axe scan, per ADR-0400
e2e-a11y *args:
    nix develop .#e2e --command bash scripts/e2e.sh test:a11y "$@"

# Only the screenshot baselines, per ADR-0601. Add --update-snapshots to write them again
e2e-visual *args:
    nix develop .#e2e --command bash scripts/e2e.sh test:visual "$@"

# Web vitals and the bundle budget of each route, per ADR-0400
lighthouse *args:
    nix develop .#e2e --command bash scripts/e2e.sh lighthouse "$@"

# The Lighthouse origin with no cluster, per ADR-0400
lighthouse-up: in-shell
    bash scripts/lighthouse-stack.sh up

# Remove the containers and the network of lighthouse-up
lighthouse-down: in-shell
    bash scripts/lighthouse-stack.sh down

# The steady load baseline, per ADR-0601. It needs the full tier
perf: in-shell
    bash test/perf/run.sh browse load
    bash test/perf/run.sh checkout load

# Both scenarios with one virtual user for a few seconds
perf-smoke: in-shell
    bash test/perf/run.sh browse smoke
    bash test/perf/run.sh checkout smoke

# Ramp to saturation to find the knee. The thresholds are expected to fail
perf-stress: in-shell
    bash test/perf/run.sh browse stress
    bash test/perf/run.sh checkout stress

# Sustained load for about 30 minutes, to find leaks
perf-soak: in-shell
    bash test/perf/run.sh browse soak

# Seed bulk catalog products, 5000 by default. --clean removes them
perf-seed *args: in-shell
    bash test/perf/seed/seed.sh "$@"

# Compute again the measured numbers that the ADRs state, per ADR-0001
perf-re-derive: in-shell
    bash scripts/perf-rederive.sh

# Collect the browser source maps of a release build, per ADR-0503
frontend-sourcemaps *args: in-shell
    bash scripts/frontend-sourcemaps.sh "$@"

# Run a workflow locally with act
act-local *args: in-shell
    bash scripts/act-local.sh "$@"

# Report how the zones of the provider differ from infra/dns/dnsconfig.js, per ADR-0206
dns-check: in-shell
    bash scripts/dns.sh check

# Make the zones of the provider match infra/dns/dnsconfig.js, per ADR-0206
dns-apply: in-shell
    bash scripts/dns.sh apply

# Write the hashes of the Go modules and the subcharts into flake.nix again, after a change to go.sum or a Chart.lock
nix-hashes: in-shell
    bash scripts/nix-hashes.sh

# Write the files that follow a dependency change, per ADR-0117
deps-sync: bun-nix nix-hashes

# Write bun.nix again from bun.lock. Run it after each change of a dependency
bun-nix: in-shell
    bun2nix -o bun.nix
    nixfmt bun.nix

[private]
in-shell:
    @test -n "${IN_NIX_SHELL:-}" || { echo "Enter the dev shell first: run nix develop, or allow direnv." >&2; exit 1; }
