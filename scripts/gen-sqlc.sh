#!/usr/bin/env bash
# Regenerate sqlc Go code for every service that has a sqlc.yaml (ADR-0300).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

shopt -s nullglob

for cfg in services/*/sqlc.yaml; do
  service_dir=$(dirname "$cfg")
  step "sqlc: $service_dir"
  (cd "$service_dir" && sqlc generate)
done
