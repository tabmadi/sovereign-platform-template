#!/usr/bin/env bash
# The Lighthouse origin without a cluster, per ADR-0400: the production frontend image, the API mock, a Kratos stub, and Traefik.
# A measured page reads nothing else, so a cluster adds minutes of start time and CPU noise, and changes no number.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

NET=lighthouse
PORT="${LIGHTHOUSE_PORT:-8444}"
IMAGE=lighthouse/frontend:local
DIR="$PWD/test/e2e/lighthouse"
SPEC="apps/frontend/public/devportal/openapi/internal.json"
# The same pins as infra/local/image-refs.txt and infra/local/mock.yaml.
TRAEFIK=docker.io/traefik:v3.7.10
PRISM=docker.io/stoplight/prism:5.15.10

down() {
  docker rm -f lighthouse-edge lighthouse-frontend lighthouse-mock lighthouse-kratos >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
}

case "${1:-}" in
up)
  [ -f "$SPEC" ] || fail "missing ${SPEC}. Run \`mise run gen\` first"
  down

  # The builder and the arguments of ci:build-images, so a push's publish job finds this build in the cache.
  step "building the frontend's production image"
  builder="ci-keep-$(id -un)"
  docker buildx inspect "$builder" >/dev/null 2>&1 ||
    docker buildx create --name "$builder" --driver docker-container >/dev/null
  docker buildx build --builder "$builder" --progress plain --load --tag "$IMAGE" \
    --file apps/frontend/Dockerfile --build-arg "SERVICE_VERSION=${GIT_SHA:-dev}" .

  step "starting the stack on https://dev.localtest.me:${PORT}"
  docker network create "$NET" >/dev/null
  # Prism reads its document once, at startup. A copy into the container, not a bind mount, because a remote Docker daemon cannot see this checkout.
  for svc in mock kratos; do
    docker create --name "lighthouse-${svc}" --network "$NET" --network-alias "$svc" \
      "$PRISM" mock -h 0.0.0.0 -p 4010 --multiprocess false /spec.json >/dev/null
  done
  docker cp "$SPEC" lighthouse-mock:/spec.json
  docker cp "${DIR}/kratos-stub.json" lighthouse-kratos:/spec.json
  docker start lighthouse-mock lighthouse-kratos >/dev/null
  # Server components fetch `/api` through the edge, as in the cluster, on the plain `web` entrypoint.
  docker run -d --name lighthouse-frontend --network "$NET" --network-alias frontend \
    -e EDGE_PUBLIC_ORIGIN="https://dev.localtest.me:${PORT}" -e EDGE_INTERNAL_ORIGIN=http://edge:8080 \
    -e KRATOS_PUBLIC_URL=http://kratos:4010 "$IMAGE" >/dev/null
  # No certificate is configured, so Traefik serves its own. lighthouserc.cjs already ignores certificate errors.
  docker create --name lighthouse-edge --network "$NET" --network-alias edge -p "127.0.0.1:${PORT}:8443" "$TRAEFIK" \
    --entrypoints.web.address=:8080 --entrypoints.websecure.address=:8443 --entrypoints.websecure.http.tls=true \
    --providers.file.filename=/edge.yaml >/dev/null
  docker cp "${DIR}/edge.yaml" lighthouse-edge:/edge.yaml
  docker start lighthouse-edge >/dev/null

  for _ in $(seq 1 60); do
    if curl -ksf -o /dev/null "https://127.0.0.1:${PORT}/" &&
      curl -ksf -o /dev/null "https://127.0.0.1:${PORT}/auth/self-service/login/flows?id=lighthouse-login"; then
      ok "serving https://dev.localtest.me:${PORT}"
      exit 0
    fi
    sleep 1
  done
  docker logs --tail 20 lighthouse-frontend >&2 || true
  fail "the stack did not answer on :${PORT}"
  ;;
down)
  down
  ok "the Lighthouse stack is removed"
  ;;
*)
  fail "usage: mise run lighthouse:up or lighthouse:down"
  ;;
esac
