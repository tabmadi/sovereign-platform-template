#!/usr/bin/env bash
# Renovate over this repository, per ADR-0117. The scheduled renovate workflow calls it.
# The schedule in .github/renovate.json decides when a branch opens. A run outside it only refreshes the dashboard issue.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

: "${RENOVATE_TOKEN:?RENOVATE_TOKEN is unset}" "${GITHUB_API_URL:?}" "${GITHUB_REPOSITORY:?}"

platform=forgejo
if [[ "$GITHUB_API_URL" == "https://api.github.com" ]]; then
  platform=github
  # The noreply address of the repository owner, so a copy of this repo signs with its own owner.
  export RENOVATE_GIT_AUTHOR="Renovate <${GITHUB_REPOSITORY_OWNER_ID}+${GITHUB_REPOSITORY_OWNER}@users.noreply.github.com>"
fi
export RENOVATE_PLATFORM="$platform" RENOVATE_ENDPOINT="$GITHUB_API_URL" RENOVATE_REPOSITORIES="$GITHUB_REPOSITORY"
# Lockfile updates run the tools of the dev shell, not a copy that Renovate downloads.
export RENOVATE_CONFIG_FILE=.config/renovate.json
if [[ -n "${DOCKERHUB_USERNAME:-}" && -n "${DOCKERHUB_TOKEN:-}" ]]; then
  RENOVATE_HOST_RULES="$(jq -nc --arg u "$DOCKERHUB_USERNAME" --arg p "$DOCKERHUB_TOKEN" \
    '[{hostType: "docker", matchHost: "docker.io", username: $u, password: $p}]')"
  export RENOVATE_HOST_RULES
else
  warn "DOCKERHUB_USERNAME or DOCKERHUB_TOKEN unset. Docker Hub lookups are anonymous and rate limited"
fi

step "running renovate on ${GITHUB_REPOSITORY} through ${platform}"
renovate
ok "renovate finished. The dashboard issue lists what is pending"
