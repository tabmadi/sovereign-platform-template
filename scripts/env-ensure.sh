#!/usr/bin/env bash
# Guard the one failure of the inner loop that shows no error, per ADR-0205.
# Run it from a service directory, as a dependency of its server, worker, and migrate tasks.
set -euo pipefail
# log.sh alone, not lib/bootstrap.sh: this script works on the directory it was called from, and a cd to the repository root would lose it.
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

[ -f .env ] && exit 0

[ -f .env.example ] || fail "no .env or .env.example in $(pwd)"

cp .env.example .env
step "seeded .env from .env.example"
detail "review it, then run again. mise reads .env when it loads the config,"
detail "so this run has no environment yet."
exit 1
