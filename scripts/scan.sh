#!/usr/bin/env bash
# The vulnerability and misconfiguration merge gate (ADR-0104, ADR-0106).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

# HIGH and CRITICAL only. MEDIUM on a transitive dependency is a weekly Renovate
# bump, not a merge blocker, and a gate that blocks on everything is one that gets
# an --exit-code 0 within a month.
SEVERITY="${TRIVY_SEVERITY:-HIGH,CRITICAL}"

# Directories with nothing of ours in them. node_modules is the e2e island's npm
# tree (its own lockfile is scanned); .next and dist are build output; test-results
# holds Playwright traces.
SKIP=(
  # Vendored upstream Helm charts, unpacked from their .tgz. Someone else's
  # manifests; a finding here is a finding for them.
  --skip-dirs "**/charts"
  --skip-dirs "**/node_modules"
  --skip-dirs "**/.next"
  --skip-dirs "**/dist"
  --skip-dirs "**/test-results"
  --skip-dirs "**/playwright-report"
)

# `report` is the triage view: everything, gated on nothing. It is what you run
# when the question is "what do we carry", not "does this merge".
if [ "${1:-gate}" = "report" ]; then
  step "every dependency finding, fixed or not, at every severity"
  trivy fs --scanners vuln --no-progress "${SKIP[@]}" .
  step "every misconfiguration, at every severity"
  trivy fs --scanners misconfig --no-progress "${SKIP[@]}" .
  exit 0
fi

step "scanning dependencies (severity ${SEVERITY})"
trivy fs \
  --scanners vuln \
  --severity "$SEVERITY" \
  --ignore-unfixed \
  --exit-code 1 \
  --no-progress \
  "${SKIP[@]}" \
  .

ok "no fixable ${SEVERITY} findings"

# A separate invocation, because --ignore-unfixed is meaningless for a manifest and a combined run accepts it while changing nothing.
step "scanning manifests and Dockerfiles (severity ${SEVERITY})"
trivy fs \
  --scanners misconfig \
  --severity "$SEVERITY" \
  --exit-code 1 \
  --no-progress \
  --ignorefile .trivyignore.yaml \
  "${SKIP[@]}" \
  .

ok "no ${SEVERITY} misconfigurations"
