#!/usr/bin/env bash
# Run sqruff across all service migrations and sqlc queries, per ADR-0300.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

shopt -s nullglob globstar

targets=()
for d in services/*/migrations services/*/internal/store/queries; do
  [[ -d "$d" ]] && targets+=("$d")
done

if [[ ${#targets[@]} -eq 0 ]]; then
  ok "no SQL targets to lint yet"
  exit 0
fi

step "linting ${#targets[@]} SQL target(s) with sqruff"
sqruff lint "${targets[@]}"

# PII tagging, per ADR-0301: a column with personal data has its pii:<class> comment in the DDL.
# So erasure, export, and redaction find their targets by query, not by memory.
step "checking personal-data columns are tagged"
go run ./tools/lint-pii
