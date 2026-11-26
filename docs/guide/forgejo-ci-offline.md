# Run Forgejo CI without public internet access

Use this guide in a project generated with `forge: forgejo`, per [Setup modes](../reference/modes.md). Apply the steps to that project. Let its runner and clusters reach internal Forgejo, Zot, the Nix cache, and the package sources. Use a separate import job with upstream access to prepare inputs before routine jobs run.

## Set up the internal services

1. Provision Forgejo and a dedicated runner as NixOS machines. Follow `infra/forge-host/README.md` and `infra/runner/README.md`. Seed the internal binary cache with both systems if the build also takes place on the closed network.
2. Mirror the Actions used in `.forgejo/workflows/` and `.github/actions/` at the revisions those files use. Point Forgejo and the workflows at the internal copies. Replace the direct Nix installer step in `check.yml` with the Nix of the NixOS runner. Configure artifact upload and cache steps to use services reachable from the runner.
3. Configure the runner's Nix daemon to use and trust the internal binary cache, per [ADR-0101](../adr/0101-source-control-and-ci.md). Keep its local store between jobs. Test that the runner can read imported paths with public substituters disabled.
4. Set the Forgejo registry variables and credentials for the internal Zot, per [ADR-0114](../adr/0114-image-registry.md). Point Argo CD at the internal Forgejo repository, per the [GitOps runbook](gitops-runbook.md). Give the runner, builders, and clusters access to internal DNS and any internal CA they need.

## Import the inputs

| Job | Inputs and configuration |
| --- | --- |
| PR checks | Import the locked flake sources and make them resolvable from the internal network or local store. Seed the cache with the dev shells and the prepared Go, Bun, and Helm dependencies used by `just ci`. Point Go commands outside the Nix sandbox at an internal module proxy. |
| Image publishing and design preview | Import the BuildKit image, the Dockerfile frontend, and each base and copy stage image. Configure Docker and BuildKit to pull from the internal registry. Provide Go modules and the Bun packages of the root lockfile. Keep Inter and Vazirmatn in the frontend as local font files and load them with `next/font/local`. |
| E2E, preview, perf, and Lighthouse | Import the images in `infra/local/image-refs.txt`, the kind node and Zot images, and the images that Lighthouse starts directly. Seed the runner-local Zot from the internal registry before `cluster-up full` warms it. Serve Helm subcharts to both bootstrap and Argo CD. Import the E2E shell with its Playwright browsers. Serve the Bun packages of the root lockfile to `bun install`. |
| Trivy scan | Import the vulnerability database and the checks bundle on a schedule. Configure `just ci-scan` to use these copies in offline mode. |
| Scheduled jobs | Use a Forgejo-compatible endpoint for the nightly gate in `tabkit-ops ci-nightly-gate`. Run public DNS drift checks and Renovate upstream discovery in a network that can reach their providers. |

Record the source revision, lockfiles, image digests, and scanner snapshot for each import. Import new inputs before the change that uses them runs with public egress blocked. Make a missing input fail with its name. A pull-through cache that fetches from the internet on a miss still puts that fetch in the job's path.

## Verify the pipeline

1. Start with a fresh runner and populated internal services. Block public egress from the runner, Docker, BuildKit, and the test cluster. Keep internal DNS and service access available.
2. Run the PR checks and Trivy scan. Publish a service image, the frontend image, and the admin image to internal Zot. Verify the signatures and attestations.
3. Run the full cluster, E2E, and Lighthouse jobs. Verify that Argo CD reconciles from internal Forgejo and deploys signed images from internal Zot in the target test environment.
4. Check egress logs for attempted public connections, including DNS queries. Trace each attempt to its job or cluster component. Repeat the run after you fix the source.

## Measure the effect on job time

1. Time the same commit with the current upstream path and with preloaded internal inputs. Use equivalent runners and the same initial runner cache state.
2. Record job setup, dependency preparation, image builds, cluster startup, and test time. Compare job time separately from the time the import job takes.
3. Run the commit again on the warm runner. Record the time saved by the local Nix store, BuildKit cache, and local Zot separately from the effect of internal sources.
