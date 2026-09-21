#!/usr/bin/env bash
# One-shot in-cluster deploy from the working tree, for edge, auth and e2e testing (ADR-0200, ADR-0205). No watch loop: the daily loop is native execution.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/cluster.sh"

CLUSTER="${CLUSTER:-platform}"
NS="platform"

SVC="${1:?usage: mise run service:deploy -- <svc>}"
VALUES="infra/gitops/services/local/values/${SVC}.yaml"
[ -f "$VALUES" ] || fail "missing local values: ${VALUES}"

if [ -d "services/${SVC}" ]; then
  KIND=service
  SVC_DIR="services/${SVC}"
  # The chart's deployment is always <name>-server; only the image name differs.
  IMAGE="${SVC}-server"
elif [ -d "apps/${SVC}" ]; then
  KIND=app
  SVC_DIR="apps/${SVC}"
  IMAGE="${SVC}"
else
  fail "no such deployable: neither services/${SVC} nor apps/${SVC}"
fi

k() { kubectl --context "$(cluster_ctx)" -n "$NS" "$@"; }
h() { helm --kube-context "$(cluster_ctx)" "$@"; }

# Bring up what this service declares it needs (ADR-0205, ADR-0600): without it a deploy onto a bare base silently CrashLoops.
# Read straight from the service's config — `mise tasks deps` only resolves from inside the service directory.
# Comment lines are excluded and the name must start with a letter, or a prose `dep:*` matches with an empty component name.
deps="$(grep -v '^[[:space:]]*#' "${SVC_DIR}/.mise.toml" | grep -o 'dep:[a-z][a-z-]*' | sort -u || true)"
# db-secrets is an in-cluster-only need: a natively-run service reads .env instead,
# so it is not in the service's own task graph and is added on this path alone. An
# app has no database, and the chart mounts it no <name>-db secret.
if [ "$KIND" = service ]; then
  deps="${deps} dep:db-secrets"
fi
# Only on the inner loop: a `dep:*` is a stand-in (ADR-0600), and the full tier already runs the real component.
# Applying one there adds a second database beside CNPG's for a service whose values point at the real one.
if [ "$(cluster_tier)" = "full" ]; then
  step "full tier: dependencies come from the platform charts, not stand-ins"
  deps=""
fi
for dep in $deps; do
  bash scripts/dep-apply.sh "${dep#dep:}"
done

# Siblings resolve by DNS in-cluster, so they must be present but not port-forwarded; this recurses into deploy rather than calling svc-apply.sh.
# DEPLOYING_SERVICES carries the visited set: nothing enforces an acyclic call graph, and a cycle would fork-bomb.
svcs="$(grep -v '^[[:space:]]*#' "${SVC_DIR}/.mise.toml" | grep -o 'svc:[a-z][a-z-]*' | sort -u || true)"
export DEPLOYING_SERVICES="${DEPLOYING_SERVICES:-} ${SVC}"
for s in $svcs; do
  name="${s#svc:}"
  case " ${DEPLOYING_SERVICES} " in
  *" ${name} "*)
    step "${name} already in this deploy chain — skipping (cycle guard)"
    continue
    ;;
  esac
  if k rollout status "deploy/${name}-server" --timeout=0 >/dev/null 2>&1; then
    detail "${name} already deployed — skipping"
  else
    step "${SVC} calls ${name}; deploying it first"
    bash scripts/service-deploy.sh "$name"
  fi
done

# One mechanism for both tiers, because both are kind (ADR-0600): `kind load docker-image` copies from the host's store into every node, with no registry round trip.
publish_image() {
  kind load docker-image "$1" --name "$(cluster_name)" >/dev/null
}

TAG="local-$(date +%s)" # unique tag forces a re-pull of the imported image
# The name is never resolved over the network, and must still be allow-listed: Kyverno matches the reference against `<repo>:*` patterns from image-allowlist.yaml (ADR-0104).
REPO="${REGISTRY}:5000/${IMAGE}"
WORKER_REPO="${REGISTRY}:5000/${SVC}-worker"
SET=(--set "image.repository=${REPO}" --set "image.tag=${TAG}")

# Build identity baked into the image (ADR-0103): the working-tree SHA (+ -dirty
# for uncommitted edits — the norm for this local path), so /version and the
# X-App-Version header report exactly what you deployed.
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
  # `output: "standalone"` freezes next.config into server.js, so the server-action CSRF allowlist is decided at build time (ADR-0306).
  docker build -t "${REPO}:${TAG}" \
    --build-arg "SERVICE_VERSION=${REV}" \
    --build-arg "EDGE_PUBLIC_ORIGIN=$(yq -r '.env.EDGE_PUBLIC_ORIGIN // ""' "$VALUES")" \
    -f "${SVC_DIR}/Dockerfile" .
fi
publish_image "${REPO}:${TAG}"

# Build the worker too when this service declares one (orders, payment).
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

step "helm upgrade ${SVC} (working-tree image ${TAG})"
h upgrade --install "$SVC" infra/helm/service -n "$NS" -f "$VALUES" \
  --take-ownership --force-conflicts --set image.pullPolicy=IfNotPresent "${SET[@]}" --timeout 5m
k rollout restart "deploy/${SVC}-server"
k rollout status "deploy/${SVC}-server" --timeout=180s
ok "${SVC} deployed from working tree (tag ${TAG})"
