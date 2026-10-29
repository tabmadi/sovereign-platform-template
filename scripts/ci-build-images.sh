#!/usr/bin/env bash
# Build, push, and sign every affected image of one kind in one job, per ADR-0101 and ADR-0104.
# One job, not one for each image: on one runner, the setup of a job costs more than an image build from a warm cache.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

kind="${1:-}"
case "$kind" in
services | apps) ;;
*) fail "usage: mise run ci:build-images -- services|apps" ;;
esac
[ -n "${IMAGE_PREFIX:-}" ] || fail "IMAGE_PREFIX is unset"
[ -n "${GIT_SHA:-}" ] || fail "GIT_SHA is unset"
items="${ITEMS:-[]}"
# The lists below are read from process substitutions, whose failure would build nothing and pass.
printf '%s' "$items" | jq -e 'type == "array"' >/dev/null || fail "ITEMS is not a JSON array: ${items}"

# One builder for each runner user, kept between jobs, so the Go build cache and the layer cache outlive a job.
# runner-gc spares the `ci-keep-` prefix. BuildKit's default GC policy caps what the builder keeps on the disk.
builder="ci-keep-$(id -un)"
docker buildx inspect "$builder" >/dev/null 2>&1 ||
  docker buildx create --name "$builder" --driver docker-container >/dev/null

# <name> <context> <dockerfile> [buildx flags]
build() {
  local name="$1" context="$2" file="$3" meta digest
  shift 3
  # A hosted machine starts with an empty builder. The Actions cache service then holds the layers, one scope for each image.
  local cache=()
  if [ "${RUNNER_ENVIRONMENT:-}" = github-hosted ]; then
    cache=(--cache-from "type=gha,scope=${name}" --cache-to "type=gha,mode=max,scope=${name}")
  fi
  meta="$(mktemp)"
  docker buildx build --builder "$builder" --progress plain --push \
    --file "$file" --tag "${IMAGE_PREFIX}/${name}:${GIT_SHA}" --metadata-file "$meta" \
    "${cache[@]}" "$@" "$context" || {
    rm -f "$meta"
    return 1
  }
  digest="$(jq -r '."containerimage.digest"' "$meta")"
  rm -f "$meta"
  # By digest, not by the new tag, per ADR-0104. A tag can move between two resolves.
  mise run ci:sign -- "${IMAGE_PREFIX}/${name}@${digest}"
}

# Every image is tried, so one failure does not hide another. promote then sees the failed job and pins nothing.
# The list is read on descriptor 3, because a build or a sign that reads stdin would take the rest of the list.
failed=()
case "$kind" in
services)
  while IFS=$'\t' read -r -u 3 svc cmd; do
    [ -n "$svc" ] || continue
    step "building ${svc}-${cmd}"
    # The build identity, per ADR-0103. BUILD_VERSION stays `dev` for master builds. The release stamps prod's CalVer.
    build "${svc}-${cmd}" . "services/${svc}/Dockerfile" \
      --build-arg "APP_CMD=${cmd}" --build-arg "GIT_SHA=${GIT_SHA}" \
      --build-arg BUILD_VERSION=dev --build-arg "BUILD_TIME=${BUILD_TIME:-}" ||
      failed+=("${svc}-${cmd}")
  done 3< <(printf '%s' "$items" | jq -r '.[] | [.service, .cmd] | @tsv')
  ;;
apps)
  while read -r -u 3 app; do
    [ -n "$app" ] || continue
    step "building ${app}"
    context="$(bash scripts/ci-build-context.sh "$app" | sed -n 's/^context=//p')"
    build "$app" "$context" "apps/${app}/Dockerfile" --build-arg "SERVICE_VERSION=${GIT_SHA}" ||
      failed+=("$app")
  done 3< <(printf '%s' "$items" | jq -r '.[]')
  ;;
esac

[ "${#failed[@]}" -eq 0 ] || fail "these images did not build, push, or sign: ${failed[*]}"
ok "every ${kind} image is built, pushed, and signed"
