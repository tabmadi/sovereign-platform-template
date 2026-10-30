#!/usr/bin/env bash
# Shared by the forge-host and runner scripts, per ADR-0102. They reach a Debian machine over SSH, with an optional jump host.
# shellcheck source=../../scripts/lib/bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/bootstrap.sh"

# One answer from the Copier answers file. The answers name the project, so no script here repeats the slug or the apex.
answer() { # <key>
  awk -v k="$1:" '$1 == k {print $2; exit}' .copier-answers.yml 2>/dev/null
}

# Runs stdin as a bash script on <target>, as `user@host`. <jump> is a host that the target is reachable only from.
# The key reaches both hops, because ProxyJump does not pass an identity file to the first one.
on() { # <target> [jump]
  local target="$1" jump="${2:-}" opts=(-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new)
  if [ -n "${SSH_KEY:-}" ]; then opts+=(-i "$SSH_KEY"); fi
  if [ -n "$jump" ]; then
    # The jump host is the hypervisor. Its keys are pinned when the project committed them, and the machine behind it is new.
    hop=("${opts[@]}")
    if [ -n "${KNOWN_HOSTS:-}" ]; then
      hop=(-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=${KNOWN_HOSTS}")
      if [ -n "${SSH_KEY:-}" ]; then hop+=(-i "$SSH_KEY"); fi
    fi
    opts+=(-o "ProxyCommand=ssh ${hop[*]} -W %h:%p ${jump}")
  fi
  ssh "${opts[@]}" "$target" 'bash -s'
}
