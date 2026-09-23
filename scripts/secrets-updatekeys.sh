#!/usr/bin/env bash
# Re-encrypt every SOPS file to .sops.yaml's current recipients (ADR-0202). The list that grants access is the one embedded in each file, so a .sops.yaml edit does nothing until this runs and the result is committed.
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
  warn "left unchanged — re-keying a file requires already being able to decrypt it:"
  printf '  %s\n' "${failed[@]}"
  fail "sops updatekeys failed on ${#failed[@]} of ${#files[@]} file(s)"
fi

ok "every SOPS file matches .sops.yaml — commit the diff to grant or revoke access"
