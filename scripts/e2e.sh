#!/usr/bin/env bash
# Runs one npm script of the e2e island, inside its dev shell, per ADR-0601: test, test:smoke, test:a11y, test:visual, or lighthouse.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

script="${1:?usage: just e2e, e2e-smoke, e2e-a11y, e2e-visual, or lighthouse}"
shift

# The suite reaches the edge directly, never through a dev HTTPS_PROXY. The port-forwards in the cluster are on loopback.
export NO_PROXY="localhost,127.0.0.1,.localtest.me" no_proxy="localhost,127.0.0.1,.localtest.me"

cd test/e2e
[ -d node_modules ] || npm ci
# The `--` hands the added arguments to Playwright. Without it, npm takes them.
exec npm run "$script" -- "$@"
