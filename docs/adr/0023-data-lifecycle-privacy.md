# ADR-0023: Data Lifecycle & Privacy

- **Status:** Accepted
- **Date:** 2026-07-06
- **Deciders:** Platform team
- **Related:** [ADR-0006](0006-temporal.md), [ADR-0007](0007-data.md), [ADR-0010](0010-auth.md), [ADR-0011](0011-observability.md)

## Context

[ADR-0011](0011-observability.md) forbids PII in telemetry and provides redaction, but the platform has no
decision on the *data* it deliberately stores: how long it is kept, how it is erased, and how a subject
access request is served. A multi-tenant application at meaningful MAU has GDPR/CCPA obligations
(retention limits, right-to-erasure, data portability) that cannot be retrofitted cheaply once data has
accreted across services.

## Decision drivers

1. **Erasure and export must be correct across stores** — application DB *and* OpenFGA
   ([ADR-0010](0010-auth.md)), or a user is "deleted" but still appears in authz tuples.
2. **A durable, auditable process**, not a hand-run script — the same reliability primitive as every other
   cross-store mutation ([ADR-0006](0006-temporal.md)).
3. **Retention is declared, not incidental** — data has a class and a lifespan.
4. **PII is identifiable** so retention and redaction can target it.

## Decision

- **Data classes with retention.** Every stored data category is classified (operational, PII, audit,
  telemetry) with a declared retention period. Telemetry retention is [ADR-0011](0011-observability.md)'s;
  backups are [ADR-0003](0003-cluster-topology.md)'s; this ADR owns application-data retention.
- **PII is tagged at the schema level.** Columns holding personal data are annotated so erasure, export,
  and redaction can target them mechanically rather than by tribal knowledge.
- **Right-to-erasure is a Temporal workflow.** A deletion request runs a workflow that erases or
  anonymises the subject's rows across every owning service *and* removes the corresponding OpenFGA tuples,
  as dual-write activities ([ADR-0006](0006-temporal.md), [ADR-0010](0010-auth.md)). This is the only
  correct way to keep the application DB and the authz store consistent through a delete.
- **DSAR (access/portability) is a Temporal workflow** that gathers the subject's data across services via
  their APIs ([ADR-0008](0008-api-contracts.md)) and produces an export.
- **Retention enforcement is a Temporal `Schedule`** that prunes or anonymises data past its class's
  retention, opening a tracking record — matching the quarterly-audit pattern in
  [ADR-0011](0011-observability.md).

## Consequences

### Positive

- Erasure and export are correct across the application DB and OpenFGA by construction, not by a script an
  engineer remembers to also run against authz.
- Retention is a declared property of each data class, enforced on a schedule, not left to grow unbounded.
- PII tagging makes redaction ([ADR-0011](0011-observability.md)) and erasure target the right fields.

### Negative / Risks

- Every authz-relevant service must implement the erasure/DSAR activities for the data it owns. Accepted;
  it is the same per-service dual-write discipline authz already requires.
- Anonymise-vs-hard-delete is a per-category judgement (audit data may need retention that erasure
  requests cannot override). Documented per data class, not left implicit.

### Follow-ups

- A data-class + retention registry, and the schema-level PII tagging convention.
- Erasure and DSAR workflows in the owning services; a retention `Schedule`.
- `docs/data/lifecycle.md` with the classes, retention periods, and the erasure/DSAR procedure.

## Rules

- Every stored data category has a declared class and retention period; retention is enforced by a Temporal
  `Schedule`. `(review-only)`
- Personal data columns are tagged at the schema level so erasure, export, and redaction target them
  mechanically. `(review-only)`
- Right-to-erasure and DSAR run as Temporal workflows that act across every owning service **and** OpenFGA;
  a raw multi-store delete script is forbidden ([ADR-0010](0010-auth.md)). `(review-only)`
