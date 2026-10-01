#!/usr/bin/env bash
# Add one opt-in local dependency component on top of `cluster:up`. It backs the `dep:*` tasks that services declare, per ADR-0205 and ADR-0600.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=lib/cluster.sh
source "$LIB/cluster.sh"

CLUSTER="${CLUSTER:-platform}"
NS="platform"

COMPONENT="${1:?usage: bash scripts/dep-apply.sh <component>}"

# The guard below reads a failed probe as `not up`. So check first that the probe can run.
# Then an unreachable cluster fails with an error, and nothing is applied again blindly.
require_cluster

k() { kubectl --context "$(cluster_ctx)" "$@"; }

# Each component names the resource whose existence and readiness mean `already up`.
# Deployments get a rollout wait. A Secret exists or it does not.
case "$COMPONENT" in
postgres)
  kind=deploy
  probe=postgres
  ;;
temporal)
  kind=deploy
  probe=temporal
  ;;
openfga)
  kind=deploy
  probe=openfga
  ;;
db-secrets)
  kind=secret
  probe=orders-db
  ;;
*)
  fail "unknown component: ${COMPONENT}. Known: postgres, temporal, openfga, db-secrets"
  ;;
esac

# `rollout status --timeout=0` returns non-zero and does not block when the Deployment is not complete. That answers `up or not`.
if [ "$kind" = deploy ]; then
  if k -n "$NS" rollout status "deploy/${probe}" --timeout=0 >/dev/null 2>&1; then
    detail "dep:${COMPONENT} already up, skipping"
    exit 0
  fi
elif k -n "$NS" get "secret/${probe}" >/dev/null 2>&1; then
  detail "dep:${COMPONENT} already up, skipping"
  exit 0
fi

step "adding dep:${COMPONENT}"
# The namespace is not in this file. It comes from the namespaces chart, with its pod-security profile, per ADR-0200.
# The selection here is the component itself.
k apply -f infra/local/deps.yaml -l "local.platform/component=${COMPONENT}"

if [ "$kind" = deploy ]; then
  k -n "$NS" rollout status "deploy/${probe}" --timeout=180s
fi
