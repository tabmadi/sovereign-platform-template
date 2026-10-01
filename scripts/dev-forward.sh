#!/usr/bin/env bash
# Port-forward the inner-loop dependencies, so a service that runs natively can reach them, per ADR-0200 and ADR-0205. It runs until stopped.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

CLUSTER="${CLUSTER:-platform}"
# shellcheck source=lib/cluster.sh
source "$LIB/cluster.sh"
NS="platform"
k() { kubectl --context "$(cluster_ctx)" -n "$NS" "$@"; }

step "forwarding deps: postgres 5432, temporal 7233 and 8233. Press Ctrl-C to stop"
pids=()
cleanup() { kill "${pids[@]}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

k port-forward svc/postgres 5432:5432 &
pids+=($!)
k port-forward svc/temporal 7233:7233 &
pids+=($!)
k port-forward svc/temporal 8233:8233 &
pids+=($!)
# Local 18080, not 8080: the local edge maps host 8080. This matches OPENFGA_API_URL in services/*/.env.example.
# Services bind their own registered ports from scripts/lib/ports.sh, so they never collide here.
k port-forward svc/openfga 18080:8080 &
pids+=($!)

# The OTel collector is in its own namespace, per ADR-0200, so it needs its own kubectl call and not the `k` helper.
agent() { kubectl --context "$(cluster_ctx)" -n otel-agent "$@"; }
if agent get svc otel-collector >/dev/null 2>&1; then
  step "observability detected: grafana 3001, faro 12347"
  k port-forward svc/grafana 3001:80 &
  pids+=($!)
  agent port-forward svc/otel-collector 12347:8027 &
  pids+=($!)
fi

wait
