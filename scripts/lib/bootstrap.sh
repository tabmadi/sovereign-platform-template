# shellcheck shell=bash

if [[ -n "${__BOOTSTRAP_SH_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
__BOOTSTRAP_SH_LOADED=1

# Absolute, and resolved before the cd: a relative invocation path stops resolving once the shell leaves the caller's directory.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$LIB/log.sh"

# Every relative path in every script is repo-relative, so where the caller stood cannot change what a script reads or writes.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || fail "cannot enter the repository root at $ROOT"
