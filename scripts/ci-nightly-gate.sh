#!/usr/bin/env bash
# Decide whether tonight's cluster:up full suite runs, as a forge step-output assignment, per ADR-0102 and ADR-0601.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

summary() {
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$*" >>"$GITHUB_STEP_SUMMARY"
  :
}
decide() {
  summary "$2"
  printf 'run=%s\n' "$1"
  exit 0
}

[[ "${EVENT:-}" == schedule ]] || decide true "→ ${EVENT:-manual} is an explicit request. Running the suite."

# 26h, not 24. Cron runs wait in a shared pool and start late by a variable time. The 03:00 run has started at 05:52 and 06:09.
# A 24h window drops commits into the gap between a late run and the next one.
[[ -z "$(git log --since='26 hours ago' --oneline)" ]] || decide true "→ new commits since the last nightly. Running the suite."

# The check is whether the last run passed, not whether one happened: a forge run whose jobs all skip is green.
# With no token there is no query, and the activity skip above stands. This is the fork case.
if [[ -n "${GITHUB_TOKEN:-}" && -n "${GITHUB_REPOSITORY:-}" && -n "${WORKFLOW_FILE:-}" ]]; then
  last="$(curl -sf --max-time 20 -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows/${WORKFLOW_FILE}/runs?status=completed&per_page=20" |
    yq -r '[.workflow_runs[] | select(.conclusion != "skipped")][0].conclusion // ""' 2>/dev/null || true)"
  # Only a known success can skip. An empty answer means the query failed, and a pass in that case brings back the bug this fixes.
  case "$last" in
  success) ;;
  "") decide true "→ could not read the last run's conclusion. Running, because a pass is not certain." ;;
  *) decide true "→ the last completed run was '${last}'. Running, because a failure is not resolved." ;;
  esac
fi

# Monthly floor: base images, charts, and registry contents change under an unchanged commit.
# It uses the day of the month, so it stays one run each month.
[[ "$(date -u +%d)" != 01 ]] || decide true "→ no new commits, but it is the 1st. Running the monthly floor."

decide false "✓ no commits in the last 26h. Skipping tonight's run."
