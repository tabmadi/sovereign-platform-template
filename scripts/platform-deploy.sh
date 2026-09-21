#!/usr/bin/env bash
# One-shot working-tree overlay of a platform chart (ADR-0205). Pauses ArgoCD auto-sync on that one app so self-heal does not revert it.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

CLUSTER="${CLUSTER:-platform}"
# shellcheck source=lib/cluster.sh
source "$LIB/cluster.sh"
NS="platform"

CHART="${1:?usage: mise run platform:deploy -- <chart>}"
CHART_DIR="infra/helm/platform/${CHART}"
[ -d "$CHART_DIR" ] || fail "no such platform chart: ${CHART_DIR}"

k() { kubectl --context "$(cluster_ctx)" "$@"; }
h() { helm --kube-context "$(cluster_ctx)" "$@"; }

# `lowdefy build` bakes apps/admin's YAML pages into the image (ADR-0401), so a chart change alone is not enough.
if [ "$CHART" = "lowdefy" ]; then
  REG="registry.localhost:5000"
  step "regenerating admin pages + rebuilding the admin image (${REG}/admin:local)"
  bash scripts/gen-admin.sh
  docker build -t "${REG}/admin:local" -f apps/admin/Dockerfile apps/admin
  docker push "${REG}/admin:local"
fi

APP="local-platform-${CHART}"
if k -n argocd get application.argoproj.io "$APP" >/dev/null 2>&1; then
  step "pausing ArgoCD auto-sync on ${APP}"
  k -n argocd patch application.argoproj.io "$APP" --type merge \
    -p '{"spec":{"syncPolicy":{"automated":null}}}'
fi

# Mirror what the platform ApplicationSet supplies; keep in step with appset-platform.yaml.
# The appset applies both auth value files to every chart, and omitting them fails silently: Kratos CrashLoops on `missing properties: "schemas"`, and Oathkeeper reports Ready with empty accessRules.
extra_args=(
  -f infra/auth/kratos/values.yaml
  -f infra/auth/oathkeeper/values.yaml
)
case "$CHART" in
openfga)
  # Without this seed.model is empty and the seed Job is disabled (no store is
  # created) — ADR-0304.
  extra_args+=(--set-file "seed.model=infra/auth/openfga/model.json")
  ;;
ory)
  extra_args+=(
    --set-file 'kratos.kratos.identitySchemas.user\.v1\.json=infra/auth/kratos/identity-schemas/user.v1.json'
    --set-file 'oathkeeper.oathkeeper.accessRules=infra/auth/oathkeeper/access-rules.json'
  )
  ;;
esac

step "helm upgrade ${CHART} from the working tree"
h dependency update "$CHART_DIR" >/dev/null
# Value-file order matches the ApplicationSet: auth overlays first, the per-env overlay last so it wins.
h upgrade --install "$CHART" "$CHART_DIR" -n "$NS" \
  --take-ownership --force-conflicts "${extra_args[@]}" \
  -f infra/gitops/platform/local/values.yaml --timeout 8m

# lowdefy's image tag is stable (:local), so helm sees no change to trigger a
# rollout; restart explicitly to re-pull the image just rebuilt above.
if [ "$CHART" = "lowdefy" ]; then
  step "restarting lowdefy to re-pull the rebuilt image"
  k -n "$NS" rollout restart deploy/lowdefy
  k -n "$NS" rollout status deploy/lowdefy --timeout=180s
fi
ok "${CHART} overlaid from working tree."
detail "Re-enable GitOps when done:"
detail "  kubectl -n argocd patch application.argoproj.io ${APP} --type merge \\"
detail "    -p '{\"spec\":{\"syncPolicy\":{\"automated\":{\"prune\":true,\"selfHeal\":true}}}}'"
