#!/usr/bin/env bash
# Start the sprint that holds today, per ADR-0107. A sprint is a two-week milestone named `Sprint <year>-W<week>`.
# The task creates it in every repository of the organization, moves the open issues of each ended sprint into it, and
# closes the ended milestone. A second run in the same sprint changes nothing.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

LABELS="$(dirname "${BASH_SOURCE[0]}")/../infra/forge/labels.yaml"
url="${FORGE_URL:-}"
token="${FORGE_TOKEN:-}"
[[ -n "$url" && -n "$token" ]] || fail "FORGE_URL or FORGE_TOKEN unset. No sprint is started"
# The organization comes from FORGE_ORG, or from the label set where the repository commits one.
org="${FORGE_ORG:-}"
if [[ -z "$org" && -f "$LABELS" ]]; then
  org="$(yq -r '.org' "$LABELS")"
fi
[[ -n "$org" ]] || fail "FORGE_ORG unset, and ${LABELS} does not exist"

api() { # <method> <path> [body]
  curl -fsS -X "$1" -H "Authorization: token ${token}" -H "Content-Type: application/json" \
    ${3:+--data "$3"} "${url}/api/v1/$2"
}

today="$(date -u +%F)"
monday() { date -u -d "$1 -$(($(date -u -d "$1" +%u) - 1)) days" +%F; } # the Monday of the week that holds $1
week_of() { date -u -d "$1" +%G-W%V; }
start_of() { # <year>-W<week> → its Monday, which is the Monday of the week that holds 4 January plus the weeks
  local year="${1%-W*}" week="${1#*-W}"
  date -u -d "$(monday "${year}-01-04") +$(((10#$week - 1) * 7)) days" +%F
}

mapfile -t repos < <(api GET "orgs/${org}/repos?limit=50" | jq -r '.[] | select(.archived | not) | .name')
[[ -n "${repos[0]:-}" ]] || fail "the organization ${org} has no repository"

# The latest sprint in any repository decides the cadence. With no sprint yet, the first one starts this Monday.
latest="$(for repo in "${repos[@]}"; do api GET "repos/${org}/${repo}/milestones?state=all&limit=50"; done |
  jq -rs '[.[][] | .title | select(test("^Sprint [0-9]{4}-W[0-9]{2}$")) | ltrimstr("Sprint ")] | sort_by(.) | last // ""')"
if [[ -z "$latest" ]]; then
  start="$(monday "$today")"
else
  start="$(start_of "$latest")"
  while (($(date -u -d "$start + 14 days" +%s) <= $(date -u -d "$today" +%s))); do
    start="$(date -u -d "$start + 14 days" +%F)"
  done
fi
title="Sprint $(week_of "$start")"
due="$(date -u -d "$start + 13 days" +%F)T23:59:59Z"
step "starting ${title}, ${start} to ${due%T*}"

for repo in "${repos[@]}"; do
  milestones="$(api GET "repos/${org}/${repo}/milestones?state=all&limit=50")"
  id="$(jq -r --arg t "$title" '.[] | select(.title == $t) | .id' <<<"$milestones")"
  if [[ -z "$id" ]]; then
    body="$(jq -nc --arg t "$title" --arg d "$due" '{title: $t, due_on: $d, description: "A two-week sprint, per ADR-0107."}')"
    id="$(api POST "repos/${org}/${repo}/milestones" "$body" | jq -r '.id')"
    detail "${repo}: created ${title}"
  fi
  # An ended sprint is an open sprint milestone that starts before this one.
  while IFS=$'\t' read -r old_id old_title; do
    [[ -n "$old_id" ]] || continue
    moved=0
    while read -r number; do
      [[ -n "$number" ]] || continue
      api PATCH "repos/${org}/${repo}/issues/${number}" "{\"milestone\": ${id}}" >/dev/null
      moved=$((moved + 1))
    done < <(api GET "repos/${org}/${repo}/issues?state=open&type=issues&milestones=${old_id}&limit=50" | jq -r '.[].number')
    api PATCH "repos/${org}/${repo}/milestones/${old_id}" '{"state": "closed"}' >/dev/null
    detail "${repo}: moved ${moved} open issue(s) from ${old_title}, and closed it"
  done < <(jq -r --arg t "$title" '.[] | select(.state == "open" and (.title | test("^Sprint [0-9]{4}-W[0-9]{2}$")) and .title < $t) |
    [.id, .title] | @tsv' <<<"$milestones")
done
ok "${title} is the current sprint in ${#repos[@]} repository(s)"
