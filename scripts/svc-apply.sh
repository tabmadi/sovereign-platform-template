#!/usr/bin/env bash
# Make one sibling service reachable from a process that runs natively. It backs the `svc:*` tasks that services declare, per ADR-0205 and ADR-0600.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=lib/ports.sh
source "$LIB/ports.sh"
# shellcheck source=lib/cluster.sh
source "$LIB/cluster.sh"

CLUSTER="${CLUSTER:-platform}"
NS="platform"

SVC="${1:?usage: bash scripts/svc-apply.sh <service>}"
[ -d "services/${SVC}" ] || fail "no such service: services/${SVC}"

PORT="$(service_port "$SVC")"
RUNDIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/platform-local"
PIDFILE="${RUNDIR}/portforward-${SVC}.pid"

# Before any guard: a probe that cannot run must not count as `not up`. Otherwise the next step builds images against an unreachable cluster.
require_cluster

k() { kubectl --context "$(cluster_ctx)" -n "$NS" "$@"; }

# Probe the local port with bash's /dev/tcp, not curl. It only checks that something listens.
# It does not depend on a health endpoint, on auth, or on a finished startup.
port_open() { (exec 3<>"/dev/tcp/127.0.0.1/${PORT}") >/dev/null 2>&1; }

# The same contract as dep-apply.sh: exit at once when already satisfied, so each `mise run worker` stays cheap.
# Without it, each run would deploy again a service that is already up.
if port_open; then
  detail "svc:${SVC} already reachable on :${PORT}, skipping"
  exit 0
fi

# A stale pidfile means a forward stopped, after a cluster restart or a laptop sleep. Clear it before a new forward, so the pidfile never outlives its process.
if [ -f "$PIDFILE" ]; then
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
fi

# Deploy only if it is not there. `cluster:add -- <svc>` is the same code path, so this uses a service you deployed by hand and does not rebuild it.
if k rollout status "deploy/${SVC}-server" --timeout=0 >/dev/null 2>&1; then
  detail "svc:${SVC} already deployed, forwarding only"
else
  step "svc:${SVC}: deploying, because the caller needs it and you are not working on it"
  bash scripts/service-deploy.sh "$SVC"
fi

# :80 is the Service port, not the container's :8080: infra/helm/service/templates/service.yaml maps 80 → targetPort http.
# A forward to 8080 fails, because a svc/ port-forward resolves against the Service's declared ports.
step "svc:${SVC}: forwarding :${PORT} → ${SVC}-server:80"
mkdir -p "$RUNDIR"

# Detached, because a mise task must return for the graph to continue, and the forward must outlive it.
# This is the only process management in the dev loop. It stays here, uses a pidfile, and cluster:remove stops it.
nohup kubectl --context "$(cluster_ctx)" -n "$NS" \
  port-forward "svc/${SVC}-server" "${PORT}:80" \
  >"${RUNDIR}/portforward-${SVC}.log" 2>&1 &
echo $! >"$PIDFILE"

for _ in $(seq 1 50); do
  port_open && break
  sleep 0.2
done

port_open || fail "svc:${SVC}: port-forward did not start. See ${RUNDIR}/portforward-${SVC}.log"
ok "svc:${SVC} reachable on :${PORT}"
