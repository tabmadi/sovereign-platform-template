#!/usr/bin/env bash
# Decide whether tonight's cluster:up full suite should run, as a forge step-output
# assignment (ADR-0102, ADR-0601). Both nightlies cost a full-platform bring-up,
# and re-running one against a commit that already passed buys nothing: the code
# is identical, so a red is flake or upstream drift and a green is a result already
# held. On a repository that pauses for a few weeks that is every night.
#
# EVENT is the forge event name; anything but the cron is someone explicitly asking
# for the suite. Progress goes to $GITHUB_STEP_SUMMARY when the forge provides it.
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

# The skip above rests on "the commit already passed". Nothing checked that, and a
# suite that failed skipped every night afterwards on the grounds that it had
# already answered — reporting success each time, because a forge run whose jobs all
# skip is green. Measured: the full tier last RAN on 2026-09-06 and was cancelled;
# the eight green nights that followed executed nothing.
#
# So the question the skip needs answered is whether the last run passed, not
# whether one happened. The failure mode of guessing wrong here is one wasted
# bring-up; the failure mode of the old assumption was ten days of false green.
#
# No token means no query, and then this says nothing and the activity skip above
# stands — the fork case, where a nightly full-platform bring-up on someone else's
# runner is not a favour. Inside the forge the token is always present.
if [[ -n "${GITHUB_TOKEN:-}" && -n "${GITHUB_REPOSITORY:-}" && -n "${WORKFLOW_FILE:-}" ]]; then
  last="$(curl -sf --max-time 20 -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows/${WORKFLOW_FILE}/runs?status=completed&per_page=20" |
    yq -r '[.workflow_runs[] | select(.conclusion != "skipped")][0].conclusion // ""' 2>/dev/null || true)"
  # Only a KNOWN success may skip. An empty answer means the query failed — no
  # network, no `yq`, no history — and treating that as "it passed" reproduces the
  # bug this check exists to close, silently. Running an unnecessary bring-up costs
  # one night; skipping on an unverified failure cost ten.
  case "$last" in
  success) ;;
  "") decide true "→ could not read the last run's conclusion; running rather than assuming it passed." ;;
  *) decide true "→ the last completed run was '${last}'; running rather than skipping on an unanswered failure." ;;
  esac
fi

# Monthly floor. Code standing still does not mean the world does: base images,
# Helm charts, and registry contents move underneath an unchanged commit, and the
# 1st-of-the-month run is what catches that on a dormant repository. Day-of-month
# rather than a weekday so it stays one run per month however the calendar falls.
[[ "$(date -u +%d)" != 01 ]] || decide true "→ no new commits, but it is the 1st; running the monthly floor."

decide false "✓ no commits in the last 26h — skipping tonight's bring-up."
