#!/usr/bin/env bash
# Generate the platform's image-signing key pair (ADR-0104, ADR-0202).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

KEY_DIR="infra/auth/cosign"
PUB_KEY="${KEY_DIR}/cosign.pub"
PRIVATE="${KEY_DIR}/signing-key.enc.yaml"

# NON-EMPTY, not merely present: the template commits an empty cosign.pub so the
# Helm fileParameter that reads it resolves in every environment (a path that does
# not exist fails every application in the tier, not just this one).
if [ -s "$PUB_KEY" ] || [ -f "$PRIVATE" ]; then
  fail "${KEY_DIR} already holds a key pair. Generating a second one is a ROTATION — follow docs/guide/secrets-runbook.md, which carries both public keys through the window."
fi

# The recipients come from .sops.yaml. Refusing early with the real reason beats
# failing inside sops with "malformed recipient": the template ships placeholder
# age keys, so this is the first thing a new project hits.
if grep -q 'age1example' .sops.yaml; then
  fail ".sops.yaml still carries placeholder recipients. Add your real engineer and CI age keys first (mise run secrets:age, then .sops.yaml) — a signing key encrypted to a placeholder is a signing key nobody can decrypt."
fi

mkdir -p "$KEY_DIR"

# cosign writes cosign.key/cosign.pub into the working directory and reads COSIGN_PASSWORD. The passphrase is generated: it is encrypted beside the key it protects.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
password="$(head -c 32 /dev/urandom | base64 | tr -d '\n=' | head -c 32)"

step "generating the platform image-signing key pair"
(cd "$work" && COSIGN_PASSWORD="$password" cosign generate-key-pair >/dev/null)

cp "$work/cosign.pub" "$PUB_KEY"
ok "public key → ${PUB_KEY} (committed in the clear; every environment's Kyverno policy names it)"

step "encrypting the private half into ${PRIVATE}"
COSIGN_KEY="$(cat "$work/cosign.key")" COSIGN_PASSWORD="$password" \
  yq -n '{
    "apiVersion": "v1",
    "kind": "Secret",
    "metadata": { "name": "cosign-signing-key" },
    "stringData": {
      "cosign.key": strenv(COSIGN_KEY),
      "COSIGN_PASSWORD": strenv(COSIGN_PASSWORD)
    }
  }' >"$work/plain.yaml"
sops --encrypt --filename-override "$PRIVATE" "$work/plain.yaml" >"$PRIVATE"

ok "private key + passphrase → ${PRIVATE}"
echo
echo "Next:"
echo "  1. Commit both halves. The public one is plaintext by design."
echo "  2. Kyverno's ClusterPolicy names ${PUB_KEY} as its attestor (infra/helm/platform/kyverno)."
echo "  3. Give CI an age recipient in .sops.yaml and its private half as a forge"
echo "     secret, so ci:sign can decrypt this file. Nothing else ever decrypts it."
