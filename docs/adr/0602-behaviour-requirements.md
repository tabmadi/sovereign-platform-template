# ADR-0602: Behaviour Requirements

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0001](0001-documentation-conventions.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0601](0601-testing-strategy.md)
- **Decides:** A service's behaviour is a list of EARS requirements with IDs in its `requirements.md`, and a test that CI finds cites each one.

## Context

Three questions about a service have a home. An ADR says why the platform works as it does. The OpenAPI spec says the exact shape of every request and response, per [ADR-0303](0303-api-contracts-and-lifecycle.md). A guide says how to do a task. The fourth question has no home: what a service must do. Examples are which caller gets a 403, and what a failed charge leaves behind.

Today that answer lives in handler code, in test names, and in the head of the person who wrote them. A human reader and a coding agent both rebuild it from the code before each change. They rebuild it differently, and a change that breaks an unstated rule passes review because nobody wrote the rule down.

An ADR is the wrong home for it. An ADR is stable law about the platform. Service behaviour changes with every feature, and one service's behaviour binds no other service, per [ADR-0000](0000-platform-foundations.md).

This ADR decides where behaviour is written, the form of one requirement, and how a requirement stays true. Out of scope: the test layers, which [ADR-0601](0601-testing-strategy.md) owns, and the contract shape, which [ADR-0303](0303-api-contracts-and-lifecycle.md) owns.

## Decision drivers

1. **A requirement and its proof cannot drift apart without a red build.** Prose that no machine checks drifts from the code. This is principle 9 of [ADR-0000](0000-platform-foundations.md): what can be generated or checked is not left to memory.
2. **Humans and coding agents read the same file.** One fixed sentence form is faster to read for both, and a tool can parse it.
3. **One fact, one place**, per [ADR-0001](0001-documentation-conventions.md). Behaviour does not repeat the contract shape or the reason for a decision.
4. **No new tool and no new runtime**, per principle 5 of [ADR-0000](0000-platform-foundations.md). The test runners that [ADR-0601](0601-testing-strategy.md) chose already exist in two languages.
5. **The committed record holds standing fact, not planned work**, per [ADR-0001](0001-documentation-conventions.md).

## Considered options

### Where behaviour lives

| Option | 1 Checked trace | 2 One form for both readers | 3 One fact, one place | 4 No new tool | 5 Standing fact only | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| **EARS requirements with an ID in `requirements.md`, cited by test names** | **Yes. A linter checks the trace in both directions** | **Yes. Five fixed sentence openers** | **Yes. Behaviour only, the contract stays in the spec** | **Yes. The checker is the prose linter that runs anyway** | **Yes** | **Chosen** |
| Gherkin feature files, run by godog and playwright-bdd | Yes, and tighter: the runner executes each step | Yes | Yes | No. A step layer in Go and in TypeScript, and two tools | Yes | Rejected on driver 4. It is the runner-up |
| Spec Kit or Kiro, with a spec, a plan, and a task list for each feature | No. The files are prose | Yes | No. The plan restates the spec | Yes | No. The plan and the tasks are planned work | Rejected on drivers 1 and 5 |
| OpenSpec, with a `changes/` folder of proposals folded into the spec on merge | No | Yes | Yes | Needs its CLI | No. The proposal folder is planned work | Rejected on drivers 1 and 5 |
| Behaviour as Rules in ADRs | No | Yes | No. An ADR binds every service, per [ADR-0000](0000-platform-foundations.md) | Yes | Yes | Rejected on drivers 1 and 3 |
| Do nothing: the tests are the requirements | Partly. A deleted test removes its rule with no trace | No. A reader cannot see a rule that no test states | Yes | Yes | Yes | Rejected on drivers 1 and 2 |

Sources:

- The EARS patterns and their openers: [Mavin, EARS](https://alistairmavin.com/ears/).
- Gherkin runners for Go and Playwright: [godog](https://github.com/cucumber/godog), [playwright-bdd](https://github.com/vitalets/playwright-bdd).
- A spec, a plan, and tasks for each feature: [GitHub Spec Kit](https://github.com/github/spec-kit), [Kiro specs](https://kiro.dev/docs/specs/).
- A `changes/` folder of proposals: [OpenSpec](https://github.com/Fission-AI/OpenSpec).

### The checker of the trace

| Option | 1 Checked trace | 4 No new tool | Covers | Verdict |
| --- | --- | --- | --- | --- |
| `tools/lint-requirements`, a Go program in this repo | Yes | Yes | The prefix, the row form, EARS, and the trace both ways | Rejected. It is a second copy of the rules that tablint holds, and this repo maintains it alone |
| **The `requirement` rules of tabkit** | **Yes, with the line of each citation** | **Yes. tabkit already checks the prose, per [ADR-0001](0001-documentation-conventions.md)** | **The same checks, with the `TPL` placeholder of `services/_template/` built in** | **Chosen** |

Both ran on the same four faults: an opener that is not EARS, a malformed row, an untested requirement, and a citation of an unknown ID. Both gave the same four findings *(measured)*.

Sources:

- The `requirement` rules: `tabkit rules` in the dev shell lists them, and the measurement above ran both checkers.

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

tabkit checks the trace in both directions, through `just lint-prose`. Every requirement has at least one citing test. Every ID that a test cites exists. A requirement with no test is a claim with no proof, so the build is red until the test exists.

### How behaviour changes

A pull request that changes behaviour changes `requirements.md`, the tests, and the code together. The diff to `requirements.md` is the proposal that a reviewer reads first. A rejected proposal is a closed pull request, per [ADR-0000](0000-platform-foundations.md). No proposal, plan, or task file is committed.

A new service starts from `services/_template/requirements.md`. Its placeholder prefix `TPL` fails `lint-prose` until the service declares its own prefix.

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

- What a service must do is written in `services/<name>/requirements.md`. What a journey across services must do is written in `docs/requirements/<journey>.md`. `(CI: lint-service-contract)`
- A requirement uses one EARS pattern, in the present tense, and starts with `The`, `When`, `While`, `If`, or `Where`. `(CI: lint-prose)`
- A requirement is one table row: its ID, then one sentence. `(CI: lint-prose)`
- A requirement states observable behaviour. It does not restate a field, a type, or a format of the OpenAPI spec, or the reason for an ADR.
- Each requirements file declares one prefix of two to four capital letters. No two files share a prefix, and no file outside `services/_template/` uses `TPL`. `(CI: lint-prose)`
- An ID is the prefix, a hyphen, and three digits. It is unique across the repository. `(CI: lint-prose)`
- An ID names one meaning. A requirement whose meaning changes gets a new ID, and a retired ID is not used again.
- Every requirement is cited by at least one test, and every ID that a test cites exists in a requirements file. `(CI: lint-prose)`
- A test cites a requirement by its ID in the test name: a Go subtest or case name, or a Playwright tag. A Go test function with no subtest cites it in its doc comment.
- A pull request that changes behaviour changes the requirements file, the tests, and the code together.
- No proposal, plan, or task file for a change is committed. The pull request's diff is the proposal.
