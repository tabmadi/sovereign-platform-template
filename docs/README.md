# Documentation

Decisions are [ADRs](adr/README.md). Everything else is here. A document is here only because of one rule:

> An ADR records a decision and its reasons. A doc holds what an ADR must not hold: a **procedure to execute**, or **live state that changes while no decision changes**. Everything else is a link.

So no doc repeats a stack choice, and no runbook argues for its own design.

**New readers:** [reading-path](reading-path.md) is the ordered way in. It takes ninety minutes to learn the set. Then it lists what each role reads next.

## How this tree is laid out

The genre decides the directory. So a path tells the reader the kind of document before the file opens, per [ADR-0001](adr/0001-documentation-and-output-conventions.md).

| Path | Genre | Holds |
| --- | --- | --- |
| `adr/` | explanation and reference | the decisions |
| `guide/` | how-to | a procedure someone executes |
| `reference/` | reference | a lookup, a registry, or live state |
| `product/` | evidence | dated observations of the outside world, with sources. It is optional and binds nothing, per [ADR-0701](adr/0701-product-design-and-discovery.md) |
| `docs/*.md` | entry and canonical registries | the way in, and the documents that the ADR set names as the only record of a thing |

The root holds few files, and this is intentional. It holds two kinds of file:

- Entry documents: [reading-path](reading-path.md) and [dev-loop](dev-loop.md) are where a reader starts.
- Canonical registries: the ADR set names each of these as the single home of one record.

| Registry | Single home of |
| --- | --- |
| [operational-surface](operational-surface.md) | the component inventory |
| [adoption-path](adoption-path.md) | the reduction order |
| [tool-register](tool-register.md) | the tool inventory |
| [brand](brand.md) | the design roles |
| [security-baseline](security-baseline.md) | the control index |

The topic is in the filename, not in a directory. A directory with one file adds nothing. A `runbook.md` in each topic directory gives four files that an editor cannot tell apart.

## How-to: procedures

| Doc | Answers |
| --- | --- |
| [first-change](guide/first-change.md) | How to make the first change after you read the set, and the gates it passes through |
| [dev-loop](dev-loop.md) | How to run and debug a service on your machine |
| [database-migrations](guide/database-migrations.md) | How to write and apply a schema migration |
| [postgres-major-upgrade](guide/postgres-major-upgrade.md) | How to move Postgres to a new major version |
| [gitops-runbook](guide/gitops-runbook.md) | How to deploy, and what to do when a sync is stuck |
| [gitops-local](guide/gitops-local.md) | How to test uncommitted GitOps wiring |
| [disaster-recovery](guide/disaster-recovery.md) | How to recover from full cluster loss |
| [secrets-runbook](guide/secrets-runbook.md) | How to onboard, offboard, or rotate a key |
| [gateway-runbook](guide/gateway-runbook.md) | How to change an edge rule or a rate limit |
| [break-glass](guide/break-glass.md) | How to reach the dashboards when auth is down |
| [incident-management](guide/incident-management.md) | What counts as an incident, who does what, and what is owed after it |
| [designing-a-screen](guide/designing-a-screen.md) | How to design a screen, and what promoting it requires |
| [http-proxy](guide/http-proxy.md) | How to work behind a corporate proxy |
| [performance-runbook](guide/performance-runbook.md) | How to run a load test and read the result |

## Reference: lookup

| Doc | Holds |
| --- | --- |
| [local-environment](reference/local-environment.md) | Local ports, URLs, the frontend environment contract, and the task index |
| [operational-surface](operational-surface.md) | Every platform component in the tiers Core, Scale, and Opt-in, with its recurring obligation. It also holds the budget rule |
| [adoption-path](adoption-path.md) | What to give up, and in what order, when the floor is more than the capacity. It also holds the cost to take each part back |
| [tool-register](tool-register.md) | Every tool, with its exit-cost tier, licence, governing body, and owning ADR |
| [brand](brand.md) | What each design token is for, the voice, and what the brand refuses to do. The values live in the token file |
| [security-baseline](security-baseline.md) | Every security control and the mechanism that enforces it. **Generated** from the Rules sections of the owning ADRs |
| [system-view](reference/system-view.md) | What runs, how a request moves through it, and where identity enters. One page |
| [risk-register](reference/risk-register.md) | Every accepted risk in the set, ranked, with its compensating control and its trigger |
| [deferral-register](reference/deferral-register.md) | The trigger of every deferral, and whether a machine can see it fire |
| [detection-latency](reference/detection-latency.md) | For each failure class: what detects it, and how long that takes |
| [build-path](reference/build-path.md) | For each class of defect: what stops it before production, and what reaches production unchecked |
| [threat-model](reference/threat-model.md) | The adversaries that each control acts against, over the three boundaries |
| [cost-model](reference/cost-model.md) | The shape of the bill and what appears on it. The adopter sets the prices |
| [credential-register](reference/credential-register.md) | Where every credential is kept, and who can open it. It never holds a value |
| [rules-index](reference/rules-index.md) | Every rule in the set with its enforcement. **Generated** |
| [per-instance-hardening](reference/per-instance-hardening.md) | What a project turns on for its own risk profile or compliance framework |
| [asvs-verification](reference/asvs-verification.md) | The ASVS L2 claim for each concern, with the date of the last check |
| [upstream-status](reference/upstream-status.md) | Third-party facts that the decisions rest on, with the date of each check |
| [jwt-validation](reference/jwt-validation.md) | The JWT validation rules, defined once |
| [long-running-workflows](reference/long-running-workflows.md) | The registry of workflows whose wall-clock time is longer than one deploy cycle |
| [slo-recording-rules](reference/slo-recording-rules.md) | The recording rules of each service, which the shared burn-rate alerts read |

## Where a fact lives

| Looking for | Go to |
| --- | --- |
| Why a tool was chosen, and what it won against | the owning ADR |
| The rule a reviewer enforces | the *Rules* section of that ADR |
| The command to run | the how-to above |
| What is deployed now | [operational-surface](operational-surface.md) |
| What it costs to keep a component running | [operational-surface](operational-surface.md), *Recurring obligation* |
| Whether we can run less than this | [adoption-path](adoption-path.md) |
| What failures this platform accepts | [risk-register](reference/risk-register.md) |
| How long until we notice a failure | [detection-latency](reference/detection-latency.md) |
| What can reach production unchecked | [build-path](reference/build-path.md) |
| Whether a tool has a recorded comparison | [tool-register](tool-register.md) |
| What we wait for, and who watches it | [deferral-register](reference/deferral-register.md) |
| The shape of the system | [system-view](reference/system-view.md) |
| Whether an upstream fact still holds | [upstream-status](reference/upstream-status.md) |
| How the prose in this repo is written | [ADR-0001](adr/0001-documentation-and-output-conventions.md) |
