#!/usr/bin/env bash
# Generate this engineer's SOPS age key (ADR-0202). Idempotent.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

KEY_DIR="${SOPS_AGE_KEY_DIR:-$HOME/.config/sops/age}"
KEY_FILE="$KEY_DIR/keys.txt"

mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"

if [[ -f "$KEY_FILE" ]]; then
  step "age key already exists at $KEY_FILE (leaving it)"
else
  step "generating age key at $KEY_FILE"
  age-keygen -o "$KEY_FILE"
  chmod 600 "$KEY_FILE"
fi

echo
echo "Your age PUBLIC key — add it to .sops.yaml, then run 'sops updatekeys' on encrypted files:"
echo "  $(age-keygen -y "$KEY_FILE")"
