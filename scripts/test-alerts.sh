#!/usr/bin/env bash
# Test every alert with simulated time, per ADR-0500. The tests prove the condition, the wait, and the labels.
# promtool compares annotations too, so the test copy drops them, and `check rules` still validates their templates.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

DIR="infra/observability/alerts"
TESTS="$DIR/tests/alerts.test.yaml"
mapfile -t rules < <(find "$DIR" -maxdepth 1 -name '*.yaml' ! -name Chart.yaml | sort)
[ "${#rules[@]}" -gt 0 ] || fail "no rule files in ${DIR}"

step "checking the syntax of ${#rules[@]} rule files"
promtool check rules "${rules[@]}" >/dev/null

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/rules"
for file in "${rules[@]}"; do
  yq 'del(.groups[].rules[].annotations)' "$file" >"$work/rules/$(basename "$file")"
done
cp "$TESTS" "$work/alerts.test.yaml"

step "checking that each alert has a test that fires it"
missing="$(LC_ALL=C comm -23 \
  <(yq -N -r '.groups[].rules[] | select(has("alert")) | .alert' "${rules[@]}" | LC_ALL=C sort -u) \
  <(yq -r '.tests[].alert_rule_test[] | select((.exp_alerts | length) > 0) | .alertname' "$TESTS" | LC_ALL=C sort -u))"
[ -z "$missing" ] || fail "no firing test in ${TESTS} for: ${missing//$'\n'/ }"

step "running the alert tests"
(cd "$work" && promtool test rules alerts.test.yaml)
ok "every alert fires after its wait and stays quiet on healthy input"
