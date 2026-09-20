#!/usr/bin/env bash
# Regenerate the Lowdefy admin pages from the service OpenAPI specs (ADR-0401).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

echo "→ admin pages (Lowdefy) from services/*/openapi.yaml"
go run ./tools/admin-gen
