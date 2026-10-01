# ADR-0001: Documentation and Output Conventions

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0002](0002-tool-adoption.md), [ADR-0500](0500-observability.md)
- **Decides:** Every text uses Simple English on the ASD-STE100 model, and adopts ISO 24495-1, the Google developer style, OTel log conventions, and clig.dev.

## Context

This repository has five surfaces with written language: ADRs and docs, structured logs, human CLI output, code comments, and UI copy. Humans and LLMs read all of them. Many human readers do not speak English as a first language.

Without a written style, each surface grows its own dialect. Scripts invent symbols. Logs put context into message strings. Docs use long sentences and rare words. Comments repeat the code beside them.

Most of a house style is already published. A new rulebook that repeats it is longer and nobody checks it.

## Decision drivers

1. **One style for humans and LLMs.** A rule is a closed list or a limit that a linter checks. A rule is never a matter of taste.
2. **A reader with B1 English reads every text.** The platform has an international audience, and a misread rule is applied wrongly.
3. **Technical meaning stays exact.** A simple word never replaces a technical term with a different meaning.
4. **Adopt, do not restate.** A citation is shorter than a paraphrase, and a borrowed rule is harder to argue with than a house rule.
5. **Density is a correctness property.** A reader who skims a long ADR applies it wrongly.
6. **Symbols are for humans, never for machines.**

## Considered options

| Option | Coverage | Maintenance | Why not |
| --- | --- | --- | --- |
| No written style | none | none | Each surface gets its own dialect, and a reviewer has no basis to call a PR wrong |
| Write a complete house style guide | total | high: a second standards body to run | It repeats Google, OTel, and clig.dev at lower quality and drifts from them |
| Plain language only, ISO 24495-1 | prose | low | It states outcomes, not limits. Nothing in it is checkable, so long sentences and rare words stay |
| Full ASD-STE100 with its dictionary | prose | high | The dictionary has about 900 words and one meaning each. Platform reasoning needs more general words than that |
| **Adopt standards by reference, add a Simple English profile on the ASD-STE100 model, make only the deltas normative** | total | low: the deltas are short and a linter checks most of them | **Chosen** *(reasoned)* |
| Adopt [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174) keywords for Rules | normative strength | low | Its `SHOULD` and `MAY` levels invite negotiation. Every Rule here binds. The enforcement annotation carries strength instead |

## Decision

### Adopted standards

| Surface | Adopted standard | Local delta, normative |
| --- | --- | --- |
| Prose and docs | [ASD-STE100](https://www.asd-ste100.org) Simplified Technical English, as a model. [ISO 24495-1:2023](https://www.iso.org/standard/78907.html) plain language. [Google Developer Documentation Style Guide](https://developers.google.com/style): present tense, active voice. [Diátaxis](https://diataxis.fr) genres | the Simple English profile, the density rules, and the banned constructs below. `ADR-XXXX` citation form. Final-state facts. Second person scoped by genre |
| ADR structure | [MADR](https://adr.github.io/madr/) section set | the fixed section order below. A comparison table is mandatory, per principle 7 of [ADR-0000](0000-platform-foundations.md) |
| Structured logs | [OTel Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/). [RFC 5424](https://www.rfc-editor.org/rfc/rfc5424) severity | no symbols. Context goes in attributes and is never interpolated |
| CLI and human stdout | [clig.dev](https://clig.dev). POSIX Utility Conventions: exit codes, `--help`, `--version` | the fixed `→ ✓ ✗ ⚠` vocabulary and a 2-space indent for sub-detail |
| Code comments | [Effective Go](https://go.dev/doc/effective_go), [Go Code Review Comments](https://go.dev/wiki/CodeReviewComments). [Google Style Guides](https://google.github.io/styleguide/) for TypeScript. [Fowler, *Refactoring*](https://martinfowler.com/books/refactoring.html) for the Comments smell | the Simple English profile, the three tests, and the survivor grounds below |
| UI copy | the Simple English profile | every string is a key in the message catalogues, per [ADR-0400](0400-frontend.md) |

Diátaxis classifies an ADR as **explanation plus reference**. An ADR is not a tutorial and not a how-to. It records a decision and its constraints. It never walks a reader through a task.

### Simple English

Every text in this repository uses Simple English. This covers docs, ADRs, comments, commit titles, task descriptions, CLI and linter output, API descriptions, dashboard descriptions, and UI copy.

The profile follows ASD-STE100. STE is a controlled language for technical text read by people with limited English. It keeps general words simple and permits the technical words of the field. This profile takes its writing rules and replaces its fixed dictionary with a CEFR B1 word level.

#### Words

| Rule | Bad | Good |
| --- | --- | --- |
| General words are at CEFR B1. Use the most common word for the meaning | `utilize`, `leverage`, `facilitate`, `prior to`, `in order to`, `hence` | `use`, `use`, `help`, `before`, `to`, `so` |
| Technical names and technical verbs are always allowed, as in STE rule 1.1. A technical term is never replaced with a general word that changes its meaning | `sync the cluster` for Argo CD's reconcile | `Argo CD reconciles the cluster` |
| One term names one concept everywhere. [ADR-0000](0000-platform-foundations.md) holds the vocabulary | `tenant` in one ADR and `org` in the next for the same thing | the ADR-0000 term in both |
| A word has one meaning. It is not used in a second sense | `the floor` as the platform minimum and as a number rounded down | `the floor` for the minimum only |
| A single verb replaces a phrasal verb when one exists. A phrasal verb that is the technical name stays | `kick off`, `figure out`, `carry out` | `start`, `find`, `do`. `set up` and `roll back` stay |
| No idioms. Figurative language is limited to the ADR-0000 vocabulary | `a moving target`, `under the hood`, `out of the box` | `changes often`, `inside`, `by default` |
| No abbreviations of Latin phrases | `e.g.`, `i.e.`, `etc.`, `vs.` | `for example`, `that is`, a complete list, `or` |
| No contractions | `don't`, `it's`, `can't` | `do not`, `it is`, `cannot` |

#### Sentences

| Rule | Limit |
| --- | --- |
| One idea per sentence | one main clause, and at most one dependent clause |
| Sentence length in descriptive text: ADRs, reference, comments, output | 25 words |
| Sentence length in procedures: `docs/guide/` and numbered steps | 20 words, as in STE rule 5.1 |
| Voice and tense | active voice, present tense |
| Three or more parallel items or steps | a list, not a sentence |
| A procedure step | one instruction, starting with the verb |

A table cell, a list item, and a heading each count as separate text. A code span counts as one word.

#### Punctuation

Prose uses a closed set. Anything not in the allowed row is banned.

| Status | Marks |
| --- | --- |
| Allowed | period `.`, comma `,`, colon `:`, apostrophe for the possessive `the platform's` |
| Banned | em dash, en dash, semicolon, parentheses, `?`, `!`, ellipsis, quote marks, `&`, and `/` in the sense of `or` or `and` |

The banned marks have a standard replacement:

| Instead of | Write |
| --- | --- |
| An em dash or a semicolon that joins two clauses | two sentences, or a colon when the second part explains the first |
| An em dash or parentheses around an aside | a separate sentence, or delete the aside |
| A citation in parentheses, `(ADR-0204)` | a link in the sentence: `[ADR-0204](0204-resource-management.md) sets the limit.` or `The limit is 2 GiB, per [ADR-0204](0204-resource-management.md).` |
| An en dash in a number range | `1 to 5` |
| A question | the answer, as a statement |
| Quote marks around literal text | backticks. Emphasis uses bold or italics |
| `and/or`, `A / B` | `A or B`, `A and B`, or a list |
| `&` | `and` |

These are not prose, and the punctuation rules do not apply to them:

- Markdown syntax: links, images, tables, emphasis, headings, and HTML comments.
- Code spans, code fences, paths, URLs, identifiers, and call syntax such as `run()`.
- A hyphen inside a word: `read-only`, `per-service`.
- The enforcement annotations `(CI: <task>)`, `(enforced: <policy>)`, and `(ref: <standard>)`.
- The CLI symbols `→ ✓ ✗ ⚠`.
- A text adopted verbatim from a third party, such as `CODE_OF_CONDUCT.md`.

A translated UI string follows the meaning of the English string and the same banned marks, including the locale's own forms: guillemets, German low quotes, and the Arabic-script question mark and semicolon.

**The em dash, en dash, ellipsis, and curly quotes are banned in every tracked text file, code included.** They have no use in code, and a copy-paste from prose is the only way they arrive.

### Genre decides the path

Diátaxis organises the tree, not only the prose. A reader learns a document's genre from its path before opening it. A document that fits no genre has no settled purpose.

| Path | Genre | Holds |
| --- | --- | --- |
| `docs/adr/` | explanation and reference | one decision per file |
| `docs/guide/` | how-to | a procedure someone executes |
| `docs/reference/` | reference | a lookup, a registry, or live state |
| `docs/*.md` | entry, and canonical registries | the ordered way in, and the documents this set cites by name as the only record of a fact |

**The root is not a genre and not a default.** A file sits at `docs/` only as the set's entry point or as a registry an ADR names as canonical. The registries are [`operational-surface.md`](../operational-surface.md) for components, [`adoption-path.md`](../adoption-path.md) for the reduction order, and [`tool-register.md`](../tool-register.md) for tools, per [ADR-0002](0002-tool-adoption.md). Every other file takes a genre directory.

**Topic lives in the filename.** A directory that holds one file groups nothing. Four documents all called `runbook.md` are four files a search cannot separate. The name states the subject and the directory states the genre, so `guide/secrets-runbook.md` is both, with no nested tree.

A generated document names its generator in a comment on its second line, and nobody edits it by hand. Examples are [`security-baseline.md`](../security-baseline.md) and [`reference/rules-index.md`](../reference/rules-index.md).

**Second person follows the genre, not the repository.** Google's *you* addresses a person who performs a task. That is the voice of tutorials and how-to guides, such as `docs/dev-loop.md` and `docs/guide/break-glass.md`. An ADR addresses nobody. Its subject is the platform, and its rules read as law: *deployments reference images by digest*, never *you reference images by digest*.

### ADR structure

Sections appear in this order. A section with nothing to say is omitted, not filled.

| # | Section | Contains |
| --- | --- | --- |
| 1 | Header | Status, Date, Deciders, Related, Decides |
| 2 | Context | The problem and the constraints from earlier ADRs |
| 3 | Decision drivers | The properties the decision optimises for, in priority order. See *A driver is a property, not an answer* |
| 4 | Considered options | A comparison table of the alternatives. Mandatory, per principle 7 of [ADR-0000](0000-platform-foundations.md) |
| 5 | Decision | Declarative statements: `We use X. We do not use Y.` |
| 6 | Consequences | Positive, and Negative and Risks. No `Follow-ups`. See *An ADR is law, not a plan* |
| 7 | Rules | Flat, greppable, normative bullets that follow from the decision |

**The header's `Decides` line is one sentence. It is the fast way to read the set.** Every sentence in a dense ADR carries meaning, so nothing in the body can be skipped. One declarative line per ADR gives a fast read without making the body less exact. The [index](README.md) carries the same line in its *Decides* column. The line states what is true of the platform, never what the document contains: *Go is the backend language and TypeScript the frontend one*, not *chooses the languages*.

The comparison table uses text cells, and every option answers the same questions. It is not a scoring grid. The trade-offs are qualitative, and numeric scores make a false precision. [ADR-0002](0002-tool-adoption.md) owns the table's depth and the grade that its decisive cells carry.

[ADR-0000](0000-platform-foundations.md) is the one exception. It chooses no technology, so it has no options to compare and no single decision. It holds the thesis, principles, process, prior art, and vocabulary. Every other ADR uses the order above.

### A driver is a property, not an answer

A driver states the property that the decision optimises for. A reader who does not know the outcome can apply the driver and reach one.

Two failures make a driver useless. Both look like reasoning:

| Failure | Example | Instead |
| --- | --- | --- |
| **The driver names its own answer** | `One repo-wide release version, because the repo ships as a unit` | `The unit of versioning is the unit of shipping`. This is the property, and the version line follows from it |
| **The driver describes the loser at its worst** | `Keyless over key management. A team this size should not operate a signing-key HSM`, when the alternative was a key in the existing secret store | State the property. The option then loses on what it is |

With either failure, the Considered options table cites a driver that was written to reject the loser. That argument is circular, but it looks rigorous.

The test: swap the chosen option for a rejected one and read the drivers again. If the drivers now sound wrong, not unmet, they describe the answer and not the problem.

### An ADR is law, not a plan

An ADR states what is true of this platform. It never states what someone intends to do. **`Deployments reference images by digest` is law. `Wire the digest check into CI` is a task.** Both describe something absent from the repo. The difference is where the obligation sits.

| An ADR's Rule | A working-file task |
| --- | --- |
| Holds for as long as the ADR stands | Completes, and is then deleted |
| Code violates it | An empty repo leaves it *unmet*, which is not a violation |
| Binds every reader, including a generated project | Binds one person in one repo |
| A reviewer cites it to reject a PR | A reviewer cannot cite it |

**Planned work is not part of the committed record.** Every generated project inherits a tracked plan and then carries someone else's queue. As per-engineer state, a tracked plan also turns one person's backlog into everyone's merge conflict. A task belongs in the forge's issues, per [ADR-0102](0102-source-control-and-ci.md). There it has an assignee and a close condition.

So a committed document states the platform as it is. It does not mark a rule with its progress. It does not link to a working file, because that link works in one clone and breaks in every other.

### Density

An ADR is a dense technical document. Every word carries meaning, or it is deleted.

| Rule | Test a reviewer applies |
| --- | --- |
| One idea per sentence | The sentence has one main clause |
| Delete what survives deletion | Remove a clause. If the meaning does not change, it stays removed |
| Table over prose | Three or more items that share two or more attributes become a table |
| Bullets over prose | Three or more parallel items become a list |
| Paragraphs are short | A paragraph over about 60 words becomes a list or a table |
| No restatement | A fact appears in exactly one ADR. Everywhere else it is a link |
| Figurative language is limited to the [ADR-0000](0000-platform-foundations.md) vocabulary | Any other metaphor, analogy, or wordplay is cut |

Simple English and density do not conflict. A shorter sentence with common words carries the same facts. A longer text is accepted only where the simpler sentence needs it.

### Numbers

A number is stated when the number **is** the decision. One test settles it:

> **If this number doubled, the decision would change.** When that is true, state the number.

| Test result | Kind | Example | Treatment |
| --- | --- | --- | --- |
| True | **Threshold** | `a restore rehearsal over half the RTO`, `funnel-query p95 above 2s` | Stated. A change to it is a reviewed act |
| True | **Measurement that set a value** | Tempo's measured peak, which sets its explicit limit, per [ADR-0204](0204-resource-management.md) | Stated in the ADR that decides, **with its conditions and how to measure it again**, and graded *(measured)*. Never repeated in a comment beside the value. The figure comes from this platform's hardware and load. An inheriting project would read a number that was never about its cluster |
| True | **Count of what is on the page** | `the six forces below` | Stated. The reader checks it against the table beside it |
| False | **Illustrative figure** | a footprint quoted to show that the platform dominates | **Not stated.** State the shape: `the platform dominates the footprint` |
| False | **Count of live state elsewhere** | `~25 always-on components`, `ten workflows under .github/workflows/` | **Not stated.** Name the thing and link to its registry |

The last two go stale. Nothing forces an update, and a figure without a date reads as current. A reader then draws a conclusion that is no longer true. A count of components, files, ADRs, or services belongs to the registry that owns them. [`docs/operational-surface.md`](../operational-surface.md) owns platform components, and [`README.md`](README.md) owns the ADR set.

### Versions

**A tool's release version is not stated.** A dependency upgrade must not need an ADR edit. A version in prose goes stale without notice, while the lockfile that contradicts it stays correct. The pin lives where a machine reads it: a lockfile, `.mise.toml`, or the chart that installs the tool.

Three kinds of number look like a tool version but are not:

| Stated | Kind | Example |
| --- | --- | --- |
| Yes | **A specification or format version** | OpenAPI 3.1, OCI 1.1, UUIDv7, RFC 9562. It names the contract that an option is judged against, not the implementation |
| Yes | **A licence identifier** | Apache-2.0, BUSL 1.1. The number is part of the licence's name |
| Yes | **A capability boundary that the decision depends on** | `the referrers API arrived in Distribution's 3.x line`. It is stated as a **floor**, never a pin, so a later release keeps the sentence true |

Every other version is the tool's own business. A capability is described by what it does: `Forgejo mints per-job OIDC tokens for Actions`. That stays true across upgrades. `Forgejo v15.0 LTS does` stops being the reason anyone reads the line.

The argument almost never needs the figure. `A floor of a couple of dozen components, fixed for any service count` carries the same weight as an exact count and does not go stale. A load-bearing figure is a threshold, or it states its conditions and where to measure it again.

### Banned constructs

| Banned | Example from this repo | Write instead |
| --- | --- | --- |
| **Chronology**: how the decision came to be | `It has since grown into a good workload directory` | The standing fact: what it is now |
| **The former state** | `Today this is done with psql, curl, and Temporal` | The problem, with no date |
| **Discovery narrative** | `it turned out to be exactly the floor plus the mock` | `It is the floor plus the mock` |
| **Retrospection about the ADR set** | `ADR-NNNN did not previously cover` | Cover it, without comment |
| **Intensifiers** | `very`, `really`, `quite`, `actually`, `simply`, `just`, `of course`, `obviously`, `clearly` | Delete it. A claim that needs an intensifier is not established |
| **Hedges** | `arguably`, `essentially`, `basically`, `more or less`, `in practice` | Decide. A hedge is an unfinished decision, per [ADR-0000](0000-platform-foundations.md) |
| **Meta-commentary** | `It is worth knowing`, `Note that`, `It should be noted` | State the thing |
| **Questions** | `But is the pod actually running the new code?` | The answer, as a statement |
| **Dated section headings** | `## Implementation, 2026-07-26` | A heading with no date |
| **Planned work**: a `Follow-ups` list, a `TODO`, a roadmap | `tools/lint-prose for the intensifier and hedge lists` | Nothing. State the law and stop. A task belongs in an issue |
| **The implementation's status** | `tracked in`, `not yet wired`, `lands in a later phase`, `the status quo`, a count of what exists so far | The rule, with no qualifier. Whether the artefact exists is not the ADR's subject. An option loses on its merits, not because it is what runs today |
| **A link to an untracked file** | `[plan.md](plan.md)` | Nothing. The file is absent from every other clone |

A documentation PR can always delete a word, with no other reason.

### Line breaks and tables

**Markdown is not hard-wrapped.** Each paragraph, list item, or table row is one line. A line ends only where the content ends. `MD013` is disabled in `.rumdl.toml` for this reason.

**Tables are compact, never padded.** Each pipe has one space inside it, and the delimiter is a bare `---` for any column width. `MD060` enforces it, and `mise run format:md` applies it.

Both rules protect the diff. A reflowed paragraph or a wider column rewrites every line after it. A one-word edit then shows as a whole-file change, and a reviewer cannot see what changed. Padding must also be redone by hand on each edit. A wrap column is a personal choice, and a repo without this rule ends up with three of them.

The reader chooses their own line length. Editors and renderers both soft-wrap.

### Structured logs

The message is a short lowercase phrase with no final punctuation and no symbols. All context goes in key-value attributes that follow the OTel semantic conventions. Context is never interpolated into the message string. This restates [ADR-0500](0500-observability.md) as a Rule. It is not a second decision.

### Human CLI output

Scripts use a fixed vocabulary of four symbols:

| Symbol | Means |
| --- | --- |
| `→` | a step starts |
| `✓` | a step succeeded |
| `✗` | a fatal error |
| `⚠` | a warning. Never a bare `WARN` |

Sub-detail under a step has a two-space indent.

No written standard fixes these symbols. The checkmark and arrow style copies npm, cargo, and kubectl. clig.dev is cited for the principle, and this ADR fixes the vocabulary. `scripts/lib/log.sh` implements it with `step`, `ok`, `fail`, and `warn`. It only formats and never swallows an error.

The text after a symbol follows the Simple English profile.

### Code comments

The Simple English profile, the density rules, and the banned constructs all apply to comments in Go, TypeScript, shell, YAML, and TOML. SQL comments follow the Simple English profile.

**The reader is an expert with an LLM at hand.** The code shows what it does, how it is structured, and why a shape is idiomatic. A comment carries only what neither the code nor the ADR set shows. Depth is the job of the docs and of the reader.

The first step is always to change the code instead. Fowler states it in the Comments smell of [*Refactoring*](https://martinfowler.com/books/refactoring.html): *whenever we feel the need to comment something, we write a method instead*. A name carries the explanation to every call site and cannot fall out of step with what it names.

Three tests decide every comment that survives that step. A comment that fails one test is deleted.

| Test | What it asks | What fails it |
| --- | --- | --- |
| **Deletion** | Without it, would a reader make a wrong change | A comment that makes a reader faster but does not change what they would do. Doubt resolves to deletion |
| **Genre** | Would the sentence still be true if this file were deleted | A decision, a procedure, or a lookup. It belongs in an ADR, `docs/guide/`, or `docs/reference/`, and the comment cites it |
| **Length** | Is it one paragraph of at most three lines | A second paragraph, which is a document. One line is the norm |

A comment survives on one of five grounds:

- an external system's behaviour that its own documentation omits or contradicts
- a constraint that an ADR owns and the code cannot express, cited as `ADR-XXXX`
- an ordering or timing dependency that the call site does not show
- a deliberate omission: something a reader would otherwise add back
- on an exported identifier: units, nil values, bounds, side effects, or error conditions

An exported identifier gets a doc comment only when the comment states a fact that the signature cannot. A doc comment that restates the signature is deleted. A doc comment is in present tense and full sentences. In Go it starts with the identifier's name.

| Banned | Reason |
| --- | --- |
| A comment that explains confusing code | It is a defect. Rewrite the code, as [Kernighan and Plauger](https://en.wikipedia.org/wiki/The_Elements_of_Programming_Style) state: do not comment bad code, rewrite it |
| A comment about a state that a later edit makes false: a placeholder to swap, a step for day one | The value already states it. Once the value changes, the comment is not stale but wrong |
| A comment that teaches a third-party tool what its own documentation teaches | The reader is an expert with an LLM at hand |
| A comment that restates a convention the path, file name, or identifier carries | The structure is the statement |
| Commented-out code | Git holds it |
| Changelog, author, or date comments | Git holds them |
| Decorative banners and section dividers | The file structure is the structure |
| A `TODO` with no issue or ADR behind it | An uncited `TODO` is the temporary state that [ADR-0000](0000-platform-foundations.md) forbids |

**No comment count is enforced.** A count or density limit cannot tell a grounded comment from a weak one. To meet it, an author deletes the newest comment, not the weakest. Deleting code also raises the density. The rules above judge each comment on its own grounds, and a linter names the one that fails.

### Template docs are final-state facts

**Scope: the `docs/` of this template repository only.** A project generated from it is a living system. There, ADR history, `Supersedes` and `Amends`, `Proposed → Accepted`, and real dates are correct.

**Every generated project inherits the ADR set.** The project clones it, and it becomes that project's own record. So an ADR is written for the engineer who maintains the system, never for a person who decides whether to adopt it. The consequences:

- **The subject is `this platform`, not `this template`.** Some text reads correctly only in this repo: *we build a template*, *when not to use this*, *who should adopt this*. That is selection guidance for a reader who has not decided. It belongs in the root `README.md`. The ADR states the chosen position.
- **`template` names an artefact, not the audience.** `services/_template/` and *the template default* are correct in any repo. *This template targets* is not.
- **No doc under `docs/` links to the root `README.md`.** A generated project rewrites or deletes that file, so a link into it breaks and its facts disappear. The ADR set itself states every term, test, and table that an ADR depends on.
- **The overlap between the README and the ADRs is expected.** It does not violate one-fact-one-place, which governs the ADR set. The README restates for a reader who has not decided. The ADR states for the engineer who owns the result. Deleting from the ADR to remove the overlap is the wrong direction.

The template's snapshot follows these rules:

- **No change history or evolution narrative.** Each decision is a standing fact and its rationale, never its history.
- **No `Supersedes` or `Amends` chains.** Every ADR is current. An ADR that must change is rewritten in place.
- **No `Proposed → Accepted` progression.** A shipped ADR reads `Accepted`.
- **One date across the set**, so the set reads as one design, not as layers added over time.
- **Full rewrite over patch.** A patched paragraph in a different voice is a defect, even when it is correct.

### Numbering

ADR numbers come in blocks of a hundred, one block per layer, in sequence inside the block. The first two digits carry the layer, so a new ADR enters its block without renumbering the set. [`README.md`](README.md) holds the block map.

### Enforcement annotations

A Rule that a machine can check names the mechanism, so a reader can find and read the check.

| Annotation | Means |
| --- | --- |
| `(CI: <task>)` | a named `mise` task rejects the violation. The annotation names the task, never the workflow file that calls it. [ADR-0102](0102-source-control-and-ci.md) makes the task the portable name and the workflow a thin caller |
| `(enforced: <policy>)` | admission control rejects it in the cluster, and CI cannot bypass that |
| `(ref: <standard>)` | the adopted external standard is the rule |

**A Rule with no annotation is not a weaker Rule.** The annotation points to a mechanism. It is not a status report. No annotation means only that no gate names the rule. That is the normal case, and it is why a human reads a diff. A human-enforced marker would put the build state of a check inside the law, which *An ADR is law, not a plan* forbids.

The named mechanism is one the ADR set decides on. A task or policy that no decision names and the repo does not have is a wish, not an annotation, and it is left off.

## Consequences

### Positive

- A reader with B1 English reads every text in the repository, and an LLM gets closed lists and limits, not taste.
- Technical terms stay exact, because the profile limits general words and not technical ones.
- A linter checks the punctuation, length, and word rules, so the style does not drift.
- The conventions are mostly links, so they are short and hard to argue with.
- `Follow OTel semconv, clig.dev, and Google` is one instruction an LLM acts on without a custom rulebook.
- The banned-constructs table gives a reviewer a mechanical reason to reject prose. A citation replaces taste.
- The density rules limit ADR length, which limits the cost for every later reader.

### Negative and Risks

- Some ideas need two or three short sentences where one long sentence was used before. Accepted: the reader reads faster and misreads less.
- No linter can check the B1 word level completely. The linter checks a list of common complex words, and a reviewer checks the rest.
- Upstream standards change, and a citation can drift. Only the deltas are normative, which limits this.
- A person, not a task, reads most of these rules. The banned-constructs list is written to be grep-shaped, so a linter is an addition, not a redesign.
- Short prose can lose nuance. Accepted: nuance that matters becomes a table row, and nuance that does not is deleted.

## Rules

- Prose follows the Google developer-docs voice, present tense and active, and ISO 24495-1 plain language, organised by Diátaxis genre. An ADR is explanation plus reference, never a tutorial. `(ref: Google dev-docs, ISO 24495-1, Diátaxis)`
- Every text in the repository uses the Simple English profile: docs, ADRs, comments, task descriptions, CLI and linter output, API and dashboard descriptions, and UI copy. `(ref: ASD-STE100)`
- General words are at CEFR B1, with the most common word for the meaning. Technical names and technical verbs are always allowed, and are never replaced with a general word that changes the meaning.
- A word from the complex-word list is replaced with its simple form: `utilize` and `leverage` become `use`, `facilitate` becomes `help`, `prior to` becomes `before`, `in order to` becomes `to`, `hence` and `thus` become `so`. `(CI: lint:prose, lint:comments)`
- One term names one concept across the set, and a word keeps one meaning. [ADR-0000](0000-platform-foundations.md) holds the vocabulary.
- A single verb replaces a phrasal verb when one exists. No idioms.
- Latin abbreviations and contractions are not used: no `e.g.`, `i.e.`, `etc.`, or `vs.`, and no `don't` or `it's`. `(CI: lint:prose, lint:comments)`
- A sentence has one idea and at most 25 words. A sentence under `docs/guide/` or in a numbered procedure has at most 20 words. `(CI: lint:prose, lint:comments)`
- Prose punctuation is period, comma, colon, and the possessive apostrophe. The em dash, en dash, semicolon, parentheses, `?`, `!`, ellipsis, quote marks, `&`, and `/` in the sense of `or` are not used in prose. Markdown syntax, code, paths, URLs, and enforcement annotations are not prose. `(CI: lint:prose, lint:comments)`
- The em dash, en dash, ellipsis, and curly quotes appear in no tracked text file, code included. A text adopted verbatim from a third party is exempt. `(CI: lint:prose)`
- A translated UI string carries the meaning of the English string and follows the same punctuation rules, including the locale's own forms. `(CI: lint:prose)`
- Second person is the voice of the tutorial and how-to genres. An ADR addresses no reader: it states what is true of the platform, and its Rules read as law, not as instructions.
- Every word carries meaning. A clause whose deletion does not change the meaning is deleted.
- Three or more items that share two or more attributes are a table. Three or more parallel items are a list.
- Intensifiers, hedges, meta-commentary, questions, and chronology are not used in template docs. `(CI: lint:prose)`
- Figurative language is limited to the [ADR-0000](0000-platform-foundations.md) vocabulary.
- A number is stated only if doubling it would change the decision: a threshold, a measurement that set a value, or a count of what is on the same page. An illustrative figure becomes the shape it shows. A count of live state elsewhere becomes a link to its registry.
- A tool's release version is not stated. A specification version, a licence identifier, and a capability boundary stated as a floor are not tool versions. The pin lives in the lockfile, `.mise.toml`, or the chart.
- A fact appears in exactly one ADR. Every other mention is a link.
- Markdown is not hard-wrapped: one line per paragraph, list item, or table row. `(CI: lint:md)`
- Tables are compact, never padded: one space inside each pipe and a bare `---` delimiter. `(CI: lint:md)`
- An ADR uses the section order Context, Decision drivers, Considered options, Decision, Consequences, Rules, and omits an empty section instead of padding it.
- An ADR's header carries a one-sentence `Decides` line that states what is true of the platform because of the ADR. The ADR index carries that line in its *Decides* column. `(CI: lint:adr-xref)`
- A decision driver states a property to optimise for. It never restates the chosen option and never describes a rejected option at its worst. With the winner swapped for a loser, the drivers are unmet, not wrong.
- An ADR states standing law, never planned work. No `Follow-ups` section, no roadmap, no `TODO`, and no note on whether an artefact exists yet.
- Planned work belongs in the forge's issues, never in a committed document. No committed file links to an untracked one. `(CI: lint:md, lint:prose)`
- ADR numbers come in blocks of a hundred by layer, per [`docs/adr/README.md`](README.md).
- A document's genre decides its directory: `docs/adr/` for decisions, `docs/guide/` for procedures, `docs/reference/` for lookups. The `docs/` root holds the set's entry documents and the registries an ADR names as canonical, and nothing else. `(CI: lint:adr-xref)`
- The filename carries the topic, never a directory that holds a single file. No two documents in `docs/` share a filename. `(CI: lint:adr-xref)`
- Structured logs carry a lowercase message with no final punctuation and no symbols. Context is in OTel-conventioned attributes, never interpolated into the string. `(ref: OTel semconv)`
- Human CLI output uses `→` for a step, `✓` for success, `✗` for a fatal error, and `⚠` for a warning. Sub-detail has a two-space indent. Bare `WARN` or `ERROR` text and other symbols are not used. `(ref: clig.dev)`
- The first answer to the need for a comment is to extract a named method. `(ref: Fowler, Refactoring)`
- A comment carries only what an expert reader cannot derive from the code and the ADR set. Doubt resolves to deletion. `(CI: lint:comments)`
- A comment does not state a measurement of this platform's own workload. The ADR that decides states it. The code states the shape the value was chosen for.
- A comment is one paragraph of at most three lines. One line is the norm. `(CI: lint:comments)`
- A fact that outlives the file it describes is an ADR or a doc, and the comment cites it instead of restating it. `(CI: lint:comments)`
- An exported identifier has a doc comment only when the comment states a fact the signature cannot. A doc comment that restates the signature is deleted. `(CI: lint:comments)`
- A comment that survives on one of the five grounds is not deleted to make room for another.
- No comment describes a state that a later edit makes false. The value it describes states it.
- A comment does not teach a third-party tool what that tool documents, and does not restate a convention that the path or identifier carries.
- Commented-out code, changelog, author, or date comments, and decorative banners are not committed. `(CI: lint:comments)`
- A `TODO` cites an issue or an ADR. `(CI: lint:comments)`
- A comment that exists to explain confusing code is a defect. The code is rewritten.
