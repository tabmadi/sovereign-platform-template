# shellcheck shell=bash

# shellcheck disable=SC2317  # the guard's `return` is reached when re-sourced.
if [[ -n "${__CLUSTER_SH_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
__CLUSTER_SH_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"

# Loaded, not computed. kind reads the proxy variables from its own environment, and only kind can add the node's name to NO_PROXY.
# Without that, `kind create` stops on an EOF.
if [ -f "$ROOT/infra/local/proxy.local.env" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$ROOT/infra/local/proxy.local.env"
  set +a
fi
CLUSTER="${CLUSTER:-platform}"
NS="${NS:-platform}"
DOMAIN="${DOMAIN:-dev.localtest.me}"
KIND_CONFIG="infra/local/kind.yaml"
REGISTRY="registry.localhost"
# A path, never a named volume: a forge cache can restore a directory. A warm from nothing is most of the cost of `cluster:up`, per ADR-0205.
ZOT_DATA="${ZOT_DATA:-${XDG_CACHE_HOME:-$HOME/.cache}/zot/${REGISTRY}}"
ZOT_IMAGE="ghcr.io/project-zot/zot-linux-amd64:v2.1.20"
FORCE="${FORCE:-}"

# Checked when the file is sourced. The functions run as `$(cluster_ctx)`, where an exit ends only the subshell.
case "${TIER:-}" in
"" | base | full) ;;
*) fail "'${TIER}' is not a tier. Use \"base\" or \"full\"" ;;
esac

cluster_tier() { printf '%s' "$TIER"; }
# The tier is an argument, so a message naming a command names its tier too.
up_hint() {
  if [ "$TIER" = full ]; then printf 'mise run cluster:up -- full'; else printf 'mise run cluster:up'; fi
}
# The full tier's name includes the tier, so `docker ps` and `kubectl config get-contexts` both show which cluster is which.
cluster_name_of() {
  if [ "$1" = full ]; then printf '%s-full' "$CLUSTER"; else printf '%s' "$CLUSTER"; fi
}
cluster_name() { cluster_name_of "$TIER"; }
# A CI runner can run two jobs at once and lives longer than both. There, the registry and the cluster belong to the job that created them.
# The registry is the first host-level stage. It carries the job's name and acts as the lock.
ci_job() { printf '%s-%s-%s' "${GITHUB_RUN_ID:-}" "${GITHUB_JOB:-}" "${GITHUB_RUN_ATTEMPT:-}"; }
ci_owned() { [ -z "${CI:-}" ] || grep -qx "$1" "${RUNNER_TEMP:?}/kind-cluster" 2>/dev/null; }
registry_job() { docker inspect -f '{{index .Config.Labels "platform.ci-job"}}' "$REGISTRY" 2>/dev/null || true; }
# This job never replaces, resumes, or moves another job's registry and cluster. It waits for that job to finish.
ci_wait_for_runner() {
  local waited=0 held
  while :; do
    held="$(registry_job)"
    { [ -n "$held" ] && [ "$held" != "$(ci_job)" ]; } ||
      cluster_exists "$(cluster_name_of base)" || cluster_exists "$(cluster_name_of full)" || return 0
    [ "$waited" -lt 3600 ] || fail "another job has held this runner's registry and edge for an hour"
    [ "$waited" -gt 0 ] || step "waiting for another job to release this runner's registry and edge"
    sleep 30
    waited=$((waited + 30))
  done
}
other_tier() { if [ "$TIER" = full ]; then printf 'base'; else printf 'full'; fi; }
cluster_exists() { kind get clusters 2>/dev/null | grep -qx "$1"; }
# A tier-scoped verb that finds nothing reports it and names the tier that is up.
# The tiers are alternatives, so `no such cluster` usually means the wrong tier was named.
other_tier_hint() {
  local other
  other="$(other_tier)"
  cluster_exists "$(cluster_name_of "$other")" &&
    detail "the ${other} tier is up. To use it, run 'mise run cluster:${1} -- ${other}'"
  return 0
}
cluster_ctx() { printf 'kind-%s' "$(cluster_name)"; }

# True when this cluster's node runs, not only exists. Both tiers can exist at once.
# Only one can hold the edge ports, so only one serves.
cluster_running() {
  docker inspect -f '{{.State.Running}}' "${1}-control-plane" 2>/dev/null | grep -qx true
}

# The tier that is up, or nothing. A running tier wins over a created one.
# When the answer is not clear, it returns nothing, so the caller must name the cluster it wants.
detect_tier() {
  # One listing for both tiers: this runs on every source, and `kind get clusters` is a docker round-trip.
  # `if`, not `&&`, so a stopped cluster is an answer and not a non-zero status that ends the caller under `set -e`.
  local tier name clusters running=() present=()
  clusters="$(kind get clusters 2>/dev/null || true)"
  for tier in base full; do
    name="$(cluster_name_of "$tier")"
    printf '%s\n' "$clusters" | grep -qx "$name" || continue
    present+=("$tier")
    if cluster_running "$name"; then running+=("$tier"); fi
  done
  if [ "${#running[@]}" -eq 1 ]; then
    printf '%s' "${running[0]}"
  elif [ "${#running[@]}" -eq 0 ] && [ "${#present[@]}" -eq 1 ]; then
    printf '%s' "${present[0]}"
  else
    return 1
  fi
}

# The tier a script acts on. The order: TIER in the environment, then TIER_FROM_ARGV=1 for cluster.sh, then the tier that is up, then base.
# A hardcoded default fails with no clear error: every kubectl fails against a context that does not exist, and it looks like the platform is down.
if [ -z "${TIER:-}" ] && [ -z "${TIER_FROM_ARGV:-}" ]; then
  TIER="$(detect_tier || true)"
fi
TIER="${TIER:-base}"
# Exported, because stages call scripts that resolve the context from it.
# Without the export, `identity-seed.sh` seeds the inner loop while the full tier waits.
export TIER

k() { kubectl --context "$(cluster_ctx)" "$@"; }
h() { helm --kube-context "$(cluster_ctx)" "$@"; }

forced() { [[ ",${FORCE}," == *",$1,"* ]]; }

# Poll until a command succeeds. Custom readiness loops made the two tiers drift apart.
wait_for() { # <what> <seconds> <cmd> [args]
  local what="$1" budget="$2"
  shift 2
  local waited=0
  until "$@" >/dev/null 2>&1; do
    [ "$waited" -ge "$budget" ] && fail "timed out after ${budget}s waiting for ${what}"
    sleep 2
    waited=$((waited + 2))
  done
}

# `build` is the offline path and needs the dependency's repo registered in the caller's helm config.
# `update` resolves it from Chart.yaml. Developer machines pass on the first, and clean runners only on the second.
chart_deps() { helm dependency build "$1" >/dev/null 2>&1 || helm dependency update "$1" >/dev/null; }

# An absent tool looks like an answer: a failed `kind get clusters` looks like a cluster that was never created.
# Every probe below has the same problem. So check the tools first, and `not found` cannot mean `not created`.
require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 ||
      fail "${tool} not found on PATH. Run this through mise, as \`mise run <task>\`, which puts the pinned toolchain there"
  done
}

# Fail unless the probe can run. Otherwise an unreachable cluster looks like `not deployed` to every idempotence guard.
require_cluster() {
  require_tools kubectl
  k cluster-info >/dev/null 2>&1 ||
    fail "cluster $(cluster_ctx) is not reachable. Run '$(up_hint)' first"
}

# The committed ApplicationSet named apps after the values file, and now it removes the extension. So both names exist.
# A wrong guess leaves auto-sync on, and Argo reverts the deploy.
argo_service_app() {
  local name
  for name in "local-service-${1}" "local-service-${1}.yaml"; do
    if k -n argocd get application.argoproj.io "$name" >/dev/null 2>&1; then
      echo "$name"
      return 0
    fi
  done
}

# zot, the registry every environment runs, per ADR-0105, as a host container next to both clusters.
# It mirrors the upstreams on demand, so nothing is preloaded and no image list needs upkeep. It survives a cluster delete and recreate.
stage_registry() {
  [ -z "${CI:-}" ] || ci_wait_for_runner
  # Outside the repository, because it holds a token, per ADR-0202. Written on every run, as `{}` when the environment has no token, so the mount always resolves.
  local creds="${XDG_RUNTIME_DIR:-/tmp}/zot-sync-creds-${REGISTRY}.json"
  # Docker creates a missing bind-mount source as a root-owned directory, and every later run then fails on it.
  [ ! -e "$creds" ] || [ -f "$creds" ] || rm -rf "$creds"
  if [ -n "${DOCKERHUB_USERNAME:-}" ] && [ -n "${DOCKERHUB_TOKEN:-}" ]; then
    printf '{"registry-1.docker.io":{"username":"%s","password":"%s"}}\n' \
      "$DOCKERHUB_USERNAME" "$DOCKERHUB_TOKEN" >"$creds"
    # An authenticated sync and an anonymous one give the same 429, which zot reports as a 404. So this line is the only sign of the mode.
    # The token is never printed.
    detail "docker hub sync authenticated as ${DOCKERHUB_USERNAME}"
  else
    printf '{}\n' >"$creds"
    detail "docker hub sync is anonymous. The pull limit for each IP applies, and this runner shares its IP"
  fi
  chmod 600 "$creds"

  # A container with mounts from another run cannot be reused. One created before the credentials mount has none.
  # One created from another checkout, such as a moved clone or an earlier CI job's workspace, mounts files that can be gone.
  # A replacement is cheap: the store is on the host, so the images stay.
  local want have
  want="$(printf '%s\n' "${ROOT}/infra/local/zot-config.yaml:/etc/zot/config.yaml" \
    "${creds}:/etc/zot/sync-creds.json" "${ZOT_DATA}:/var/lib/zot" | LC_ALL=C sort)"
  if docker inspect "$REGISTRY" >/dev/null 2>&1; then
    have="$(docker inspect -f '{{range .Mounts}}{{.Source}}:{{.Destination}}{{"\n"}}{{end}}' "$REGISTRY" |
      sed '/^$/d' | LC_ALL=C sort)"
    if [ "$have" != "$want" ]; then
      step "recreating '${REGISTRY}' against this checkout"
      docker rm -f "$REGISTRY" >/dev/null
    fi
  fi

  if ! docker inspect "$REGISTRY" >/dev/null 2>&1; then
    step "creating the local registry '${REGISTRY}:5000', which is zot"
    # Before docker, not after: the daemon creates a missing bind-mount source as root, and zot then cannot write its own store.
    mkdir -p "$ZOT_DATA"
    # Runs as the caller, so a forge cache can archive the store. zot defaults to root and writes mode 0600 everywhere.
    # The image's default command names a config.json, and this config is YAML.
    local label=()
    [ -z "${CI:-}" ] || label=(--label "platform.ci-job=$(ci_job)")
    docker run -d --restart=always --name "$REGISTRY" "${label[@]}" \
      -p 127.0.0.1:5000:5000 \
      --user "$(id -u):$(id -g)" \
      -v "${ROOT}/infra/local/zot-config.yaml:/etc/zot/config.yaml:ro" \
      -v "${creds}:/etc/zot/sync-creds.json:ro" \
      -v "${ZOT_DATA}:/var/lib/zot" \
      "$ZOT_IMAGE" serve /etc/zot/config.yaml >/dev/null
  elif [ "$(docker inspect -f '{{.State.Running}}' "$REGISTRY")" != true ]; then
    step "starting the local registry '${REGISTRY}'"
    docker start "$REGISTRY" >/dev/null
  fi
  # Check that it answers, not only that it runs. `--restart=always` keeps a container that exits at once in the `running` state.
  local waited=0
  until [ "$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' --max-time 5 \
    "http://127.0.0.1:5000/v2/" 2>/dev/null)" = 200 ]; do
    [ "$waited" -ge 30 ] && fail "the registry '${REGISTRY}' is not serving on :5000:
$(docker logs --tail 15 "$REGISTRY" 2>&1 | sed 's/^/    /')"
    sleep 1
    waited=$((waited + 1))
  done
}

# Fill zot with every third-party image that the cluster pulls, before the cluster exists, per ADR-0105.
# zot's on-demand sync copies a whole image before it answers, so about 18 pods at once exceed containerd's pull deadline.
# The list is generated with Kyverno's allow-list, so the two always agree.
stage_warm() {
  local refs="infra/local/image-refs.txt" total warmed=0 fetched=0
  local missed=()
  # The normalised repository path of each miss, kept next to the display form.
  # The failure report uses it to find that image's lines in the registry log.
  local missed_paths=()
  [ -f "$refs" ] || fail "${refs} is missing. Run 'mise run gen:image-allowlist'"
  # The tier's part of the list, by its first column: a base tier runs no ArgoCD and nothing that ArgoCD deploys.
  # WARM_TIER=full lets the job that saves the mirror cache fill it for both tiers.
  local wanted tier="${WARM_TIER:-$TIER}"
  wanted="$(mktemp)"
  awk -v tier="$tier" '
    /^#/ || /^[[:space:]]*$/ { next }
    $1 == "base" || tier == "full" { print $2 }
  ' "$refs" >"$wanted"
  total="$(grep -cvE '^\s*$' "$wanted" || true)"
  [ "$total" -gt 0 ] ||
    fail "${refs} names no image for the ${tier} tier. Run 'mise run gen:image-allowlist'"
  step "warming the registry with ${total} third-party image(s) for the ${tier} tier"

  local ref host path reference name tag status attempt
  while read -r ref; do
    # Split the reference the way a registry client does.
    host=docker.io
    path="$ref"
    if [[ "$ref" == */* ]]; then
      name="${ref%%/*}"
      # A first segment is a registry only if it looks like a host.
      # `alpine/k8s` is a Docker Hub repository, and `quay.io/cilium/cilium` is not.
      if [[ "$name" == *.* || "$name" == *:* || "$name" == localhost ]]; then
        host="$name"
        path="${ref#*/}"
      fi
    fi
    reference=""
    if [[ "$path" == *@* ]]; then
      reference="${path#*@}"
      path="${path%@*}"
    fi
    name="${path##*/}"
    tag=""
    if [[ "$name" == *:* ]]; then
      tag="${name##*:}"
      path="${path%:*}"
    fi
    # Docker Hub keeps its own images under `library/`.
    [ "$host" != docker.io ] || [[ "$path" == */* ]] || path="library/${path}"
    [ -n "$reference" ] || reference="$tag"

    # Check whether the image is already here. The tags API reads local storage only, so it answers in microseconds.
    # A manifest GET does not: with sync on, zot checks the upstream on every GET, and this stage pays that cost once.
    if [ -n "$tag" ] && curl -sf --noproxy '*' --max-time 10 \
      "http://127.0.0.1:5000/v2/${path}/tags/list" 2>/dev/null |
      yq -e ".tags // [] | contains([\"${tag}\"])" >/dev/null 2>&1; then
      warmed=$((warmed + 1))
      continue
    fi

    detail "· ${ref}"
    # Three attempts: this manifest request makes zot stream the whole image, so a miss is usually a truncated read or a rate limit.
    # The status is captured and not left to `-f`, which turns every HTTP error into exit 22. A 429 is throttling, and a 404 is a wrong reference.
    status=000
    for attempt in 1 2 3; do
      status="$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' --max-time 900 \
        -H 'Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json' \
        "http://127.0.0.1:5000/v2/${path}/manifests/${reference}?ns=${host}" || true)"
      [ -n "$status" ] || status=000
      [ "$status" = 200 ] && break
      # Wait between attempts: an upstream that just rate-limited this pull is not ready for the same request at once.
      [ "$attempt" = 3 ] || sleep $((attempt * 5))
    done
    if [ "$status" = 200 ]; then
      fetched=$((fetched + 1))
    else
      missed+=("${ref}, HTTP ${status}")
      missed_paths+=("$path")
    fi
  done <"$wanted"
  rm -f "$wanted"

  ok "registry warm: ${warmed} already cached, ${fetched} fetched"
  if [ "${#missed[@]}" -gt 0 ]; then
    printf '    · %s\n' "${missed[@]}" >&2
    # zot answers 404 for `no such tag` and for a failed sync. Only its own log shows the difference.
    # Filtered to the missed repositories, not the tail: the warm follows file order, so an early miss is thousands of lines back.
    local -a miss_pat=()
    local p own errors
    for p in "${missed_paths[@]}"; do miss_pat+=(-e "$p"); done
    detail "${REGISTRY} log for the images that missed:"
    own="$({ docker logs "$REGISTRY" 2>&1 || true; } | grep -F "${miss_pat[@]}" || true)"
    errors="$(printf '%s\n' "$own" |
      grep -iE '"level":"(error|warn)"|denied|unauthorized|toomanyrequests|rate.?limit|error' |
      tail -20 || true)"
    # Three outcomes: an error names the upstream's refusal, lines with no error mean zot stopped with no message, and no lines mean it never tried the sync.
    if [ -n "$errors" ]; then
      printf '%s\n' "$errors" | sed 's/^/      /' >&2
    elif [ -n "$own" ]; then
      detail "  sync attempted, no error logged. This is a truncated read, so run it again"
      printf '%s\n' "$own" | tail -10 | sed 's/^/      /' >&2
    else
      detail "  no sync attempted. The fault is the reference, not the upstream"
    fi
    fail "${#missed[@]} image(s) above could not be cached. The nodes pull only from
  this registry, so the cluster cannot start without them. Run it again to retry.
  If it still fails, check egress with 'mise run proxy:setup -- --check'."
  fi
}

# The kind cluster: create it, or start every node it already has.
# A stopped multi-node cluster comes back with its workers down, and a control plane alone reports Ready while nothing schedules.
stage_cluster() {
  local name other
  name="$(cluster_name)"

  other="$(cluster_name_of "$(other_tier)")"
  # The tiers share the edge's host ports, so they are alternatives.
  # Name the conflict, so docker does not report a bind failure from inside a half-created cluster.
  if cluster_exists "$other" && cluster_running "$other"; then
    fail "cluster '${other}' is running and holds the edge ports 8080 and 8443.
  Run one tier at a time:
    mise run cluster:stop -- $([ "$TIER" = full ] && echo base || echo full)"
  fi

  if ! kind get clusters 2>/dev/null | grep -qx "$name"; then
    step "creating kind cluster '${name}' from ${KIND_CONFIG}"
    kind create cluster --name "$name" --config "$KIND_CONFIG"
    [ -z "${CI:-}" ] || printf '%s\n' "$name" >"${RUNNER_TEMP:?}/kind-cluster"
  else
    local n stopped=0
    mapfile -t nodes < <(kind get nodes --name "$name")
    for n in "${nodes[@]}"; do
      [ "$(docker inspect -f '{{.State.Running}}' "$n" 2>/dev/null)" = false ] && stopped=1
    done
    if [ "$stopped" = 1 ]; then
      step "starting ${#nodes[@]} stopped node(s) of '${name}'"
      for n in "${nodes[@]}"; do docker start "$n" >/dev/null; done
      k wait --for=condition=Ready node --all --timeout=300s
    fi
  fi

  # kind recreates the `kind` docker network with the first cluster, and the nodes resolve registry.localhost through its embedded DNS.
  # So attach the registry again on every run.
  if docker network inspect kind >/dev/null 2>&1 &&
    ! docker inspect "$REGISTRY" \
      --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' | grep -qw kind; then
    step "attaching ${REGISTRY} to the kind network"
    docker network connect kind "$REGISTRY"
  fi

  kubectl config use-context "$(cluster_ctx)" >/dev/null
}

# Cilium, per ADR-0206. The cluster is created with disableDefaultCNI, so nothing schedules until this runs.
stage_cni() {
  if ! forced cni && h -n kube-system status cilium >/dev/null 2>&1 &&
    k get node -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q True; then
    return 0
  fi

  # The container name, because loopback is the API server on the control plane only, and a node's docker IP changes across restarts.
  # It resolves through docker's embedded DNS from the host netns, so it needs no CNI.
  local apiserver
  apiserver="$(cluster_name)-control-plane"
  step "installing Cilium with apiserver ${apiserver}:6443"
  chart_deps infra/helm/platform/cilium
  h upgrade --install cilium infra/helm/platform/cilium -n kube-system \
    --set cilium.operator.replicas=1 \
    --set "cilium.k8sServiceHost=${apiserver}" \
    --set cilium.k8sServicePort=6443 \
    --timeout 5m
  k wait --for=condition=Ready node --all --timeout=600s

  # The agent's hostPort backs hubble-peer. After a stop and start, Cilium quarantines the only backend and never reconciles it again.
  # hubble-relay then hangs. The chart has no setting for this.
  k -n kube-system patch svc hubble-peer --type merge \
    -p '{"spec":{"publishNotReadyAddresses":true}}' >/dev/null
  ok "Cilium installed, node Ready"
}

# `dev.localtest.me` is public DNS for 127.0.0.1: right on the host, wrong in a pod.
# The rewrite keeps the host and SNI that the IngressRoutes match.
stage_coredns() {
  local corefile patched
  corefile="$(k -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')"
  if ! forced coredns && printf '%s' "$corefile" | grep -q "name exact ${DOMAIN}"; then
    return 0
  fi

  step "rewriting ${DOMAIN} to the edge in CoreDNS"
  local stanza="rewrite stop {
    name exact ${DOMAIN} traefik.kube-system.svc.cluster.local
    answer auto
}
rewrite stop {
    name regex (.*)\\.${DOMAIN//./\\.} traefik.kube-system.svc.cluster.local
    answer auto
}"
  # kind's Corefile always opens with the default `.:53 {` block.
  patched="$(printf '%s\n' "$corefile" |
    awk -v stanza="$stanza" 'NR == 1 { print; print stanza; next } { print }')"
  k -n kube-system create configmap coredns --from-literal="Corefile=$patched" \
    --dry-run=client -o yaml | k apply -f - >/dev/null
  k -n kube-system rollout restart deploy/coredns >/dev/null
  k -n kube-system rollout status deploy/coredns --timeout=180s
}

# The namespaces and their Pod Security Admission profile, per ADR-0200, from the chart that the GitOps tiers sync.
# This runs before any admission: PSA is an admission check, so a label added after the pods applies only to the next admission.
stage_namespaces() {
  step "applying the namespaces and their pod-security profile"
  h template namespaces infra/helm/platform/namespaces \
    -f infra/gitops/platform/local/values.yaml | k apply -f - >/dev/null
}

# Traefik, per ADR-0305. kind has no ingress controller. Its CRDs must be registered before any IngressRoute is applied,
# by the glue stage below or by the gateway Application on the full tier.
stage_edge() {
  if ! forced edge && h -n kube-system status traefik >/dev/null 2>&1 &&
    k -n kube-system rollout status deploy/traefik --timeout=0 >/dev/null 2>&1; then
    return 0
  fi
  step "installing Traefik, the edge controller"
  # No gitops overlay merges here: traefik is imperative only and not in the platform ApplicationSet.
  # So the chart's own values hold the NodePort mapping.
  chart_deps infra/helm/platform/traefik
  h upgrade --install traefik infra/helm/platform/traefik -n kube-system --timeout 5m
  k -n kube-system rollout status deploy/traefik --timeout=300s
}

# Edge glue for this machine, not managed by GitOps on purpose. The docker-bridge gateway changes across restarts, so every start applies it again.
stage_glue() { # [<name> <port>]
  k get crd ingressroutes.traefik.io >/dev/null 2>&1 ||
    fail "traefik.io CRDs are not registered. Start the cluster first"

  local gw name="${1:-frontend}" port="${2:-3000}"
  gw="$(docker inspect "$(cluster_name)-control-plane" \
    --format '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}')"
  [ -n "$gw" ] || fail "could not read the docker-bridge gateway for $(cluster_name)-control-plane"

  [ "$#" -ge 2 ] || k apply -f infra/local/edge-auth.yaml >/dev/null
  k apply -f - >/dev/null <<EOF
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: ${name}-dev
  namespace: ${NS}
  labels:
    kubernetes.io/service-name: ${name}-dev
addressType: IPv4
ports:
  - name: http
    port: ${port}
    protocol: TCP
endpoints:
  - addresses: ["${gw}"]
    conditions: { ready: true }
EOF
  ok "edge glue applied: ${name} → host ${gw}:${port}"
}

# Postgres from the shared dependency manifest. Temporal and OpenFGA are in the same file, and the label skips them.
# They are opt-in: the services that declare them add them. Postgres is in the floor because Kratos needs a store.
stage_postgres() {
  step "applying the postgres dependency stand-in, which is Kratos's store"
  k apply -f infra/local/deps.yaml -l 'local.platform/component=postgres' >/dev/null
  k -n "$NS" rollout status deploy/postgres --timeout=180s
}

# Two passes: the CRDs are templates of the subchart.
# A single render validates cert-manager.io/v1 objects against an API server that does not know the group yet.
stage_certs() {
  step "installing cert-manager and the self-signed wildcard issuer"
  chart_deps infra/helm/platform/cert-manager
  h upgrade --install cert-manager infra/helm/platform/cert-manager \
    -n "$NS" --create-namespace --timeout 5m --wait \
    -f infra/gitops/platform/local/values.yaml --set issuers.enabled=false
  k -n "$NS" rollout status deploy/cert-manager-webhook --timeout=180s

  local attempt
  for attempt in 1 2 3; do
    h upgrade --install cert-manager infra/helm/platform/cert-manager \
      -n "$NS" --create-namespace --timeout 5m --wait \
      -f infra/gitops/platform/local/values.yaml && break
    [ "$attempt" = 3 ] && fail "cert-manager did not install after 3 attempts"
    detail "waiting for the cert-manager webhook, then retrying"
    k -n "$NS" rollout status deploy/cert-manager-webhook --timeout=180s || true
  done
  k -n "$NS" wait --for=condition=Ready certificate/wildcard --timeout=120s
}

# Only the PriorityClasses, per ADR-0204. The service chart always sets priorityClassName, so without them `cluster:add` fails at pod creation.
# The quotas, limit ranges, and PDBs in that chart are sized for the full platform.
stage_priority() {
  step "applying the priority classes services are scheduled by"
  h template resource-governance infra/helm/platform/resource-governance \
    -f infra/gitops/platform/local/values.yaml |
    yq 'select(.kind == "PriorityClass")' | k apply -f - >/dev/null
}

# The shared edge middlewares, per ADR-0305. Only middlewares.yaml: the rest of infra/gateway routes the ops tier, which this tier does not run.
stage_middlewares() {
  step "applying the edge middlewares"
  k apply -n "$NS" -f infra/gateway/middlewares.yaml >/dev/null
}

# Kratos's secrets from the committed local SOPS bundle, with the dsn pointed at the stand-in Postgres instead of CNPG.
stage_secrets() {
  # The template ships one local age key, so this creates a key for the project and re-encrypts the bundle.
  # It runs before the decrypt, which then needs a key that this repository no longer holds.
  bash scripts/rotate-local-age-key.sh

  step "materialising kratos-secrets from the committed local SOPS bundle"
  local secrets dsn
  secrets="$(SOPS_AGE_KEY_FILE=infra/gitops/platform/local/age.key \
    sops -d infra/gitops/platform/local/secrets/platform.enc.yaml |
    yq -o=json '.spec.secretTemplates[] | select(.name == "kratos-secrets") | .stringData')"
  [ -n "$secrets" ] || fail "kratos-secrets not found in the local SOPS bundle"
  dsn="postgres://dev:dev@postgres.${NS}.svc.cluster.local:5432/kratos?sslmode=disable"
  k -n "$NS" create secret generic kratos-secrets \
    --from-literal=secretsDefault="$(jq -r .secretsDefault <<<"$secrets")" \
    --from-literal=secretsCookie="$(jq -r .secretsCookie <<<"$secrets")" \
    --from-literal=secretsCipher="$(jq -r .secretsCipher <<<"$secrets")" \
    --from-literal=smtpConnectionURI="$(jq -r .smtpConnectionURI <<<"$secrets")" \
    --from-literal=dsn="$dsn" --dry-run=client -o yaml | k apply -f - >/dev/null
}

# Kratos and Oathkeeper, wired as the platform ApplicationSet wires them: the canonical infra/auth overlays and the string artefacts.
# They are never inline in chart values, per `lint:auth-inline`.
stage_ory() {
  step "installing kratos and oathkeeper"
  chart_deps infra/helm/platform/ory
  h upgrade --install ory infra/helm/platform/ory \
    -n "$NS" --create-namespace --timeout 8m --wait \
    -f infra/auth/kratos/values.yaml \
    -f infra/auth/oathkeeper/values.yaml \
    -f infra/gitops/platform/local/values.yaml \
    --set-file 'kratos.kratos.identitySchemas.user\.v1\.json=infra/auth/kratos/identity-schemas/user.v1.json' \
    --set-file 'oathkeeper.oathkeeper.accessRules=infra/auth/oathkeeper/access-rules.json'
}

# The committed test identities, per ADR-0601. The e2e suite uses the same identities.
stage_identities() { bash scripts/identity-seed.sh; }

# The bootstrap root of trust, per ADR-0202: the committed throwaway local age key, as the Secret that the sops-operator mounts.
stage_sopskey() {
  step "planting sops-age-key, the local throwaway key"
  k -n "$NS" create secret generic sops-age-key \
    --from-file=keys.txt=infra/gitops/platform/local/age.key \
    --dry-run=client -o yaml | k apply -f - >/dev/null
}

# Runs before the root app. Otherwise Argo creates pods for images that do not exist.
stage_images() {
  local reg="registry.localhost:5000"
  # Docker chooses HTTP or HTTPS from its insecure-registry CIDRs, so `registry.localhost` works only where NSS maps *.localhost to loopback.
  # 127.0.0.1 is insecure on every daemon.
  local push_reg="127.0.0.1:5000"
  local rev
  rev="$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
  git diff --quiet 2>/dev/null || rev="${rev}-dirty"
  local build_id=(--build-arg "GIT_SHA=${rev}" --build-arg BUILD_VERSION=local
    --build-arg "BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)")

  build_push() { # <image-name> <dockerfile> <context> [build args]
    local name="$1" dockerfile="$2" context="$3" attempt
    shift 3
    # Buildkit's fetch of the frontend and base images can hit TLS-handshake timeouts on a slow link.
    # The layers it got are cached, so a retry continues from there.
    for attempt in 1 2 3; do
      docker build -t "${push_reg}/${name}:local" -f "$dockerfile" "$@" "$context" &&
        docker push "${push_reg}/${name}:local" && return 0
      detail "build and push of ${name} attempt ${attempt} failed, retrying"
    done
    fail "could not build and push ${name} after 3 attempts"
  }

  step "building and pushing repo images to ${reg}"
  # From the values files: the ApplicationSet generates one Application for each file.
  # A file with no built image stays in ImagePullBackOff.
  local values svc
  for values in infra/gitops/services/local/values/*.yaml; do
    svc="$(basename "$values" .yaml)"
    # Apps have their own Dockerfile, context, and build args. They are built below.
    [ -f "services/${svc}/Dockerfile" ] || continue
    if [ "$(yq -r '.server.enabled // true' "$values")" = true ]; then
      build_push "${svc}-server" "services/${svc}/Dockerfile" . \
        --build-arg SERVICE="${svc}" --build-arg APP_CMD=server "${build_id[@]}"
    fi
    if [ "$(yq -r '.worker.enabled // false' "$values")" = true ]; then
      build_push "${svc}-worker" "services/${svc}/Dockerfile" . \
        --build-arg SERVICE="${svc}" --build-arg APP_CMD=worker "${build_id[@]}"
    fi
  done
  build_push admin apps/admin/Dockerfile apps/admin
  # `output: "standalone"` freezes next.config into server.js, so the build sets the server-action CSRF allowlist.
  # It is read from the same values file that the pod reads at runtime, per ADR-0306.
  build_push frontend apps/frontend/Dockerfile . \
    --build-arg "SERVICE_VERSION=${rev}" \
    --build-arg "EDGE_PUBLIC_ORIGIN=$(yq -r '.env.EDGE_PUBLIC_ORIGIN // ""' \
      infra/gitops/services/local/values/frontend.yaml)"
}

# ArgoCD, which cannot sync itself into existence. The local platform ApplicationSet excludes it, so this release is authoritative.
stage_argocd() {
  # Kyverno's webhook is failurePolicy: Fail, so every apply is rejected while the admission controller is not ready.
  # The check uses the deployment, not the namespace, because the namespaces stage creates the kyverno namespace early.
  if k -n kyverno get deploy kyverno-admission-controller >/dev/null 2>&1; then
    step "waiting for the Kyverno admission webhook to serve"
    k -n kyverno rollout status deploy/kyverno-admission-controller --timeout=300s
    # The rollout is the Deployment's view. The API server dials the endpoint, which becomes ready after the pod.
    # shellcheck disable=SC2329  # invoked by name through wait_for.
    kyverno_endpoint_ready() {
      [ -n "$(k -n kyverno get endpointslice -l kubernetes.io/service-name=kyverno-svc \
        -o jsonpath='{.items[*].endpoints[?(@.conditions.ready==true)].addresses[0]}')" ]
    }
    wait_for "a ready kyverno endpoint" 120 kyverno_endpoint_ready
  fi

  step "installing ArgoCD"
  chart_deps infra/helm/platform/argocd
  # Machine-local values that proxy:setup writes. They are absent on a direct network.
  # The repo-server is the one component that reaches git and the chart repositories from inside the cluster, so it needs the host's egress route.
  local overlay=()
  [ -f infra/local/proxy.local.yaml ] && overlay=(-f infra/local/proxy.local.yaml)
  h upgrade --install argocd infra/helm/platform/argocd -n argocd --create-namespace --timeout 8m "${overlay[@]}"
  k -n argocd rollout status deploy/argocd-server --timeout=300s
  k -n argocd rollout status deploy/argocd-repo-server --timeout=300s
  k -n argocd rollout status deploy/argocd-applicationset-controller --timeout=300s
  stage_repo_creds
}

# A private repository needs a credential that Argo can clone with: ARGOCD_REPO_USERNAME and ARGOCD_REPO_PASSWORD where set, as a CI job's own token.
# Otherwise it uses the engineer's git credential for the forge. A public repository needs neither.
# The url is the forge's origin, as in scripts/argocd-bootstrap.sh.
stage_repo_creds() {
  local url host user="${ARGOCD_REPO_USERNAME:-}" pass="${ARGOCD_REPO_PASSWORD:-}" creds
  url="$(yq -r '.spec.source.repoURL' infra/gitops/local-bootstrap/root-application.yaml)"
  host="$(sed -E 's|^https://([^/]+)/.*|\1|' <<<"$url")"
  if [ -z "$pass" ]; then
    creds="$(printf 'protocol=https\nhost=%s\n\n' "$host" |
      GIT_TERMINAL_PROMPT=0 GIT_ASKPASS='' SSH_ASKPASS='' git credential fill 2>/dev/null)" || creds=""
    user="$(sed -n 's/^username=//p' <<<"$creds")"
    pass="$(sed -n 's/^password=//p' <<<"$creds")"
  fi
  [ -n "$pass" ] || return 0
  step "giving Argo CD a credential for https://${host}/"
  k -n argocd create secret generic forge-creds --from-literal=type=git --from-literal=url="https://${host}/" \
    --from-literal=username="${user:-git}" --from-literal=password="$pass" --dry-run=client -o yaml |
    k label --local -f - argocd.argoproj.io/secret-type=repo-creds -o yaml |
    k apply -f - >/dev/null
}

# The local root App-of-Apps, then a wait for Argo to converge. Argo orders Grafana's dashboards and everything else by sync-wave.
stage_rootapp() {
  step "applying the local root application"
  k apply -f infra/gitops/local-bootstrap/root-application.yaml >/dev/null

  # The argocd CLI in core mode reads the Application CRDs directly, per ADR-0201, and takes its namespace from the kube-context.
  # So it runs against a throwaway kubeconfig and does not change the user's.
  local kubeconfig
  kubeconfig="$(mktemp)"
  # shellcheck disable=SC2064  # expand the path now, not at trap time
  trap "rm -f '$kubeconfig'" RETURN
  k config view --minify --flatten >"$kubeconfig"
  kubectl --kubeconfig "$kubeconfig" config set-context --current --namespace argocd >/dev/null
  ac() { KUBECONFIG="$kubeconfig" argocd --core "$@"; }

  # `cluster:stop` freezes a sync in progress. On resume the controller reuses its old task plan, which never converges against changed manifests.
  # `argocd app wait` reports only a timeout, so the reason is in pod events, which nothing else prints.
  dump_unhealthy() {
    local app ns
    warn "applications that did not reach Synced and Healthy:"
    ac app list -o wide 2>/dev/null |
      awk 'NR==1 || $2!="Synced" || $3!="Healthy"' | sed 's/^/    /' >&2 || true
    # Pod detail for the namespaces of those applications. A CrashLoop, a failed mount, and an unschedulable pod need three different fixes.
    # The app status shows all three as `Progressing`.
    for ns in $(k get ns -o name 2>/dev/null | sed 's#namespace/##'); do
      local bad
      bad="$(k -n "$ns" get pods --no-headers 2>/dev/null |
        awk '$3!="Running" && $3!="Completed"' || true)"
      [ -n "$bad" ] || continue
      warn "  namespace ${ns}:"
      printf '%s\n' "$bad" | sed 's/^/      /' >&2
      k -n "$ns" get events --sort-by=.lastTimestamp 2>/dev/null |
        grep -iE 'warn|fail|error|back-off' | tail -8 | sed 's/^/      /' >&2 || true
    done
  }

  # shellcheck disable=SC2329  # invoked by name through wait_for.
  op_ended() {
    [[ ! "$(k -n argocd get application "$1" -o jsonpath='{.status.operationState.phase}')" =~ ^(Running|Terminating)$ ]]
  }

  wait_apps() {
    local timeout="$1" app
    shift
    ac app wait "$@" --sync --health --operation --timeout "$timeout" && return 0
    warn "[$*] did not converge in ${timeout}s. Terminating their operations, which are probably stale from a cluster:stop, and syncing again"
    for app in "$@"; do ac app terminate-op "$app" || true; done
    # Termination is asynchronous, and a sync sent while it runs is refused with `another operation is already in progress`.
    for app in "$@"; do
      wait_for "${app}'s operation to end" 120 op_ended "$app"
      ac app sync "$app" --timeout "$timeout"
    done
    # Half the budget on the retry: the first wait already showed that the set does not settle alone.
    ac app wait "$@" --sync --health --operation --timeout "$((timeout / 2))" && return 0
    dump_unhealthy
    fail "ArgoCD did not converge. The applications and pod events above give the reason. \`kubectl --context $(cluster_ctx) -n <ns> describe pod <pod>\` gives the rest."
  }

  step "waiting for ArgoCD to converge. The first run is slow"
  wait_apps 900 local-root
  # Appset generation comes after appset sync, so the set is listed again until it is stable.
  local apps
  while :; do
    apps="$(ac app list -o name)"
    # shellcheck disable=SC2086  # newline-separated names, intentional split
    # 900, not 1800. With the mirror warm, every image is a local pull, so an application that has not settled in 15 minutes is stuck.
    wait_apps 900 $apps
    [ "$(ac app list -o name)" = "$apps" ] && break
  done
  ok "all ArgoCD applications Synced and Healthy"
}

# Fill the in-cluster zot's catalogue with the first-party images, per ADR-0105. Best effort: no pod's start depends on it.
stage_populatezot() {
  bash "$(dirname "${BASH_SOURCE[0]}")/../populate-zot.sh" ||
    warn "populate-zot did not complete. The in-cluster zot console can be empty. This is not fatal"
}
