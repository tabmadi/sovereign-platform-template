# ADR-0019: Prose, Logging & Output Conventions

- **Status:** Accepted
- **Date:** 2026-07-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0011](0011-observability.md)

## Context

Three output surfaces need a consistent house style so that humans and LLMs read and write the repo the same way: prose
(docs and ADRs), structured logs, and human-facing CLI/script output. Left unspecified, each drifts — scripts mix
symbol vocabularies, logs interpolate context into message strings, docs accrete a house dialect nobody wrote down.

Most of what a house style would say is already a published standard. Re-deriving it from scratch is wasted effort and
produces a worse, unaudited rulebook. The decision is therefore to **adopt the relevant standards by reference and write
only the project-specific deltas.**

## Decision drivers

1. **One style, humans and LLMs alike.** The conventions are the house style an agent needs; they must be greppable and
   unambiguous ([ADR-0000](0000-platform-foundations.md)).
2. **Adopt, don't restate.** Citing a standard beats paraphrasing it — shorter, authoritative, and it passes
   [ADR-0000](0000-platform-foundations.md)'s "don't restate what a standard already says" bar.
3. **Symbols are for humans, never for machines.** The dividing line runs through every surface below.

## Decision

Adopt four external standards as the house style, and make normative only the project-specific deltas.

| Surface | Adopted standard (reference) | Project delta (normative here) |
|---|---|---|
| Prose / docs | [Google Developer Documentation Style Guide](https://developers.google.com/style) (voice: second person, present tense, active) + [Diátaxis](https://diataxis.fr) for doc structure | project terminology; the `ADR-XXXX` citation rule; the template docs-style rules below |
| Structured logs | [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/) (attribute names, severity) + RFC 5424 (severity ladder) + [12-Factor §XI](https://12factor.net/logs) (logs are a stdout event stream) | reaffirm [ADR-0011](0011-observability.md); no symbols in structured logs; context as attributes, never string interpolation |
| CLI / human stdout | [clig.dev](https://clig.dev) (human-first output; color/symbol use; stderr vs stdout) + GNU Coding Standards / POSIX Utility Conventions (exit codes, `--help`/`--version`) | the fixed `→ / ✓ / ✗ / ⚠` step vocabulary and 2-space sub-detail indent |
| Code comments | [Effective Go](https://go.dev/doc/effective_go) + [Go Code Review Comments](https://go.dev/wiki/CodeReviewComments) (Go); [Google Style Guides](https://google.github.io/styleguide/) (TS) | "why, not what"; present tense; cite `ADR-XXXX` when load-bearing |

### Structured logs

Machine-read logs (`slog`, `pino`) carry no symbols and no punctuation-decorated prose. The message is a short lowercase
phrase; all context is key-value attributes following OTel semantic conventions, never interpolated into the message
string. This is [ADR-0011](0011-observability.md) restated as a Rule, not a new decision.

### Human CLI / script output

Scripts speak a fixed four-symbol vocabulary so their output scans identically everywhere:

- `→` a step is starting
- `✓` a step succeeded
- `✗` a fatal error
- `⚠` a warning (never bare `WARN`)
- two-space indent for sub-detail under a step

This vocabulary is the one genuinely project-specific piece: there is no written standard for TUI symbols (the
checkmark/arrow idiom is convention-by-imitation of npm/pnpm/cargo/kubectl), so clig.dev is cited for the *principle*
and the vocabulary is fixed here. An optional `scripts/lib/log.sh` (`step`/`ok`/`fail`/`warn`) implements it; it is
formatting, not error-swallowing, so it is compatible with the "explicit scripts, no magic" rule.

### Template docs are final-state facts

**Scope: this rule governs this template repository's own `docs/` only, not a project generated from it.** A generated
project is a living system where ADR history, `Supersedes`/`Amends`, `Proposed → Accepted`, and real authored dates are
legitimate and expected. The following applies to the template's starting snapshot:

- **No change-history or evolution narrative.** State each decision as a standing fact plus its rationale; never its
  chronology ("we dropped X", "previously", "originally", "now prefer").
- **No `Supersedes` / `Amends` chains between ADRs.** Every ADR is simply current. When one needs to change, rewrite the
  target in place to its final state.
- **No `Proposed → Accepted` progression as visible history.** A shipped ADR reads `Accepted`.
- **Uniform day-one date** across the ADR set, so it reads as one design, not artifacts accreted over months.
- **Prefer a full rewrite over patching.** An ADR that changes is rewritten end-to-end in one voice. The whole set
  reads as if one author wrote it in one sitting; a patched-in paragraph that clashes in voice is a defect even if
  factually correct.

### Enforcement

Each Rule is annotated with how it is enforced, so an agent knows a hard invariant from an aspiration: `(CI: <lint>)`
for a linted rule, `(review-only)` for a human-reviewed one, `(ref: <standard>)` for an adopted standard that this repo
does not itself lint.

## Consequences

### Positive

- The conventions are mostly links to authoritative standards, so they are short and hard to argue with.
- "Follow OTel semconv / clig.dev / Google" is a single instruction an LLM can act on without a bespoke rulebook.
- The docs-style rules keep the template's ADR set readable as one coherent document.

### Negative / Risks

- Adopted standards evolve upstream; a citation can drift from what the repo actually does. Mitigated by only making the
  *deltas* normative and treating the standards as reference.
- The four-symbol CLI vocabulary is enforced by review until `scripts/lib/log.sh` and a lint exist.

### Follow-ups

- `docs/*/conventions.md` stubs that link the adopted standards and list the project deltas.
- Optional `scripts/lib/log.sh` (`step`/`ok`/`fail`/`warn`) and a lint for the symbol vocabulary.
- `AGENTS.md` points at this ADR and the adopted-standard links as the house style.

## Rules

- Structured logs carry a lowercase message with no trailing punctuation and **no symbols**; context is key-value
  attributes following OTel semantic conventions, never string-interpolated. `(review-only; ref: OTel semconv)`
- Human CLI/script output uses the fixed vocabulary `→` step, `✓` success, `✗` fatal, `⚠` warning, with two-space
  sub-detail indent. Bare `WARN`/`ERROR` prose and ad-hoc symbols are not used. `(review-only; ref: clig.dev)`
- Prose follows the Google developer-docs voice (second person, present tense, active) and is organised by Diátaxis
  genre (tutorial / how-to / reference / explanation; ADRs are decision records). `(ref: Google dev-docs, Diátaxis)`
- Code comments explain *why*, not *what*, in present tense, and cite `ADR-XXXX` when load-bearing. `(review-only)`
- Template docs are final-state facts: no change-history, no `Supersedes`/`Amends` chains, no `Proposed → Accepted`
  narrative, a uniform day-one date, and full-rewrite-over-patch. **`(scope: template repo only)`** — a generated
  project keeps honest ADR history. `(review-only)`
- Every ADR Rule is annotated with its enforcement: `(CI: <lint>)`, `(review-only)`, or `(ref: <standard>)`. `(review-only)`
