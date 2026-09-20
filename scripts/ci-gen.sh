#!/usr/bin/env bash
# Drift check: regenerate and reformat everything, then fail if anything changed (ADR-0101, ADR-0303).
set -euo pipefail
source "$(dirname "$0")/lib/log.sh"
source "$(dirname "$0")/lib/repo-files.sh"
cd "$(cd "$(dirname "$0")/.." && pwd)"

snapshot() {
  repo_files | xargs -0 sha256sum 2>/dev/null | LC_ALL=C sort
}

before="$(snapshot)"
if [[ -z "$before" ]]; then
  fail "no files found via $(repo_source) — the enumeration is broken rather than the tree empty"
fi

mise run gen
mise run format

after="$(snapshot)"
if [[ "$after" == "$before" ]]; then
  ok "no drift: generated and formatted artifacts are current"
  exit 0
fi

echo "::error::Generated or formatted artifacts are out of date. Run 'mise run ci:gen' and commit the result."
# The changed paths only; a full diff buries the drift in every other uncommitted change.
# `comm` compares under its own collation and its output is undefined when the inputs are not sorted that way, so LC_ALL=C applies to both.
LC_ALL=C comm -3 <(printf '%s\n' "$before") <(printf '%s\n' "$after") |
  sed -n 's/^[[:space:]]*[0-9a-f]\{64\}[[:space:]]*//p' | LC_ALL=C sort -u
exit 1
