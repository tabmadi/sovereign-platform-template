#!/usr/bin/env bash
# Print what the ops tier says after a failed e2e run, because a forge run keeps no cluster and no report, per ADR-0601.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
TIER="${TIER:-full}"
# shellcheck source=lib/cluster.sh
source "$LIB/cluster.sh"
require_cluster

# The workloads that sit on the path of an ops route, in the order that a request meets them.
for workload in ory-oathkeeper authz-server orgs-server grafana temporal-web mailpit; do
  step "${workload}"
  k -n "$NS" logs "deploy/${workload}" --tail=4000 2>&1 |
    grep -E 'level=(ERROR|error|WARN|warn)|status=[45][0-9][0-9]|panic' | grep -v -E 'status=401' | tail -40 | cut -c1-300 || true
done
step "edge"
k -n kube-system logs deploy/traefik --tail=60 2>&1 || warn "traefik has no logs"
