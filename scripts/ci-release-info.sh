#!/usr/bin/env bash
# Resolve a CalVer release tag to its version and commit (ADR-0102, ADR-0103). The `^{}` peel turns an annotated tag into the commit it points at.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

ref="${GITHUB_REF:-}"
[[ "$ref" == refs/tags/* ]] || fail "GITHUB_REF is not a tag: ${ref:-<unset>}"

printf 'version=%s\n' "${ref#refs/tags/}"
printf 'sha=%s\n' "$(git rev-parse "${ref}^{}")"
