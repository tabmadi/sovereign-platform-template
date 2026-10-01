# ADR-NNNN: Title

- **Status:** Accepted
- **Date:** YYYY-MM-DD
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md)
- **Decides:** one declarative sentence that names what is true of the platform because of this ADR. It is the index entry and the skim line, not a summary of the reasoning.

<!--
Written to ADR-0001. Before merging, check:
  - The text follows the Simple English profile in ADR-0001, section Simple English: B1 words, 25-word sentences, and only period, comma, colon, and apostrophe.
  - Every word is load-bearing. No intensifiers, hedges, meta-commentary, or chronology.
  - Three or more items that share two or more attributes are a table.
  - A fact appears in exactly one ADR. Everywhere else, it is a link.
  - Standing law only. No Follow-ups, no roadmap, no TODO, no note on whether the artefact exists yet. Planned work is not part of the committed record.
  - Every tool named in the Decision has a tool-register row. It also has a comparison at the depth its tier requires, per ADR-0002.
  - Every decisive comparison cell is graded `(measured)`, `(documented)`, or `(reasoned)`.
  - Every number survives the doubling test. No illustrative figures, and no count of live state that lives elsewhere.
  - No tool release versions. Spec versions, licence identifiers, and a capability boundary stated as a floor are fine. The pin lives in the lockfile or the chart. A documentation link uses `/latest/` where the site has one.
  - Drivers are properties. Swap the winner for a loser and read them again: they must be unmet, not wrong.
  - Written for the engineer who maintains this platform, not for a possible adopter. Selection guidance goes in README.md.
  - A section with nothing to say is omitted, not padded.
  - The number comes from the block that your layer owns. README.md lists the blocks.
-->

## Context

The problem, and the constraints from earlier ADRs. What this ADR decides, and what is out of scope.

## Decision drivers

In priority order. Anchor each driver to an ADR-0000 principle where one applies.

1. **Driver.** Why it matters here.
2. **Driver.** Why it matters here.

## Considered options

This section is **mandatory**, per principle 7 of [ADR-0000](0000-platform-foundations.md). It is a table with text cells, and every option answers the same questions. It is not a scoring grid: the trade-offs are qualitative, and numeric scores make a false precision.

The tool's exit-cost tier sets the depth, per [ADR-0002](0002-tool-adoption.md). Tier 1 gets a full table with a named runner-up. Tier 2 gets a short table, and Tier 3 gets a register line. A long deep-dive belongs in the PR discussion, not here.

The cell that produces each verdict is graded *(measured)*, *(documented)*, or *(reasoned)*. Cells that do not decide the row are not graded.

| Option | <the question that decides it> | <the second question> | Verdict |
| --- | --- | --- | --- |
| **Chosen option** | | | **Chosen.** Why *(grade)* |
| Alternative | | | Why it lost *(grade)*. The runner-up says so |
| Alternative | | | Why it lost *(grade)* |
| Do nothing | | | The honest baseline, and why it fails |

## Decision

Declarative statements: `We use X. We do not use Y.` Use tables for anything with structure.

A deferral states all three fields. Without them, it is not a deferral:

| Field | Value |
| --- | --- |
| **Trigger** | an *observable* condition. `When we grow` is not a trigger |
| **Seam** | whether the slot already exists. Without one, this is a **bet**, and it carries that label |
| **Cost if adopted late** | what the delay buys, and what it risks |

## Consequences

### Positive

- What this buys.

### Negative and Risks

- **The cost, stated plainly.** How it is mitigated, or that it is accepted and why.

## Rules

Flat, greppable, normative. A rule that a task, a policy, or a standard enforces names it. A rule that nothing enforces has no annotation, and it is equally binding.

- The rule, stated as a standing fact. `(CI: <task>)`
- The rule, stated as a standing fact. `(enforced: <admission policy>)`
- The rule, stated as a standing fact. `(ref: <standard>)`
- The rule, stated as a standing fact.
