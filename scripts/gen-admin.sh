#!/usr/bin/env bash
# Regenerate the Lowdefy admin pages from the service OpenAPI specs, per ADR-0401.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

step "Lowdefy admin pages from services/*/openapi.yaml"
go run ./tools/admin-gen
