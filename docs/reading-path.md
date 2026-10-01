# Reading Path

The ADR set is written for a reader who has already read it. That reader applies it correctly. This suits the person who maintains the platform, but it does not suit a first week. So this document is the ordered way in. It lists what to read, in what order, and what each role can skip.

**Start with a running cluster, not with ADR-0000.** [`dev-loop.md`](dev-loop.md) ends with a served request. The reasons behind a system read differently after you see the system respond.

## The first ninety minutes

Read these in this order. Each one is needed before the next.

| # | Read | Why here |
| --- | --- | --- |
| 1 | [`dev-loop.md`](dev-loop.md) | A cluster comes up and serves a request. Everything below is about a thing you have seen work |
| 2 | [`reference/system-view.md`](reference/system-view.md) | The shape: what runs, what calls what, and where a request goes. One page |
| 3 | [ADR-0000](adr/0000-platform-foundations.md), *Thesis* and *Principles* | The three axes and this platform's position on them. Then the ten principles that every later decision cites. Stop before *Prior art* |
| 4 | [ADR-0001](adr/0001-documentation-and-output-conventions.md), *ADR structure* and *Banned constructs* | How to read the documents, and how to write one. It is the shortest path to a fast read of the rest |
| 5 | [`operational-surface.md`](operational-surface.md) | What is always on, what it obliges, and what stops working when each part stops |
| 6 | The **Decides** line of every ADR, from [the index](adr/README.md) | One sentence for each ADR. All decisions of the set in a single pass |

After these, you can find your way through the set. **The estimate assumes a fast read of steps 3 and 5, not a close read.** Those steps are dense. The ninety minutes give orientation, not memory. What remains is depth, and you read depth when you need it.

## Then make a change

Knowing your way around is not the same as being productive. [`guide/first-change.md`](guide/first-change.md) takes one small change through every gate it passes. The change adds a field to a service. The gates are:

- the spec
- `mise run gen`
- the migration
- the drift check
- the nine CI gates, in the order they fail
- the four classes that review exists for

It is the how-to partner of this document. It is the fastest way to turn a read of the set into a working model of it.

## By role

Every role reads the ninety minutes above. The table lists what to read next, and what to leave until it matters.

| Role | Read next | Safe to defer |
| --- | --- | --- |
| **Anyone, before their first pull request** | [`guide/first-change.md`](guide/first-change.md) | nothing. It is one walkthrough, and it is shorter than the time that its prevented mistakes would cost |
| **Backend** | [0303](adr/0303-api-contracts-and-lifecycle.md) contracts, [0300](adr/0300-data.md) data, [0302](adr/0302-temporal.md) workflows, [0304](adr/0304-identity-and-authorization.md) authorization, [0003](adr/0003-naming-and-identifiers.md) identifiers, [0500](adr/0500-observability.md) instrumentation | the cluster block, 02xx, and the frontend block, 04xx |
| **Frontend** | [0400](adr/0400-frontend.md) stack, [0306](adr/0306-trust-tiers-and-urls.md) tiers and origins, [0303](adr/0303-api-contracts-and-lifecycle.md) generated clients, [0700](adr/0700-analytics.md) consent and events | data, which is 03xx beyond contracts, and infrastructure, which is 02xx |
| **Platform** | the whole 02xx block, then [0104](adr/0104-supply-chain-security.md), [0201](adr/0201-gitops.md), [0203](adr/0203-policy-enforcement.md), and [0500](adr/0500-observability.md) to [0502](adr/0502-alerting-and-on-call.md) | the frontend block and analytics |
| **Security reviewer** | [`security-baseline.md`](security-baseline.md), then [0304](adr/0304-identity-and-authorization.md), [0305](adr/0305-edge-auth-and-traffic-policy.md), [0306](adr/0306-trust-tiers-and-urls.md), [0203](adr/0203-policy-enforcement.md), [0202](adr/0202-secrets.md), [0301](adr/0301-data-lifecycle-privacy.md), and [`reference/risk-register.md`](reference/risk-register.md) | everything else. The register is the fastest route to what this platform accepts |
| **Deciding whether to adopt** | the root README, then [`adoption-path.md`](adoption-path.md) and [`operational-surface.md`](operational-surface.md) | the ADRs. They answer *why*, and adoption is a question about *cost* |
| **An agent** | [`../AGENTS.md`](../AGENTS.md), then the Rules sections that it names for the task class | full ADR bodies, until the reason for a rule is the real question |

## Reading an ADR quickly

The sections have a fixed order. So you know what a partial read covers.

| Want | Read |
| --- | --- |
| What is true | the **Decides** line, then **Rules** |
| Whether a rule is enforced | the annotation on that rule: a task, a policy, a standard, or nothing. Nothing means review enforces it |
| The reasons, in one pass | **Decision drivers**, then the verdict column of **Considered options** |
| Why not the obvious alternative | the row of that option. Each losing option appears in its best form, so the row is worth reading |
| What it takes to change it | **Consequences**, and any table of Trigger, Seam, and Cost |

## Where the set is not the answer

| Question | Not an ADR |
| --- | --- |
| How to run it | [`dev-loop.md`](dev-loop.md), and the how-to documents that [`README.md`](README.md) indexes |
| How to change it | [`guide/first-change.md`](guide/first-change.md) |
| What can reach production unchecked | [`reference/build-path.md`](reference/build-path.md) |
| What is deployed, and what it costs to keep | [`operational-surface.md`](operational-surface.md) |
| Whether we can run less than this | [`adoption-path.md`](adoption-path.md) |
| What failures this platform accepts | [`reference/risk-register.md`](reference/risk-register.md) |
| How long until we notice a failure | [`reference/detection-latency.md`](reference/detection-latency.md) |
| What we wait for, and who watches it | [`reference/deferral-register.md`](reference/deferral-register.md) |
