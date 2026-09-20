#!/usr/bin/env bash
# Collect the frontend's browser source maps for a release, and keep them out of the served bundle (ADR-0503).
set -euo pipefail
source "$(dirname "$0")/lib/log.sh"
cd "$(cd "$(dirname "$0")/.." && pwd)"

RELEASE="${1:-${GIT_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}}"
BUILD_DIR="apps/frontend/.next"
OUT="apps/frontend/sourcemaps-${RELEASE}.tar.zst"

[ -d "$BUILD_DIR" ] || fail "no build at ${BUILD_DIR} — run the production build first"

step "collecting source maps for release ${RELEASE}"

maps=$(find "$BUILD_DIR" -name '*.js.map' -type f | wc -l)
[ "$maps" -gt 0 ] || fail "no .js.map files in ${BUILD_DIR} — is productionBrowserSourceMaps on?"

find "$BUILD_DIR" -name '*.js.map' -type f -print0 | tar --null -T - -c --zstd -f "$OUT"
detail "archived ${maps} maps to ${OUT}"

# Out of the served tree. `standalone` copies `.next/static` into the image, so a
# map left here is a map published on the product origin.
find "$BUILD_DIR" -name '*.js.map' -type f -delete
ok "collected ${maps} source maps and removed them from the build output"

# Stored in the registry beside the image (ADR-0503, ADR-0105): one auth model, one retention policy, one digest-addressed store.
# The archive must never be reachable from the product origin — a map served to a browser hands over the unminified application.
# Skipped with a warning when no registry is configured: the maps are already stripped by this point.
REGISTRY="${SOURCEMAP_REGISTRY:-${IMAGE_REGISTRY:-}}"
if [ -z "$REGISTRY" ]; then
  warn "SOURCEMAP_REGISTRY is unset — the archive stays at ${OUT} and is not stored"
  warn "a release whose maps are only on this machine cannot be symbolicated later"
  exit 0
fi

REF="${REGISTRY}/frontend-sourcemaps:${RELEASE}"
step "pushing ${OUT} to ${REF}"

# The local registry is plain HTTP and every deployed one is not. Detected from the address, so the flag cannot be left on against a real registry.
SCHEME=()
case "$REGISTRY" in
registry.localhost:* | 127.0.0.1:* | localhost:*) SCHEME=(--plain-http) ;;
esac

# A relative path: oras refuses an absolute one unless
# repo root this script already cd'd to.

# `--artifact-type` marks this as NOT an image. A registry will serve it either
# way, but a client pulling images sees a media type it does not recognise and
# skips it, rather than trying to run it.
oras push "$REF" "${SCHEME[@]+"${SCHEME[@]}"}" \
  --artifact-type application/vnd.platform.sourcemaps.v1+zstd \
  --annotation "org.opencontainers.image.revision=${RELEASE}" \
  --annotation "org.opencontainers.image.description=Browser source maps, retained per release (ADR-0503). Never served to a browser." \
  "${OUT}:application/zstd"

ok "source maps for ${RELEASE} stored at ${REF}"
detail "retrieve with: oras pull ${REF}"
