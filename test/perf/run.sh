#!/usr/bin/env bash
# k6 runner, per ADR-0601. It connects a scenario to the cluster's telemetry plane, then runs it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
# ../../ because this file is at test/perf/, two levels under the repo root.
source ../../scripts/lib/log.sh

scenario="${1:-}"
profile="${2:-smoke}"
[ -n "$scenario" ] || fail "usage: test/perf/run.sh <scenario> [profile]"

script="scenarios/${scenario}.js"
[ -f "$script" ] || fail "no such scenario: ${script}"

CLUSTER="${CLUSTER:-platform}"
source ../../scripts/lib/cluster.sh
# The library works from the repository root. The scenario and result paths below are relative to this directory.
cd "$here"
# The tier comes from the cluster that is up. So a load run with no cluster reports `no cluster`,
# and does not report a forward that could never work.
require_cluster
# Loopback port for the collector forward. It is high and specific, so it does not collide with the e2e suite's forwards,
# 13100, 13200, and 19090, when both run.
OTLP_PORT="${PERF_OTLP_PORT:-14317}"

k6_args=(run "$script")

# Anonymous usage reporting is off, the same as the phone-home setting for Temporal and MinIO in this repo.
k6_args+=(--no-usage-report)

# The Prometheus series expire with the TSDB retention, so a run whose numbers matter needs a file. It is gitignored: results are evidence for a PR, not repo content.
mkdir -p results
k6_args+=(--summary-export "results/${scenario}-${profile}.json")

if [ "${PERF_OTLP:-1}" = "1" ]; then
  step "forwarding otel-collector :${OTLP_PORT} → svc/otel-collector:4317"
  # `otel-agent`, not `platform`: the collector runs in its own namespace, because of hostPath and hostPorts, per ADR-0200.
  kubectl --context "$(cluster_ctx)" -n otel-agent port-forward svc/otel-collector "${OTLP_PORT}:4317" >/dev/null 2>&1 &
  pf=$!
  trap 'kill "$pf" 2>/dev/null || true' EXIT
  # Wait for the forward, and do not sleep for a guessed time. If the forward is not up yet, k6 drops all metrics of the run and reports nothing.
  for _ in $(seq 1 40); do
    if (echo >"/dev/tcp/127.0.0.1/${OTLP_PORT}") 2>/dev/null; then break; fi
    sleep 0.25
  done
  if ! (echo >"/dev/tcp/127.0.0.1/${OTLP_PORT}") 2>/dev/null; then
    fail "otel-collector port-forward did not come up on the $(cluster_tier) tier.
  The collector comes with the observability stack, so a base tier has none.
  PERF_OTLP=0 runs the scenario without exporting metrics."
  fi

  export K6_OTEL_GRPC_EXPORTER_ENDPOINT="127.0.0.1:${OTLP_PORT}"
  export K6_OTEL_GRPC_EXPORTER_INSECURE="true"
  # The collector's OTLP translation makes service.name a Prometheus label. This value keeps load metrics apart from a platform service's own metrics.
  export K6_OTEL_SERVICE_NAME="k6"
  # Namespace k6's built-ins: bare `http_req_duration` and `http_reqs` would take names in the shared Prometheus namespace,
  # next to the platform's own `http_server_request_duration_seconds`, per ADR-0500.
  # The prefix also covers the scenarios' custom metrics, so those have bare names.
  export K6_OTEL_METRIC_PREFIX="k6_"
  # Export often. The default interval is longer than a smoke run, and the run would end with its metrics still in the exporter's buffer.
  export K6_OTEL_EXPORT_INTERVAL="5s"
  export K6_OTEL_FLUSH_INTERVAL="1s"
  k6_args+=(--out opentelemetry)
else
  warn "PERF_OTLP=0: metrics stay local to this terminal, and nothing reaches Grafana"
fi

export PERF_PROFILE="$profile"
step "k6 ${scenario} @ profile=${profile} → ${PERF_HOST:-dev.localtest.me:8443}"

# The Overview landing page does not link the Load test dashboard, per ADR-0501, so this line is its entry point. It prints before the run, so you can watch live.
started_ms="$(($(date +%s) * 1000))"
if [ "${PERF_OTLP:-1}" = "1" ]; then
  host="${PERF_GRAFANA_HOST:-grafana.ops.${PERF_HOST:-dev.localtest.me:8443}}"
  detail "watch it: https://${host}/d/load-test/load-test?var-scenario=${scenario}&from=${started_ms}&to=now"
fi

# `|| k6_status=$?` and not a bare call: k6 exits non-zero when a threshold is breached.
# Under `set -e`, a bare call would stop the script here and lose the last link on the runs where the graphs matter most.
k6_status=0
k6 "${k6_args[@]}" || k6_status=$?

# Print the link again at the end with a closed window. So a finished run leaves a link to its own time range, not to a moving `to=now`.
if [ "${PERF_OTLP:-1}" = "1" ]; then
  detail "this run: https://${host}/d/load-test/load-test?var-scenario=${scenario}&from=${started_ms}&to=$(($(date +%s) * 1000))"
fi
exit "$k6_status"
