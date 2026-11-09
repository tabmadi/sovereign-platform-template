#!/usr/bin/env bash
# The design preview of one pull request, per ADR-0701: build and sign the design image, then post its URL.
# This script runs from the base branch. The pull request's code is only a build context, and nothing here executes it on the runner.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

verb="${1:-}"
case "$verb" in
build | comment) ;;
*) fail "usage: mise run ci:design-preview -- build|comment" ;;
esac

pr="${PREVIEW_PR:-}"
[[ "$pr" =~ ^[0-9]+$ ]] || fail "PREVIEW_PR is not a pull request number: '${pr}'"

if [ "$verb" = build ]; then
  [ -n "${IMAGE_PREFIX:-}" ] || fail "IMAGE_PREFIX is unset"
  [ -n "${GITHUB_OUTPUT:-}" ] || fail "GITHUB_OUTPUT is unset"

  # The forge keeps this ref for every pull request, a fork's too, per ADR-0205.
  src="$(mktemp -d)"
  trap 'git worktree remove --force "$src" >/dev/null 2>&1 || rm -rf "$src"' EXIT
  git fetch -q --depth=1 origin "+refs/pull/${pr}/head"
  sha="$(git rev-parse FETCH_HEAD)"
  git worktree add -q --detach "$src" "$sha"
  ref="${IMAGE_PREFIX}/design/frontend:pr-${pr}-${sha}"

  # A builder of its own. The production builds share a persistent cache, and a pull request's build must not write to it.
  builder="ci-design-$(id -un)"
  docker buildx inspect "$builder" >/dev/null 2>&1 ||
    docker buildx create --name "$builder" --driver docker-container >/dev/null
  cache=()
  if [ "${RUNNER_ENVIRONMENT:-}" = github-hosted ]; then
    cache=(--cache-from "type=gha,scope=design-frontend" --cache-to "type=gha,mode=max,scope=design-frontend")
  fi

  step "building ${ref}"
  meta="$(mktemp)"
  docker buildx build --builder "$builder" --progress plain --push \
    --file "${src}/apps/frontend/Dockerfile" --tag "$ref" --metadata-file "$meta" "${cache[@]}" \
    --build-arg NEXT_PUBLIC_FIXTURES=1 --build-arg NEXT_PUBLIC_DESIGN_BUILD=1 --build-arg "SERVICE_VERSION=${sha}" \
    "$src"
  digest="$(jq -r '."containerimage.digest"' "$meta")"
  rm -f "$meta"
  # Admission verifies this signature in the design namespace, per ADR-0104.
  mise run ci:sign -- "${IMAGE_PREFIX}/design/frontend@${digest}"
  printf 'sha=%s\n' "$sha" >>"$GITHUB_OUTPUT"
  ok "pushed and signed ${ref}"
  exit 0
fi

: "${GITHUB_TOKEN:?the job token is unset}" "${GITHUB_API_URL:?}" "${GITHUB_REPOSITORY:?}"
sha="${PREVIEW_SHA:?PREVIEW_SHA is unset}"
host="$(yq -r '.envHost' infra/gitops/platform/dev/values.yaml)"
url="https://design-pr-${pr}.ops.${host}/"
marker="<!-- design-preview -->"
body="${marker}
The design preview of this pull request is at ${url}

It shows commit \`${sha}\` in fixture mode. Log in as an operator to open it. Argo CD deletes it when this pull request closes or the \`design-preview\` label goes, per ADR-0701."

api() { # <method> <path> [json]
  curl -fsS -X "$1" -H "Authorization: token ${GITHUB_TOKEN}" -H "Content-Type: application/json" \
    "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}$2" ${3:+-d "$3"}
}

# One comment for each pull request, edited on each build, so a busy pull request does not collect one comment for each push.
payload="$(jq -nc --arg b "$body" '{body: $b}')"
id="$(api GET "/issues/${pr}/comments?limit=100" | jq -r --arg m "$marker" '[.[] | select(.body | startswith($m))][0].id // empty')"
if [ -n "$id" ]; then
  api PATCH "/issues/comments/${id}" "$payload" >/dev/null
else
  api POST "/issues/${pr}/comments" "$payload" >/dev/null
fi
ok "posted ${url} on #${pr}"
