#!/usr/bin/env bash
# Mirror the first-party images into the full tier's in-cluster zot, per ADR-0105.
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

command -v oras >/dev/null || fail "oras is not on PATH. Run through mise, so the pinned tool resolves"

k -n "$NS" rollout status deploy/zot --timeout=120s >/dev/null 2>&1 ||
  {
    warn "populate-zot: zot is not ready, skipping"
    exit 0
  }

step "mirroring first-party images into the in-cluster zot"

# Port-forward the registry API on 5000, not the console proxy on 5001. A push authenticates against zot's own htpasswd, as CI does.
k -n "$NS" port-forward svc/zot "${FWD_PORT}:5000" >/dev/null 2>&1 &
fwd_pid=$!
trap 'kill "$fwd_pid" 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do
  if curl -sf -o /dev/null "http://${DST}/v2/"; then break; fi
  sleep 0.5
done

o_src=(--plain-http)
o_dst=(--to-plain-http --to-username "$PUSH_USER" --to-password "$PUSH_PASSWORD")

copied=0 skipped=0
# `:local` is the tag that `stage_images` gives every repo image it builds, and no other image has it.
# So this selects exactly the first-party set, with no manual list.
for repo in $(oras repo ls "${o_src[@]}" "$SRC" 2>/dev/null); do
  oras repo tags "${o_src[@]}" "${SRC}/${repo}" 2>/dev/null | grep -qx local || {
    skipped=$((skipped + 1))
    continue
  }
  # Two attempts: zot answers a blob PUT with a 500 when its object-store write fails briefly under a concurrent copy.
  # oras skips the layers already there, so a retry copies only what the first pass missed.
  if oras cp --from-plain-http "${o_dst[@]}" "${SRC}/${repo}:local" "${DST}/${repo}:local" >/dev/null 2>&1 ||
    oras cp --from-plain-http "${o_dst[@]}" "${SRC}/${repo}:local" "${DST}/${repo}:local" >/dev/null 2>&1; then
    detail "mirrored ${repo}:local"
    copied=$((copied + 1))
  else
    warn "could not mirror ${repo}:local. The console will not show it"
  fi
done

ok "in-cluster zot populated: ${copied} first-party image(s) mirrored, ${skipped} upstream repo(s) left in place"
