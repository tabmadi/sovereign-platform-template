# ADR-0502: Alerting and On-Call

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0307](0307-outbound-email.md), [ADR-0500](0500-observability.md), [ADR-0501](0501-operator-uis-and-dashboards.md)
- **Decides:** Prometheus evaluates alerts from committed rule files, Alertmanager routes them, and escalation is a recorded concession.

## Context

[ADR-0500](0500-observability.md) ships alert rules as committed Prometheus rule files, and it stops there. A firing alert shows on the Prometheus alerts page and as the `ALERTS` series, and it reaches no one. At night, that is the same as no alerting.

[ADR-0000](0000-platform-foundations.md) ranks alert routing and on-call **second** to concede when the platform moves down axis B. The reason given is that no mature self-hosted escalation layer exists. That ranking mixes two concerns that have different answers.

| Concern | Question | Self-hosted answer |
| --- | --- | --- |
| **Routing** | which humans and systems this alert reaches, with deduplication, grouping, and silences during maintenance | mature and standard |
| **Escalation** | who is on call now, what happens when they do not acknowledge in five minutes, and how a phone rings | thin, and the reason for ADR-0000's ranking |

Routing is a solved component that the platform chose not to run. Escalation is a real gap. Because the two were decided together, the platform has neither.

## Decision drivers

1. **An alert that reaches no one is not an alert.** Routing is the minimum that makes the rule files of [ADR-0500](0500-observability.md) real.
2. **Configuration in the repository**, per principle 1 of [ADR-0000](0000-platform-foundations.md). Routes, receivers, and silences are files.
3. **One primitive per concern**, per principle 5. Alerts evaluate in one place, not in two.
4. **Thinnest viable platform**, per principle 2. Routing does not arrive as an incident-management suite.
5. **The escalation exit is honest**, per principle 3. Where the self-hosted answer is thin, this ADR says so and does not hide it.

## Considered options

### Where alerts evaluate and route

| Option | Rules as files | Routing, grouping, silencing | Weight | Verdict |
| --- | --- | --- | --- | --- |
| **Prometheus rules and Alertmanager** | native rule files, already shipped | Alertmanager's routing tree, as a committed config | one Go binary, no datastore | **Chosen.** It is the receiver the rule files were always written for *(reasoned)* |
| Grafana unified alerting | rules become Grafana objects, provisionable as YAML | built into Grafana, already Core | none, because Grafana already runs | Zero added weight, and rejected on principle 5. Alert state moves into Grafana's database. Evaluation splits between two engines while the rule files of [ADR-0500](0500-observability.md) still exist |
| Alertmanager with [Karma](https://github.com/prymitive/karma) in front | native rule files | Alertmanager's, with Karma as the surface over it | one more always-on UI | Karma reads an Alertmanager and does not replace one. So it adds to the chosen row and does not compete with it. The surface here is Grafana, which already runs |
| Rule files with no receiver, the honest baseline | yes | none | none | An alert that evaluates and reaches nobody. Driver 1 rules it out |

### Escalation and paging

| Option | Self-hosted | Rotation, escalation, acknowledgement | Reaches a phone | Verdict |
| --- | --- | --- | --- | --- |
| **A managed paging service, reached by webhook** | no | yes | yes | **Chosen as the sanctioned concession**, exactly where [ADR-0000](0000-platform-foundations.md) ranks it *(reasoned)* |
| Grafana OnCall | **no longer** | yes | never, without Grafana's cloud | The self-hosted answer the field used to have. Its open-source distribution entered maintenance in March 2025 and was **archived in March 2026**. The repository is read-only, and OSS users lost phone and SMS delivery. It is the direct evidence behind ADR-0000's ranking of this component |
| Keep | yes | alert enrichment, correlation, and workflows, but no rotation calendar | no | It answers the tier above this one: deduplication and enrichment of alerts. It does not answer whose phone rings at 03:00 |
| LinkedIn Oncall | yes | **rotation calendars only** | no | A scheduling system with no alert path. Pairing it with a delivery tool builds the product again from two halves and an integration that nobody maintains |
| GoAlert | yes | **yes**: schedules, escalation policies, acknowledgement | **through a carrier account**, such as Twilio for SMS and voice | The closest self-hosted escalation layer that still exists. It is the reason the claim below is qualified and not absolute. It does not remove the third party. It **moves** it from a paging vendor to a telco, billed per message, with an account and credentials to hold. It adds a Postgres-backed service to run, and it has no incident timeline or runbooks. Adopt it when a real rotation exists. Before that, it is a rotation service with nobody on the rota |
| OneUptime | yes | yes, inside a full status-page and monitoring suite | through a carrier account | It answers this question, but it brings a second observability platform. Most of the product overlaps with the stack of [ADR-0500](0500-observability.md) |
| ntfy or Gotify as a receiver | yes | none, delivery only | push notification, not a call | The honest self-hosted delivery floor. It moves a notification to a device. It does not know who is on duty, and it does not notice that nobody acknowledged |
| Email and chat only | yes | none | no | Enough where no rotation exists, and honest about its limits. It is the template default |
| Build a rotation and escalation service | yes | whatever we write | whatever we integrate | An incident-management product, not platform glue |

**No self-hosted option reaches a phone without a third party.** That is the lasting finding. It is narrower than the claim that no self-hosted escalation layer exists: GoAlert is one, and it works. But it cannot put a call through alone. SMS and voice need a carrier account, so a self-hosted scheduler moves the dependency and does not remove it. Grafana OnCall seemed to avoid this, and its archival removed that option. It only seemed to avoid it because Grafana's own cloud did the delivery.

**A pager that shares the failure domain it pages about is not a pager.** This decides more than it seems to. An in-cluster paging service is unreachable in exactly the outage that is worth waking someone for. So any self-hosted choice here runs **outside** the cluster, like the forge in [ADR-0102](0102-source-control-and-ci.md) and the production object store in [ADR-0207](0207-cluster-storage.md). That is a second host to operate before the first page goes out. It is why the managed concession has its rank. The concession is not a preference between comparable options. It exists because there is no comparable option.

## Decision

| Concern | Decision |
| --- | --- |
| Evaluation | **Prometheus**, from the committed rule files in [ADR-0500](0500-observability.md). Grafana alerting is not used |
| Routing | **Alertmanager**, which joins Core. Its routing tree, receivers, inhibitions, and silences are committed files that Argo reconciles, per [ADR-0201](0201-gitops.md) |
| Default receivers | **email** through [ADR-0307](0307-outbound-email.md), a **generic webhook** receiver, and a separate **heartbeat** receiver for the Watchdog. Both webhooks ship wired to nothing |
| Severity | every rule carries `severity: page` or `severity: ticket`. `page` routes to the webhook, and `ticket` routes to email. A match by name routes the Watchdog before both |
| Escalation | **not shipped.** The webhook receiver is the seam where a paging service attaches |
| Silences | a maintenance window is a committed silence, not a click in the Alertmanager UI, per principle 1 |

**`severity: page` is a claim about a human.** A rule carries it only when a person must act within minutes. Every other rule is `ticket`. Without that discipline the routing tree is decoration. A receiver that fires forty times a night is muted by its recipient within a week.

The test for the severity is [Google SRE's symptom rule](https://sre.google/sre-book/monitoring-distributed-systems/). Page on what the user experiences. Ticket on what only explains it. A saturated queue is a `ticket`. The latency that it later causes is a `page`. With a named test, a reviewer applies a rule and does not make a judgement.

**Error budgets are the other half of that framing, and they route as `ticket`.** [ADR-0500](0500-observability.md) defines the per-service SLIs and the window. So a budget is derivable, and a burn rate is a rule like any other. While no receiver reaches a human, a burn rule does not carry `severity: page`. That severity claims that a human acts within minutes. A fast-burn rule that pages nothing lies about itself. So burn alerts are authored at `ticket`. The escalation trigger below promotes them, and nothing else about them changes.

**What this routing supports limits the objective a project states.** Escalation is absent, so out-of-hours detection is next-working-day, per [`docs/reference/detection-latency.md`](../reference/detection-latency.md). A tighter availability objective is not an alerting gap. It is a claim the platform cannot honour, and the trigger below is its price.

### On-call rotation is deferred, with the seam built

| Field | Value |
| --- | --- |
| **Trigger** | the platform commits to a response-time obligation outside working hours. This is an availability target with consequences, or the first paying customer contract that names one |
| **Seam** | ✓ Alertmanager's webhook receiver. A paging service attaches with a receiver URL and a credential. Alert rules, severities, and the routing tree do not change |
| **Cost if adopted late** | overnight incidents are found in the morning. The rules already have the split between `page` and `ticket`, so nothing is authored again when the pager arrives |

This is a **deferral, not a bet**. The seam exists, and it is the receiver interface that every paging vendor implements.

### What would change this decision

| Change | Effect |
| --- | --- |
| A self-hosted escalation layer becomes credible again | **Decisive on the escalation half**, and nothing else moves. Routing, severities, and the rule files do not depend on what rings the phone |
| The project states an availability objective tighter than next-working-day | **Decisive.** The objective and the paging receiver are one decision, per [ADR-0500](0500-observability.md). An objective without a receiver is a claim nothing can keep |
| Grafana's alerting gains a property that Prometheus rules lack | **None.** Rules as committed files is principle 1, not a feature comparison |
| Alert volume makes the split between `page` and `ticket` unreliable | **None on the mechanism**, and decisive on the rules. It is a symptom of rules at the wrong severity. The answer is to demote rules, not to change where they route |
| A second team needs its own routing tree | **Decisive.** One tree with one owner keeps silences and inhibitions reviewable. Two teams make a routing hierarchy, which is a different design |

## Consequences

### Positive

- Alert rules reach a destination. This makes the rule files of [ADR-0500](0500-observability.md) load-bearing, not decorative.
- The routing tree, silences, and severities are reviewable files, so an alert's destination is a diff.
- One place states the escalation gap, with a measurable trigger. An absence does not imply it.

### Negative and Risks

- **Alertmanager joins Core.** It adds a component whose own failure is silent. Its `Watchdog` alert is the standard answer: a **dead man's switch**. It is a rule that always fires, so only its absence carries information. When a paging service exists, it watches for a missing Watchdog.
- **Nothing pages anyone until the trigger fires.** This platform detects overnight incidents in the morning. That is a deliberate position, not an oversight. A rotation with nobody on it is a page that wakes no one.
- **Email as a `ticket` receiver depends on [ADR-0307](0307-outbound-email.md).** An outbound-mail failure degrades alerting. So mail-path alerts route to the webhook and not to email.
- **Alert fatigue is the failure mode**, and no component prevents it. Review enforces the rule for `page` and `ticket`, and review is weaker than a linter.

## Rules

- Alerts evaluate in Prometheus from committed rule files. Grafana-managed alert rules are not used.
- Alertmanager routes every alert. Its routing tree, receivers, and silences are committed files, never UI state, per principle 1 of [ADR-0000](0000-platform-foundations.md).
- Every alert rule carries `severity: page` or `severity: ticket`. `page` claims that a human must act within minutes. `(CI: lint:alert-severity)`
- Error-budget burn rules are authored against the SLIs in [ADR-0500](0500-observability.md). They carry `severity: ticket` while no paging receiver is attached.
- Maintenance silences are committed, time-bounded, and expire on their own.
- No on-call rotation is claimed until a paging receiver is attached to the webhook.
- Alerts about the outbound-mail path do not route through email.
- The Watchdog routes to its own heartbeat receiver, never to a receiver a human reads. A heartbeat sent to a page destination is an empty message on every repeat interval. It mutes the channel that the pages arrive on.
