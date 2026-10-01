# SLO recording rules

A project publishes these recording rules for each service. The shared burn-rate alerts in `infra/observability/alerts/slo-burn.yaml` read them. Each service's targets live in its own `slo.yaml`, per [ADR-0500](../adr/0500-observability.md).

Until these rules exist, the alerts evaluate over an empty set and never fire. This is the correct state for a service whose owner has not chosen a target.

## Availability: one rule

Availability needs only the target for each service. The ratio rules are generic, and `slo-burn.yaml` already ships them.

```yaml
- record: service:slo_availability_target:ratio
  expr: 0.995
  labels: { service_name: <this service> }
```

## Latency: two rules

Latency needs the service's own threshold inside the query, as an `le` label selector on the histogram. PromQL cannot take a label selector from a series. So the ratio is per service, and only its burn alerts are shared.

Publish one ratio for each of the four windows that the burn alerts pair: 5m, 30m, 1h, and 6h. Set `le` to the service's threshold and `service_name` to the service:

```yaml
- record: service:request_latency_errors:ratio_rate5m
  expr: |
    1 - (
      sum(rate(http_server_request_duration_seconds_bucket{service_name="<this service>",le="0.5"}[5m]))
        / (sum(rate(http_server_request_duration_seconds_count{service_name="<this service>"}[5m])) > 0)
    )
  labels: { service_name: <this service> }
```

When the owner chooses the objective, publish it too:

```yaml
- record: service:slo_latency_target:ratio
  expr: 0.99
  labels: { service_name: <this service> }
```

`le` must match a bucket boundary of the histogram. A value between boundaries selects the next bucket up. The SLI then measures a looser threshold than `slo.yaml` states. This is the one failure here that gives a green dashboard and not an empty one.
