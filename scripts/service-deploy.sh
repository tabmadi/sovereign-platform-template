#!/usr/bin/env bash
# A one-time in-cluster deploy from the working tree, for edge, auth, and e2e testing, per ADR-0200 and ADR-0205.
# No watch loop: the daily loop is native execution.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=lib/cluster.sh
source "$LIB/cluster.sh"

CLUSTER="${CLUSTER:-platform}"
NS="platform"

SVC="${1:?usage: mise run cluster:add -- <svc>}"
VALUES="infra/gitops/services/local/values/${SVC}.yaml"
[ -f "$VALUES" ] || fail "missing local values: ${VALUES}"

if [ -d "services/${SVC}" ]; then
  KIND=service
  SVC_DIR="services/${SVC}"
  # The chart's deployment is always <name>-server. Only the image name differs.
  IMAGE="${SVC}-server"
elif [ -d "apps/${SVC}" ]; then
  KIND=app
  SVC_DIR="apps/${SVC}"
  IMAGE="${SVC}"
else
  fail "no such deployable: there is no services/${SVC} and no apps/${SVC}"
fi

k() { kubectl --context "$(cluster_ctx)" -n "$NS" "$@"; }
h() { helm --kube-context "$(cluster_ctx)" "$@"; }

# Start what this service declares it needs, per ADR-0205 and ADR-0600. Without it, a deploy onto a bare base CrashLoops with no clear error.
# Read from the service's config, because `mise tasks deps` resolves only inside the service directory.
# Comment lines are excluded and the name must start with a letter. Otherwise a `dep:*` in prose matches with an empty name.
deps="$(grep -v '^[[:space:]]*#' "${SVC_DIR}/.mise.toml" | grep -o 'dep:[a-z][a-z-]*' | sort -u || true)"
# db-secrets is needed only in the cluster: a service that runs natively reads .env instead. So only this path adds it.
# An app has no database, and the chart mounts no <name>-db secret for it.
if [ "$KIND" = service ]; then
  deps="${deps} dep:db-secrets"
fi
# Only on the inner loop: a `dep:*` is a stand-in, per ADR-0600, and the full tier already runs the real component.
# A stand-in there adds a second database next to CNPG's, for a service whose values point at the real one.
if [ "$(cluster_tier)" = "full" ]; then
  step "full tier: dependencies come from the platform charts, not stand-ins"
  deps=""
fi
for dep in $deps; do
  bash scripts/dep-apply.sh "${dep#dep:}"
done

# In the cluster, siblings resolve by DNS, so they must be present but not port-forwarded. So this calls deploy again, not svc-apply.sh.
# DEPLOYING_SERVICES holds the visited set: nothing enforces an acyclic call graph, and a cycle would start processes without end.
svcs="$(grep -v '^[[:space:]]*#' "${SVC_DIR}/.mise.toml" | grep -o 'svc:[a-z][a-z-]*' | sort -u || true)"
export DEPLOYING_SERVICES="${DEPLOYING_SERVICES:-} ${SVC}"
for s in $svcs; do
  name="${s#svc:}"
  case " ${DEPLOYING_SERVICES} " in
  *" ${name} "*)
    step "${name} already in this deploy chain. Skipping, to stop a cycle"
    continue
    ;;
  esac
  if k rollout status "deploy/${name}-server" --timeout=0 >/dev/null 2>&1; then
    detail "${name} already deployed, skipping"
  else
    step "${SVC} calls ${name}. Deploying it first"
    bash scripts/service-deploy.sh "$name"
  fi
done

# One mechanism for both tiers, because both are kind, per ADR-0600. `kind load docker-image` copies from the host's store into every node with no registry.
publish_image() {
  kind load docker-image "$1" --name "$(cluster_name)" >/dev/null
}

TAG="local-$(date +%s)" # unique tag forces a re-pull of the imported image
# The name is never resolved over the network, and it must still be allow-listed.
# Kyverno matches the reference against `<repo>:*` patterns from image-allowlist.yaml, per ADR-0104.
REPO="${REGISTRY}:5000/${IMAGE}"
WORKER_REPO="${REGISTRY}:5000/${SVC}-worker"
SET=(--set "image.repository=${REPO}" --set "image.tag=${TAG}")

# The build identity in the image, per ADR-0103: the working-tree SHA, with -dirty for uncommitted edits, which is normal on this path.
# So /version and the X-App-Version header report exactly what you deployed.
REV="$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
git diff --quiet 2>/dev/null || REV="${REV}-dirty"

step "building ${REPO}:${TAG}"
if [ "$KIND" = service ]; then
  docker build -t "${REPO}:${TAG}" \
    --build-arg SERVICE="${SVC}" --build-arg APP_CMD=server \
    --build-arg "GIT_SHA=${REV}" --build-arg BUILD_VERSION=local \
    --build-arg "BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    -f "${SVC_DIR}/Dockerfile" .
else
  # `output: "standalone"` freezes next.config into server.js, so the build sets the server-action CSRF allowlist, per ADR-0306.
  docker build -t "${REPO}:${TAG}" \
    --build-arg "SERVICE_VERSION=${REV}" \
    --build-arg "EDGE_PUBLIC_ORIGIN=$(yq -r '.env.EDGE_PUBLIC_ORIGIN // ""' "$VALUES")" \
    -f "${SVC_DIR}/Dockerfile" .
fi
publish_image "${REPO}:${TAG}"

# Build the worker too when this service declares one, as orders and payment do.
if grep -qE '^\s*enabled:\s*true' <(awk '/^worker:/{f=1} f' "$VALUES"); then
  step "building ${WORKER_REPO}:${TAG}"
  docker build -t "${WORKER_REPO}:${TAG}" \
    --build-arg SERVICE="${SVC}" --build-arg APP_CMD=worker \
    --build-arg "GIT_SHA=${REV}" --build-arg BUILD_VERSION=local \
    --build-arg "BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    -f "${SVC_DIR}/Dockerfile" .
  publish_image "${WORKER_REPO}:${TAG}"
  SET+=(--set "worker.image.repository=${WORKER_REPO}" --set "worker.image.tag=${TAG}")
fi

# Pause Argo auto-sync on this service if the full tier manages it.
APP="$(argo_service_app "$SVC")"
if [ -n "$APP" ]; then
  step "pausing ArgoCD auto-sync on ${APP}"
  k -n argocd patch application.argoproj.io "$APP" --type merge \
    -p '{"spec":{"syncPolicy":{"automated":null}}}'
fi

step "helm upgrade ${SVC} with working-tree image ${TAG}"
h upgrade --install "$SVC" infra/helm/service -n "$NS" -f infra/gitops/services/local/shared.yaml -f "$VALUES" \
  --take-ownership --force-conflicts --set image.pullPolicy=IfNotPresent "${SET[@]}" --timeout 5m
k rollout restart "deploy/${SVC}-server"
k rollout status "deploy/${SVC}-server" --timeout=180s
ok "${SVC} deployed from the working tree, tag ${TAG}"
