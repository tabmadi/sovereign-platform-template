#!/usr/bin/env bash
# The pull-request preview environment, per ADR-0205.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

verb="${1:-}"
case "$verb" in
up | down) ;;
*) echo "usage: ci-preview.sh up|down" >&2 && exit 1 ;;
esac

pr="${PREVIEW_PR:-}"
[[ "$pr" =~ ^[0-9]+$ ]] || fail "PREVIEW_PR is not a pull request number: '${pr}'"

# Set before lib/cluster.sh is sourced: the cluster name, the kube-context, and every path from them are computed at source time.
CLUSTER="pr-${pr}"
TIER=full
export CLUSTER TIER
# shellcheck source=lib/cluster.sh
source "$LIB/cluster.sh"

if [ "$verb" = down ]; then
  step "destroying preview pr-${pr}"
  bash scripts/cluster.sh down full
  ok "preview pr-${pr} destroyed"
  exit 0
fi

rev="${PREVIEW_REVISION:-}"
[[ -n "$rev" ]] ||
  fail "PREVIEW_REVISION is unset. A preview syncs the pull request's branch, not master"

step "preview pr-${pr} on ${rev}"

# The tier itself, with images built from this checkout, per ADR-0600. Argo starts pointed at master, as the committed root Application says.
bash scripts/cluster.sh up full

# Then the pull request's manifests. The root Application is repointed after the start and not templated.
# So there is one committed bootstrap file, and a preview does not add a second GitOps entrypoint.
step "repointing the root application at ${rev}"
k -n argocd patch application local-root --type merge \
  -p "{\"spec\":{\"source\":{\"targetRevision\":\"${rev}\"}}}" >/dev/null

kubeconfig="$(mktemp)"
# shellcheck disable=SC2064  # expand the path now, not at trap time
trap "rm -f '$kubeconfig'" EXIT
k config view --minify --flatten >"$kubeconfig"
kubectl --kubeconfig "$kubeconfig" config set-context --current --namespace argocd >/dev/null
KUBECONFIG="$kubeconfig" argocd --core app wait -l env=local --sync --health --timeout 900

ok "preview pr-${pr} is up at https://${DOMAIN}:8443/"
detail "it holds no real data and no real credential, and nothing is released from it"
