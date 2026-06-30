#!/usr/bin/env bash
# Ops-tier authorizer policy (ADR-0017, Phase 8). Every operator-dashboard access
# rule must authorize per-tool via the remote_json authorizer (→ SpiceDB Checker),
# never `allow`. A re-introduced `"authorizer": {"handler": "allow"}` on an ops
# route is exactly the gap this whole effort closes, so CI fails on it.
#
# Product /api routes legitimately keep `allow` (services authorize in-process via
# libs/go/authz), so only ops-* rules are checked.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

RULES="infra/auth/oathkeeper/access-rules.json"

# Single-binary Go check (toolchain philosophy: Go + bun only, no ambient Python).
go run ./tools/lint-authorizer "$RULES"
