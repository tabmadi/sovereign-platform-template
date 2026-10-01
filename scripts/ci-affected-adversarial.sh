#!/usr/bin/env bash
# Test affected-detection from the other side, per ADR-0101 and ADR-0601.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

BASE="${BASE_REF:-HEAD}"

work="$(mktemp -d)"
cleanup() {
  git worktree remove --force "$work/tree" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

step "creating a scratch worktree at ${BASE}"
git worktree add --quiet --detach "$work/tree" "$BASE"
base_sha="$(git -C "$work/tree" rev-parse HEAD)"

# Built from the working tree, to a binary outside it. `tools/` is a global trigger, so a classifier inside the tree makes every probe return `global: true`.
step "building the classifier under test"
go build -o "$work/affected" ./tools/affected

fail=0
checked=0

for dir in services/*/; do
  svc="$(basename "$dir")"
  [ "${svc#_}" = "$svc" ] || continue # the scaffold deploys nowhere

  # A file the service owns, and a change that is clearly its own: a comment at the end of its README.
  # Not a Go file: this tests the path classifier, and a broken build would mix up the two failures.
  target="${dir}README.md"
  [ -f "$work/tree/$target" ] || {
    warn "${svc}: no README.md to perturb"
    fail=1
    continue
  }

  printf '\n<!-- affected-detection probe -->\n' >>"$work/tree/$target"
  git -C "$work/tree" add "$target" >/dev/null
  git -C "$work/tree" -c user.email=ci@local -c user.name=ci \
    commit --quiet --no-verify -m "chore: perturb ${svc}"

  manifest="$(cd "$work/tree" && "$work/affected" --base "$base_sha")"
  named="$(printf '%s' "$manifest" | jq -r --arg s "$svc" '(.services // []) | index($s) != null')"
  global="$(printf '%s' "$manifest" | jq -r '.global')"

  # `global` counts as naming it. A global change rebuilds everything, which is over-selection. This checks for under-selection.
  if [ "$named" = true ] || [ "$global" = true ]; then
    detail "${svc}: selected"
  else
    warn "${svc}: changed and not selected. CI would skip it"
    printf '%s\n' "$manifest" >&2
    fail=1
  fi
  checked=$((checked + 1))

  # Back to the base for the next service, so each service is tested alone.
  git -C "$work/tree" reset --hard --quiet "$base_sha"
done

if [ "$fail" -ne 0 ]; then
  fail "affected-detection missed a changed service"
fi

ok "affected-detection selected all ${checked} services when each was changed alone"
