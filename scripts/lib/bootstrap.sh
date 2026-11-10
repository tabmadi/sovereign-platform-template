# shellcheck shell=bash

if [[ -n "${__BOOTSTRAP_SH_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
__BOOTSTRAP_SH_LOADED=1

# Absolute, and resolved before the cd. A relative path stops working after the shell leaves the caller's directory.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$LIB/log.sh"

# Stop background jobs and their children. `f &` on a shell function forks a subshell, so `kill $!` alone leaves its kubectl running.
reap() {
  local p
  for p in "$@"; do
    [ -n "$p" ] || continue
    pkill -P "$p" 2>/dev/null
    kill "$p" 2>/dev/null
  done
  return 0
}

# Every relative path in every script is relative to the repo, so the caller's directory cannot change what a script reads or writes.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || fail "cannot enter the repository root at $ROOT"
