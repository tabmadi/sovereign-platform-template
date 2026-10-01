#!/usr/bin/env bash
# Lay the bootstrap floor of the environment in the current kubectl context and give it to Argo CD, per ADR-0200 steps 2 and 3.
# The floor is Argo CD, Traefik, the cluster's age key, and the forge credential that Argo clones with.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

ENV="${1:?usage: argocd-bootstrap.sh <env>}"
ROOT_APP="infra/gitops/${ENV}-bootstrap/root-application.yaml"
REPO_SECRET="infra/gitops/platform/${ENV}/secrets/argocd-repo.enc.yaml"
[ -f "$ROOT_APP" ] || fail "no ${ROOT_APP}: '${ENV}' is not an environment"

step "bootstrapping ${ENV} in $(kubectl config current-context)"

install_chart() { # <release> <chart> <namespace>
  [ -d "$2/charts" ] || helm dependency build "$2" >/dev/null 2>&1 || helm dependency update "$2" >/dev/null
  helm upgrade --install "$1" "$2" -n "$3" --create-namespace --timeout 10m
}

step "installing Argo CD"
install_chart argocd infra/helm/platform/argocd argocd
for d in argocd-server argocd-repo-server argocd-applicationset-controller; do
  kubectl -n argocd rollout status "deploy/${d}" --timeout=300s
done

step "installing Traefik, whose CRDs the gateway's Middlewares resolve against"
install_chart traefik infra/helm/platform/traefik kube-system
kubectl -n kube-system rollout status deploy/traefik --timeout=300s

step "the cluster's age key"
kubectl create namespace platform --dry-run=client -o yaml | kubectl apply -f - >/dev/null
if [ -n "${CLUSTER_AGE_KEY:-}" ]; then
  kubectl -n platform create secret generic sops-age-key --from-file=keys.txt="$CLUSTER_AGE_KEY" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  detail "planted from ${CLUSTER_AGE_KEY}"
else
  # On Talos the machine config carries it as an inline manifest.
  kubectl -n platform get secret sops-age-key >/dev/null 2>&1 ||
    fail "no sops-age-key in the cluster. Set CLUSTER_AGE_KEY to the ${ENV} cluster's age private key"
  detail "present"
fi

# A plain Secret, not a SopsSecret: Argo deploys the sops-operator that renders SopsSecrets, and this Secret lets Argo run.
# Its url is the forge's origin, so it survives a move of the repository to a new owner. See docs/guide/gitops-runbook.md.
if [ -f "$REPO_SECRET" ]; then
  step "the forge credential"
  field() { sops --decrypt --extract "[\"stringData\"][\"$1\"]" "$REPO_SECRET"; }
  origin="$(field FORGE_REPO_URL | sed -E 's|^(https://[^/]+/).*|\1|')"
  kubectl -n argocd create secret generic forge-creds --from-literal=type=git --from-literal=url="$origin" \
    --from-literal=username="$(field FORGE_REPO_USERNAME)" --from-literal=password="$(field FORGE_REPO_PASSWORD)" \
    --dry-run=client -o yaml |
    kubectl label --local -f - argocd.argoproj.io/secret-type=repo-creds -o yaml |
    kubectl apply -f - >/dev/null
  detail "$origin"
fi

step "applying the root application"
kubectl apply -f "$ROOT_APP" >/dev/null
ok "Argo CD reconciles ${ENV}. Watch it with 'kubectl -n argocd get applications'"
