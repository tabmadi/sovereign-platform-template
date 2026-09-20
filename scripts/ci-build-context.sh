#!/usr/bin/env bash
# Emit an app's Docker build context as a forge step-output assignment (ADR-0102).
set -euo pipefail
# shellcheck source=lib/log.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

app="${1:-}"
[[ -n "$app" ]] || fail "usage: mise run ci:build-context -- <app>"

case "$app" in
admin) printf 'context=apps/admin\n' ;;
*) printf 'context=.\n' ;;
esac
