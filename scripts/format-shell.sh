#!/usr/bin/env bash
# Shell formatter: shfmt in place over every script, `-i 2` to match the repo's style (ADR-0101).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/repo-files.sh"

mapfile -d '' -t files < <(sh_files)
if [[ ${#files[@]} -eq 0 ]]; then
  fail "no shell scripts found via $(sh_source) — this repository has dozens, so the enumeration is broken rather than the tree empty"
fi

shfmt -w -i 2 "${files[@]}"
ok "shfmt formatted ${#files[@]} scripts"
