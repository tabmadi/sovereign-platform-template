# ADR-0002: Tool Adoption and Comparison Requirement

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0001](0001-documentation-and-output-conventions.md)
- **Decides:** Exit cost sorts every tool into three tiers, each tier owes a fixed depth of recorded comparison, and one register lists every tool.

## Context

Principle 7 of [ADR-0000](0000-platform-foundations.md) states that a tool with no recorded comparison is an assumption and not a decision. It sets the depth by exit cost. Principle 7 is the rule. It does not say what `recorded` means for a linter compared with a database. It also does not say where the record lives.

Without that, the rule fails in both directions. At ADR depth for every tool, every transitive dependency demands a page, and nobody can read the set. By taste, depth follows how interesting the choice felt at the time. That has no relation to what the choice costs to undo.

This ADR sets the tiers, the depth each tier owes, the single register, and the grade that a comparison cell carries. It decides no tool.

## Decision drivers

1. **Depth follows exit cost, not interest.** Principle 4 of [ADR-0000](0000-platform-foundations.md) already measures adoption by what abandonment costs. The record applies that measure to itself: the effort to write a comparison is proportional to the effort to act on it later.
2. **A machine can check the record.** A rule that a reviewer applies from memory decays. A parse can tell whether a tool has a register row, and whether the ADR of that row holds a comparison table.
3. **A comparison is evidence that an evaluation happened.** It lets a later reader argue the decision again correctly. That needs the losing options and what each one was judged on. A justification of the winner does not give that.
4. **One home per fact.** [ADR-0001](0001-documentation-and-output-conventions.md) puts a fact in exactly one place. A tool's tier, licence, governing body, and maturity are one fact each. They belong together in one registry, not spread across the ADRs that use the tool.

## Considered options

### How depth is set

| Option | What decides depth | Failure mode | Verdict |
| --- | --- | --- | --- |
| **Tiers by exit cost** | how long removal takes and what it touches | a tier assignment can be argued, and the argument is the useful part | **Chosen.** It is principle 4 applied to the record, so the same judgement produces both the adoption and its documentation *(reasoned)* |
| Principle 7 alone, no tiers | the author | depth follows novelty and enthusiasm, and the boring expensive choice gets the thinnest record *(reasoned)* | The observed failure of the rule with no qualifier |
| One depth for every tool | nothing | either every linter gets an ADR, or the database gets a line | Uniformity at the cost of the property that is measured |
| Tiers by component tier: Core, Scale, Opt-in | operational obligation | independent of exit cost. An Opt-in library can need a rewrite to remove, and a Core component can be a chart swap | It measures the wrong axis. [`docs/operational-surface.md`](../operational-surface.md) keeps that tiering for its own purpose |
| Weighted scoring matrix | a numeric total | it creates false precision from qualitative trade-offs, and the author chooses the weights after the answer is known | Rejected on the same grounds as scoring grids in [ADR-0001](0001-documentation-and-output-conventions.md) |

### Where the record lives

| Option | Discoverable by | Why not |
| --- | --- | --- |
| **Comparison in the owning ADR, one register row per tool** | reading the decision, or the register | **Chosen.** The reasoning sits beside what it decides. The register answers `what is in here and why` in one file *(reasoned)* |
| Register only, with no ADR table | the register | A row cannot carry what each option was judged on. The comparison becomes a list of names *(reasoned)* |
| ADR only, no register | reading all of the ADRs | A tool with no ADR is invisible. That is the exact failure that principle 7 exists to catch |
| A separate document per comparison | a directory listing | It splits the decision from its reasoning, and [ADR-0001](0001-documentation-and-output-conventions.md) gives an ADR both |

## Decision

### The three tiers

One question sets a tool's tier: **what does its removal cost, and what does it touch.**

| Tier | Exit cost | Touches | Owes |
| --- | --- | --- | --- |
| **1: structural** | months, and possibly customer data | the architecture, or state that must be migrated | a full comparison table in the owning ADR, a **named runner-up**, and a register row |
| **2: substitutable** | weeks | one interface, one chart, or the output of one generator | a short comparison table in the owning ADR, with the decisive question and the options that answered it differently, and a register row |
| **3: library** | days | code inside one package or one build step | a register row that names what the tool was picked over |

**The tier is a property of the seam, not of the component's size.** PostgreSQL is Tier 1 because the data is in it. Argo CD is Tier 1 because the reconciliation of every environment runs through it. `zod` is Tier 3 because its replacement is a mechanical edit inside the packages that import it, however many there are.

**A Tier 1 tool names its runner-up.** The runner-up is the fallback that principle 4 of [ADR-0000](0000-platform-foundations.md) requires of every young component. With a runner-up, a novel choice is a deferral and not a bet. A Tier 1 table can disqualify all its losing options on a hard constraint. It then has no runner-up, and it states this.

### Evidence grading

A comparison cell that produces a verdict states where its claim comes from. There are three grades, and every decisive cell carries one of them:

| Grade | Means | Obligation |
| --- | --- | --- |
| *(measured)* | a number that this platform produced | states its conditions and how to derive it again, per *Numbers* in [ADR-0001](0001-documentation-and-output-conventions.md) |
| *(documented)* | read from the option's own documentation, licence, or governing body | carries a citation, because it can become false without notice. Load-bearing instances are dated in [`reference/upstream-status.md`](../reference/upstream-status.md) |
| *(reasoned)* | follows from a property that this set already establishes | carries no citation. There is nothing external to check, and that is the purpose of the mark |

**Only the decisive cell is graded**: the one that the verdict rests on. A grade on every cell brings back the density that the tables exist to avoid. A reader who cannot tell which cell decided the row reads a table that has not finished deciding.

The grade lets a reader argue the decision again correctly. A *(documented)* claim is checked again against upstream. A *(measured)* claim is run again. A *(reasoned)* claim is argued with. When the three are mixed, a stale table still reads as rigorous.

### The register

[`docs/tool-register.md`](../tool-register.md) lists every tool that this platform runs, builds with, or generates from, at every tier. It is the canonical inventory in the sense of [ADR-0001](0001-documentation-and-output-conventions.md). It is the one place that records a tool's tier, licence, governing body, maturity signal, and owning ADR.

It is not a second place for decisions. A row states facts about a tool and points to the ADR that chose it. The reasoning stays in the ADR.

**Licence, governing body, and maturity are recorded and do not veto**, per principle 4 of [ADR-0000](0000-platform-foundations.md). They are evidence about exit cost. A single-vendor project under a source-available licence has a different abandonment profile from a foundation-governed one. The register carries them, so that evidence is available without new research.

### What is out of scope

**Transitive dependencies are not tools.** The register row above a transitive package governs it. When the platform vendors, forks, or depends directly on a transitive package, that is a Tier 3 adoption, and the package gets a row.

**A specification is not a tool.** OpenAPI, OCI, RFC 9457, and SLSA are contracts that the platform conforms to. When the platform chose one over an alternative, the comparison lives in the ADR that adopted it, and no register row follows.

## Consequences

### Positive

- Depth is derived, not negotiated. A reviewer asks what removal costs, and the required record follows.
- The register makes a missing comparison visible without a read of the set. That is the failure that principle 7 names, and the register lets a reviewer see it.
- Evidence grading gives a way to catch a stale table. A *(documented)* cell has a source that a reviewer can read again, and that is a bounded task.
- A Tier 1 runner-up is a fallback recorded before anyone needs it. So a novel structural choice is a deferral and not a bet.

### Negative and Risks

- **Review enforces the tier assignment.** An author can file a tool at Tier 3 to avoid a table. No parse detects a wrong tier, only a missing row. Two facts mitigate this: the tier test is one question with a checkable answer, and the register shows the claimed exit cost beside the tier.
- **The register copies the tool's name into a second file.** Accepted: the copy is one row, a linter checks it for drift, and the alternative is a fact with no home.
- **Grading adds a token to decisive cells.** Accepted at three characters per row, for the ability to tell a measurement from an inference.

## Rules

- Every tool that this platform runs, builds with, or generates from has a row in [`docs/tool-register.md`](../tool-register.md). The row states its tier, owning ADR, licence, governing body, maturity signal, and exit cost. `(CI: lint:tool-register)`
- Exit cost sets a tool's tier: **1** is structural, months and possibly customer data. **2** is substitutable, weeks behind a stable interface. **3** is library, days inside one package.
- A Tier 1 tool has a full comparison table in its owning ADR and a **named runner-up**. Without a runner-up, it states that no option survived the hard constraints. `(CI: lint:tool-register)`
- A Tier 2 tool has a short comparison table in its owning ADR, with the decisive question and the options that answered it differently. `(CI: lint:tool-register)`
- The register row of a Tier 3 tool names what the tool was picked over. No ADR table is owed.
- Every alternative named in a register row appears in the *Considered options* of the owning ADR. A rejection that nobody can see looks the same as an option that nobody considered. `(CI: lint:tool-register)`
- A comparison cell that produces a verdict is graded *(measured)*, *(documented)*, or *(reasoned)*. Cells that do not decide the row are not graded.
- A *(documented)* claim carries a citation. A load-bearing one is dated in [`docs/reference/upstream-status.md`](../reference/upstream-status.md).
- A *(measured)* claim states the conditions it was measured under and how to derive it again. `(ref: ADR-0001 Numbers)`
- Licence, governing body, and maturity are recorded for every tool and do not veto a choice.
- The register row above a transitive dependency governs it. A direct dependency on one makes it a Tier 3 adoption and gives it a row.
- A comparison is a table with prose cells, never a weighted scoring matrix.
