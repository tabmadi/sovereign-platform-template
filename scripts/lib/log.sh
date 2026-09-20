# shellcheck shell=bash

# Avoid re-defining if sourced twice.
if [[ -n "${__LOG_SH_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
__LOG_SH_LOADED=1

# → a step is starting.
step() { printf '→ %s\n' "$*"; }

# ✓ a step succeeded.
ok() { printf '✓ %s\n' "$*"; }

# ⚠ a warning (recoverable); goes to stderr so it stands out but does not pollute
# a piped stdout.
warn() { printf '⚠ %s\n' "$*" >&2; }

# ✗ a fatal error to stderr, then exit. Optional second arg is the exit code.
fail() {
  printf '✗ %s\n' "$1" >&2
  exit "${2:-1}"
}

# Two-space-indented sub-detail under a step.
detail() { printf '  %s\n' "$*"; }
