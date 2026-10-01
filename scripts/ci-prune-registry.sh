#!/usr/bin/env bash
# Delete first-party image tags that nothing can deploy, per ADR-0105. A tag stays when an environment's values pin it or its digest.
# A tag also stays when it names one of the last PRUNE_KEEP commits on the branch: the rollback window. cosign's tags go with the image they sign.
# Any other tag stays. The registry's own garbage collection frees the blobs.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

prefix="${IMAGE_PREFIX:?IMAGE_PREFIX is unset. It is the registry and repository that the pipeline pushes to}"
keep="${PRUNE_KEEP:-10}"
user="${REGISTRY_USERNAME:?REGISTRY_USERNAME is unset}"
pass="${REGISTRY_PASSWORD:?REGISTRY_PASSWORD is unset}"
dry="${PRUNE_DRY_RUN:-}"

# Every pinned image in every environment, as `<repository> <tag> <digest>` lines.
pins="$(find infra/gitops -name '*.yaml' -print0 |
  xargs -0 yq -N -o tsv '.. | select(tag == "!!map" and has("repository") and has("tag")) | [.repository, .tag, (.digest // "")]' 2>/dev/null |
  sort -u)"
[ -n "$pins" ] || fail "no pinned image found under infra/gitops"
recent="$(git rev-list --max-count="$keep" HEAD)"

registry() { # <method> <host> <path> [curl args]
  local method="$1" host="$2" path="$3"
  shift 3
  if [ "$method" = HEAD ]; then set -- -I "$@"; else set -- -X "$method" "$@"; fi
  curl -sS -u "${user}:${pass}" "$@" "https://${host}/v2/${path}"
}
accept='application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json'

host="${prefix%%/*}"
case "$host" in
ghcr.io | docker.io | *.docker.io)
  warn "${host} does not delete tags through the registry API. Its own retention applies"
  exit 0
  ;;
esac

deleted=0
kept=0
drop() { # <name> <tag>
  if [ -n "$dry" ]; then
    detail "would delete ${1}:${2}"
  else
    local code
    code="$(registry DELETE "$host" "${1}/manifests/${2}" -o /dev/null -w '%{http_code}')"
    [[ "$code" =~ ^2 ]] || fail "${host} refused to delete ${1}:${2}, HTTP ${code}"
  fi
  deleted=$((deleted + 1))
}
while read -r repo; do
  name="${repo#*/}"
  pinned_tags="$(awk -F'\t' -v r="$repo" '$1 == r {print $2}' <<<"$pins")"
  pinned_digests="$(awk -F'\t' -v r="$repo" '$1 == r && $3 != "" {print $3}' <<<"$pins")"
  tags="$(registry GET "$host" "${name}/tags/list" -f)" || fail "cannot list ${name}'s tags on ${host}"
  held=""
  for tag in $(jq -r '.tags // [] | .[] | select(test("^[0-9a-f]{40}$"))' <<<"$tags"); do
    digest="$(registry HEAD "$host" "${name}/manifests/${tag}" -f -H "Accept: ${accept}" |
      awk 'tolower($1) == "docker-content-digest:" {print $2}' | tr -d '\r')" ||
      fail "cannot read ${name}:${tag}'s digest on ${host}"
    if grep -qx "$tag" <<<"$pinned_tags" || grep -qx "$tag" <<<"$recent" || grep -qx "$digest" <<<"$pinned_digests"; then
      held+="${digest}"$'\n'
      kept=$((kept + 1))
    else
      drop "$name" "$tag"
    fi
  done
  # cosign's signature and attestation tags name their digest, and they go with it.
  for tag in $(jq -r '.tags // [] | .[] | select(test("^sha256-[0-9a-f]{64}[.]"))' <<<"$tags"); do
    digest="sha256:$(cut -c8-71 <<<"$tag")"
    if grep -qx "$digest" <<<"$held"; then kept=$((kept + 1)); else drop "$name" "$tag"; fi
  done
done < <(cut -f1 <<<"$pins" | grep "^${prefix}/" | sort -u)
ok "registry pruned: ${deleted} tag(s) ${dry:+would be }deleted, ${kept} kept"
