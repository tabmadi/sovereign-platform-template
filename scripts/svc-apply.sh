#!/usr/bin/env bash
# Make one sibling service reachable from a natively-run process, backing the `svc:*` tasks services declare (ADR-0205, ADR-0600).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/ports.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/cluster.sh"

CLUSTER="${CLUSTER:-platform}"
NS="platform"

SVC="${1:?usage: bash scripts/svc-apply.sh <service>}"
[ -d "services/${SVC}" ] || fail "no such service: services/${SVC}"

PORT="$(service_port "$SVC")"
RUNDIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/platform-local"
PIDFILE="${RUNDIR}/portforward-${SVC}.pid"

# Before any guard: a probe that CANNOT run must not be read as "not up", or the
# fall-through starts building images against an unreachable cluster.
require_cluster

k() { kubectl --context "$(cluster_ctx)" -n "$NS" "$@"; }

# Probe the local port with bash's /dev/tcp rather than curl: it asks the only
# question that matters (is something listening?) without caring whether the
# service has a health endpoint, needs auth, or is mid-startup.
port_open() { (exec 3<>"/dev/tcp/127.0.0.1/${PORT}") >/dev/null 2>&1; }

# Same contract as dep-apply.sh: fast-exit when already satisfied, so re-entering
# the graph on every `mise run worker` stays cheap. Without it each run would
# re-deploy a service that is already up.
if port_open; then
  detail "svc:${SVC} already reachable on :${PORT} — skipping"
  exit 0
fi

# A stale pidfile means a forward died (cluster restart, laptop sleep). Clear it
# before starting a new one so the pidfile never outlives its process.
if [ -f "$PIDFILE" ]; then
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
fi

# Deploy only if it isn't there. `cluster:add -- <svc>` is the same code path, so a
# service you deployed by hand earlier is picked up rather than rebuilt.
if k rollout status "deploy/${SVC}-server" --timeout=0 >/dev/null 2>&1; then
  detail "svc:${SVC} deployed already — forwarding only"
else
  step "svc:${SVC}: deploying (the caller needs it; you are not working on it)"
  bash scripts/service-deploy.sh "$SVC"
fi

# :80 is the SERVICE port, not the container's :8080 — infra/helm/service/templates/
# service.yaml maps 80 → targetPort http. Forwarding to 8080 fails outright, since a
# svc/ port-forward resolves against the Service's declared ports.
step "svc:${SVC}: forwarding :${PORT} → ${SVC}-server:80"
mkdir -p "$RUNDIR"

# Detached, because a mise task must return for the graph to continue but the
# forward has to outlive it. This is the one piece of process management in the dev
# loop; it is confined here, keyed by a pidfile, and torn down by cluster:remove.
nohup kubectl --context "$(cluster_ctx)" -n "$NS" \
  port-forward "svc/${SVC}-server" "${PORT}:80" \
  >"${RUNDIR}/portforward-${SVC}.log" 2>&1 &
echo $! >"$PIDFILE"

for _ in $(seq 1 50); do
  port_open && break
  sleep 0.2
done

port_open || fail "svc:${SVC}: port-forward did not come up — see ${RUNDIR}/portforward-${SVC}.log"
ok "svc:${SVC} reachable on :${PORT}"
