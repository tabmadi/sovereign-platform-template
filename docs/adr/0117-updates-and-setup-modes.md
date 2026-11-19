# ADR-0117: Update Classes and Setup Modes

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0102](0102-dependency-updates.md), [ADR-0111](0111-monorepo.md), [ADR-0113](0113-supply-chain-security.md), [ADR-0116](0116-forge-and-pipelines.md), [ADR-0003](0003-naming-and-identifiers.md)
- **Decides:** Renovate runs from a scheduled workflow with the update classes of this platform, and `just init` sets the identity and the modes of a project.

## Context

[ADR-0102](0102-dependency-updates.md) decides that Renovate proposes every update and the CI gate decides. This platform has more pins than a small repo, and two of its facts change how Renovate runs:

- The forge can be Forgejo, per [ADR-0116](0116-forge-and-pipelines.md). The hosted Renovate app serves only some forges.
- Three positions depend on pins that move on a fixed cadence:

| Position | What it assumes | Owning ADR |
| --- | --- | --- |
| Digest-pinned production images | a digest is refreshed when its tag is rebuilt. If not, production runs a base image that nobody patches | [ADR-0113](0113-supply-chain-security.md) |
| Floating tags rejected everywhere | an upgrade is an explicit, reviewed act that someone performs | [ADR-0111](0111-monorepo.md) |
| Trivy as a merge gate | a CVE with an available fix produces a bump, not a gate that stays red | [ADR-0113](0113-supply-chain-security.md) |

Some files also fit one setup of a project and not another. The permissions blocks of a workflow fit GitHub, and Forgejo ignores them with a warning. The hypervisor scripts fit a project that runs its own hardware.

## Decision drivers

1. **Every forge.** The update run works on each forge of [ADR-0116](0116-forge-and-pipelines.md).
2. **Config in the repo.** The rules that group the pins are reviewed files, per principle 1 of [ADR-0000](0000-platform-foundations.md).
3. **A fixed cadence.** Updates arrive in a weekly slot, per [`operational-surface.md`](../operational-surface.md), and a fixed CVE arrives at once.
4. **The derived files follow.** A bump of `go.sum`, `bun.lock`, or a `Chart.lock` also updates what Nix derives from it. So the gate can pass.
5. **One setup per project.** A project holds the files of the setup it chose, and no file of a setup it did not choose.

## Considered options

### Where Renovate runs

| Option | 1 Every forge | 2 Config in the repo | 4 The derived files follow | Verdict |
| --- | --- | --- | --- | --- |
| The hosted Renovate app | GitHub, GitLab, and Bitbucket. Not Forgejo | Yes | No. The app runs no command of the repo | Rejected on drivers 1 and 4 |
| Dependabot | GitHub only | Yes | No | Rejected on drivers 1 and 4 |
| **Renovate from a scheduled workflow, as the `ci` machine user** | **Yes. Renovate has a Forgejo platform** | **Yes: `.github/renovate.json` and `.config/renovate.json`** | **Yes. `postUpgradeTasks` run `just bun-nix` and `scripts/nix-hashes.sh`** | **Chosen** |

Sources:

- The forges that the hosted app serves: [Mend Renovate app](https://docs.renovatebot.com/mend-hosted/overview/).
- Renovate supports Forgejo as a platform: [Renovate docs, Forgejo](https://docs.renovatebot.com/modules/platform/forgejo/).
- A self-hosted run reads a global config file, and runs the allowed commands after an upgrade: [Renovate docs, self-hosted configuration](https://docs.renovatebot.com/self-hosted-configuration/), [postUpgradeTasks](https://docs.renovatebot.com/configuration-options/#postupgradetasks).
- Dependabot runs only on GitHub: [GitHub docs, about Dependabot version updates](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/about-dependabot-version-updates).

### How a project chooses its setup

| Option | 5 One setup | Verdict |
| --- | --- | --- |
| Ship every setup, and let each project delete what it does not need | No. A project keeps files that do not apply to it until someone notices | Rejected |
| One template for each setup | Yes, at the cost of a copy of the platform for each setup | Rejected. Six copies of one platform drift apart |
| **A question of `just init` for each mode. It removes the paths of the other modes, and runs the script of a mode that edits files in place** | **Yes** | **Chosen** |

## Decision

### Renovate opens the pull request, and the gates decide

The weekly `renovate` workflow runs `just ci-renovate` as the `ci` machine user, with the `RENOVATE_TOKEN` secret. It reads the shared `.github/renovate.json` of [ADR-0102](0102-dependency-updates.md), and the self-hosted config `.config/renovate.json` through `RENOVATE_CONFIG_FILE`. The second file holds the classes below. Renovate merges nothing. Every update pull request passes the same gate as a human pull request.

| Class | Grouping | Schedule |
| --- | --- | --- |
| The flake inputs: nixpkgs, tabnix, and flake-parts | one PR | weekly, with the lock file maintenance of [ADR-0102](0102-dependency-updates.md) |
| Go modules and Bun packages | one PR per ecosystem, minor and patch together | weekly |
| Major versions, any ecosystem | one PR each, alone | when a person ticks it on the dashboard, because a major is a decision |
| Container base images and platform chart images | one PR for the images and one PR for the charts, minor and patch together, tag and digest together | weekly |
| Pins that add a digest or an exact version to a reference without one | one PR for every pin | weekly |
| Anything with a fixed CVE that Trivy gates on | one PR each, at once | on detection |
| OpenTofu providers and modules | one PR | monthly |

After each upgrade, Renovate runs `just bun-nix` and `bash scripts/nix-hashes.sh`. So `bun.nix` and the two fixed-output hashes of `flake.nix` follow `bun.lock`, `go.sum`, and each `Chart.lock` in the same pull request.

**A digest is updated with its tag, never separately.** A digest that moves while its tag does not is a rebuild of the same version. A reviewer cannot judge this case from the diff alone, so the PR body carries both.

**The dashboard issue of Renovate is the queue.** It lists what is pending, what is rate-limited, and what fails to build.

### Update review is a standing obligation

The weekly batch is recurring work, in the sense of [`operational-surface.md`](../operational-surface.md). It arrives whether or not anything is wrong, and a delay is the quiet failure.

**A dependency PR that fails its gates is not merged and is not disabled.** The failure is the information that the gate exists to produce.

**An update that is held back carries the reason in the Renovate configuration**, as a package rule with a description. A pin held for a reason that nobody recorded looks the same as a pin that nobody looked at.

### A project chooses its setup once

`just init` asks seven questions. Five name the project: the product name, the slug of [ADR-0003](0003-naming-and-identifiers.md), the Go module path, the apex host, and the image registry. Two choose a mode: the forge and the provisioning. [`docs/reference/modes.md`](../reference/modes.md) lists the modes and their paths.

`just init` runs `scripts/project-rename.sh`, which replaces the names in every file. It removes the paths of the modes that the project did not choose. It runs `scripts/forge-mode.sh`, which edits the workflows in place for the `forgejo` mode. It writes the answers into `infra/project.yaml`, which the scripts of `infra/` read. Then it removes these scripts and itself.

## Consequences

### Positive

- Digest pinning stays an immutability property and does not become a freeze, because something refreshes the digests on a cadence.
- One PR per ecosystem per week is a limited review surface. The single dependency graph of the monorepo makes it one PR, not one per service.
- A Renovate PR updates the derived Nix files itself, so it does not fail the gate for a stale hash.
- A held-back dependency carries its reason in a reviewed file.

### Negative and Risks

- **A grouped PR fails as a unit.** One bad minor version blocks the batch behind it, and splitting the group is manual work. The alternative is one PR per dependency, and driver 3 exists to limit that review load.
- **Renovate has a large configuration surface.** A misconfigured package rule silently stops updates to something. The dashboard issue lists what is rate-limited or disabled, so the silence is visible.
- **The workflow needs a token.** A repository without `RENOVATE_TOKEN` skips the run, and its pins go stale until someone adds the secret.
- **A mode changes only once.** `just init` removes itself, so a later change of mode is a change by hand, which [`docs/reference/modes.md`](../reference/modes.md) describes.

## Rules

- Renovate opens every dependency, image, chart, and tool update as a pull request. It merges nothing. No update bypasses the gate that a human pull request passes. `(CI: ci)`
- Renovate runs from the scheduled `renovate` workflow, with `.config/renovate.json` as its self-hosted config.
- Updates are grouped by ecosystem and batched on a schedule. A major version is proposed alone, and only after a person approves it on the dashboard.
- An update that changes `bun.lock`, `go.sum`, or a `Chart.lock` also updates `bun.nix` and the hashes of `flake.nix` in the same pull request. `(CI: ci)`
- A container image update moves the tag and the digest in the same pull request. A digest is never updated on its own. `(CI: lint-floating-tags)`
- A held-back dependency carries its reason as the description of the package rule that holds it. A pin with no recorded reason is treated as unreviewed.
- A failing update pull request stays open. The update is never disabled to clear the queue.
- A CVE that Trivy gates on and that has a fixed version available is proposed at once, outside the batch. `(CI: ci-scan)`
- A file that fits only one setup belongs to a mode. `just init` removes the paths of every mode that the project did not choose.
- A project adopts its own module path, registry namespace, and apex host before its first push. A repository whose name does not match its module path has not been renamed. `(CI: lint-project-identity)`
