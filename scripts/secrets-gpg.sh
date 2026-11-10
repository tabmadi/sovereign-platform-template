#!/usr/bin/env bash
# Generate the two commit-signing keys, per ADR-0102 and ADR-0202: one for the forge, one for the `ci` machine user.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=../infra/forge-host/forge.env
source infra/forge-host/forge.env

FORGE_KEY="infra/forge-host/signing-key.enc.yaml"
CI_KEY="infra/ci/commit-signing-key.enc.yaml"

if [ -f "$FORGE_KEY" ] || [ -f "$CI_KEY" ]; then
  fail "a commit-signing key already exists. A second one is a rotation. Follow docs/guide/secrets-runbook.md."
fi
if grep -q 'age1example' .sops.yaml; then
  fail ".sops.yaml still has placeholder recipients. Add your real engineer and CI age keys first, with mise run secrets:age."
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"

# <file> <name> <email>. The key has no passphrase, because SOPS encrypts the file that holds it.
generate() {
  local file="$1" name="$2" email="$3" home fp
  home="$(mktemp -d -p "$work")"
  chmod 700 "$home"
  GNUPGHOME="$home" gpg --batch --quiet --passphrase '' \
    --quick-generate-key "${name} <${email}>" ed25519 sign never
  fp="$(GNUPGHOME="$home" gpg --batch --with-colons --list-secret-keys "$email" | awk -F: '$1 == "fpr" {print $10; exit}')"
  [ -n "$fp" ] || fail "gpg made no key for ${email}"
  FP="$fp" EMAIL="$email" NAME="$name" \
    PRIVATE="$(GNUPGHOME="$home" gpg --batch --armor --export-secret-keys "$fp")" \
    yq -n '{
      "apiVersion": "v1",
      "kind": "Secret",
      "metadata": { "name": "commit-signing-key" },
      "stringData": {
        "private.asc": strenv(PRIVATE),
        "fingerprint": strenv(FP),
        "email": strenv(EMAIL),
        "name": strenv(NAME)
      }
    }' >"$work/plain.yaml"
  sops --encrypt --filename-override "$file" "$work/plain.yaml" >"$file"
  ok "${name} ${fp} → ${file}"
}

step "generating the forge's signing key"
generate "$FORGE_KEY" "${FORGE_ORG}-forge" "forge@noreply.${FORGE_DOMAIN}"
step "generating the signing key of the ci user"
generate "$CI_KEY" "ci" "ci@noreply.${FORGE_DOMAIN}"

echo
echo "Next:"
echo "  1. Commit both files. Only their values are ciphertext."
echo "  2. mise run forge:signing imports the forge key and sets the signing keys of app.ini."
echo "  3. mise run forge:ci-user uploads the public key of ci. Only then turn on require_signed_commits."
