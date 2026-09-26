#!/usr/bin/env bash
# ADR-0201 gate: an environment's bootstrap directory names that environment alone. A set listing several against one cluster address is several copies of every chart contending for the same objects, and narrowing it afterwards prunes what the survivor owns.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

shopt -s nullglob
dirs=(infra/gitops/*-bootstrap)
[ "${#dirs[@]}" -gt 0 ] || {
  ok "no environment bootstrap directories"
  exit 0
}

step "checking ${#dirs[@]} bootstrap director(ies) name one environment each"
rc=0
for d in "${dirs[@]}"; do
  want="$(basename "$d")"
  want="${want%-bootstrap}"
  found="$(grep -rhoE '\{ *env: *[a-z0-9-]+' "$d" 2>/dev/null | sed -E 's/.*env: *//' | sort -u)"
  [ -n "$found" ] || continue
  for env in $found; do
    if [ "$env" != "$want" ]; then
      warn "${d} generates env '${env}', but the directory is ${want}'s"
      rc=1
    fi
  done
  [ "$rc" -eq 0 ] && detail "${want}"
done

[ "$rc" -eq 0 ] || fail "a bootstrap directory names an environment that is not its own"
ok "every bootstrap directory names one environment"
