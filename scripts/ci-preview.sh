#!/usr/bin/env bash
# The pull-request preview environment (ADR-0205).
set -euo pipefail

verb="${1:-}"
case "$verb" in
up | down) ;;
*) echo "usage: ci-preview.sh up|down" >&2 && exit 1 ;;
esac

pr="${PREVIEW_PR:-}"
[[ "$pr" =~ ^[0-9]+$ ]] || {
  echo "✗ PREVIEW_PR is not a pull request number: '${pr}'" >&2
  exit 1
}

# Set BEFORE lib/cluster.sh is sourced: the cluster name, the kube-context and
# every path derived from them are computed at source time.
CLUSTER="pr-${pr}"
TIER=full
export CLUSTER TIER

# shellcheck source=lib/cluster.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/cluster.sh"
cd "$ROOT"

if [ "$verb" = down ]; then
  step "destroying preview pr-${pr}"
  bash scripts/cluster.sh down full
  ok "preview pr-${pr} destroyed"
  exit 0
fi

rev="${PREVIEW_REVISION:-}"
[[ -n "$rev" ]] ||
  fail "PREVIEW_REVISION is unset — a preview syncs the pull request's branch, and master is not it"

step "preview pr-${pr} on ${rev}"

# The tier itself, images built from this checkout (ADR-0600). Argo comes up
# pointed at master, because that is what the committed root Application says.
bash scripts/cluster.sh up full

# Then the pull request's manifests. Repointing after the bring-up rather than
# templating the root Application keeps one committed bootstrap file: a preview
# that rendered its own would be a second GitOps entrypoint to keep correct.
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
