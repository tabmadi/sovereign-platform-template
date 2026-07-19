# Observability conventions

Reference for log, metric, trace, and profile conventions. The house style is adopted by reference
([ADR-0019](../adr/0019-prose-logging-output-conventions.md)); this document lists the project specifics on top of it.
Decisions live in [ADR-0011](../adr/0011-observability.md).

## Adopted standards

- **Attribute names and severity:** [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/).
- **Severity ladder:** RFC 5424 (`DEBUG` / `INFO` / `WARN` / `ERROR`).
- **Logs as a stream:** [12-Factor §XI](https://12factor.net/logs) — structured JSON to stdout.

## Logs

- Structured JSON to stdout via `obs.Init`'s `slog` handler. `fmt.Println` for diagnostics is forbidden.
- Message is a short lowercase phrase, no trailing punctuation, **no symbols**. Context is key-value attributes, never
  interpolated into the message string.
- Levels: `DEBUG` (off in prod), `INFO` (lifecycle), `WARN` (recoverable), `ERROR` (failed operation);
  `FATAL`/`PANIC` only on startup.
- `trace_id` / `span_id` are attached automatically from `context.Context`; do not add them by hand.

## Metrics

- Use the `obs.Counter` / `obs.Histogram` API with allow-listed labels. Arbitrary high-cardinality labels
  (`user_id`, `request_id`) as metric attributes are forbidden — they destroy the metrics store.
- Names follow OTel semantic conventions where they exist, else `<service>_<noun>_<unit>_<type>`
  (e.g. `payment_settlement_duration_seconds`).
- Metrics are stored in Prometheus (Core); Mimir is the documented Scale swap
  ([docs/operational-surface.md](../operational-surface.md)).

## Traces

- Propagated via W3C `traceparent` across HTTP and Temporal; the edge preserves it.
- Head sampling only by default (errors 100%, healthy 5% — local dev overrides healthy to 100% so a
  developer sees the request they just made); tail sampling requires the collector gateway tier.

## PII

- No PII in logs, metrics, traces, or profiles. Use `libs/go/observability/redact/` for user/org identifiers.
