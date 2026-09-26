#!/usr/bin/env bash
# Publish the forge release for a CalVer tag once prod runs it (ADR-0103).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

ver="${VER:-}"
[[ -n "$ver" ]] || fail "VER is unset"
: "${GITHUB_TOKEN:?the job token is unset}" "${GITHUB_API_URL:?}" "${GITHUB_REPOSITORY:?}"

curl -fsS -X POST -H "Authorization: token ${GITHUB_TOKEN}" -H "Content-Type: application/json" \
  "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/releases" \
  -d "$(jq -nc --arg v "$ver" '{tag_name: $v, name: $v}')" >/dev/null
ok "release ${ver} published"
