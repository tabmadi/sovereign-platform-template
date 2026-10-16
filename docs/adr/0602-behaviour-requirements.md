# ADR-0602: Behaviour Requirements

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0001](0001-documentation-and-output-conventions.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0601](0601-testing-strategy.md)
- **Decides:** A service's behaviour is a list of EARS requirements with IDs in its `requirements.md`, and a test that CI finds cites each one.

## Context

Three questions about a service have a home. An ADR says why the platform works as it does. The OpenAPI spec says the exact shape of every request and response, per [ADR-0303](0303-api-contracts-and-lifecycle.md). A guide says how to do a task. The fourth question has no home: what a service must do. Examples are which caller gets a 403, and what a failed charge leaves behind.

Today that answer lives in handler code, in test names, and in the head of the person who wrote them. A human reader and a coding agent both rebuild it from the code before each change. They rebuild it differently, and a change that breaks an unstated rule passes review because nobody wrote the rule down.

An ADR is the wrong home for it. An ADR is stable law about the platform. Service behaviour changes with every feature, and one service's behaviour binds no other service, per [ADR-0000](0000-platform-foundations.md).

This ADR decides where behaviour is written, the form of one requirement, and how a requirement stays true. Out of scope: the test layers, which [ADR-0601](0601-testing-strategy.md) owns, and the contract shape, which [ADR-0303](0303-api-contracts-and-lifecycle.md) owns.

## Decision drivers

1. **A requirement and its proof cannot drift apart without a red build.** Prose that no machine checks drifts from the code. This is principle 9 of [ADR-0000](0000-platform-foundations.md): what can be generated or checked is not left to memory.
2. **Humans and coding agents read the same file.** One fixed sentence form is faster to read for both, and a tool can parse it.
3. **One fact, one place**, per [ADR-0001](0001-documentation-and-output-conventions.md). Behaviour does not repeat the contract shape or the reason for a decision.
4. **No new tool and no new runtime**, per principle 5 of [ADR-0000](0000-platform-foundations.md). The test runners that [ADR-0601](0601-testing-strategy.md) chose already exist in two languages.
5. **The committed record holds standing fact, not planned work**, per [ADR-0001](0001-documentation-and-output-conventions.md).

## Considered options

| Option | What checks it | What it adds | Verdict |
| --- | --- | --- | --- |
| **EARS requirements with an ID in `requirements.md`, cited by test names** | `lint:requirements` checks the trace in both directions | one Markdown file per service and one in-repo linter | **Chosen.** It meets every driver with no new tool *(reasoned)* |
| Gherkin feature files, run by godog and playwright-bdd | the runner executes each step | a step-definition layer in Go and in TypeScript, and two tools | Runner-up. It checks behaviour more tightly, but it adds two tools and a second test language, against driver 4 *(documented)* |
| Spec Kit or Kiro style, with a spec, a plan, and a task list committed for each feature | nothing. The files are prose | three files for each feature | The plan and the task list are planned work in the committed record, against driver 5 *(documented)* |
| OpenSpec style, with a `changes/` folder of proposals folded into the spec on merge | nothing. The files are prose | a proposal folder and a merge step | The proposal folder is planned work. A pull request already carries a proposal, as its diff *(reasoned)* |
| Behaviour as Rules in ADRs | review only | many service-scoped ADRs | Behaviour changes with each feature, and an ADR binds every service, per [ADR-0000](0000-platform-foundations.md) *(reasoned)* |
| Do nothing: the tests are the requirements | the tests themselves | nothing | A reader cannot see a rule that no test states, and a deleted test removes its rule with no trace *(reasoned)* |

## Decision

### Where behaviour lives

| Path | Holds | Cited by |
| --- | --- | --- |
| `services/<name>/requirements.md` | what one service must do | the service's Go tests, and e2e tests that exercise it |
| `docs/requirements/<journey>.md` | what a journey across services must do | the e2e tests under `test/e2e/` |

A service requirement names behaviour that one service owns. A journey requirement names an outcome that no single service can show. An example is an order that reaches `confirmed` after a lookup and a charge.

### What a requirement holds

Each artefact answers one question, and a requirement does not repeat another artefact:

| Question | Answered by |
| --- | --- |
| Why does the platform work this way | the ADR |
| What must the service do | the requirement |
| What exact shape does the request have | `openapi.yaml` |
| How does a person do a task | `docs/guide/` |

A requirement states observable behaviour: a status code, a state change, an order of effects, or what a failure leaves behind. A requirement that restates a field, a type, or a format of the contract is deleted.

### The form of a requirement

Every requirement uses one of the [EARS](https://alistairmavin.com/ears/) patterns. The local delta: a requirement is in the present tense, because ADR-0001 states law as fact, not with `shall`.

| Pattern | Form |
| --- | --- |
| Ubiquitous | `The <subject> <response>.` |
| Event | `When <trigger>, the <subject> <response>.` |
| State | `While <state>, the <subject> <response>.` |
| Unwanted | `If <condition>, the <subject> <response>.` |
| Optional | `Where <feature is on>, the <subject> <response>.` |

A requirement is one row in a two-column table: the ID, then the sentence. One row is one requirement, so a grep for an ID returns the whole rule.

### Identifiers

An ID is the file's prefix, a hyphen, and three digits: `ORD-003`. Each file declares its prefix in its header. A prefix has two to four capital letters, and no two files share one.

**An ID names one meaning.** A requirement whose meaning changes gets a new number, and the old number is not used again. So a test that still cites the old ID fails the trace and is reviewed again. A change to the wording that keeps the meaning keeps the ID.

### The trace

A test cites a requirement by putting its ID in the test's name. Then the runner selects it by ID:

| Runner | Citation | Selects it |
| --- | --- | --- |
| `go test` | a subtest or case name: `t.Run("ORD-003 a repeated key replays the first order", ...)` | `go test -run '/ORD-003' ./services/orders/...` |
| Playwright | a tag in the details: `test("...", { tag: ["@ORD-003"] }, ...)` | `playwright test --grep @ORD-003` |

A Go test function that has no subtest cites the ID in its doc comment. A test can cite several IDs, and several tests can cite one ID.

`lint:requirements` checks the trace in both directions. Every requirement has at least one citing test. Every ID that a test cites exists. A requirement with no test is a claim with no proof, so the build is red until the test exists.

### How behaviour changes

A pull request that changes behaviour changes `requirements.md`, the tests, and the code together. The diff to `requirements.md` is the proposal that a reviewer reads first. A rejected proposal is a closed pull request, per [ADR-0000](0000-platform-foundations.md). No proposal, plan, or task file is committed.

A new service starts from `services/_template/requirements.md`. Its placeholder prefix `TPL` fails `lint:requirements` until the service declares its own prefix.

## Consequences

### Positive

- A coding agent reads one file to learn what a service must do. Then it runs the tests for one ID to check its change.
- A deleted test cannot remove a rule unseen. The orphaned requirement turns the build red.
- A reviewer reads the behaviour change as a short table diff, before the code diff.

### Negative and Risks

- **The linter checks that a test cites a requirement, not that the test proves it.** A test can carry an ID and assert something else. Review is the only check on this. It is accepted, because no tool reads the meaning of an assertion.
- **Behaviour that no test covers cannot be written down.** A rule that a team knows but cannot test yet stays unwritten, and the gap is invisible. It is accepted. A requirement with no proof is the drifting prose that driver 1 rejects.
- **Test names get longer.** An ID adds one word to each citing name.

## Rules

- What a service must do is written in `services/<name>/requirements.md`. What a journey across services must do is written in `docs/requirements/<journey>.md`. `(CI: lint:service-contract)`
- A requirement uses one EARS pattern, in the present tense, and starts with `The`, `When`, `While`, `If`, or `Where`. `(CI: lint:requirements)`
- A requirement is one table row: its ID, then one sentence. `(CI: lint:requirements)`
- A requirement states observable behaviour. It does not restate a field, a type, or a format of the OpenAPI spec, or the reason for an ADR.
- Each requirements file declares one prefix of two to four capital letters. No two files share a prefix, and no file outside `services/_template/` uses `TPL`. `(CI: lint:requirements)`
- An ID is the prefix, a hyphen, and three digits. It is unique across the repository. `(CI: lint:requirements)`
- An ID names one meaning. A requirement whose meaning changes gets a new ID, and a retired ID is not used again.
- Every requirement is cited by at least one test, and every ID that a test cites exists in a requirements file. `(CI: lint:requirements)`
- A test cites a requirement by its ID in the test name: a Go subtest or case name, or a Playwright tag. A Go test function with no subtest cites it in its doc comment.
- A pull request that changes behaviour changes the requirements file, the tests, and the code together.
- No proposal, plan, or task file for a change is committed. The pull request's diff is the proposal.
