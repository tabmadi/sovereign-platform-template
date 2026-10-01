#!/usr/bin/env bash
# The API mock for the UI development loop, per ADR-0600.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

CLUSTER="${CLUSTER:-platform}"
# shellcheck source=lib/cluster.sh
source "$LIB/cluster.sh"
NS="platform"

SPEC="apps/frontend/public/devportal/openapi/internal.json"
MANIFEST="infra/local/mock.yaml"

k() { kubectl --context "$(cluster_ctx)" -n "$NS" "$@"; }

case "${1:-}" in
start)
  [ -f "$SPEC" ] || fail "missing ${SPEC}. Run \`mise run gen\` first"

  step "stamping the committed projection into the mock's spec ConfigMap"
  # The dry-run output piped to apply updates the existing object. The hash below makes the pod notice.
  k create configmap mock-spec --from-file="internal.json=${SPEC}" \
    --dry-run=client -o yaml | k apply -f - >/dev/null
  detail "$(wc -c <"$SPEC" | tr -d ' ') bytes from ${SPEC}"

  step "applying the mock"
  k apply -f "$MANIFEST" >/dev/null

  # Prism reads the document once at startup, so a changed spec needs a new pod.
  # The content-hash annotation makes that automatic and idempotent: an unchanged spec leaves the pod alone, so `mock:start` is safe to run again.
  hash="$(sha256sum "$SPEC" | cut -c1-16)"
  k patch deployment mock --type merge \
    -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"local.platform/spec-hash\":\"${hash}\"}}}}}" >/dev/null

  k rollout status deployment/mock --timeout=120s
  ok "mock serving /api at https://dev.localtest.me:8443/api/products"
  detail "it answers from the spec's examples. It has no session, no 401, and no state"
  ;;

stop)
  step "removing the mock"
  # The IngressRoute goes first: /api goes back to the real services, or to nothing, before the pod disappears.
  k delete -f "$MANIFEST" --ignore-not-found >/dev/null
  k delete configmap mock-spec --ignore-not-found >/dev/null
  ok "mock removed. /api goes to whatever is deployed"
  ;;

logs)
  k logs -f deployment/mock
  ;;

*)
  fail "usage: mise run mock:start, mock:stop, or mock:logs"
  ;;
esac
