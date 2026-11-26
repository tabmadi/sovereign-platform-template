#!/usr/bin/env bash
# The data step of the CI runner machine, per ADR-0116. runner.nix holds the machine, and `just runner-deploy` applies
# it. This step mints the registration token on the forge and writes it on the runner, outside the Nix store.
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
source "$here/../forge-host/lib.sh"
forge="$here/../forge-host/settings.nix"
facts="$here/settings.nix"

SSH_KEY="$(setting "$forge" sshKey)"
KNOWN_HOSTS="$(setting "$forge" knownHosts)"
domain="$(setting "$forge" domain)"
instances="$(setting "$facts" instances)"

usage() { fail "usage: runner.sh token"; }
[ "$#" -eq 1 ] && [ "$1" = token ] || usage

token="${RUNNER_TOKEN:-}"
if [ -z "$token" ]; then
  step "minting a registration token on ${domain}"
  token="$(on "root@$(setting "$forge" address)" "$(setting "$forge" jump)" <<<'runuser -u forgejo -- forgejo --work-path /var/lib/forgejo actions generate-runner-token' | tail -1)"
fi
[ -n "$token" ] || fail "no registration token: set RUNNER_TOKEN, or make the forge reachable over SSH"

step "writing the token on the runner and starting ${instances} instances"
on "root@$(setting "$facts" address)" "$(setting "$facts" jump)" <<SCRIPT
set -euo pipefail
install -d -m 0700 /var/lib/forgejo-runner
umask 077
printf 'TOKEN=%s\n' '${token}' > /var/lib/forgejo-runner/token
for n in \$(seq 1 ${instances}); do
  systemctl restart "gitea-runner-\$n"
done
sleep 5
for n in \$(seq 1 ${instances}); do
  systemctl is-active --quiet "gitea-runner-\$n" || { echo "gitea-runner-\$n is not running"; exit 1; }
done
SCRIPT
ok "${instances} instances registered with ${domain}"
