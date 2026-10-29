#!/usr/bin/env bash
# The CI runner machine, per ADR-0102: a dedicated Debian machine beside the forge, never on it and never a cluster node.
# A job controls the Docker of this machine, which is root on it. Each step is safe to run again.
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
source "$here/../forge-host/lib.sh"
# shellcheck source=../forge-host/forge.env
source "$here/../forge-host/forge.env"
# shellcheck source=runner.env
source "$here/runner.env"

slug="$(answer project_slug)"
[ -n "$slug" ] || fail "no project_slug in .copier-answers.yml"
name="${slug}-runner"
guest() { on "$RUNNER_SSH" "$RUNNER_JUMP"; }

usage() { fail "usage: runner.sh install"; }
[ "$#" -eq 1 ] && [ "$1" = install ] || usage

# The forge injects a GITHUB_TOKEN of its own, and api.github.com rejects it. mise reads MISE_GITHUB_TOKEN first.
mise_token="${MISE_GITHUB_TOKEN:-}"
[ -n "$mise_token" ] ||
  warn "MISE_GITHUB_TOKEN is unset: jobs that install github: or ubi: tools hit the API's anonymous limit"

step "installing Docker and forgejo-runner ${RUNNER_VERSION} on ${RUNNER_SSH}"
guest <<EOF
set -euo pipefail
cloud-init status --wait >/dev/null 2>&1 || true
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# What a provider-hosted image carries and a job assumes: Node for JavaScript actions, buildx for image builds, pipx
# for mise's pipx tools, and chromium for the shared libraries that the Playwright browser links against.
apt-get install -y -qq docker.io docker-buildx nodejs git git-lfs curl jq unzip xz-utils zstd \
  build-essential python3 pipx chromium ca-certificates >/dev/null
systemctl enable --now docker >/dev/null
# kind runs a kubelet in each node container. Each one holds inotify instances, and the Debian default runs out.
printf 'fs.inotify.max_user_watches = 524288\nfs.inotify.max_user_instances = 512\n' >/etc/sysctl.d/90-kind.conf
sysctl -q --system
# Every checkout runs $(git init), which prints a hint on each job while git has no default branch name.
git config --system init.defaultBranch master
if ! /usr/local/bin/forgejo-runner --version 2>/dev/null | grep -q "${RUNNER_VERSION}"; then
  curl -fsSL -o /tmp/fr \
    "https://code.forgejo.org/forgejo/runner/releases/download/v${RUNNER_VERSION}/forgejo-runner-${RUNNER_VERSION}-linux-amd64"
  install -m 0755 /tmp/fr /usr/local/bin/forgejo-runner && rm -f /tmp/fr
fi
install -d -m 0755 /var/lib/forgejo-runner
EOF

# One job per instance, each as its own user with its own home and temp directory. Tools unpack into both, and one
# job's cache restore or registry logout otherwise lands under another job that is still running.
for n in $(seq 1 "$INSTANCES"); do
  user="runner-${n}"
  state="/var/lib/forgejo-runner/${n}"
  guest <<EOF
set -euo pipefail
id ${user} >/dev/null 2>&1 || useradd --create-home --shell /bin/bash --groups docker ${user}
install -d -m 0700 -o ${user} -g ${user} /home/${user}/run /home/${user}/tmp
install -d -m 0750 -o ${user} -g ${user} ${state}
EOF
  if ! guest <<<"test -f ${state}/.runner"; then
    step "registering ${name}-${n} with ${FORGE_DOMAIN}"
    token="${RUNNER_TOKEN:-}"
    if [ -z "$token" ]; then
      token="$(on "$FORGE_SSH" "$FORGE_JUMP" <<<'su forgejo -c "/usr/local/bin/forgejo actions generate-runner-token --config /etc/forgejo/app.ini" | tail -1')"
    fi
    [ -n "$token" ] || fail "no registration token: set RUNNER_TOKEN, or make the forge reachable over FORGE_SSH"
    guest <<EOF
cd ${state}
su ${user} -c "/usr/local/bin/forgejo-runner register --no-interactive --instance https://${FORGE_DOMAIN} \
  --token '${token}' --name ${name}-${n} --labels ubuntu-24.04:host,ubuntu-latest:host"
EOF
  fi

  # `ubuntu-24.04` is the machine itself, as on a provider-hosted runner, per ADR-0102.
  # One cache, served by instance 1. Separate caches would each warm the registry mirror against one shared Docker Hub limit.
  if [ "$n" = 1 ]; then
    cache="dir: /var/lib/forgejo-runner/cache
  port: ${CACHE_PORT}"
  else
    cache="external_server: http://127.0.0.1:${CACHE_PORT}/"
  fi
  step "writing the config of ${name}-${n}"
  guest <<EOF
set -euo pipefail
umask 077
[ -s /etc/forgejo-runner-cache.secret ] || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' >/etc/forgejo-runner-cache.secret
install -d -m 0700 -o runner-1 -g runner-1 /var/lib/forgejo-runner/cache
cat > ${state}/config.yml <<CFG
cache:
  enabled: true
  host: ${RUNNER_ADDRESS}
  secret: "\$(cat /etc/forgejo-runner-cache.secret)"
  ${cache}
runner:
  capacity: 1
  # Above every workflow's timeout-minutes, which is the limit that ends a job.
  timeout: 3h
  labels: ["ubuntu-24.04:host", "ubuntu-latest:host"]
  envs:
    MISE_GITHUB_TOKEN: "${mise_token}"
    XDG_RUNTIME_DIR: /home/${user}/run
    TMPDIR: /home/${user}/tmp
host:
  workdir_parent: /home/${user}/work
CFG
chown ${user}:${user} ${state}/config.yml
EOF
done

step "writing the units and starting ${INSTANCES} instances"
guest <<EOF
set -euo pipefail
# A job that dies before its post steps leaves its BuildKit builder or its kind cluster running. Nothing else on a
# machine that outlives its jobs removes them. Anything younger than the job cap is left, because a live job can use it.
cat > /usr/local/sbin/runner-gc <<'GC'
#!/bin/sh
cutoff=\$(date -d '-3 hours' +%s)
old() { [ "\$(date -d "\$(docker inspect -f '{{.Created}}' "\$1")" +%s)" -lt "\$cutoff" ]; }
# A \`ci-keep-\` builder is the cache that ci:build-images keeps between jobs on purpose, and BuildKit's own GC bounds it.
docker ps -a --filter name=buildx_buildkit_ --format '{{.Names}}' | while read -r c; do
  case "\$c" in buildx_buildkit_ci-keep-*) continue ;; esac
  old "\$c" || continue
  docker rm -f "\$c" >/dev/null && docker volume rm "\${c}_state" >/dev/null 2>&1
done
# An orphaned kind node or job registry also holds the ports and the lock that every later job needs.
for label in io.x-k8s.kind.cluster platform.ci-job; do
  docker ps -a --filter label=\$label --format '{{.Names}}' | while read -r c; do
    old "\$c" && docker rm -f -v "\$c" >/dev/null
  done
done
docker volume prune -f >/dev/null
# A job's zot store gathers the first-party images of every commit. Past 20GB, and with no registry serving it, it
# goes. The next job restores the third-party mirror from the Actions cache.
if [ -z "\$(docker ps -q --filter name=registry.localhost)" ]; then
  for d in /home/runner-*/.cache/zot/*; do
    [ -d "\$d" ] && [ "\$(du -s "\$d" | cut -f1)" -gt 20000000 ] && rm -rf "\$d"
  done
fi
docker image prune -af --filter until=6h >/dev/null
docker builder prune -af --filter until=6h >/dev/null
GC
chmod 0755 /usr/local/sbin/runner-gc
cat > /etc/systemd/system/runner-gc.service <<'UNIT'
[Unit]
Description=Reclaim what finished CI jobs left behind
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/runner-gc
UNIT
cat > /etc/systemd/system/runner-gc.timer <<'UNIT'
[Unit]
Description=Hourly CI runner garbage collection
[Timer]
OnCalendar=hourly
Persistent=true
[Install]
WantedBy=timers.target
UNIT
cat > /etc/systemd/system/forgejo-runner@.service <<'UNIT'
[Unit]
Description=Forgejo Actions runner %i
After=docker.service
Requires=docker.service

[Service]
User=runner-%i
Environment=HOME=/home/runner-%i
WorkingDirectory=/var/lib/forgejo-runner/%i
ExecStart=/usr/local/bin/forgejo-runner daemon --config /var/lib/forgejo-runner/%i/config.yml
Restart=always

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now runner-gc.timer >/dev/null
for n in \$(seq 1 ${INSTANCES}); do
  systemctl enable forgejo-runner@\$n >/dev/null
  systemctl restart forgejo-runner@\$n
done
# An instance above the count stops. Run this step while that instance is idle, or its job dies.
for unit in \$(systemctl list-units --all --plain --no-legend 'forgejo-runner@*.service' | cut -d' ' -f1); do
  n=\${unit#forgejo-runner@}
  n=\${n%.service}
  [ "\$n" -le ${INSTANCES} ] || systemctl disable --now "\$unit" >/dev/null
done
sleep 5
for n in \$(seq 1 ${INSTANCES}); do
  systemctl is-active --quiet forgejo-runner@\$n || { echo "forgejo-runner@\$n is not running"; exit 1; }
done
EOF
ok "${INSTANCES} instances of ${name} polling ${FORGE_DOMAIN}"
