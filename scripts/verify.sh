#!/usr/bin/env bash
# Assert the active tier is up and serving (ADR-0600): nodes, pods, ArgoCD, the edge,
# and the parity mechanism the local overlay turns on. Every failure is reported, not
# just the first, so one run is one fix list.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=lib/cluster.sh
source "$LIB/cluster.sh"

require_cluster

failures=()
step "checking nodes"
not_ready="$(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' |
  awk '$2 != "True"' || true)"
[ -z "$not_ready" ] || {
  failures+=("nodes not Ready")
  printf '%s\n' "$not_ready" | sed 's/^/    /' >&2
}

step "checking pods"
bad_pods="$(k get pods -A --no-headers 2>/dev/null | awk '$4 != "Running" && $4 != "Completed"' || true)"
[ -z "$bad_pods" ] || {
  failures+=("pods not Running")
  printf '%s\n' "$bad_pods" | sed 's/^/    /' >&2
}

if k get ns argocd >/dev/null 2>&1; then
  step "checking ArgoCD applications"
  bad_apps="$(k -n argocd get applications.argoproj.io --no-headers 2>/dev/null |
    awk '$2 != "Synced" || $3 != "Healthy"' || true)"
  [ -z "$bad_apps" ] || {
    failures+=("ArgoCD applications not Synced + Healthy")
    printf '%s\n' "$bad_apps" | sed 's/^/    /' >&2
  }
fi

step "checking the edge"
# 2xx or 3xx: a 502 or 503 is the edge answering for a storefront that is down.
code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "https://${DOMAIN}:8443/" || true)"
case "$code" in
2?? | 3??) ;;
*) failures+=("the storefront at https://${DOMAIN}:8443/ answered ${code:-nothing}") ;;
esac

# The assertion is the point: a backup setting that is enabled but never exercised is
# configuration, not coverage. Shared with lint:parity's allowlist entry, which the
# setting retires once it lands.
if [ "$(cluster_tier)" = full ] &&
  [ "$(yq -r '.cluster.backup.enabled // false' infra/gitops/platform/local/values.yaml)" = true ]; then
  step "triggering a base backup (cluster.backup's parity assertion)"
  backup_name="verify-$(date +%s)"
  k -n "$NS" apply -f - >/dev/null <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: ${backup_name}
  namespace: ${NS}
spec:
  cluster:
    name: postgres
EOF
  # shellcheck disable=SC2329  # invoked by name in the loop below.
  backup_completed() {
    [ "$(k -n "$NS" get backup "$backup_name" -o jsonpath='{.status.phase}' 2>/dev/null)" = completed ]
  }
  waited=0
  until backup_completed; do
    if [ "$waited" -ge 300 ]; then
      failures+=("the base backup did not complete")
      break
    fi
    sleep 2
    waited=$((waited + 2))
  done
  backup_completed && k -n "$NS" delete backup "$backup_name" >/dev/null || true
fi

if [ "${#failures[@]}" -gt 0 ]; then
  warn "verify found ${#failures[@]} problem(s):"
  printf '  · %s\n' "${failures[@]}" >&2
  fail "the active tier is not ready"
fi
ok "the active tier is up and serving"
