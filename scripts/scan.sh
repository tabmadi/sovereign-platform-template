#!/usr/bin/env bash
# The vulnerability and misconfiguration merge gate, per ADR-0104 and ADR-0106.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

# HIGH and CRITICAL only. MEDIUM on a transitive dependency is a weekly Renovate bump, not a merge blocker.
# A gate that blocks on everything soon gets an --exit-code 0.
SEVERITY="${TRIVY_SEVERITY:-HIGH,CRITICAL}"

# Directories with nothing of ours. node_modules is the npm tree of the e2e island, and its own lockfile is scanned.
# .next and dist are build output, and test-results holds Playwright traces.
SKIP=(
  # Vendored upstream Helm charts, unpacked from their .tgz. These are another project's manifests, and a finding here belongs to them.
  --skip-dirs "**/charts"
  --skip-dirs "**/node_modules"
  --skip-dirs "**/.next"
  --skip-dirs "**/dist"
  --skip-dirs "**/test-results"
  --skip-dirs "**/playwright-report"
)

# `report` is the triage view: everything, and it gates nothing. Run it to see what the repo carries, not to decide a merge.
if [ "${1:-gate}" = "report" ]; then
  step "every dependency finding, fixed or not, at every severity"
  trivy fs --scanners vuln --no-progress "${SKIP[@]}" .
  step "every misconfiguration, at every severity"
  trivy fs --scanners misconfig --no-progress "${SKIP[@]}" .
  exit 0
fi

step "scanning dependencies, severity ${SEVERITY}"
trivy fs \
  --scanners vuln \
  --severity "$SEVERITY" \
  --ignore-unfixed \
  --exit-code 1 \
  --no-progress \
  "${SKIP[@]}" \
  .

ok "no fixable ${SEVERITY} findings"

# A separate run: --ignore-unfixed has no meaning for a manifest, and a combined run accepts it and changes nothing.
step "scanning manifests and Dockerfiles, severity ${SEVERITY}"
trivy fs \
  --scanners misconfig \
  --severity "$SEVERITY" \
  --exit-code 1 \
  --no-progress \
  --ignorefile .trivyignore.yaml \
  "${SKIP[@]}" \
  .

ok "no ${SEVERITY} misconfigurations"
