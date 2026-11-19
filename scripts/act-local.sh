#!/usr/bin/env bash
# Runs a workflow locally with act, per ADR-0116. Each job installs Nix itself, so the base image holds no toolchain.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

PROXY="${ACT_PROXY:-}"
IMAGE="${ACT_IMAGE:-catthehacker/ubuntu:act-latest}"
EVENT="${ACT_EVENT:-pull_request}"
ENV_FILE="${ACT_ENV_FILE:-.env}"

NO_PROXY="127.0.0.1,localhost"
HOST_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") print $(i + 1)}' || true)"
[[ -n "$HOST_IP" ]] && NO_PROXY+=",$HOST_IP"

ACT_ARGS=()
proxy_env=()
if [[ -n "$PROXY" ]]; then
  step "checking proxy ${PROXY}"
  curl -sS -o /dev/null -m 10 -x "$PROXY" https://cache.nixos.org/nix-cache-info ||
    fail "proxy ${PROXY} is unreachable. A job needs it to download Nix and the toolchain"
  proxy_env=(--env "HTTP_PROXY=$PROXY" --env "HTTPS_PROXY=$PROXY" --env "NO_PROXY=$NO_PROXY")
fi

secrets=()
[[ -f "$ENV_FILE" ]] && secrets=(--secret-file "$ENV_FILE")

step "running act ${EVENT} on ${IMAGE}"
act "$EVENT" \
  -P "ubuntu-latest=${IMAGE}" -P "ubuntu-24.04=${IMAGE}" \
  --network host \
  "${proxy_env[@]}" \
  "${secrets[@]}" \
  -e ".github/act/$EVENT.json" \
  "$@"
