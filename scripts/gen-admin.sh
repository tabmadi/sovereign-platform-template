#!/usr/bin/env bash
# Regenerate the Lowdefy admin pages from the service OpenAPI specs (ADR-0401).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

step "admin pages (Lowdefy) from services/*/openapi.yaml"
go run ./tools/admin-gen
