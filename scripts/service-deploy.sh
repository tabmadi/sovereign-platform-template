#!/usr/bin/env bash
# One-shot in-cluster deploy of a service from the WORKING TREE (ADR-0003,
# ADR-0016) — the occasional "I need my uncommitted service in the cluster for
# edge/auth/e2e testing" case. No watch loop (that was Skaffold's job; the daily
# loop is native execution). Builds the image(s), imports them into k3d, and helm-
# upgrades the same chart prod uses with the local values overlay.
#
#   mise run service:deploy -- <svc>
#
# If the full tier (ArgoCD) manages this service, its auto-sync is paused first so
# self-heal does not revert your local image; re-enable with:
#   argocd app set local-svc-<svc> --sync-policy automated   (or just cluster:full)
set -euo pipefail

CLUSTER="${CLUSTER:-platform}"
NS="platform"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SVC="${1:?usage: mise run service:deploy -- <svc>}"
SVC_DIR="services/${SVC}"
VALUES="infra/gitops/services/local/values/${SVC}.yaml"
[ -d "$SVC_DIR" ] || { echo "✗ no such service: ${SVC_DIR}" >&2; exit 1; }
[ -f "$VALUES" ]  || { echo "✗ missing local values: ${VALUES}" >&2; exit 1; }

k() { kubectl --context "k3d-${CLUSTER}" -n "$NS" "$@"; }
h() { helm --kube-context "k3d-${CLUSTER}" "$@"; }

TAG="local-$(date +%s)"   # unique tag forces a re-pull of the imported image
SET=(--set "image.repository=${SVC}-server" --set "image.tag=${TAG}")

echo "→ building ${SVC}-server"
docker build -t "${SVC}-server:${TAG}" \
  --build-arg SERVICE="${SVC}" --build-arg APP_CMD=server \
  -f "${SVC_DIR}/Dockerfile" .
k3d image import "${SVC}-server:${TAG}" -c "$CLUSTER"

# Build the worker too when this service declares one (orders, payment).
if grep -qE '^\s*enabled:\s*true' <(awk '/^worker:/{f=1} f' "$VALUES"); then
  echo "→ building ${SVC}-worker"
  docker build -t "${SVC}-worker:${TAG}" \
    --build-arg SERVICE="${SVC}" --build-arg APP_CMD=worker \
    -f "${SVC_DIR}/Dockerfile" .
  k3d image import "${SVC}-worker:${TAG}" -c "$CLUSTER"
  SET+=(--set "worker.image.repository=${SVC}-worker" --set "worker.image.tag=${TAG}")
fi

# Pause Argo auto-sync on this service if the full tier manages it.
if k -n argocd get application.argoproj.io "local-svc-${SVC}" >/dev/null 2>&1; then
  echo "→ pausing ArgoCD auto-sync on local-svc-${SVC}"
  k -n argocd patch application.argoproj.io "local-svc-${SVC}" --type merge \
    -p '{"spec":{"syncPolicy":{"automated":null}}}'
fi

echo "→ helm upgrade ${SVC} (working-tree image ${TAG})"
h upgrade --install "$SVC" infra/helm/service -n "$NS" -f "$VALUES" \
  --set image.pullPolicy=IfNotPresent "${SET[@]}" --timeout 5m
k rollout restart "deploy/${SVC}-server"
k rollout status  "deploy/${SVC}-server" --timeout=180s
echo "✓ ${SVC} deployed from working tree (tag ${TAG})"
