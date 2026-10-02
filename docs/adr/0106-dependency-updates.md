# ADR-0106: Dependency Updates and Template Propagation

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0101](0101-monorepo.md), [ADR-0102](0102-source-control-and-ci.md), [ADR-0104](0104-supply-chain-security.md)
- **Decides:** Renovate proposes every pin bump as a batched pull request the normal gates judge, and Copier propagates template changes by 3-way merge.

## Context

Every version in this repository is pinned:

- Developer and CI tools are pinned in `.mise.toml`.
- Runtime images carry an explicit tag in Helm values.
- Production values carry a digest.
- CI and admission reject floating tags, per [ADR-0101](0101-monorepo.md) and [ADR-0104](0104-supply-chain-security.md).

Pinning fixes what runs. It moves the problem of staying current to whoever moves the pins. Three decided positions depend on something that moves the pins on a cadence:

| Position | What it assumes | Owning ADR |
| --- | --- | --- |
| Digest-pinned production images | a digest is refreshed when its tag is rebuilt. If not, production runs a base image that nobody patches | [ADR-0104](0104-supply-chain-security.md) |
| Floating tags rejected everywhere | an upgrade is an explicit, reviewed act that someone performs | [ADR-0101](0101-monorepo.md) |
| Trivy as a merge gate | a CVE with an available fix produces a bump, not a gate that stays red | [ADR-0104](0104-supply-chain-security.md) |

A second currency problem runs in the other direction. This repository is a template. So a fix made here must reach the projects generated from it. The mechanism that carries the fix is the same class of decision: an automated pull request against a repository whose gates decide whether it lands.

This ADR decides both. [ADR-0104](0104-supply-chain-security.md) decides what a CVE means once it is found: triage, severity, and whether a build is blocked.

## Decision drivers

1. **An upgrade is a reviewed change, not an event.** [ADR-0101](0101-monorepo.md) makes a version bump a normal PR, so that any SHA reproduces its own toolchain. Whatever moves a pin produces a PR and passes the gates. If it does not, it defeats the pinning.
2. **The platform sets the cadence, not the dependency.** A tool that pushes changes when upstream releases gives the release schedule to whoever publishes most often. The recurring obligation is a fixed slot, per [`operational-surface.md`](../operational-surface.md), and that means batching.
3. **One repository, one dependency graph**, per [ADR-0101](0101-monorepo.md). The monorepo already forces every service onto one version of a dependency. So the update mechanism has one PR to open, not one per consumer.
4. **No ambient runtime**, per principle 6 of [ADR-0000](0000-platform-foundations.md). The mechanism runs from a pinned toolchain, like everything else.
5. **Propagation is a merge, not a regeneration.** A generated project has diverged on purpose. Nobody runs a mechanism twice if it overwrites their divergence.

## Considered options

### Dependency updates

| Option | Ecosystems it covers | Grouping and scheduling | Digest pinning | Self-hosted | Verdict |
| --- | --- | --- | --- | --- | --- |
| **Renovate** | Go modules, npm and Bun, Dockerfiles, Helm charts and values, GitHub and Forgejo Actions, `.mise.toml`, Terraform, and pins matched by regex anywhere else | grouped presets, any schedule, and a dependency dashboard issue | [resolves and writes the digest](https://docs.renovatebot.com/configuration-options/#pindigests) beside the tag it pins *(documented)* | a container, run from CI or as a service | **Chosen.** It is the only option that covers the whole pin surface. It is also the only one that writes digests, not only tags *(documented)* |
| Dependabot | Go modules, npm, Docker, Actions | limited grouping, daily or weekly | tags only | native to the forge, and the forge here is not GitHub | Loses on coverage. `.mise.toml`, Helm values, and Terraform are outside it, so a second mechanism must cover the rest *(documented)* |
| `renovate` that pins everything and merges nothing, plus manual sweeps | as Renovate | a person | as Renovate | not applicable | The honest baseline. It is the result when nothing is configured. In a busy quarter, the fixed slot of driver 2 is the thing that is skipped |
| A scheduled job that runs the own updater of each ecosystem | whatever is scripted | custom | custom | fully | Rebuilds Renovate at lower quality. The updater of each ecosystem has different opinions about lockfiles |
| Nothing: bump on demand | not applicable | not applicable | not applicable | not applicable | Makes the digest pin a permanent freeze. That turns the immutability property of [ADR-0104](0104-supply-chain-security.md) into an unpatched base image *(reasoned)* |

### Template propagation

| Option | Update model | Divergence in the generated project | Runtime | Verdict |
| --- | --- | --- | --- | --- |
| **Copier** | `copier update` performs a [**3-way merge**](https://copier.readthedocs.io/en/stable/updating/) between the old template render, the new one, and the current state of the project | preserved. Conflicts show as conflicts | Python, run as a pinned tool | **Chosen.** The 3-way merge is the property. It is the only option here that treats the generated project as the authority over its own divergence *(documented)* |
| Cookiecutter | regeneration only | overwritten, or reconciled by hand | Python | No update path. A second tool would have to do the merge, which is the whole problem |
| A git remote, with periodic merges from the template | git merge | preserved | none | Works. It pulls the whole history of the template into every generated project, including files that the project deleted at generation time |
| Copy once, never propagate | not applicable | total | none | The honest baseline. This template would take this position if a fix here never had to reach a generated project. It does have to |

**Copier is a Python tool. Principle 6 of [ADR-0000](0000-platform-foundations.md) bans ambient runtimes, not Python.** Copier is pinned in `.mise.toml` like every other tool. It runs on a developer or CI machine. No service, image, or cluster workload depends on it. [ADR-0100](0100-language-and-runtime.md) takes the same position on developer tooling in general: the two-language cap governs authored code, not the tools that generate it.

## Decision

### Renovate opens the pull request, and the gates decide

Renovate runs on a schedule from CI and opens pull requests. It merges nothing. Every update PR passes the same gates as a human PR: lint, generated-code drift, tests, and the affected-service selection of [ADR-0101](0101-monorepo.md). A bump that skips them is a pin that was never load-bearing.

| Class | Grouping | Schedule |
| --- | --- | --- |
| Go modules and Bun packages | one PR per ecosystem, minor and patch together | weekly |
| Major versions, any ecosystem | one PR each, alone | weekly, and never grouped, because a major is a decision |
| Container base images and platform chart images | one PR per image, tag and digest together | weekly |
| Pinned tools in `.mise.toml` | one PR for the file | weekly |
| Anything with a fixed CVE that Trivy gates on | one PR each, at once | on detection |
| Terraform providers and modules | one PR | monthly |

**A digest is updated with its tag, never separately.** A digest that moves while its tag does not is a rebuild of the same version. Base-image patching produces this case. A human reviewer cannot judge this case from the diff alone. So the PR body carries both.

**The dashboard issue of Renovate is the queue.** It lists what is pending, what is rate-limited, and what fails to build. It lives in the forge, where work is tracked, per [ADR-0102](0102-source-control-and-ci.md).

### Update review is a standing obligation

The weekly batch is recurring work, in the sense of [`operational-surface.md`](../operational-surface.md). It arrives whether or not anything is wrong, and a delay is the quiet failure. Two rules limit it.

**A dependency PR that fails its gates is not merged and is not disabled.** The failure is the information that the gate exists to produce. Renovate opens it again every week, and that is the correct behaviour.

**An update that is held back carries the reason in the Renovate configuration**, as a package rule with a comment. The reason does not live in a person's memory. A pin held for a reason that nobody recorded looks the same as a pin that nobody looked at.

### Copier propagates the template

A generated project tracks this repository through the Copier answers file, and updates by 3-way merge. The template states a limited guarantee:

| Guarantee | Value |
| --- | --- |
| **What propagates** | files that the template renders and the project has not rewritten |
| **What does not** | anything the project edited. It arrives as a conflict, not an overwrite |
| **Compatibility promise** | none. A template update can conflict, and the project resolves it |
| **Cadence** | set by the project, on its own schedule |

**The rename runs at every update, not only at generation.** An update renders the old template and the new template, and it merges the difference into the project. Both renders carry the project's names. So the merge sees only what the template changed, and a reworded line that holds a name does not conflict.

**Renovate updates the template pin.** The Copier answers file records the commit of the template. That makes it a dependency like any other. So the same weekly mechanism proposes the template bump, and the same gates judge it.

## Consequences

### Positive

- Digest pinning stays an immutability property and does not become a freeze, because something refreshes the digests on a cadence.
- One PR per ecosystem per week is a limited review surface. The single dependency graph of the monorepo makes it one PR, not one per service.
- A held-back dependency carries its reason in a reviewed file.
- A fix made in the template reaches generated projects through a mechanism that respects their divergence. So the second update costs no more than the first.

### Negative and Risks

- **A grouped PR fails as a unit.** One bad minor version blocks the batch behind it, and splitting the group is manual work. This is accepted. The alternative is one PR per dependency, and driver 2 exists to limit that review load.
- **Renovate has a large configuration surface.** A misconfigured package rule silently stops updates to something. The dashboard issue mitigates this: it lists what is rate-limited or disabled, so the silence is visible.
- **The template makes no compatibility promise.** So a project that skips updates for long enough faces one large conflicted merge, not several small ones. This is stated, not mitigated. The template is a starting point that a project owns. To pretend otherwise would make it a framework.
- **Copier is a Python tool in a two-language platform.** This is accepted under the developer-tooling scope above, and Copier is pinned like every other tool.

## Rules

- Renovate opens every dependency, image, chart, and tool-version update as a pull request. It merges nothing. No update bypasses the gates that a human pull request passes. `(CI: ci:lint, ci:gen, ci:test)`
- Updates are grouped by ecosystem and batched on a schedule. A major version is proposed alone.
- A container image update moves the tag and the digest in the same pull request. A digest is never updated on its own. `(CI: lint:floating-tags)`
- A held-back dependency carries its reason as a comment on the package rule that holds it. A pin with no recorded reason is treated as unreviewed.
- A failing update pull request stays open. The update is never disabled to clear the queue.
- A CVE that Trivy gates on and that has a fixed version available is proposed at once, outside the batch. `(CI: ci:scan)`
- A generated project tracks this template through the Copier answers file and updates by 3-way merge. The template makes no compatibility promise, and the project resolves each conflict.
- The rename runs at generation and at every update. Both renders of an update carry the project's names.
- A project created from this template adopts its own module path, registry namespace, and apex host before its first push. A repository whose name does not match its module path has not been renamed. `(CI: lint:project-identity)`
- Copier and Renovate are pinned in `.mise.toml` like every other tool. Neither runs inside a cluster workload. `(CI: lint:node-scope)`
