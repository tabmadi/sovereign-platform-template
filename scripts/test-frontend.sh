#!/usr/bin/env bash
# The frontend unit and component tests, with a line coverage floor for each route group, per ADR-0400.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

# Each route group under src/app/[locale]/ has a row, and `shared` is the code under src/ outside src/app/.
# A floor only rises. Bun reports only the files that a test loads, so a group that no test loads is not measured.
floors="
(analytics) 0
(devportal) 0
(landing) 0
(panel) 90
shared 25
"

# The app's tsconfig leaves the tests out of `next build`. This one checks the MSW handlers against the generated SDK types.
(cd apps/frontend && bunx tsc --noEmit -p tsconfig.test.json && bun test --coverage)

lcov=apps/frontend/coverage/lcov.info
[ -f "$lcov" ] || fail "frontend coverage: $lcov is missing"

for dir in apps/frontend/src/app/\[locale\]/\(*\)/; do
  group="$(basename "$dir")"
  grep -qF "$group " <<<"$floors" || fail "frontend coverage: the route group $group has no floor in $0"
done

measured="$(awk -F: '
  /^SF:/ { file = $2 }
  /^LF:/ { found[group(file)] += $2 }
  /^LH:/ { hit[group(file)] += $2 }
  function group(path, parts) {
    if (path !~ /^src\/app\//) return "shared"
    split(path, parts, "/")
    return parts[4]
  }
  END { for (g in found) printf "%s %d %d\n", g, hit[g], found[g] }
' "$lcov")"

rc=0
while read -r group floor; do
  [ -n "$group" ] || continue
  row="$(awk -v g="$group" '$1 == g { print $2, $3 }' <<<"$measured")"
  if [ -z "$row" ]; then
    detail "$group: no test loads it"
    continue
  fi
  read -r hit found <<<"$row"
  percent=$((100 * hit / found))
  if [ "$percent" -lt "$floor" ]; then
    warn "$group: line coverage is ${percent}%, below the floor of ${floor}%"
    rc=1
  else
    detail "$group: line coverage is ${percent}%, the floor is ${floor}%"
  fi
done <<<"$floors"

[ "$rc" -eq 0 ] || fail "frontend coverage: a route group is below its floor"
ok "frontend coverage: every measured route group meets its floor"
