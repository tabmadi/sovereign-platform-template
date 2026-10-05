#!/usr/bin/env bash
# Generate a project from this working tree and prove that it reaches a serving cluster, per ADR-0106. This defines `ready to use`.
# It needs Docker, so it runs in CI and never in the template's own `check`.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

DATA_FILE="${ACCEPTANCE_DATA:-test/template/fixtures/valid/defaults.yml}"
WORK="$(mktemp -d)"
# The stand-in forge below: a git daemon on this host, on the port that git:// uses.
GIT_PORT=9418
git_pid=""
# Its own lint cache. Every run has the same module path in a new directory, and a shared cache then reports stale paths.
export GOLANGCI_LINT_CACHE="$WORK/golangci-lint"
trap '[ -z "$git_pid" ] || kill "$git_pid" 2>/dev/null; rm -rf "$WORK"' EXIT

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
mise x -- copier copy --trust --defaults --data-file "$DATA_FILE" "$SRC" "$PROJECT" >/dev/null
cd "$PROJECT"
git init -q .
mise trust -q

step "first run: bootstrap"
mise run bootstrap

# The rename changes names that generated files sort by. So the generators run before the gates, as the last line of the rename says.
step "regenerating after the rename"
mise run gen

step "the generated project's own gates"
mise run check

# The full tier's Argo CD syncs from the project's own forge, and a test run has no forge. A git daemon on this host
# stands in for it. Argo CD reaches it through the gateway of the kind network, the same route as the frontend's edge glue.
# The project's local bootstrap points there, and nothing else in the project changes.
step "serving the generated project to Argo CD"
git add -A
# No hooks: `check` above already ran every gate on this tree, and the messages follow the commit-msg rule anyway.
LEFTHOOK=0 git -c user.email=acceptance@local -c user.name=acceptance commit -qm "chore: generate the project"
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
LEFTHOOK=0 git -c user.email=acceptance@local -c user.name=acceptance commit -qam "chore: serve from the stand-in forge"
git clone -q --bare . "$SERVE/project.git"
git daemon --export-all --reuseaddr --base-path="$SERVE" --listen="$gateway" --port="$GIT_PORT" "$SERVE" &
git_pid=$!
detail "Argo CD reads git://${gateway}:${GIT_PORT}/project.git"

step "bringing the full tier up"
mise run cluster:up -- full

step "verifying the tier serves"
mise run verify

step "the generated project's full e2e suite"
mise run e2e:install
mise run e2e

ok "a generated project reaches a serving cluster and passes its own gates"
