#!/usr/bin/env bash
# Pin every prod values file to a release commit by digest, and label the images with the CalVer, per ADR-0103 and ADR-0201.
# A digest cannot be pushed again.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=lib/yaml.sh
source "$LIB/yaml.sh"
# shellcheck source=lib/image.sh
source "$LIB/image.sh"

sha="${SHA:-}"
ver="${VER:-}"
[[ -n "$sha" ]] || fail "SHA is unset"
[[ -n "$ver" ]] || fail "VER is unset"

# image.repository is read from each values file, so this covers the -server and -worker services and the apps. The frontend has no suffix.
pin() { # <values-file> <yaml-path-to-image-block>
  local path="$1" block="$2" repo digest
  [[ -f "$path" ]] || return 0
  repo="$(yq "${block}.repository // \"\"" "$path")"
  [[ -n "$repo" ]] || return 0
  digest="$(image_digest "${repo}:${sha}")"
  yaml_set_scalar "$path" "${block}.digest" "$digest"
  yaml_set_scalar "$path" "${block}.tag" "$sha"
  docker buildx imagetools create -t "${repo}:${ver}" "${repo}:${sha}"
  detail "${repo} → ${digest}, labelled ${ver}"
}

shopt -s nullglob
step "pinning prod to ${sha}"
for path in infra/gitops/services/prod/values/*.yaml; do
  pin "$path" ".image"
  pin "$path" ".worker.image"
done
# The admin console is the one repo-built platform image, in the lowdefy chart, per ADR-0401.
pin "infra/gitops/platform/prod/values.yaml" ".lowdefy.image"

ok "prod pinned to ${sha}, images labelled ${ver}"
