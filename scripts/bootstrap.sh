#!/usr/bin/env bash
# One command for a fresh checkout, per ADR-0106. Idempotent.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

if [ ! -f .env ] && [ -f .env.example ]; then
  cp .env.example .env
  detail ".env seeded from .env.example"
fi

# A template checkout keeps the shipped keys. A new key would encrypt its secrets to one engineer's machine.
if [ ! -f .copier-answers.yml ]; then
  ok "template checkout: project keys are not changed"
  exit 0
fi

step "ensuring this engineer's SOPS age key"
bash scripts/secrets-age.sh >/dev/null
recipient="$(age-keygen -y "${SOPS_AGE_KEY_DIR:-$HOME/.config/sops/age}/keys.txt")"

# The placeholder blocks every encryption until a person gives a key, so bootstrap gives it.
if grep -q 'age1example' .sops.yaml; then
  step "adopting the engineer recipient that starts with ${recipient:0:20}"
  sed -i -E "s|(&eng_placeholder[[:space:]]+)age1[a-z0-9]+|\1${recipient}|" .sops.yaml
  grep -q "$recipient" .sops.yaml ||
    fail ".sops.yaml does not name the engineer recipient. The &eng_placeholder anchor was not found"
fi

step "minting this project's local-tier age key"
bash scripts/rotate-local-age-key.sh

step "re-encrypting the committed secrets to the current recipients"
bash scripts/secrets-updatekeys.sh

ok "bootstrap complete. Run 'mise run cluster:up'"
if [ ! -s infra/auth/cosign/cosign.pub ]; then
  printf '  Signing key: add the CI and ops-recovery age recipients to .sops.yaml, then run '\''mise run secrets:cosign'\''.\n'
fi
