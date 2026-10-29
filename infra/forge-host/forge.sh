#!/usr/bin/env bash
# The forge machine, per ADR-0102. A forge that Argo CD deployed could not recover a lost cluster. So it is a Debian
# machine beside the workload cluster, not a chart inside it. Each step is safe to run again.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=forge.env
source "$(dirname "${BASH_SOURCE[0]}")/forge.env"

slug="$(answer project_slug)"
apex="$(answer apex_host)"
[ -n "$slug" ] && [ -n "$apex" ] || fail "no project_slug or apex_host in .copier-answers.yml"
guest() { on "$FORGE_SSH" "$FORGE_JUMP"; }

usage() { fail "usage: forge.sh <install|configure|seed>"; }
[ "$#" -eq 1 ] || usage

case "$1" in
install)
  step "installing Postgres and Forgejo ${FORGEJO_VERSION} on ${FORGE_SSH}"
  # No hosts entry for the public name. A loopback override is inherited by every job container, where nothing serves 443.
  guest <<EOF
set -euo pipefail
cloud-init status --wait >/dev/null 2>&1 || true
for _ in \$(seq 1 60); do fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || break; sleep 5; done
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq postgresql git git-lfs curl jq ca-certificates >/dev/null
id forgejo >/dev/null 2>&1 || useradd --system --shell /bin/bash --comment forgejo \
  --home-dir /var/lib/forgejo --create-home forgejo
install -d -o forgejo -g forgejo /var/lib/forgejo /etc/forgejo /var/log/forgejo

if ! su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='forgejo'\"" | grep -q 1; then
  PW=\$(head -c 18 /dev/urandom | base64 | tr -d '/+=' | head -c 24)
  su - postgres -c "psql -c \"CREATE ROLE forgejo LOGIN PASSWORD '\${PW}'\""
  su - postgres -c "createdb -O forgejo forgejo"
  printf '%s' "\${PW}" > /root/.forgejo-db-password
  chmod 600 /root/.forgejo-db-password
fi

if [ ! -x /usr/local/bin/forgejo ] || ! /usr/local/bin/forgejo --version | grep -q "${FORGEJO_VERSION}"; then
  curl -fsSL -o /tmp/forgejo \
    "https://codeberg.org/forgejo/forgejo/releases/download/v${FORGEJO_VERSION}/forgejo-${FORGEJO_VERSION}-linux-amd64"
  install -m 0755 /tmp/forgejo /usr/local/bin/forgejo && rm -f /tmp/forgejo
fi
/usr/local/bin/forgejo --version
EOF
  ok "base installed. Run 'configure' next"
  ;;

configure)
  step "writing app.ini and the unit"
  # Forgejo's own ACME, not a reverse proxy: the host serves one service on 80 and 443, so a proxy decides no route.
  # Binding 443 needs the capability, not root.
  guest <<EOF
set -euo pipefail
PW=\$(cat /root/.forgejo-db-password)
if [ -f /etc/forgejo/app.ini ]; then
  # A second run keeps the secrets. New ones would end every session and break every stored token.
  SECRET=\$(awk -F' = ' '\$1 ~ /^SECRET_KEY/ {print \$2}' /etc/forgejo/app.ini)
  TOKEN=\$(awk -F' = ' '\$1 ~ /^INTERNAL_TOKEN/ {print \$2}' /etc/forgejo/app.ini)
  LFS=\$(awk -F' = ' '\$1 ~ /^LFS_JWT_SECRET/ {print \$2}' /etc/forgejo/app.ini)
  JWT=\$(awk -F' = ' '\$1 ~ /^JWT_SECRET/ {print \$2}' /etc/forgejo/app.ini)
else
  SECRET=\$(/usr/local/bin/forgejo generate secret SECRET_KEY)
  TOKEN=\$(/usr/local/bin/forgejo generate secret INTERNAL_TOKEN)
  LFS=\$(/usr/local/bin/forgejo generate secret LFS_JWT_SECRET)
  JWT=\$(/usr/local/bin/forgejo generate secret JWT_SECRET)
fi
cat > /etc/forgejo/app.ini <<CFG
APP_NAME = ${slug}
RUN_USER = forgejo
RUN_MODE = prod
WORK_PATH = /var/lib/forgejo

[server]
PROTOCOL            = https
DOMAIN              = ${FORGE_DOMAIN}
ROOT_URL            = https://${FORGE_DOMAIN}/
HTTP_PORT           = 443
REDIRECT_OTHER_PORT = true
PORT_TO_REDIRECT    = 80
ENABLE_ACME         = true
ACME_ACCEPTTOS      = true
ACME_DIRECTORY      = /var/lib/forgejo/acme
ACME_EMAIL          = ${ACME_EMAIL}
START_SSH_SERVER    = true
SSH_PORT            = 2222
SSH_LISTEN_PORT     = 2222
LFS_START_SERVER    = true
LFS_JWT_SECRET      = \${LFS}
APP_DATA_PATH       = /var/lib/forgejo/data

[database]
DB_TYPE  = postgres
HOST     = 127.0.0.1:5432
NAME     = forgejo
USER     = forgejo
PASSWD   = \${PW}
SSL_MODE = disable

[security]
INSTALL_LOCK   = true
SECRET_KEY     = \${SECRET}
INTERNAL_TOKEN = \${TOKEN}

[oauth2]
JWT_SECRET = \${JWT}

[service]
DISABLE_REGISTRATION = true

[repository]
DEFAULT_BRANCH = master

[actions]
ENABLED = true
# The workflows call actions from GitHub that the default action mirror does not carry.
DEFAULT_ACTIONS_URL = github
CFG
chmod 640 /etc/forgejo/app.ini && chown root:forgejo /etc/forgejo/app.ini

cat > /etc/systemd/system/forgejo.service <<UNIT
[Unit]
Description=Forgejo
After=network.target postgresql.service

[Service]
Type=simple
User=forgejo
WorkingDirectory=/var/lib/forgejo
ExecStart=/usr/local/bin/forgejo web --config /etc/forgejo/app.ini
Restart=always
AmbientCapabilities=CAP_NET_BIND_SERVICE
Environment=USER=forgejo HOME=/var/lib/forgejo GITEA_WORK_DIR=/var/lib/forgejo

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable forgejo >/dev/null
systemctl restart forgejo
sleep 8
systemctl is-active forgejo
EOF
  ok "forgejo configured and running at https://${FORGE_DOMAIN}"
  ;;

seed)
  step "creating the break-glass admin, the machine users, and ${FORGE_ORG}/${slug}"
  guest <<EOF
set -euo pipefail
FJ="su forgejo -c"
cfg="--config /etc/forgejo/app.ini"
API="https://${FORGE_DOMAIN}/api/v1"
# The break-glass admin is nobody's login, per ADR-0306. Its password and token go to the credential register and offline.
if ! \$FJ "/usr/local/bin/forgejo admin user list \$cfg" | grep -qw breakglass; then
  PW=\$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
  \$FJ "/usr/local/bin/forgejo admin user create --admin --username breakglass \
    --password '\${PW}' --email breakglass@${apex} --must-change-password=false \$cfg"
  printf '%s' "\${PW}" > /root/.forgejo-breakglass-password
  chmod 600 /root/.forgejo-breakglass-password
fi
if [ ! -s /root/.forgejo-breakglass-token ]; then
  \$FJ "/usr/local/bin/forgejo admin user generate-access-token --username breakglass \
    --token-name ${slug} --scopes all \$cfg" | awk '{print \$NF}' > /root/.forgejo-breakglass-token
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
  if ! \$FJ "/usr/local/bin/forgejo admin user list \$cfg" | grep -qw "\$u"; then
    PW=\$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
    \$FJ "/usr/local/bin/forgejo admin user create --username \$u --password '\${PW}' \
      --email \$u@${apex} --must-change-password=false \$cfg"
  fi
  if [ ! -s "/root/.forgejo-\$u-token" ]; then
    \$FJ "/usr/local/bin/forgejo admin user generate-access-token --username \$u \
      --token-name ${slug} --scopes \$perm:repository \$cfg" | awk '{print \$NF}' > "/root/.forgejo-\$u-token"
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
EOF
  ok "forge seeded. The tokens are in /root/.forgejo-*-token on the forge machine"
  ;;

*) usage ;;
esac
