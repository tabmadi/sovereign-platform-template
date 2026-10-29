#!/usr/bin/env bash
# Fit the workflows to the forge that runs them, per ADR-0106 and ADR-0102. It runs at generation and at every update.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

forge="${1:-}"
case "$forge" in
github)
  ok "workflows kept for github"
  exit 0
  ;;
forgejo) ;;
*) fail "usage: forge-mode.sh github|forgejo" ;;
esac

# Forgejo ignores `permissions` and warns on every run. Its token scope is fixed, per ADR-0102.
# A block is the key line and every deeper line after it. A blank line that the removal doubles goes too.
for f in .github/workflows/*.yml; do
  awk '
    function indent(s) { match(s, /[^ ]/); return RSTART }
    {
      blank = ($0 ~ /^[[:space:]]*$/)
      if (skip && !blank && indent($0) > depth) next
      skip = 0
      if ($0 ~ /^[[:space:]]*permissions:/) {
        depth = indent($0)
        skip = ($0 ~ /permissions:[[:space:]]*$/)
        dropped = 1
        next
      }
      if (blank && dropped && lastblank) next
      dropped = 0
      lastblank = blank
      print
    }
  ' "$f" >"$f.tmp"
  mv "$f.tmp" "$f"
done
ok "workflows fitted to forgejo: no permissions blocks"
