# ADR-0301: Data Lifecycle and Privacy

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0200](0200-cluster-topology.md), [ADR-0300](0300-data.md), [ADR-0302](0302-temporal.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0304](0304-identity-and-authorization.md), [ADR-0500](0500-observability.md)
- **Decides:** Every stored category is classified with a declared retention, and personal data is tagged in the DDL that creates it.

## Context

[ADR-0500](0500-observability.md) forbids PII in telemetry and provides redaction. That leaves the data the platform stores **on purpose**. It needs a decision on how long it is kept, how it is erased, and how a subject access request is served.

A multi-tenant application with a meaningful count of monthly active users has obligations: retention, the right to erasure, and portability. Once data has spread across services, adding these later is expensive.

The obligations come from these [GDPR](https://eur-lex.europa.eu/eli/reg/2016/679/oj) articles:

| Article | Obligation |
| --- | --- |
| `Art. 15` | access |
| `Art. 17` | erasure |
| `Art. 20` | portability |
| `Art. 5(1)(e)` | storage limitation |

This ADR names them because they set the deadline and the scope of the machinery it builds. The platform is not a compliance product. A project under a different regime uses its own articles, and the mechanism below does not change.

## Decision drivers

1. **Erasure and export are correct across stores**: the application database *and* OpenFGA, per [ADR-0304](0304-identity-and-authorization.md). Otherwise a deleted subject still appears in authz tuples.
2. **A half-completed erasure is worse than one that has not started.** The deadline is one month from the request, per GDPR `Art. 12(3)`. So the process survives a partial failure and resumes. It does not restart from an unknown point.
3. **One execution states whether a subject is erased.** Whatever runs it can report this without correlating the logs of several services.
4. **Retention is declared, not accidental.** Every stored category has a class and a lifespan.
5. **A machine can identify PII**, so retention, export, and redaction target it mechanically, not by memory.

## Considered options

| Option | Survives a partial failure | Spans stores outside one database | How it shows the request is done | Verdict |
| --- | --- | --- | --- | --- |
| **Temporal workflows for erasure, DSAR, and retention** | yes: each activity retries, and the execution resumes where it stopped | yes, including OpenFGA | one execution, and its event history is the audit trail | **Chosen.** The obligation is a long-running, multi-store mutation with a deadline. [ADR-0302](0302-temporal.md) already buys a primitive for that shape *(reasoned)* |
| Outbox events, consumed per service | yes, per hop | yes, eventually | only by correlating every consumer | No single execution owns the request. [ADR-0302](0302-temporal.md) keeps the outbox for fire-and-forget work, and a legal deadline is not fire-and-forget |
| A dedicated erasure service that calls the API of each owning service | only after it implements its own retries, timers, and state | yes | its own store, once built | This rebuilds Temporal's job inside one service, while Temporal is already Core |
| Change data capture, such as Debezium | yes | yes | not directly: the same correlation problem, plus a connector | It adds a component and a second delivery path. The platform can already answer the question directly |
| A scheduled script per service | no | no: nothing coordinates OpenFGA | logs only | It produces the exact failure that driver 1 names |
| Database-level cascade deletes | within one transaction | no | none | OpenFGA is not in the database, and neither is the data of another service |
| A manual runbook on request, the honest baseline | no | only as far as the operator is thorough | a ticket | Latency has no bound, and correctness depends on who runs it |

## Decision

| Concern | Mechanism |
| --- | --- |
| **Data classes** | Every stored category has a class and a declared retention period. The classes are operational, PII, audit, and telemetry. [ADR-0500](0500-observability.md) owns telemetry retention and [ADR-0200](0200-cluster-topology.md) owns backups. This ADR owns application data |
| **PII tagging** | A column with personal data carries `COMMENT ON COLUMN ... IS 'pii:<class>'` in the migration that creates it, per [ADR-0300](0300-data.md). The tag lives in the DDL, moves with the schema, and is readable from `pg_description`. So erasure, export, and redaction find their targets by query, not by memory |
| **Right to erasure** | A Temporal workflow erases or anonymises the subject's rows in every owning service. It **also** removes the matching OpenFGA tuples, as dual-write activities |
| **Subject access and portability** | A Temporal workflow collects the subject's data from services through their APIs, per [ADR-0303](0303-api-contracts-and-lifecycle.md), and produces an export |
| **Retention enforcement** | A Temporal `Schedule` prunes or anonymises data past its class's retention. Each run's event history records that the run happened, and what it changed |

The choice between anonymise and hard delete is a per-category decision, recorded with the data class. Audit data can carry a retention obligation that an erasure request cannot override.

## Consequences

### Positive

- Erasure and export are correct across the application database and OpenFGA by construction. They do not depend on an engineer who remembers to also run something against authz.
- Retention is a declared property of each class, enforced on a schedule.
- PII tagging makes redaction and erasure target the right fields.

### Negative and Risks

- **Every service implements erasure and DSAR activities for the data it owns.** Accepted: it is the same per-service dual-write discipline that authz already requires.
- **A new service can silently omit them.** The omission shows only on the first request that needs it. The data-class registry reduces this: it is the checklist for the review of a new service.

## Rules

- Every stored data category has a declared class and retention period, enforced by a Temporal `Schedule`.
- A column with personal data carries a `pii:<class>` column comment in the migration that creates it. So erasure, export, and redaction find their targets by query. `(CI: lint:sql)`
- Right to erasure and DSAR run as Temporal workflows that act across every owning service **and** OpenFGA. A raw multi-store delete script is not used.
- The choice between anonymise and delete is recorded per data class, never decided per request.
