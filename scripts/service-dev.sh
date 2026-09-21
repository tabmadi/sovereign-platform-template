#!/usr/bin/env bash
# Run a service natively behind the real edge (ADR-0205, ADR-0600) — the other half of `cluster:add`.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=lib/ports.sh
source "$LIB/ports.sh"

CLUSTER="${CLUSTER:-platform}"
# shellcheck source=lib/cluster.sh
source "$LIB/cluster.sh"
NS="platform"
DOMAIN="${DOMAIN:-dev.localtest.me}"

SVC="${1:?usage: mise run service:dev -- <svc>}"
# The registry, not a flag: the glue must point at the same port the service's own
# .mise.toml makes it bind, or Traefik forwards to nothing. One source of truth.
PORT="$(service_port "$SVC")"
SVC_DIR="services/${SVC}"
VALUES="infra/gitops/services/local/values/${SVC}.yaml"

[ -d "$SVC_DIR" ] || fail "no such service: ${SVC_DIR}"
[ -f "$VALUES" ] || fail "missing local values: ${VALUES}"

k() { kubectl --context "$(cluster_ctx)" "$@"; }

# The deployed service and the native one would both answer for the same routes.
# Rather than racing them on route priority, refuse — one of them is what you meant.
if k -n "$NS" get "deploy/${SVC}-server" >/dev/null 2>&1; then
  fail "${SVC} is deployed in-cluster; run 'mise run cluster:remove -- ${SVC}' first"
fi

step "stamping the edge glue for a native ${SVC}"

# Selector-less Service; the EndpointSlice below supplies the address.
k apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${SVC}-dev
  namespace: ${NS}
  labels: { local.platform/glue: "${SVC}" }
spec:
  ports:
    - name: http
      port: ${PORT}
      targetPort: ${PORT}
EOF

# The same resources and middleware chain the service chart routes when deployed,
# read from the committed local values so the two paths cannot drift.
resources="$(yq -r '.ingress.resources // [] | join(" ")' "$VALUES")"
[ -n "$resources" ] || fail "${SVC} declares no ingress.resources in ${VALUES} (nothing to route)"

match=""
for r in $resources; do
  [ -n "$match" ] && match="${match} || "
  match="${match}PathPrefix(\`/api/${r}\`)"
done

# Mirrors infra/helm/service/templates/ingressroute.yaml: same match, same middleware chain, same order. Flat-API routing strips /api (ADR-0306).
k apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: ${SVC}-dev-stripprefix
  namespace: ${NS}
  labels: { local.platform/glue: "${SVC}" }
spec:
  stripPrefix:
    prefixes:
      - /api
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: ${SVC}-dev
  namespace: ${NS}
  labels: { local.platform/glue: "${SVC}" }
spec:
  entryPoints: [websecure]
  routes:
    - kind: Rule
      match: Host(\`${DOMAIN}\`) && (${match})
      middlewares:
        # Anti-spoofing (ADR-0305): strip client-supplied identity headers BEFORE
        # forwardAuth, so nothing can inject X-User-* on an anonymous /api route.
        - name: strip-identity-headers
        - name: oathkeeper-forward-auth
        - name: security-headers
        - name: ${SVC}-dev-stripprefix
      services:
        - name: ${SVC}-dev
          port: ${PORT}
  tls:
    secretName: wildcard-tls
EOF

bash scripts/cluster.sh glue "$SVC" "$PORT"

cat <<EOF

✓ ${SVC} glued to the host on :${PORT}.

  Now run it (its own tasks pull the dependency components in):
    cd services/${SVC} && mise run server

  Reached at:  https://${DOMAIN}:8443/api/$(echo "$resources" | cut -d' ' -f1)
  Through:     the real Oathkeeper chain — identity headers are genuine here
  Remove:      mise run cluster:remove -- ${SVC}
EOF
