#!/usr/bin/env bash
# Every TypeScript workspace member is copied into the frontend image build.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

MANIFEST="package.json"
DOCKERFILE="apps/frontend/Dockerfile"

[ -f "$MANIFEST" ] || fail "$MANIFEST not found"
[ -f "$DOCKERFILE" ] || fail "$DOCKERFILE not found"

all_members="$(yq -r '.workspaces[]' -p json "$MANIFEST" 2>/dev/null || true)"
members="$(grep -v '\*' <<<"$all_members" || true)"
globs="$(grep '\*' <<<"$all_members" || true)"
[ -n "$members" ] || fail "no explicit workspace members parsed from ${MANIFEST}"

rc=0
count=0
while IFS= read -r member; do
  [ -n "$member" ] || continue
  count=$((count + 1))
  if ! grep -qF "COPY ${member}/package.json" "$DOCKERFILE"; then
    warn "${member} is a workspace member but ${DOCKERFILE} never copies its package.json"
    rc=1
  fi
done <<<"$members"

while IFS= read -r glob; do
  [ -n "$glob" ] || continue
  count=$((count + 1))
  parent="${glob%/*}"
  if ! grep -qE "^COPY ${parent}/? ${parent}/?\$" "$DOCKERFILE"; then
    warn "${glob} matches workspace members but ${DOCKERFILE} never copies ${parent}/"
    rc=1
  fi
done <<<"$globs"

[ "$count" -gt 0 ] || fail "no members checked — the gate would pass vacuously"

if [ "$rc" -eq 0 ]; then
  ok "every workspace member is copied into the frontend build (${count} checked)"
fi
exit "$rc"
