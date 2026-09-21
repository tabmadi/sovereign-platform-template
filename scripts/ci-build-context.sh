#!/usr/bin/env bash
# Emit an app's Docker build context as a forge step-output assignment (ADR-0102).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

app="${1:-}"
[[ -n "$app" ]] || fail "usage: mise run ci:build-context -- <app>"

case "$app" in
admin) printf 'context=apps/admin\n' ;;
*) printf 'context=.\n' ;;
esac
