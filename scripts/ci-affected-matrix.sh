#!/usr/bin/env bash
# Emit the affected manifest as forge step-output assignments, with services and apps as separate JSON arrays (ADR-0102).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

manifest="$(mise run ci:affected)"
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
