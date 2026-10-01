#!/usr/bin/env bash
# Pin the dev and staging values files for every component that a push published to its digest, per ADR-0201 and ADR-0105.
# Prod is pinned on release, in promote-prod.sh.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=lib/yaml.sh
source "$LIB/yaml.sh"
# shellcheck source=lib/image.sh
source "$LIB/image.sh"

sha="${SHA:-}"
[[ -n "$sha" ]] || fail "SHA is unset, so there is nothing to promote to"

# The set that publish.yml built, passed on and not computed again. A second diff could disagree with the one that decided what is in the registry.
names="$(jq -rn --argjson s "${SERVICES:-[]}" --argjson a "${APPS:-[]}" '$s[], $a[]')"
[[ -n "$names" ]] || {
  ok "nothing published"
  exit 0
}

# A service values file has up to two images: the server, and the worker when the service has one.
# Both move together, because they are built from the same commit.
bump() { # <values-file> <yaml-path-to-image-block>
  local path="$1" block="$2" repo digest
  repo="$(yq "${block}.repository // \"\"" "$path")"
  [[ -n "$repo" ]] || return 0
  digest="$(image_digest "${repo}:${sha}")"
  yaml_set_scalar "$path" "${block}.tag" "$sha" || true
  yaml_set_scalar "$path" "${block}.digest" "$digest" ||
    fail "${path}: ${block} has no digest key. Kyverno admits first-party images by digest only, per ADR-0104"
  detail "$(basename "$path") ${block} → ${digest}"
}

# The admin console is a platform chart, per ADR-0401, so its image is at .lowdefy.image in the platform overlay, not in the services layout.
while read -r name; do
  for env in dev staging; do
    if [[ "$name" == admin ]]; then
      bump "infra/gitops/platform/${env}/values.yaml" ".lowdefy.image"
      continue
    fi
    path="infra/gitops/services/${env}/values/${name}.yaml"
    [[ -f "$path" ]] || continue
    bump "$path" ".image"
    bump "$path" ".worker.image"
  done
done <<<"$names"

ok "dev and staging pinned to ${sha}"
