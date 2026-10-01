#!/usr/bin/env bash
# The live-patch window, per ADR-0201 and ADR-0600.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=lib/cluster.sh
source "$LIB/cluster.sh"

STS=statefulset/argocd-application-controller

verb="${1:?usage: argo.sh <pause|resume>}"
case "$verb" in
pause | resume) ;;
*) fail "'${verb}' is not a verb. Use \"pause\" or \"resume\"" ;;
esac
# The window is cluster-wide, so there is no second operand. An ignored argument looks like an applied one.
[ "$#" -eq 1 ] || fail "argo.sh takes one verb, got: $*"

require_cluster
[ "$(cluster_tier)" = full ] ||
  fail "Argo CD runs on the full tier only, and the ${TIER} tier is what is up.
  Nothing reconciles the inner loop, so there is no window to open or close."

k -n argocd get "$STS" >/dev/null 2>&1 ||
  fail "no application-controller in $(cluster_ctx). The full tier is up but its
  GitOps bootstrap is not. Run '$(up_hint)' again."

if [ "$verb" = pause ]; then
  step "pausing Argo CD on $(cluster_ctx). The cluster stops tracking master"
  k -n argocd scale "$STS" --replicas=0 >/dev/null
  ok "paused. Resume with 'mise run argo:resume' when the patch is committed"
  exit 0
fi

step "resuming Argo CD on $(cluster_ctx)"
k -n argocd scale "$STS" --replicas=1 >/dev/null
# Rollout status, not the return value of scale: scale only records the intent. `resumed` means a controller that runs.
k -n argocd rollout status "$STS" --timeout=180s >/dev/null ||
  fail "the application-controller did not come back. Run 'kubectl -n argocd describe ${STS}'"

# A pause that cluster:add sets on one app is narrower, and it survives a controller restart.
# custom-columns and awk, not jsonpath: kubectl's jsonpath has no negation, so the filter would match nothing.
mapfile -t manual < <(
  k -n argocd get application.argoproj.io --no-headers \
    -o custom-columns='NAME:.metadata.name,AUTO:.spec.syncPolicy.automated' 2>/dev/null |
    awk '$2 == "<none>" { print $1 }'
)
if [ "${#manual[@]}" -gt 0 ]; then
  warn "${#manual[@]} application(s) still have auto-sync off. cluster:add pauses the app it deploys:"
  printf '    · %s\n' "${manual[@]}" >&2
  detail "turn auto-sync on again with: argocd app set <name> --sync-policy automated"
fi
ok "resumed. The cluster tracks master again"
