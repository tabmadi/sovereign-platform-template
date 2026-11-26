#!/usr/bin/env bash
# The data steps of the forge machine, per ADR-0116. forge.nix holds the machine, and `just forge-deploy` applies it.
# These steps hold what no configuration can: the signing key, the users, the tokens, and the repository.
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
source "$here/lib.sh"
facts="$here/settings.nix"

slug="$(answer slug)"
apex="$(answer apex)"
[ -n "$slug" ] && [ -n "$apex" ] || fail "no slug or apex in infra/project.yaml"
SSH_KEY="$(setting "$facts" sshKey)"
KNOWN_HOSTS="$(setting "$facts" knownHosts)"
FORGE_DOMAIN="$(setting "$facts" domain)"
FORGE_ORG="$(setting "$facts" org)"
MIRROR_URL="$(setting "$facts" mirrorUrl)"
guest() { on "root@$(setting "$facts" address)" "$(setting "$facts" jump)"; }

usage() { fail "usage: forge.sh <signing|seed>"; }

SIGNING_KEY_FILE="infra/forge-host/signing-key.enc.yaml"
[ "$#" -eq 1 ] || usage

case "$1" in
signing)
  [ -f "$SIGNING_KEY_FILE" ] || fail "no key at ${SIGNING_KEY_FILE}. Run just secrets-gpg once"
  step "importing the forge's signing key into the Forgejo user"
  key="$(sops -d "$SIGNING_KEY_FILE" | yq -r '.stringData["private.asc"]')"
  guest <<SCRIPT
set -euo pipefail
install -d -m 700 -o forgejo -g forgejo /var/lib/forgejo/.gnupg
runuser -u forgejo -- env GNUPGHOME=/var/lib/forgejo/.gnupg gpg --batch --quiet --import <<'KEY'
${key}
KEY
SCRIPT
  facts_json="$(sops -d "$SIGNING_KEY_FILE" | yq -o=json '.stringData')"
  ok "key imported. Set signing in infra/forge-host/settings.nix to these values, then run just forge-deploy"
  detail "key = $(jq -r .fingerprint <<<"$facts_json")"
  detail "name = $(jq -r .name <<<"$facts_json")"
  detail "email = $(jq -r .email <<<"$facts_json")"
  ;;

seed)
  step "creating the break-glass admin, the machine users, and ${FORGE_ORG}/${slug}"
  guest <<SCRIPT
set -euo pipefail
FJ="runuser -u forgejo -- forgejo --work-path /var/lib/forgejo"
API="https://${FORGE_DOMAIN}/api/v1"
# The break-glass admin is nobody's login, per ADR-0306. Its password and token go to the credential register and offline.
if ! \$FJ admin user list | grep -qw breakglass; then
  PW=\$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
  \$FJ admin user create --admin --username breakglass \
    --password "\${PW}" --email breakglass@${apex} --must-change-password=false
  printf '%s' "\${PW}" > /root/.forgejo-breakglass-password
  chmod 600 /root/.forgejo-breakglass-password
fi
if [ ! -s /root/.forgejo-breakglass-token ]; then
  \$FJ admin user generate-access-token --username breakglass \
    --token-name ${slug} --scopes all | awk '{print \$NF}' > /root/.forgejo-breakglass-token
  chmod 600 /root/.forgejo-breakglass-token
fi
TOKEN=\$(cat /root/.forgejo-breakglass-token)
auth=(-H "Authorization: token \${TOKEN}" -H "Content-Type: application/json")
curl -fsS -X POST "\$API/orgs" "\${auth[@]}" \
  -d '{"username":"${FORGE_ORG}","visibility":"private"}' >/dev/null 2>&1 || true
curl -fsS -X POST "\$API/orgs/${FORGE_ORG}/repos" "\${auth[@]}" \
  -d '{"name":"${slug}","private":true,"default_branch":"master"}' >/dev/null 2>&1 || true
REPO="\$API/repos/${FORGE_ORG}/${slug}"
curl -fsS "\$REPO" "\${auth[@]}" >/dev/null

# Machine users sign in by token alone, so their passwords are thrown away. ci pushes the promotion commit, per
# ADR-0201. argocd clones for Argo CD.
for spec in ci:write argocd:read; do
  u=\${spec%:*} perm=\${spec#*:}
  if ! \$FJ admin user list | grep -qw "\$u"; then
    PW=\$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
    \$FJ admin user create --username \$u --password "\${PW}" \
      --email \$u@${apex} --must-change-password=false
  fi
  if [ ! -s "/root/.forgejo-\$u-token" ]; then
    \$FJ admin user generate-access-token --username \$u \
      --token-name ${slug} --scopes \$perm:repository | awk '{print \$NF}' > "/root/.forgejo-\$u-token"
    chmod 600 "/root/.forgejo-\$u-token"
  fi
  curl -fsS -X PUT "\$REPO/collaborators/\$u" "\${auth[@]}" -d "{\"permission\":\"\$perm\"}"
done
curl -fsS -X PUT "\$REPO/actions/secrets/PROMOTE_TOKEN" "\${auth[@]}" \
  -d "{\"data\":\"\$(cat /root/.forgejo-ci-token)\"}"

# A mirror is a push copy, never the source. The forge makes the mirror's key pair, and its public half is the
# deploy key that the mirror's host needs. A recreated mirror has a new key.
if [ -n "${MIRROR_URL}" ] && [ "\$(curl -fsS "\$REPO/push_mirrors" "\${auth[@]}" | jq length)" = 0 ]; then
  curl -fsS -X POST "\$REPO/push_mirrors" "\${auth[@]}" \
    -d '{"remote_address":"${MIRROR_URL}","use_ssh":true,"interval":"8h0m0s","sync_on_commit":true}' |
    jq -r '"add as a deploy key with write access on the mirror: " + .public_key'
fi
SCRIPT
  ok "forge seeded. The tokens are in /root/.forgejo-*-token on the forge machine"
  ;;

*) usage ;;
esac
