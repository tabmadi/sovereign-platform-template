#!/usr/bin/env bash
# Shell lint gate, per ADR-0101: shellcheck over every tracked *.sh, with `-x` to follow the `source lib/log.sh` includes.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=lib/repo-files.sh
source "$LIB/repo-files.sh"

step "shellcheck: linting shell scripts"

# Shared with format:shell, so the linter and the formatter act on the same set.
# An empty result is a failure, not a clean run: `act` runs outside a git work tree and would pass after checking nothing.
mapfile -d '' -t files < <(sh_files)
if [[ ${#files[@]} -eq 0 ]]; then
  fail "no shell scripts found through $(repo_source). This repository has dozens, so the enumeration is broken, and the tree is not empty"
fi

# `--severity=warning` does not fail on style and info notes, such as SC2016 for the yq single-quote DSL or SC2001.
# Silence those inline where they are wrong.
shellcheck -x --severity=warning "${files[@]}"

ok "shellcheck clean, ${#files[@]} scripts"
