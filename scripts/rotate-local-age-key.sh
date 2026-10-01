#!/usr/bin/env bash
# Give this project its own local-tier age key, per ADR-0202 and ADR-0205.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

KEY_FILE="infra/gitops/platform/local/age.key"
SOPS_FILE=".sops.yaml"
SECRETS_GLOB="infra/gitops/platform/local/secrets"

# The recipient that this template ships. A key that matches it is not rotated, and this script exists to detect that.
# It is recorded here, not in a separate file, so there is one place to update if the shipped key changes.
TEMPLATE_RECIPIENT="age1aapmzzzcs8qm2n9exkel8vtknqsmy9t3k9g99wpypfez8av4uaps0f9gpp"

FORCE=false
[ "${1:-}" != "--force" ] || FORCE=true

[ -f "$KEY_FILE" ] || fail "$KEY_FILE does not exist"

current="$(age-keygen -y "$KEY_FILE")"

if [ "$FORCE" = false ] && [ "$current" != "$TEMPLATE_RECIPIENT" ]; then
  ok "the local age key is this project's own, ${current:0:20}"
  exit 0
fi

step "minting a local age key for this project"

# The header that explains why a private key is committed must survive the rotation.
# `age-keygen -o` writes its own file, so the header is attached again.
header="$(grep '^#' "$KEY_FILE" || true)"
tmp="$(mktemp)"
old="$(mktemp)"
both="$(mktemp)"
trap 'rm -f "$tmp" "$old" "$both"' EXIT

# The old key must survive the overwrite: `sops updatekeys` must decrypt the file before it re-encrypts to the new recipients.
cp "$KEY_FILE" "$old"

# `age-keygen -o` refuses to overwrite an existing file, and mktemp already created one.
# So the name is reserved and then cleared before the key is written.
rm -f "$tmp"
age-keygen -o "$tmp" 2>/dev/null
chmod 600 "$tmp"
new_recipient="$(age-keygen -y "$tmp")"

{
  printf '%s\n' "$header"
  grep -v '^#' "$tmp"
} >"$KEY_FILE"
chmod 600 "$KEY_FILE"

step "pointing .sops.yaml's cluster_local recipient at it"
# Matched on the anchor name, so this cannot rewrite one of the other four recipients if the file is reordered.
sed -i -E "s|(&cluster_local[[:space:]]+)age1[a-z0-9]+|\1${new_recipient}|" "$SOPS_FILE"

grep -q "$new_recipient" "$SOPS_FILE" ||
  fail ".sops.yaml still does not name the new recipient. The cluster_local anchor was not found"

# Re-encrypt while the old key can still read the existing values. `sops updatekeys` decrypts with a current recipient
# and re-encrypts to the new recipient set.
step "re-encrypting the local secrets to the new recipient"
shopt -s nullglob
files=("$SECRETS_GLOB"/*.enc.yaml)
shopt -u nullglob

if [ ${#files[@]} -eq 0 ]; then
  # Not a silent pass. The template ships an encrypted file here, so none means the path moved or a project deleted it.
  # In the second case, the rotation above just orphaned the recipients of that file.
  fail "no encrypted files under ${SECRETS_GLOB}/. Expected at least one"
fi

# Both keys in one file: sops reads every identity it gets. The old one opens the file, and the new one is the recipient .sops.yaml now names.
cat "$old" "$tmp" >"$both"

for f in "${files[@]}"; do
  SOPS_AGE_KEY_FILE="$both" sops updatekeys --yes "$f" >/dev/null
  printf '  %s\n' "$f"
done

ok "local age key rotated to ${new_recipient:0:20}"
printf '  The shared template key no longer opens this project.\n'
