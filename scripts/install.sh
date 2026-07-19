#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/log.sh"

step "installing mise (https://mise.jdx.dev)"
curl https://mise.run | sh

step "activating mise for this shell"
eval "$(~/.local/bin/mise activate bash)"

step "installing tools pinned in .mise.toml"
mise install

step "running the setup task"
mise run setup

ok "install complete"
