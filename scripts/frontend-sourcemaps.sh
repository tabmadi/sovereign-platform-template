#!/usr/bin/env bash
# Collect the frontend's browser source maps for a release, and keep them out of the served bundle, per ADR-0503.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

RELEASE="${1:-${GIT_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}}"
BUILD_DIR="apps/frontend/.next"
OUT="apps/frontend/sourcemaps-${RELEASE}.tar.zst"

[ -d "$BUILD_DIR" ] || fail "no build at ${BUILD_DIR}. Run the production build first"

step "collecting source maps for release ${RELEASE}"

maps=$(find "$BUILD_DIR" -name '*.js.map' -type f | wc -l)
[ "$maps" -gt 0 ] || fail "no .js.map files in ${BUILD_DIR}. Check that productionBrowserSourceMaps is on"

find "$BUILD_DIR" -name '*.js.map' -type f -print0 | tar --null -T - -c --zstd -f "$OUT"
detail "archived ${maps} maps to ${OUT}"

# Out of the served tree. `standalone` copies `.next/static` into the image, so a map left here is published on the product origin.
find "$BUILD_DIR" -name '*.js.map' -type f -delete
ok "collected ${maps} source maps and removed them from the build output"

# Stored in the registry next to the image, per ADR-0503 and ADR-0105: one auth model, one retention policy, one store addressed by digest.
# The product origin must never serve the archive. A map served to a browser gives away the unminified application.
# With no registry configured, this is skipped with a warning. The maps are already removed at this point.
REGISTRY="${SOURCEMAP_REGISTRY:-${IMAGE_REGISTRY:-}}"
if [ -z "$REGISTRY" ]; then
  warn "SOURCEMAP_REGISTRY is unset. The archive stays at ${OUT} and is not stored"
  warn "a release whose maps are only on this machine cannot be symbolicated later"
  exit 0
fi

REF="${REGISTRY}/frontend-sourcemaps:${RELEASE}"
step "pushing ${OUT} to ${REF}"

# The local registry is plain HTTP, and every deployed one is not. The address decides, so the flag cannot stay on against a real registry.
SCHEME=()
case "$REGISTRY" in
registry.localhost:* | 127.0.0.1:* | localhost:*) SCHEME=(--plain-http) ;;
esac

# A relative path: oras refuses an absolute path by default. The path is relative to the repo root, where this script runs.

# `--artifact-type` marks this as not an image. A registry serves it anyway.
# A client that pulls images sees a media type it does not know, and skips it instead of running it.
oras push "$REF" "${SCHEME[@]+"${SCHEME[@]}"}" \
  --artifact-type application/vnd.platform.sourcemaps.v1+zstd \
  --annotation "org.opencontainers.image.revision=${RELEASE}" \
  --annotation "org.opencontainers.image.description=Browser source maps, kept for each release, per ADR-0503. Never served to a browser." \
  "${OUT}:application/zstd"

ok "source maps for ${RELEASE} stored at ${REF}"
detail "retrieve with: oras pull ${REF}"
