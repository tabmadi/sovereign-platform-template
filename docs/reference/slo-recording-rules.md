# SLO recording rules

The recording rules a project publishes per service so the shared burn-rate alerts in `infra/observability/alerts/slo-burn.yaml` have something to read. Each service's targets live in its own `slo.yaml` ([ADR-0500](../adr/0500-observability.md)).

The alerts evaluate over an empty set until these exist, and never fire. That is the correct state for a service whose owner has not chosen a target.

## Availability — one rule

Availability needs only the target per service; the ratio rules are generic and already ship in `slo-burn.yaml`.

```yaml
- record: service:slo_availability_target:ratio
  expr: 0.995
  labels: { service_name: <this service> }
```

## Latency — two rules

Latency needs the service's own threshold inside the query, as an `le` label selector on the histogram, and PromQL cannot take a label selector from a series. The ratio is therefore per service, and only its burn alerts are shared.

Publish one ratio per window — 5m, 30m, 1h and 6h, the four the burn alerts pair — with `le` set to the service's threshold and `service_name` to the service:

```yaml
- record: service:request_latency_errors:ratio_rate5m
  expr: |
    1 - (
      sum(rate(http_server_request_duration_seconds_bucket{service_name="<this service>",le="0.5"}[5m]))
        / (sum(rate(http_server_request_duration_seconds_count{service_name="<this service>"}[5m])) > 0)
    )
  labels: { service_name: <this service> }
```

And the objective, once chosen:

```yaml
- record: service:slo_latency_target:ratio
  expr: 0.99
  labels: { service_name: <this service> }
```

`le` must match a bucket boundary the histogram has. A value between boundaries selects the next bucket up, so the SLI measures a looser threshold than `slo.yaml` states — the one failure here that produces a green dashboard rather than an empty one.
