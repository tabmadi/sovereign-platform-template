#!/usr/bin/env bash
# Shell lint gate (ADR-0101): shellcheck over every tracked *.sh, with `-x` to follow the `source lib/log.sh` includes.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/repo-files.sh"

step "shellcheck: linting shell scripts"

# Shared with format:shell, so the linter and the formatter cannot act on different sets.
# An empty result is a failure, not a clean run: `act` runs outside a git work tree and would otherwise pass having checked nothing.
mapfile -d '' -t files < <(sh_files)
if [[ ${#files[@]} -eq 0 ]]; then
  fail "no shell scripts found via $(sh_source) — this repository has dozens, so the enumeration is broken rather than the tree empty"
fi

# without failing on style/info chatter such as yq single-quote DSL (SC2016) or
# sed-vs-parameter-expansion (SC2001); silence those inline where they are wrong.
shellcheck -x --severity=warning "${files[@]}"

ok "shellcheck clean (${#files[@]} scripts)"
