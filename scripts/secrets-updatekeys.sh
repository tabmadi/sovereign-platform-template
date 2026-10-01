#!/usr/bin/env bash
# Re-encrypt every SOPS file to the current recipients in .sops.yaml, per ADR-0202.
# Each file embeds the list that grants access, so a .sops.yaml edit does nothing until this runs and the result is committed.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

mapfile -d '' -t files < <(git ls-files -z -- '*.enc.yaml' '*.enc.yml')
if [ "${#files[@]}" -eq 0 ]; then
  ok "no SOPS-managed files in this repository"
  exit 0
fi

step "re-keying ${#files[@]} encrypted file(s) to .sops.yaml"

failed=()
for f in "${files[@]}"; do
  if out="$(sops updatekeys --yes "$f" 2>&1)"; then
    detail "$f"
  else
    failed+=("$f")
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
done

if [ "${#failed[@]}" -gt 0 ]; then
  warn "left unchanged. A file can be re-keyed only by someone who can already decrypt it:"
  printf '  %s\n' "${failed[@]}"
  fail "sops updatekeys failed on ${#failed[@]} of ${#files[@]} file(s)"
fi

ok "every SOPS file matches .sops.yaml. Commit the diff to grant or revoke access"
