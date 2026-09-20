#!/usr/bin/env bash
# Plaintext-secret scan (ADR-0202). The defect survives its own fix: reverting the file leaves the value in history.
set -euo pipefail
# shellcheck source=lib/log.sh
source "$(dirname "$0")/lib/log.sh"

args=(--config .gitleaks.toml --redact --no-banner)

if [[ -n "${GITLEAKS_HISTORY:-}" ]]; then
  step "scanning full git history for plaintext secrets"
  gitleaks git "${args[@]}"
else
  step "scanning the working tree for plaintext secrets"
  gitleaks dir . "${args[@]}"
fi

ok "no plaintext secrets found"
