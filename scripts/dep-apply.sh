#!/usr/bin/env bash
# Add one opt-in local dependency component on top of `cluster:up`, backing the `dep:*` tasks services declare (ADR-0205, ADR-0600).
set -euo pipefail

source "$(dirname "$0")/lib/log.sh"
source "$(dirname "$0")/lib/cluster.sh"

CLUSTER="${CLUSTER:-platform}"
NS="platform"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

COMPONENT="${1:?usage: bash scripts/dep-apply.sh <component>}"

# The guard below reads a failed probe as "not up". Assert the probe can actually
# run first, so an unreachable cluster fails loudly instead of re-applying blindly.
require_cluster

k() { kubectl --context "$(cluster_ctx)" "$@"; }

# Each component names the resource whose existence-and-readiness means "already
# up". Deployments get a rollout wait; Secrets are either there or not.
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
  fail "unknown component: ${COMPONENT} (known: postgres, temporal, openfga, db-secrets)"
  ;;
esac

# `rollout status --timeout=0` returns non-zero rather than blocking when the
# Deployment is not yet complete, which is exactly the "up or not?" question.
if [ "$kind" = deploy ]; then
  if k -n "$NS" rollout status "deploy/${probe}" --timeout=0 >/dev/null 2>&1; then
    detail "dep:${COMPONENT} already up — skipping"
    exit 0
  fi
elif k -n "$NS" get "secret/${probe}" >/dev/null 2>&1; then
  detail "dep:${COMPONENT} already up — skipping"
  exit 0
fi

step "adding dep:${COMPONENT}"
# The namespace is not in this file — it comes from the namespaces chart, with its
# pod-security profile (ADR-0200). What is selected here is the component itself.
k apply -f infra/local/deps.yaml -l "local.platform/component=${COMPONENT}"

if [ "$kind" = deploy ]; then
  k -n "$NS" rollout status "deploy/${probe}" --timeout=180s
fi
