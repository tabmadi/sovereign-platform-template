#!/usr/bin/env bash
# The local cluster, with one entrypoint, per ADR-0600. The stages live in lib/cluster.sh.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

# This script owns the tier, and `up` with no argument creates base. Every other script takes the tier from the running cluster.
TIER_FROM_ARGV=1
# shellcheck source=lib/cluster.sh
source "$LIB/cluster.sh"

require_tools docker kind kubectl helm

# Every tier starts with this floor, and the tier adds to it.
PRELUDE=(registry warm cluster cni coredns namespaces edge glue)
STAGES_base=(postgres certs priority middlewares secrets ory identities)
STAGES_full=(sopskey images argocd rootapp populatezot identities)

run_stages() {
  local stage
  for stage in "$@"; do "stage_${stage}"; done
}

epilogue_base() {
  cat <<EOF

✓ cluster:up base: real edge, real identity, Postgres.

  Nothing else is running. Add what you need:
    cd services/<svc> && mise run server    native, pulls its own deps in
    mise run cluster:add -- <svc>           in-cluster, from the working tree
    mise run mock:start                     /api from the committed OpenAPI

  Open:       https://${DOMAIN}:8443/
  Log in:     $(login_hint)
  Teardown:   mise run cluster:stop to keep the cache, or cluster:down to delete

  Data does not persist here, and no workflow runs without dep:temporal. Check
  persistence, Temporal behaviour, and authorization decisions on the full tier.
EOF
}

epilogue_full() {
  cat <<EOF

✓ cluster:up full: ArgoCD deploys from master.
  Product:      https://${DOMAIN}:8443/api/<resource>/
  Log in:       https://${DOMAIN}:8443/auth/login as $(login_hint)
  Ops tier:     https://<name>.ops.${DOMAIN}:8443/ for argocd, grafana, hubble,
                temporal, seaweedfs, lowdefy, headlamp, and pgweb, per ADR-0306
  Frontend:     run it natively on :3000. The edge glue routes /auth and the
                landing page to the host.
  Diagnose:     mise run cluster:status
  Break-glass:  kubectl port-forward with your kubeconfig, see docs/guide/break-glass.md
  Teardown:     mise run cluster:stop to keep the cache, or cluster:down to delete
EOF
}

# The credentials are committed once, in the e2e fixtures. Read them from there.
login_hint() {
  bun --silent -e \
    "const {ADMIN} = await import('${ROOT}/test/e2e/fixtures/identities.ts'); console.log(ADMIN.email + ' with password ' + ADMIN.password)" \
    2>/dev/null || echo 'the admin in test/e2e/fixtures/identities.ts'
}

# `add` and `remove` resolve the same three namespaces, and they must agree.
# An `add` that succeeds with a `remove` that refuses to undo it is worse than neither.
classify() { # <name> → service | app | chart
  local name="$1" kinds=()
  [ -d "services/${name}" ] && [ "${name#_}" = "$name" ] && kinds+=(service)
  # An app is deployable only when it has a local values file. This separates apps/frontend, which the service chart deploys,
  # from apps/admin, which is baked into the lowdefy chart.
  [ -d "apps/${name}" ] && [ -f "infra/gitops/services/local/values/${name}.yaml" ] && kinds+=(app)
  [ -d "infra/helm/platform/${name}" ] && kinds+=(chart)

  case "${#kinds[@]}" in
  1) printf '%s' "${kinds[0]}" ;;
  0)
    detail "services:        $(find services -mindepth 1 -maxdepth 1 -type d -not -name '_*' -printf '%f ')"
    detail "platform charts: $(find infra/helm/platform -mindepth 1 -maxdepth 1 -type d -printf '%f ')"
    fail "'${name}' is not a service, an app, or a platform chart"
    ;;
  # A name in two namespaces is a repo bug, not a user error. Disjoint namespaces keep this dispatch clear.
  *) fail "'${name}' is a ${kinds[*]} at the same time. Rename one, because the namespaces must stay disjoint" ;;
  esac
}

VERB="${1:-up}"
shift || true

# The tier names the cluster, so every verb that acts on one takes it the same way.
# `add`, `remove`, and `glue` are excluded: their first argument is a name, and a service called `full` would be read as a tier.
# TIER stays the fallback.
case "$VERB" in
up | stop | down | heal | status)
  case "${1:-}" in
  base | full)
    TIER="$1"
    shift
    ;;
  "") ;;
  *) fail "'$1' is not a tier. Use \"base\" or \"full\"" ;;
  esac
  ;;
esac

case "$VERB" in
up)
  step "bringing up the ${TIER} tier as cluster '$(cluster_name)'"
  run_stages "${PRELUDE[@]}"
  case "$TIER" in
  base) run_stages "${STAGES_base[@]}" && epilogue_base ;;
  full) run_stages "${STAGES_full[@]}" && epilogue_full ;;
  esac
  ;;

stop)
  # `docker stop` keeps the containers, so each node's containerd cache stays. kind has no stop of its own.
  # Stop every node, or the rest hold memory for a cluster that nobody uses.
  name="$(cluster_name)"
  if ! cluster_exists "$name"; then
    ok "cluster '${name}' does not exist. Nothing to stop"
    other_tier_hint stop
    exit 0
  fi
  mapfile -t nodes < <(kind get nodes --name "$name")
  step "stopping '${name}': ${#nodes[@]} node(s), image cache kept"
  printf '%s\n' "${nodes[@]}" | xargs -r docker stop >/dev/null
  ok "stopped. Resume with '$(up_hint)'"
  ;;

down)
  name="$(cluster_name)"
  # Released first: a job that failed before its cluster existed still holds the runner through its registry.
  if [ -n "${CI:-}" ] && [ "$(registry_job)" = "$(ci_job)" ]; then
    docker rm -f "$REGISTRY" >/dev/null
  fi
  # kind exits 0 when it deletes a cluster that does not exist. So the check is here, or the verb reports a deletion it never did.
  if ! cluster_exists "$name"; then
    ok "cluster '${name}' does not exist. Nothing to delete"
    other_tier_hint down
    exit 0
  fi
  if ! ci_owned "$name"; then
    ok "cluster '${name}' belongs to another job on this runner. Left alone"
    exit 0
  fi
  step "deleting kind cluster '${name}'"
  kind delete cluster --name "$name"
  ok "deleted '${name}'. The registry container stays, because it is host-level"
  ;;

heal)
  # A host reboot restarts the node container raw. Cilium's datapath is then half-restored, and the docker-bridge gateway has moved.
  # A restart runs the entrypoint again cleanly.
  name="$(cluster_name)"
  if ! docker inspect "${name}-control-plane" >/dev/null 2>&1; then
    other_tier_hint heal
    fail "cluster '${name}' does not exist. Nothing to heal"
  fi
  step "restarting the nodes of '${name}'"
  kind get nodes --name "$name" | xargs -r docker restart >/dev/null
  # Poll before any call that RBAC gates. During a cold start the API server can answer Forbidden for list and watch, which is fatal under set -e.
  wait_for "the API server" 180 kubectl --context "$(cluster_ctx)" get --raw /healthz
  k wait --for=condition=Ready node --all --timeout=300s
  k -n kube-system rollout restart ds/cilium >/dev/null
  k -n kube-system rollout status ds/cilium --timeout=180s
  # CoreDNS is Ready only when a pod can reach the API, so it is the real datapath probe.
  k -n kube-system rollout restart deploy/coredns >/dev/null
  k -n kube-system rollout status deploy/coredns --timeout=180s ||
    fail "CoreDNS is still not Ready. The Cilium datapath has a fault that a
  restart does not clear. Recreate the cluster: mise run cluster:down -- ${TIER} && $(up_hint)"
  run_stages glue
  ok "heal complete. Pods can reach the API again"
  ;;

status)
  name="$(cluster_name)"
  step "tier ${TIER}, cluster '${name}', context $(cluster_ctx)"
  if ! cluster_exists "$name"; then
    warn "not created. Run '$(up_hint)'"
    other_tier_hint status
    exit 0
  fi
  detail "registry ${REGISTRY}:5000: $(docker inspect -f '{{.State.Status}}' "$REGISTRY" 2>/dev/null || echo absent)"
  k get nodes
  if k get ns argocd >/dev/null 2>&1; then
    k -n argocd get applications.argoproj.io \
      -o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
  else
    h -n "$NS" list --short
  fi
  k get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | grep . ||
    ok "every pod is Running or Succeeded"
  ;;

add)
  NAME="${1:?usage: mise run cluster:add -- <service|app|chart>}"
  # The two paths share only the start. A service resolves to a values file and builds an image.
  # A chart resolves to a directory and needs the auth overlays.
  case "$(classify "$NAME")" in
  service | app) exec bash scripts/service-deploy.sh "$NAME" ;;
  chart) exec bash scripts/platform-deploy.sh "$NAME" ;;
  esac
  ;;

remove)
  NAME="${1:?usage: mise run cluster:remove -- <service|app|chart>}"
  require_cluster
  KIND="$(classify "$NAME")"

  if [ "$KIND" = service ]; then
    # The native edge glue has a label, so a selector removes it, even when the service was never deployed.
    if k -n "$NS" get service,ingressroute,middleware,endpointslice \
      -l "local.platform/glue=${NAME}" -o name 2>/dev/null | grep -q .; then
      step "removing the native edge glue for ${NAME}"
      k -n "$NS" delete service,ingressroute,middleware,endpointslice \
        -l "local.platform/glue=${NAME}" --ignore-not-found >/dev/null
    fi
    # A svc:* port-forward lives longer than the mise task that started it, so removal stops it too.
    # Otherwise a later svc:* guard probes an open port with nothing behind it.
    PIDFILE="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/platform-local/portforward-${NAME}.pid"
    if [ -f "$PIDFILE" ]; then
      step "stopping the ${NAME} port-forward"
      kill "$(cat "$PIDFILE")" 2>/dev/null || true
      rm -f "$PIDFILE"
    fi
  fi

  if h -n "$NS" status "$NAME" >/dev/null 2>&1; then
    step "uninstalling ${NAME}"
    h -n "$NS" uninstall "$NAME"
  else
    detail "no helm release '${NAME}' in ${NS}. Nothing to uninstall"
  fi

  # Give it back to GitOps, the reverse of the pause in the deploy scripts. Removal must match add.
  # Otherwise Argo loses control of the cluster one service at a time, with no message.
  case "$KIND" in
  chart) APP="local-platform-${NAME}" ;;
  *) APP="$(argo_service_app "$NAME")" ;;
  esac
  if [ -n "$APP" ] && k -n argocd get application.argoproj.io "$APP" >/dev/null 2>&1; then
    step "restoring ArgoCD auto-sync on ${APP}"
    k -n argocd patch application.argoproj.io "$APP" --type merge \
      -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' >/dev/null
    detail "Argo syncs ${NAME} again from committed master"
  fi
  ok "${NAME} removed"
  ;;

glue)
  require_cluster
  stage_glue "$@"
  ;;

*)
  fail "unknown verb '${VERB}'. Use up, stop, down, heal, status, add, remove, or glue"
  ;;
esac
