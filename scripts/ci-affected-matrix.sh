#!/usr/bin/env bash
# Emit the affected manifest as forge step-output assignments, with services and apps as separate JSON arrays (ADR-0102).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

# A push is diffed against the commit it replaced: on master the default base is HEAD itself, and that diff is always empty. With no such commit in history — a new branch, a force-push — everything is affected.
args=(--all)
if [ -n "${BEFORE:-}" ] && git cat-file -e "${BEFORE}^{commit}" 2>/dev/null; then
  args=(--base "$BEFORE")
fi
manifest="$(mise run ci:affected -- "${args[@]}")"

# A global manifest names no components, so it expands here to every one that builds an image.
if [ "$(printf '%s' "$manifest" | jq -r '.global')" = true ]; then
  every() { find "$1" -mindepth 2 -maxdepth 2 -name Dockerfile ! -path '*/_*' | cut -d/ -f2 | sort | jq -Rsc 'split("\n") | map(select(. != ""))'; }
  manifest="$(printf '%s' "$manifest" | jq -c --argjson s "$(every services)" --argjson a "$(every apps)" '.services = $s | .apps = $a')"
fi
printf 'services=%s\n' "$(printf '%s' "$manifest" | jq -c '.services')"
printf 'apps=%s\n' "$(printf '%s' "$manifest" | jq -c '.apps')"

# Explicit {service, cmd} pairs, not a cross product: not every service has a worker, and asking the builder for a missing `cmd/worker` fails that cell.
# The filesystem is the source rather than a list here: a service gains a worker by gaining the directory.
images='[]'
for svc in $(printf '%s' "$manifest" | jq -r '.services[]'); do
  for cmd in server worker; do
    [ -d "services/${svc}/cmd/${cmd}" ] || continue
    images="$(printf '%s' "$images" | jq -c --arg s "$svc" --arg c "$cmd" '. + [{service: $s, cmd: $c}]')"
  done
done
printf 'images=%s\n' "$images"
