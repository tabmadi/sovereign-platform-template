#!/usr/bin/env bash
# Product-edge wildcard gate (ADR-0017). The `api-services` rule must enumerate the
# resources it fronts (/api/<{products,orders,...}>), never a bare `<**>/api/<**>`.
# A bare wildcard collides with every ops dashboard's own route, so an ops `/api/*`
# request matches two rules and Oathkeeper returns 500 — the panel-breaking
# regression this guard prevents from recurring.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

RULES="infra/auth/oathkeeper/access-rules.json"

# Single-binary Go check (toolchain philosophy: Go + bun only, no ambient Python).
go run ./tools/lint-api-wildcard "$RULES"
