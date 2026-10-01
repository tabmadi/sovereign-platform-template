#!/usr/bin/env bash
# Gate a release on prod converging on the release commit, per ADR-0201 and ADR-0103. Argo Healthy alone does not mean that prod runs that commit.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

sha="${SHA:-}"
[[ -n "$sha" ]] || fail "SHA is unset"

if [[ -z "${ARGOCD_SERVER:-}" || -z "${ARGOCD_AUTH_TOKEN:-}" ]]; then
  warn "ARGOCD_SERVER or ARGOCD_AUTH_TOKEN unset. Prod convergence is not verified"
  detail "argocd app wait -l env=prod --revision \"${sha}\" --sync --health --timeout 600"
  exit 0
fi

step "waiting for prod to converge on ${sha}"
argocd app wait -l env=prod --revision "$sha" --sync --health --timeout 600
ok "prod converged on ${sha}"
