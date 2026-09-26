#!/usr/bin/env bash
# Open the prod pin as a pull request and have the forge merge it once its checks pass (ADR-0201, ADR-0102). Prod is promoted through review, not pushed.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

ver="${VER:-}"
[[ -n "$ver" ]] || fail "VER is unset"
: "${GITHUB_TOKEN:?the job token is unset}" "${GITHUB_API_URL:?}" "${GITHUB_REPOSITORY:?}"
base="${BASE:-master}"
branch="deploy/prod-${ver}"
title="chore(deploy): promote ${ver} to prod"

git diff --quiet -- infra/gitops && fail "promote:prod changed no values file"
git config user.name "${GITHUB_ACTOR:-ci}"
git config user.email "${GITHUB_ACTOR:-ci}@noreply.${GITHUB_SERVER_URL#*://}"
git switch -q -c "$branch"
git add infra/gitops
git commit -q -m "$title"
git push -q origin "$branch"

api() { # <method> <path> <json>
  curl -fsS -X "$1" -H "Authorization: token ${GITHUB_TOKEN}" -H "Content-Type: application/json" \
    "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}$2" -d "$3"
}

number="$(api POST /pulls "$(jq -nc --arg h "$branch" --arg b "$base" --arg t "$title" '{head: $h, base: $b, title: $t}')" | jq -r .number)"
[[ "$number" =~ ^[0-9]+$ ]] || fail "the forge returned no pull request number"
detail "opened #${number}"

api POST "/pulls/${number}/merge" '{"Do":"merge","merge_when_checks_succeed":true,"delete_branch_after_merge":true}' >/dev/null
ok "#${number} merges when its checks pass"
