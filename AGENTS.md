# Agent guide

This guide is for any coding agent that works in this repo: Codex, Cursor, Claude Code, or another. `AGENTS.md` is the one standard. The repo has no per-tool files such as `CLAUDE.md` or `.cursor/rules/`. A tool that ignores `AGENTS.md` has a limitation, and the repo does not work around it.

## The one rule above this file

**Humans are the first developers. ADRs and `docs/` rank above this file.** Every decision, convention, or rationale lives in an [ADR](docs/adr) or a `docs/` file. Those files are for humans first, are neutral to tools, and are reviewed.

This file holds only operational hints for agents: how to navigate, build, and run the repo, and what to read first. Everything else is a link to the ADRs and docs.

- A line that a new human developer also needs belongs in an ADR or a doc. This file links to it.
- A line that only one tool needs belongs in that tool's own dotfile, not here.

## Write in Simple English

Every text you write in this repo follows the Simple English profile in [ADR-0001](docs/adr/0001-documentation-and-output-conventions.md#simple-english). This covers docs, ADRs, code comments, commit titles, task descriptions, CLI and linter output, API and dashboard descriptions, and UI copy.

- Use common words at CEFR B1. Technical names and technical verbs are always allowed. Keep one term for one concept.
- Write one idea per sentence. A sentence has at most 25 words, or 20 words in `docs/guide/` and numbered steps.
- Use only these punctuation marks in prose: period, comma, colon, and the possessive apostrophe.
- Do not use an em dash, en dash, semicolon, parentheses, `?`, `!`, ellipsis, quote marks, `&`, or `/` for `or`. Use backticks for literal text.
- Do not use `e.g.`, `i.e.`, `etc.`, or contractions such as `don't`.
- Write a citation into the sentence: `..., per [ADR-0204](docs/adr/0204-resource-management.md).` Do not put it in parentheses.

`mise run lint:prose` and `mise run lint:comments` check these rules. Run them before you finish.

## Read first

- [ADR-0000](docs/adr/0000-platform-foundations.md): the thesis, principles, vocabulary, and ADR process. Read it before anything else.
- [docs/adr/README.md](docs/adr/README.md): the block map and the full ADR index, one line for each ADR.
- The [ADR index](docs/adr): every load-bearing decision. Each ADR ends with a flat **Rules** section and has a one-sentence **Decides** line in its header. The index's *Decides* column is the fastest full pass over the set.
- [docs/reference/rules-index.md](docs/reference/rules-index.md): every rule in the set with its enforcement, generated from the Rules sections. One grep covers the whole law.
- [docs/reference/system-view.md](docs/reference/system-view.md): what runs, and how a request moves, on one page.

## What to load first, by task

The set is large, and each task needs a small part of it. Grep the Rules sections listed here before you read any ADR body. What a rule says and why it exists are separate questions.

| Changing | Load | Then check |
| --- | --- | --- |
| A service's behaviour | [0303](docs/adr/0303-api-contracts-and-lifecycle.md) contracts, [0300](docs/adr/0300-data.md) data, [0304](docs/adr/0304-identity-and-authorization.md) authorization, [0500](docs/adr/0500-observability.md) instrumentation | `mise run lint:service-contract`, `lint:authz` |
| An API spec | [0303](docs/adr/0303-api-contracts-and-lifecycle.md), [0003](docs/adr/0003-naming-and-identifiers.md) identifiers | `mise run gen`, then `lint:openapi`, `lint:api-audience` |
| A workflow | [0302](docs/adr/0302-temporal.md), and `docs/reference/long-running-workflows.md` if the workflow runs for a long time | replay tests |
| A chart or values file | [0201](docs/adr/0201-gitops.md), [0204](docs/adr/0204-resource-management.md), [0205](docs/adr/0205-environment-parity.md) | `mise run lint:resource-governance`, `lint:floating-tags` |
| Anything at the edge or about identity | [0305](docs/adr/0305-edge-auth-and-traffic-policy.md), [0306](docs/adr/0306-trust-tiers-and-urls.md), [0304](docs/adr/0304-identity-and-authorization.md) | `mise run lint:auth-inline`, and [docs/reference/threat-model.md](docs/reference/threat-model.md) |
| Frontend code | [0400](docs/adr/0400-frontend.md), [0306](docs/adr/0306-trust-tiers-and-urls.md), and [0700](docs/adr/0700-analytics.md) for anything that emits events | `mise run lint:ts`, `lint:i18n` |
| A screen's design, the brand, or product research | [0701](docs/adr/0701-product-design-and-discovery.md), [docs/brand.md](docs/brand.md) for the token roles, and [docs/guide/designing-a-screen.md](docs/guide/designing-a-screen.md) for the procedure | `mise run lint:contrast`, `lint:i18n`, `lint:ts` |
| Any user-facing copy | [0400](docs/adr/0400-frontend.md) §Localisation and the Simple English profile in [0001](docs/adr/0001-documentation-and-output-conventions.md#simple-english). Every string is a key in `apps/frontend/src/messages/<locale>.json`, and all three catalogues change together | `mise run lint:i18n`, `lint:prose`, `lint:ts` |
| A document, an ADR, or a comment | [0001](docs/adr/0001-documentation-and-output-conventions.md) with its Simple English profile, and `_template.md` for a new ADR | `mise run lint:prose`, `lint:comments`, `lint:adr-xref`, `lint:md` |
| A rule's wording | the owning ADR only. The rules index and the security baseline are generated | `mise run gen`, then `lint:rules-index` |

## How the docs are organised

- **`Rules`** at the end of each ADR are normative and greppable. A rule that a mechanism enforces names it:
  - `(CI: <task>)` is a linter or workflow.
  - `(enforced: <policy>)` is admission control.
  - `(ref: <standard>)` is an adopted external standard.

  A rule with no annotation binds in the same way, but no gate checks it. Treat a `(CI: <task>)` rule as a hard invariant. To check a convention, grep the Rules sections first. Read the full ADR only when you need the reason for a rule.
- **House style** for prose, logs, CLI output, and code comments is [ADR-0001](docs/adr/0001-documentation-and-output-conventions.md). Its Simple English profile follows ASD-STE100. It also adopts ISO 24495-1 plain language, the Google developer-docs voice, OTel semantic conventions for logs, and clig.dev for CLI output. Only the local deltas are normative.
  - Its **banned-constructs table** governs every doc and comment you write: no chronology, no intensifiers, no hedges, no meta-commentary.
  - Every word carries meaning. Three or more items that share two or more attributes are a table.
  - Its **three comment tests** decide whether a comment exists at all. The deletion test: keep a comment only if its absence would cause a wrong change, and doubt resolves to deletion. The genre test: a sentence that is still true without the file belongs in an ADR or a doc, and the comment cites it. The length test: one paragraph of at most three lines, and one line is the norm.
  - The reader is an expert with an LLM at hand, so nothing that the code shows is written down.
- **Genre decides the path**, per [ADR-0001](docs/adr/0001-documentation-and-output-conventions.md). `docs/adr/` holds decisions, `docs/guide/` holds procedures, and `docs/reference/` holds lookups and registries. The `docs/` root holds the entry documents and the registries that an ADR names as canonical. [docs/README.md](docs/README.md) indexes everything. A doc holds a procedure or live state. A decision lives only in its ADR.
- **An ADR is law, not a plan.** It states what is true of this platform, never what someone intends to do. Do not add a `Follow-ups` section, a roadmap, a `TODO`, or a remark such as `not yet wired`. A gap between an ADR and the repo is unfinished work, not an unfinished decision, and the rule binds anyway, per [ADR-0001](docs/adr/0001-documentation-and-output-conventions.md).
- **Planned work goes in a local `*.local.md` file.** `.gitignore` excludes these files, and nothing committed links to them.
  - `PLAN.local.md` is this repo's plan file. Record there any gap you find between a decision and the code.
  - The file can be absent. That is normal, because each engineer keeps their own and it is not tracked.
  - Never create a committed roadmap, backlog, or status file to replace it. Every generated project inherits a tracked plan and then carries someone else's backlog.
  - A `*.local.md` file and its content are private to the engineer who wrote it. Never cite, quote, or reference one in a commit, a doc, a PR description, or any other output. If some of its content is worth keeping, write it again in the ADR or doc where it belongs.
- **Audience.** Every project generated from this repo inherits the ADR set. So write an ADR for the engineer who maintains the platform, not for a person who decides whether to adopt it. Never write `this template targets` or `when not to use this` in an ADR. That is selection guidance, and it belongs in the root `README.md`. Nothing under `docs/` links to that file, because a generated project rewrites it, per [ADR-0001](docs/adr/0001-documentation-and-output-conventions.md).
- **Component tiers and the operational budget** are in [docs/operational-surface.md](docs/operational-surface.md): Core, Scale, and Opt-in. It is also the **only** place where platform components are counted.
- **Before you write a number, ask whether doubling it would change the decision.**
  - If it would, the number is a threshold or a sizing measurement. State it with the conditions it was measured under.
  - If it would not, the number is decoration and goes stale. Write the shape, such as `the platform dominates the footprint`, not the figure.
  - Never count live state that lives elsewhere, such as `the four observability components`, `ten workflows in .github/workflows/`, or `~25 components`. Link to the registry instead, per [ADR-0001](docs/adr/0001-documentation-and-output-conventions.md).

## Working in the repo

- The task runner is `mise`, configured in the root `.mise.toml`. Run a task with `mise run <task>`. `mise run cluster:up` and `cluster:up full` start the local cluster, per [ADR-0600](docs/adr/0600-local-development-loop.md).
- `mise` pins and installs the tools. In a shell where mise is not active, a bare tool call such as `kubectl`, `helm`, `go`, or `bun` comes from `PATH`. That is usually a version in the home folder, and it is not pinned.
  - Activate mise with `mise activate` or its shims before you call a pinned tool by name.
  - `mise run <task>` activates the toolchain for that task only. A bare tool call does not.
- Generated code is committed, and CI checks it for drift, per [ADR-0000](docs/adr/0000-platform-foundations.md) and [ADR-0303](docs/adr/0303-api-contracts-and-lifecycle.md). Regenerate it with `mise run gen`. Do not edit generated files by hand.
- Argo CD reconciles the cluster from `master`. A change in the working tree is not visible in the cluster until someone pushes it, per [ADR-0201](docs/adr/0201-gitops.md).
  - To test uncommitted work on the full tier, pause Argo CD first with `mise run argo:pause`. Resume it with `mise run argo:resume` when you finish.
  - While Argo CD is paused, the cluster stops tracking `master` and gives no warning. Never leave it paused.
- Before you finish a change, run `mise run check` or `mise run pre-commit` to lint, test, and format. `mise run test`, `lint`, and `format` run each step alone.
