#!/usr/bin/env bash
# Generate a project from this working tree and prove it reaches a serving cluster
# (ADR-0106) — what "ready to use" means. Needs Docker, so it runs in CI, never in
# the template's own `check`.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

DATA_FILE="${ACCEPTANCE_DATA:-test/template/fixtures/valid/defaults.yml}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# From the working tree, never the published tag: a release that moves while the
# template does not is the failure this job exists to catch.
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

step "the generated project's own gates"
mise run check

step "bringing the full tier up"
mise run cluster:up -- full

step "verifying the tier serves"
mise run verify

step "the generated project's full e2e suite"
mise run e2e:install
mise run e2e

ok "a generated project reaches a serving cluster and passes its own gates"
