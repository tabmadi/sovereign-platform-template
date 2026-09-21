#!/usr/bin/env bash
# The live-patch window (ADR-0201, ADR-0600).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/cluster.sh"

STS=statefulset/argocd-application-controller

verb="${1:?usage: argo.sh <pause|resume>}"
case "$verb" in
pause | resume) ;;
*) fail "'${verb}' is not a verb — use \"pause\" or \"resume\"" ;;
esac
# The window is cluster-wide, so there is no second operand to accept. An ignored
# argument reads as an applied one.
[ "$#" -eq 1 ] || fail "argo.sh takes one verb — got: $*"

require_cluster
[ "$(cluster_tier)" = full ] ||
  fail "Argo CD runs on the full tier only, and the ${TIER} tier is what is up.
  Nothing reconciles the inner loop, so there is no window to open or close."

k -n argocd get "$STS" >/dev/null 2>&1 ||
  fail "no application-controller in $(cluster_ctx) — the full tier is up but its
  GitOps bootstrap is not. Re-run '$(up_hint)'."

if [ "$verb" = pause ]; then
  step "pausing Argo CD on $(cluster_ctx) — the cluster stops tracking master"
  k -n argocd scale "$STS" --replicas=0 >/dev/null
  ok "paused; resume with 'mise run argo:resume' when the patch is committed"
  exit 0
fi

step "resuming Argo CD on $(cluster_ctx)"
k -n argocd scale "$STS" --replicas=1 >/dev/null
# Rollout status, not the scale call's return: scale reports the intent was recorded,
# and "resumed" is a claim about a controller that is actually running.
k -n argocd rollout status "$STS" --timeout=180s >/dev/null ||
  fail "the application-controller did not come back — 'kubectl -n argocd describe ${STS}'"

# A pause set per app by service:deploy is narrower and survives the controller restarting.
# custom-columns and awk rather than jsonpath: kubectl's jsonpath has no negation, so the filter would match nothing and never fire.
mapfile -t manual < <(
  k -n argocd get application.argoproj.io --no-headers \
    -o custom-columns='NAME:.metadata.name,AUTO:.spec.syncPolicy.automated' 2>/dev/null |
    awk '$2 == "<none>" { print $1 }'
)
if [ "${#manual[@]}" -gt 0 ]; then
  warn "${#manual[@]} application(s) still have auto-sync off — service:deploy pauses the app it deploys:"
  printf '    · %s\n' "${manual[@]}" >&2
  detail "hand one back with: argocd app set <name> --sync-policy automated"
fi
ok "resumed — the cluster tracks master again"
