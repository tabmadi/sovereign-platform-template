#!/usr/bin/env bash
# Bump the dev and staging values files for every affected component to a build SHA (ADR-0201). Prod pins by digest, in promote-prod.sh.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/yaml.sh"

sha="${SHA:-}"
[[ -n "$sha" ]] || fail "SHA is unset — nothing to promote to"

manifest="$(mise run ci:affected)"
names="$(printf '%s' "$manifest" | jq -r '.services[], .apps[]')"
[[ -n "$names" ]] || {
  ok "nothing affected"
  exit 0
}

# A service values file carries up to two images — the server and, where the
# service has one, the worker — and both move together, because they are built
# from the same commit. Only the paths present in the file are written.
bump() { # <values-file> <yaml-path-to-image-block>
  local path="$1" block="$2"
  if yaml_set_scalar "$path" "${block}.tag" "$sha"; then
    detail "$(basename "$path") ${block} → ${sha}"
  fi
}

# The admin console is a platform chart (ADR-0401), so its image lives at .lowdefy.image.tag in the platform overlay rather than the services layout.
while read -r name; do
  [[ -n "$name" ]] || continue
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

ok "dev and staging bumped to ${sha}"
