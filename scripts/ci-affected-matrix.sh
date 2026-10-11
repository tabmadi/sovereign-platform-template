#!/usr/bin/env bash
# Emit the affected manifest as forge step-output assignments, with services and apps as separate JSON arrays, per ADR-0102.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

# A push is compared with the last commit that reached dev, not only with the commit it replaced.
# A newer push cancels a running publish, so a change that the cancelled run would have built is still owed.
# When no such commit is in the history, after a new branch or a force-push, everything is affected.
promoted="$(git log -1 --format=%s --grep='^chore(deploy): promote ' | sed -nE 's/^chore\(deploy\): promote ([0-9a-f]+).*/\1/p')"
if [ -n "$promoted" ] && git cat-file -e "${promoted}^{commit}" 2>/dev/null && git merge-base --is-ancestor "$promoted" HEAD; then
  BEFORE="$promoted"
fi
args=(--all)
if [ -n "${BEFORE:-}" ] && git cat-file -e "${BEFORE}^{commit}" 2>/dev/null; then
  args=(--base "$BEFORE")
  # No image is built from a values file, and a promotion commit changes nothing else.
  # Counted as infra, it would publish everything again and promote again.
  if [ -z "$(git diff --name-only "${BEFORE}...HEAD" | grep -v '^infra/gitops/')" ]; then
    printf 'services=[]\napps=[]\nimages=[]\n'
    exit 0
  fi
fi
manifest="$(mise run ci:affected -- "${args[@]}")"

# A global manifest names no components, so here it expands to every component that builds an image.
if [ "$(printf '%s' "$manifest" | jq -r '.global')" = true ]; then
  every() { find "$1" -mindepth 2 -maxdepth 2 -name Dockerfile ! -path '*/_*' | cut -d/ -f2 | sort | jq -Rsc 'split("\n") | map(select(. != ""))'; }
  manifest="$(printf '%s' "$manifest" | jq -c --argjson s "$(every services)" --argjson a "$(every apps)" '.services = $s | .apps = $a')"
fi
printf 'services=%s\n' "$(printf '%s' "$manifest" | jq -c '.services')"
printf 'apps=%s\n' "$(printf '%s' "$manifest" | jq -c '.apps')"

# Explicit {service, cmd} pairs, not a cross product. Not every service has a worker, and a build for a missing `cmd/worker` fails that cell.
# The filesystem is the source, not a list: a service gets a worker when it gets the directory.
images='[]'
for svc in $(printf '%s' "$manifest" | jq -r '.services[]'); do
  for cmd in server worker; do
    [ -d "services/${svc}/cmd/${cmd}" ] || continue
    images="$(printf '%s' "$images" | jq -c --arg s "$svc" --arg c "$cmd" '. + [{service: $s, cmd: $c}]')"
  done
done
printf 'images=%s\n' "$images"
