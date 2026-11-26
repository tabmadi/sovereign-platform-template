#!/usr/bin/env bash
# Makes a project from this working tree and proves that it reaches a serving cluster, per TPL-0000. This defines `ready to use`.
# It needs Docker, so it runs in CI and never in `just check`.
set -euo pipefail
source "$(tabkit-ops lib)/bootstrap.sh"

DATA_FILE="${ACCEPTANCE_DATA:-template/test/fixtures/valid/defaults.yml}"
WORK="$(mktemp -d)"
# The stand-in forge below: a git daemon on this host, on the port that git:// uses.
GIT_PORT=9418
git_pid=""
# Its own lint cache. Every run has the same module path in a new directory, and a shared cache then reports stale paths.
export GOLANGCI_LINT_CACHE="$WORK/golangci-lint"
trap '[ -z "$git_pid" ] || kill "$git_pid" 2>/dev/null; rm -rf "$WORK"' EXIT

if [ "${ACCEPTANCE_PROXY_ONLY:-0}" = 1 ]; then
  step "checking that the runner needs the proxy"
  probe=https://cache.nixos.org/nix-cache-info
  [ -n "${HTTPS_PROXY:-${https_proxy:-}}" ] || fail "set HTTPS_PROXY before running the proxy acceptance test"
  if curl --noproxy '*' --max-time 5 --silent --output /dev/null "$probe"; then
    fail "block direct public egress before running the proxy acceptance test"
  fi
  curl --noproxy '' --max-time 20 --fail --silent --show-error --output /dev/null "$probe"
  export BUN_INSTALL_CACHE_DIR="$WORK/bun"
fi

# From the working tree, never the published tag. This job exists to catch a release that moves while the template does not.
step "snapshotting the working tree"
SRC="$WORK/template"
mkdir -p "$SRC"
git ls-files -z | tar --null -T - -cf - | tar -x -C "$SRC"
git ls-files -z --others --exclude-standard | tar --null -T - -cf - | tar -x -C "$SRC" 2>/dev/null || true
git -C "$SRC" init -q .
git -C "$SRC" add -A
git -C "$SRC" -c user.email=acceptance@local -c user.name=acceptance commit -qm "template under acceptance"

step "generating a project"
PROJECT="$WORK/project"
mkdir -p "$PROJECT"
(cd "$SRC" && tar --exclude=./template --exclude=./.github/workflows/template.yml --exclude=./.git -cf - .) | tar -x -C "$PROJECT"
cd "$PROJECT"
git init -q --initial-branch=master .
bash scripts/project-init.sh --answers "$ROOT/$DATA_FILE"

if [ "${ACCEPTANCE_PROXY_ONLY:-0}" = 1 ]; then
  step "rebuilding the Go module and Helm chart downloads"
  for output in go-modules helm-charts; do
    installable="path:$PROJECT#$output"
    if nix path-info --offline "$installable" >/dev/null 2>&1; then
      nix build --rebuild --no-link "$installable"
    else
      nix build --option substitute false --no-link "$installable"
    fi
  done
fi

step "first run: bootstrap"
just bootstrap

# The rename changes names that generated files sort by. So the generators run before the gates, as the last line of the rename says.
step "regenerating after the rename"
just gen

step "the generated project's own gates"
just check

# The full tier's Argo CD syncs from the project's own forge, and a test run has no forge. A git daemon on this host
# stands in for it. Argo CD reaches it through the gateway of the kind network, the same route as the frontend's edge glue.
# The project's local bootstrap points there, and nothing else in the project changes.
step "serving the generated project to Argo CD"
git add -A
# No hooks: `check` above already ran every gate on this tree, and the messages follow the commit-msg rule anyway.
git -c core.hooksPath=/dev/null -c user.email=acceptance@local -c user.name=acceptance commit -qm "chore: generate the project"
# The network that kind creates and then reuses. It must exist before the cluster, so the gateway is known.
docker network inspect kind >/dev/null 2>&1 ||
  docker network create --ipv6 --subnet fc00:f853:ccd:e793::/64 kind >/dev/null
gateway="$(docker network inspect kind -f '{{range .IPAM.Config}}{{.Gateway}} {{end}}' |
  tr ' ' '\n' | grep -E '^[0-9]+(\.[0-9]+){3}$' | head -n1)"
[ -n "$gateway" ] || fail "the kind network has no IPv4 gateway"
SERVE="$WORK/serve"
mkdir -p "$SERVE"
forge_url="$(yq -r '.spec.source.repoURL' infra/gitops/local-bootstrap/root-application.yaml)"
grep -rlF "$forge_url" infra/gitops/local-bootstrap |
  xargs sed -i "s|${forge_url}|git://${gateway}:${GIT_PORT}/project.git|g"
git -c core.hooksPath=/dev/null -c user.email=acceptance@local -c user.name=acceptance commit -qam "chore: serve from the stand-in forge"
git clone -q --bare . "$SERVE/project.git"
git daemon --export-all --reuseaddr --base-path="$SERVE" --listen="$gateway" --port="$GIT_PORT" "$SERVE" &
git_pid=$!
detail "Argo CD reads git://${gateway}:${GIT_PORT}/project.git"

if [ "${ACCEPTANCE_PROXY_ONLY:-0}" = 1 ]; then
  just proxy-setup
  just proxy-setup --check
fi
step "bringing the full tier up"
just cluster-up full

step "verifying the tier serves"
just verify

step "the generated project's full e2e suite"
just e2e-install
just e2e

ok "a generated project reaches a serving cluster and passes its own gates"
