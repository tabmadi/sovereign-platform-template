#!/usr/bin/env bash
# Generate the platform's image-signing key pair, per ADR-0104 and ADR-0202.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

KEY_DIR="infra/auth/cosign"
PUB_KEY="${KEY_DIR}/cosign.pub"
PRIVATE="${KEY_DIR}/signing-key.enc.yaml"

# Not empty, not only present: the template commits an empty cosign.pub so the Helm fileParameter that reads it resolves in every environment.
# A path that does not exist fails every application in the tier, not only this one.
if [ -s "$PUB_KEY" ] || [ -f "$PRIVATE" ]; then
  fail "${KEY_DIR} already holds a key pair. A second one is a rotation. Follow docs/guide/secrets-runbook.md, which keeps both public keys through the window."
fi

# The recipients come from .sops.yaml. An early refusal with the real reason is better than a `malformed recipient` failure inside sops.
# The template ships placeholder age keys, so a new project hits this first.
if grep -q 'age1example' .sops.yaml; then
  fail ".sops.yaml still has placeholder recipients. Add your real engineer and CI age keys first, with mise run secrets:age and then .sops.yaml. Nobody can decrypt a signing key encrypted to a placeholder."
fi

mkdir -p "$KEY_DIR"

# cosign writes cosign.key and cosign.pub into the working directory and reads COSIGN_PASSWORD.
# The passphrase is generated, and it is encrypted next to the key it protects.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
password="$(head -c 32 /dev/urandom | base64 | tr -d '\n=' | head -c 32)"

step "generating the platform image-signing key pair"
(cd "$work" && COSIGN_PASSWORD="$password" cosign generate-key-pair >/dev/null)

cp "$work/cosign.pub" "$PUB_KEY"
ok "public key → ${PUB_KEY}. It is committed in clear text, and every environment's Kyverno policy names it"

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

ok "private key and passphrase → ${PRIVATE}"
echo
echo "Next:"
echo "  1. Commit both halves. The public one is plaintext by design."
echo "  2. Kyverno's ClusterPolicy in infra/helm/platform/kyverno names ${PUB_KEY} as its attestor."
echo "  3. Give CI an age recipient in .sops.yaml and its private half as a forge"
echo "     secret, so ci:sign can decrypt this file. Nothing else ever decrypts it."
