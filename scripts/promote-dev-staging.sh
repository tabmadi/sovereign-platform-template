#!/usr/bin/env bash
# Pin the dev and staging values files for every component a push published to its digest (ADR-0201, ADR-0105). Prod is pinned on release, in promote-prod.sh.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=lib/yaml.sh
source "$LIB/yaml.sh"

sha="${SHA:-}"
[[ -n "$sha" ]] || fail "SHA is unset — nothing to promote to"

# The set publish.yml built, handed over rather than recomputed: a second diff could disagree with the one that decided what exists in the registry.
names="$(jq -rn --argjson s "${SERVICES:-[]}" --argjson a "${APPS:-[]}" '$s[], $a[]')"
[[ -n "$names" ]] || {
  ok "nothing published"
  exit 0
}

# A service values file carries up to two images — the server and, where the service has one, the worker — and both move together, because they are built from the same commit.
bump() { # <values-file> <yaml-path-to-image-block>
  local path="$1" block="$2" repo digest
  repo="$(yq "${block}.repository // \"\"" "$path")"
  [[ -n "$repo" ]] || return 0
  digest="$(docker buildx imagetools inspect "${repo}:${sha}" --format '{{.Manifest.Digest}}')"
  yaml_set_scalar "$path" "${block}.tag" "$sha" || true
  yaml_set_scalar "$path" "${block}.digest" "$digest" ||
    fail "${path}: ${block} has no digest key — Kyverno admits first-party images by digest only (ADR-0104)"
  detail "$(basename "$path") ${block} → ${digest}"
}

# The admin console is a platform chart (ADR-0401), so its image lives at .lowdefy.image in the platform overlay rather than the services layout.
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
