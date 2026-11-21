#!/usr/bin/env bash
# Mirror the first-party images into the full tier's in-cluster zot, per ADR-0114.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=lib/cluster.sh
source "$LIB/cluster.sh"

# Only the full tier runs an in-cluster zot. On base this does nothing.
[ "$TIER" = full ] || {
  detail "populate-zot: no in-cluster zot on the ${TIER} tier, skipping"
  exit 0
}

# The local push identity. The Secret holds only the bcrypt htpasswd, not the plaintext, so it is named here.
# It is a committed throwaway, like every other local credential, per ADR-0205. Override it for a non-default local secret.
PUSH_USER="${ZOT_LOCAL_PUSH_USER:-ci}"
PUSH_PASSWORD="${ZOT_LOCAL_PUSH_PASSWORD:-ci-local-push}"

SRC="127.0.0.1:5000" # the host container `registry.localhost`, insecure on 127.0.0.1
FWD_PORT="${ZOT_FWD_PORT:-5100}"
DST="127.0.0.1:${FWD_PORT}"

k -n "$NS" rollout status deploy/zot --timeout=120s >/dev/null 2>&1 ||
  {
    warn "populate-zot: zot is not ready, skipping"
    exit 0
  }

step "mirroring first-party images into the in-cluster zot"

# Port-forward the registry API on 5000, not the console proxy on 5001. A push authenticates against zot's own htpasswd, as CI does.
k -n "$NS" port-forward svc/zot "${FWD_PORT}:5000" >/dev/null 2>&1 &
fwd_pid=$!
# A docker config of its own, so the login touches nothing in the engineer's ~/.docker.
DOCKER_CONFIG="$(mktemp -d)"
export DOCKER_CONFIG
trap 'reap "$fwd_pid"; rm -rf "$DOCKER_CONFIG"' EXIT
for _ in $(seq 1 30); do
  if curl -sf -o /dev/null "http://${DST}/v2/"; then break; fi
  sleep 0.5
done

printf '%s' "$PUSH_PASSWORD" | docker login "$DST" -u "$PUSH_USER" --password-stdin >/dev/null 2>&1 ||
  fail "populate-zot: the in-cluster zot refused the local push identity ${PUSH_USER}"

copied=0 failed=0
# `stage_images` builds every first-party image on this host and pushes it as `:local`. So the docker daemon holds
# the exact set, and the copy needs no registry read. docker push, not oras cp: oras asks the destination for the
# manifest first. zot answers that with an on-demand sync of the name from every upstream, and then with a 503.
while IFS= read -r image; do
  [ -n "$image" ] || continue
  repo="${image#"${SRC}/"}"
  repo="${repo%:local}"
  docker tag "$image" "${DST}/${repo}:local"
  if err="$(timeout 300 docker push "${DST}/${repo}:local" 2>&1 >/dev/null)"; then
    detail "mirrored ${repo}:local"
    copied=$((copied + 1))
  else
    warn "could not mirror ${repo}:local. The console will not show it: ${err:-no answer in 300s}"
    failed=$((failed + 1))
  fi
  docker rmi "${DST}/${repo}:local" >/dev/null 2>&1 || true
done < <(docker images --filter "reference=${SRC}/*:local" --format '{{.Repository}}:{{.Tag}}' | sort -u)

[ "$copied" -gt 0 ] || [ "$failed" -gt 0 ] || warn "populate-zot: no first-party image on this host. Run \`just cluster-up full\` first"
ok "in-cluster zot populated: ${copied} first-party image(s) mirrored, ${failed} failed"
