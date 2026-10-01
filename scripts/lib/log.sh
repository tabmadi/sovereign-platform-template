# shellcheck shell=bash

# Do not define the functions again when the file is sourced twice.
if [[ -n "${__LOG_SH_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
__LOG_SH_LOADED=1

# → a step is starting.
step() { printf '→ %s\n' "$*"; }

# ✓ a step succeeded.
ok() { printf '✓ %s\n' "$*"; }

# ⚠ a recoverable warning. It goes to stderr, so it stands out and does not pollute a piped stdout.
warn() { printf '⚠ %s\n' "$*" >&2; }

# ✗ a fatal error to stderr, then exit. The optional second argument is the exit code.
fail() {
  printf '✗ %s\n' "$1" >&2
  exit "${2:-1}"
}

# A detail under a step, indented by two spaces.
detail() { printf '  %s\n' "$*"; }
