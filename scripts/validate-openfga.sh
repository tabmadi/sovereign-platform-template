#!/usr/bin/env bash
# OpenFGA model and assertion validation (ADR-0304): runs the store tests against model.fga and asserts model.json is in step with it.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

DIR="infra/auth/openfga"

step "validating OpenFGA model + assertions with fga model test"
fga model test --tests "$DIR/fga.yaml"

step "checking $DIR/model.json is in sync with model.fga"
fresh="$(mktemp --suffix=.json)"
trap 'rm -f "$fresh"' EXIT
fga model transform --file "$DIR/model.fga" --output-format json | jq -S . >"$fresh"
if ! diff -u "$DIR/model.json" "$fresh"; then
  fail "model.json is stale — run 'mise run gen:authz-model' and commit the result"
fi
ok "OpenFGA model valid and model.json in sync"
