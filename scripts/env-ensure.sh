#!/usr/bin/env bash
# Guard the inner loop's one silent failure (ADR-0205). Run from a service directory, as a dependency of its server/worker/migrate tasks.
set -euo pipefail
# log.sh alone, not lib/bootstrap.sh: this script's subject is the directory it was called from, which a cd to the repository root would discard.
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

[ -f .env ] && exit 0

[ -f .env.example ] || fail "no .env or .env.example in $(pwd)"

cp .env.example .env
step "seeded .env from .env.example"
detail "review it, then re-run — mise reads .env when it loads the config, so this"
detail "run has no environment yet."
exit 1
