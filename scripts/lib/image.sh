# shellcheck shell=bash

if [[ -n "${__IMAGE_SH_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
__IMAGE_SH_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

# image_digest <ref>
# Echoes the ref's manifest digest, or fails. Through `json`: older buildx ignores a `{{.Manifest.Digest}}` template
# and prints its whole human report, which a values file would then carry as the digest.
image_digest() {
  local digest
  digest="$(docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' | jq -r '.digest // ""')"
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "no manifest digest for $1 (got: ${digest:0:80})"
  printf '%s\n' "$digest"
}
