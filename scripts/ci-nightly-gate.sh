#!/usr/bin/env bash
# Decide whether tonight's cluster:up full suite should run, as a forge step-output assignment (ADR-0102, ADR-0601).
set -euo pipefail

summary() {
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$*" >>"$GITHUB_STEP_SUMMARY"
  :
}
decide() {
  summary "$2"
  printf 'run=%s\n' "$1"
  exit 0
}

[[ "${EVENT:-}" == schedule ]] || decide true "→ ${EVENT:-manual} is an explicit request; running the suite."

# 26h, not 24: cron runs are queued on a shared pool and start late by a variable
# amount (this repo has seen 03:00 fire at 05:52 and 06:09). A 24h window silently
# drops commits into the gap between a late run and the next one.
[[ -z "$(git log --since='26 hours ago' --oneline)" ]] || decide true "→ new commits since the last nightly; running the suite."

# The question is whether the last run passed, not whether one happened: a forge run whose jobs all skip is green.
# No token means no query, and the activity skip above stands — the fork case.
if [[ -n "${GITHUB_TOKEN:-}" && -n "${GITHUB_REPOSITORY:-}" && -n "${WORKFLOW_FILE:-}" ]]; then
  last="$(curl -sf --max-time 20 -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows/${WORKFLOW_FILE}/runs?status=completed&per_page=20" |
    yq -r '[.workflow_runs[] | select(.conclusion != "skipped")][0].conclusion // ""' 2>/dev/null || true)"
  # Only a known success may skip. An empty answer means the query failed, and treating that as a pass reproduces the bug this closes.
  case "$last" in
  success) ;;
  "") decide true "→ could not read the last run's conclusion; running rather than assuming it passed." ;;
  *) decide true "→ the last completed run was '${last}'; running rather than skipping on an unanswered failure." ;;
  esac
fi

# Monthly floor: base images, charts and registry contents move underneath an unchanged commit. Day-of-month, so it stays one run per month.
[[ "$(date -u +%d)" != 01 ]] || decide true "→ no new commits, but it is the 1st; running the monthly floor."

decide false "✓ no commits in the last 26h — skipping tonight's bring-up."
