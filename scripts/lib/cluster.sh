# shellcheck shell=bash

# shellcheck disable=SC2317  # the guard's `return` is reached when re-sourced.
if [[ -n "${__CLUSTER_SH_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
__CLUSTER_SH_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Loaded, not computed: kind reads the proxy variables from its own environment and is the only thing that can add the node's name to NO_PROXY, without which `kind create` aborts on an EOF.
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
# A path, never a named volume: a forge cache can restore a directory, and warming from scratch is the dominant cost of `cluster:up` (ADR-0205).
ZOT_DATA="${ZOT_DATA:-${XDG_CACHE_HOME:-$HOME/.cache}/zot/${REGISTRY}}"
ZOT_IMAGE="ghcr.io/project-zot/zot-linux-amd64:v2.1.20"
FORCE="${FORCE:-}"

# Validated at source time: the functions are called as `$(cluster_ctx)`, where an exit kills only the subshell.
case "${TIER:-}" in
"" | base | full) ;;
*) fail "'${TIER}' is not a tier — use \"base\" or \"full\"" ;;
esac

cluster_tier() { printf '%s' "$TIER"; }
# The tier is an argument, so a message naming a command names its tier too.
up_hint() {
  if [ "$TIER" = full ]; then printf 'mise run cluster:up -- full'; else printf 'mise run cluster:up'; fi
}
# The full tier's name carries the tier, so `docker ps` and `kubectl config
# get-contexts` both say which cluster is which.
cluster_name_of() {
  if [ "$1" = full ]; then printf '%s-full' "$CLUSTER"; else printf '%s' "$CLUSTER"; fi
}
cluster_name() { cluster_name_of "$TIER"; }
other_tier() { if [ "$TIER" = full ]; then printf 'base'; else printf 'full'; fi; }
cluster_exists() { kind get clusters 2>/dev/null | grep -qx "$1"; }
# A tier-scoped verb that found nothing says so, and names the tier that is up: the
# tiers are alternatives, so "no such cluster" is usually the wrong tier named.
other_tier_hint() {
  local other
  other="$(other_tier)"
  cluster_exists "$(cluster_name_of "$other")" &&
    detail "the ${other} tier is up — did you mean 'mise run cluster:${1} -- ${other}'?"
  return 0
}
cluster_ctx() { printf 'kind-%s' "$(cluster_name)"; }

# Is this cluster's node up, as opposed to merely created? Both tiers can exist at
# once; only one can hold the edge ports, so only one is ever serving.
cluster_running() {
  docker inspect -f '{{.State.Running}}' "${1}-control-plane" 2>/dev/null | grep -qx true
}

# The tier that is up, or nothing. Running beats merely created, and an ambiguous
# answer is no answer: a caller that has to guess between two clusters must be told
# which one it meant rather than be given one of them.
detect_tier() {
  # One listing for both tiers: this runs on every source, and `kind get clusters`
  # is a docker round-trip. `if`, not `&&`, so a stopped cluster is an answer rather
  # than a non-zero status that ends the caller under `set -e`.
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

# Which tier a script acts on. Precedence: TIER in the environment, then TIER_FROM_ARGV=1 for cluster.sh,
# then the tier that is up, then base. A hardcoded default is wrong silently — every kubectl fails against
# a context that does not exist, and reads as "the platform is down".
if [ -z "${TIER:-}" ] && [ -z "${TIER_FROM_ARGV:-}" ]; then
  TIER="$(detect_tier || true)"
fi
TIER="${TIER:-base}"
# Exported, because stages shell out to scripts that resolve the context from it.
# Unexported, `identity-seed.sh` seeds the inner loop while the full tier waits.
export TIER

k() { kubectl --context "$(cluster_ctx)" "$@"; }
h() { helm --kube-context "$(cluster_ctx)" "$@"; }

forced() { [[ ",${FORCE}," == *",$1,"* ]]; }

# Poll until a command succeeds. Bespoke readiness loops are how the two tiers drifted.
wait_for() { # <what> <seconds> <cmd…>
  local what="$1" budget="$2"
  shift 2
  local waited=0
  until "$@" >/dev/null 2>&1; do
    [ "$waited" -ge "$budget" ] && fail "timed out after ${budget}s waiting for ${what}"
    sleep 2
    waited=$((waited + 2))
  done
}

# `build` is the offline path and needs the dependency's repo already registered in
# the caller's helm config; `update` resolves it from Chart.yaml. Developer machines
# pass on the first, clean runners only on the second.
chart_deps() { helm dependency build "$1" >/dev/null 2>&1 || helm dependency update "$1" >/dev/null; }

# A tool that is absent reads as an answer: `kind get clusters` failing looks
# exactly like a cluster that was never created, and every probe below inherits
# that ambiguity. Assert the tools first, so "not found" cannot mean "not created".
require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 ||
      fail "${tool} not found on PATH — run this through mise (\`mise run …\`), which puts the pinned toolchain there"
  done
}

# Fail unless the probe CAN run. An unreachable cluster otherwise looks identical to
# "not deployed" to every idempotence guard.
require_cluster() {
  require_tools kubectl
  k cluster-info >/dev/null 2>&1 ||
    fail "cluster $(cluster_ctx) is not reachable — run '$(up_hint)' first"
}

# The committed ApplicationSet named apps after the values file and now trims the extension, so both spellings are live; guessing one leaves auto-sync unpaused and Argo reverts the deploy.
argo_service_app() {
  local name
  for name in "local-service-${1}" "local-service-${1}.yaml"; do
    if k -n argocd get application.argoproj.io "$name" >/dev/null 2>&1; then
      echo "$name"
      return 0
    fi
  done
}

# zot, the registry every environment runs (ADR-0105), as a host container beside
# both clusters. It mirrors the upstreams on demand, so nothing is preloaded and no
# image list has to be maintained. Host-level: it survives cluster delete/recreate.
stage_registry() {
  # Outside the repository because it holds a token (ADR-0202). Written every time, `{}` when the environment carries nothing, so the mount always resolves.
  local creds="${XDG_RUNTIME_DIR:-/tmp}/zot-sync-creds-${REGISTRY}.json"
  # Docker creates a missing bind-mount source as a root-owned directory, which every later run then dies on.
  [ ! -e "$creds" ] || [ -f "$creds" ] || rm -rf "$creds"
  if [ -n "${DOCKERHUB_USERNAME:-}" ] && [ -n "${DOCKERHUB_TOKEN:-}" ]; then
    printf '{"registry-1.docker.io":{"username":"%s","password":"%s"}}\n' \
      "$DOCKERHUB_USERNAME" "$DOCKERHUB_TOKEN" >"$creds"
    # An authenticated sync and an anonymous one produce the same 429, which zot reports as a 404, so the mode is not otherwise visible. The token is never printed.
    detail "docker hub sync authenticated as ${DOCKERHUB_USERNAME}"
  else
    printf '{}\n' >"$creds"
    detail "docker hub sync is ANONYMOUS — the per-IP pull limit applies, and this runner shares its IP"
  fi
  chmod 600 "$creds"

  # A container created before this mount existed has no credentials and cannot gain
  # them while it runs. Replacing it is cheap: the cache is a named volume, so the
  # images survive.
  if docker inspect "$REGISTRY" >/dev/null 2>&1 &&
    ! docker inspect -f '{{range .Mounts}}{{.Destination}} {{end}}' "$REGISTRY" |
    grep -q /etc/zot/sync-creds.json; then
    step "recreating '${REGISTRY}' to mount the sync credentials"
    docker rm -f "$REGISTRY" >/dev/null
  fi

  if ! docker inspect "$REGISTRY" >/dev/null 2>&1; then
    step "creating the local registry '${REGISTRY}:5000' (zot)"
    # Before docker, not after: a bind mount whose source is missing is created by the daemon as root, and zot then cannot write its own store.
    mkdir -p "$ZOT_DATA"
    # As the caller, so a forge cache can archive the store; zot defaults to root and writes mode 0600 throughout.
    # The image's default command names a config.json; this config is YAML.
    docker run -d --restart=always --name "$REGISTRY" \
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
  # Answering, not merely running: `--restart=always` keeps a container that exits immediately in the `running` state, so a state check passes against a registry that never serves a byte.
  local waited=0
  until [ "$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' --max-time 5 \
    "http://127.0.0.1:5000/v2/" 2>/dev/null)" = 200 ]; do
    [ "$waited" -ge 30 ] && fail "the registry '${REGISTRY}' is not serving on :5000:
$(docker logs --tail 15 "$REGISTRY" 2>&1 | sed 's/^/    /')"
    sleep 1
    waited=$((waited + 1))
  done
}

# Fill zot with every third-party image the cluster will pull, before the cluster exists (ADR-0105).
# zot's on-demand sync copies a whole image before answering the manifest request, so ~18 pods asking at once
# exceed containerd's pull deadline. The list is generated with Kyverno's allow-list, so the two cannot disagree.
stage_warm() {
  local refs="infra/local/image-refs.txt" total warmed=0 fetched=0
  local missed=()
  # The normalised repository path of each miss, kept alongside the display form so
  # the failure report can find THAT image's lines in the registry log.
  local missed_paths=()
  [ -f "$refs" ] || fail "${refs} is missing — run 'mise run gen:image-allowlist'"
  # The tier's share of the list, by its first column: a base bring-up runs no ArgoCD and none of what ArgoCD deploys.
  local wanted
  wanted="$(mktemp)"
  awk -v tier="$TIER" '
    /^#/ || /^[[:space:]]*$/ { next }
    $1 == "base" || tier == "full" { print $2 }
  ' "$refs" >"$wanted"
  total="$(grep -cvE '^\s*$' "$wanted" || true)"
  [ "$total" -gt 0 ] ||
    fail "${refs} names no image for the ${TIER} tier — run 'mise run gen:image-allowlist'"
  step "warming the registry with ${total} third-party image(s) for the ${TIER} tier"

  local ref host path reference name tag status attempt
  while read -r ref; do
    # Split the reference the way a registry client does.
    host=docker.io
    path="$ref"
    if [[ "$ref" == */* ]]; then
      name="${ref%%/*}"
      # A first segment is a REGISTRY only if it looks like a host. `alpine/k8s` is
      # a Docker Hub repository; `quay.io/cilium/cilium` is not.
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

    # Is it already here? The tags API reads local storage only, so it answers in
    # microseconds. A manifest GET does not: with sync enabled zot re-checks the
    # upstream on every one, which is the cost this whole stage exists to pay once.
    if [ -n "$tag" ] && curl -sf --noproxy '*' --max-time 10 \
      "http://127.0.0.1:5000/v2/${path}/tags/list" 2>/dev/null |
      yq -e ".tags // [] | contains([\"${tag}\"])" >/dev/null 2>&1; then
      warmed=$((warmed + 1))
      continue
    fi

    detail "· ${ref}"
    # Three attempts: answering this manifest makes zot stream the whole image, so a miss is usually a truncated read or a rate limit.
    # The status is captured rather than left to `-f`, which collapses every HTTP error into exit 22. A 429 is throttling; a 404 is a wrong reference.
    status=000
    for attempt in 1 2 3; do
      status="$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' --max-time 900 \
        -H 'Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json' \
        "http://127.0.0.1:5000/v2/${path}/manifests/${reference}?ns=${host}" || true)"
      [ -n "$status" ] || status=000
      [ "$status" = 200 ] && break
      # Backs off between attempts: an upstream that just rate-limited this pull is
      # not ready for the same request a millisecond later.
      [ "$attempt" = 3 ] || sleep $((attempt * 5))
    done
    if [ "$status" = 200 ]; then
      fetched=$((fetched + 1))
    else
      missed+=("${ref} (HTTP ${status})")
      missed_paths+=("$path")
    fi
  done <"$wanted"
  rm -f "$wanted"

  ok "registry warm: ${warmed} already cached, ${fetched} fetched"
  if [ "${#missed[@]}" -gt 0 ]; then
    printf '    · %s\n' "${missed[@]}" >&2
    # zot answers 404 both for "no such tag" and for "my sync of it failed", and only its own log separates the two.
    # Filtered to the repositories that missed, not the tail: the warm walks in file order, so an early miss is thousands of lines back.
    local -a miss_pat=()
    local p own errors
    for p in "${missed_paths[@]}"; do miss_pat+=(-e "$p"); done
    detail "${REGISTRY} log for the images that missed:"
    own="$({ docker logs "$REGISTRY" 2>&1 || true; } | grep -F "${miss_pat[@]}" || true)"
    errors="$(printf '%s\n' "$own" |
      grep -iE '"level":"(error|warn)"|denied|unauthorized|toomanyrequests|rate.?limit|error' |
      tail -20 || true)"
    # Three outcomes: an error names the upstream's refusal, lines with no error mean zot gave up quietly, and no lines mean it never attempted the sync.
    if [ -n "$errors" ]; then
      printf '%s\n' "$errors" | sed 's/^/      /' >&2
    elif [ -n "$own" ]; then
      detail "  sync attempted, no error logged — a truncated read; re-run"
      printf '%s\n' "$own" | tail -10 | sed 's/^/      /' >&2
    else
      detail "  no sync attempted — the fault is the reference, not the upstream"
    fi
    fail "${#missed[@]} image(s) above could not be cached. The nodes pull only from
  this registry, so the cluster cannot start without them. Re-run to retry; if it
  persists, check egress with 'mise run proxy:setup -- --check'."
  fi
}

# The kind cluster: create it, or start every node it already has. A stopped
# multi-node cluster comes back with its workers down, and a control plane alone
# reports Ready while nothing schedules.
stage_cluster() {
  local name other
  name="$(cluster_name)"

  # The tiers share the edge's host ports, so they are alternatives. Name the
  # conflict rather than letting docker report a bind failure from inside a
  # half-created cluster.
  other="$(cluster_name_of "$(other_tier)")"
  if cluster_exists "$other" && cluster_running "$other"; then
    fail "cluster '${other}' is running and holds the edge ports 8080/8443.
  Run one tier at a time:
    mise run cluster:stop -- $([ "$TIER" = full ] && echo base || echo full)"
  fi

  if ! kind get clusters 2>/dev/null | grep -qx "$name"; then
    step "creating kind cluster '${name}' from ${KIND_CONFIG}"
    kind create cluster --name "$name" --config "$KIND_CONFIG"
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

  # kind recreates the `kind` docker network with the first cluster, and the nodes
  # resolve registry.localhost through its embedded DNS — so re-attach every run.
  if docker network inspect kind >/dev/null 2>&1 &&
    ! docker inspect "$REGISTRY" \
      --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' | grep -qw kind; then
    step "attaching ${REGISTRY} to the kind network"
    docker network connect kind "$REGISTRY"
  fi

  kubectl config use-context "$(cluster_ctx)" >/dev/null
}

# Cilium (ADR-0206). The cluster is created with disableDefaultCNI, so nothing
# schedules until this runs.
stage_cni() {
  if ! forced cni && h -n kube-system status cilium >/dev/null 2>&1 &&
    k get node -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q True; then
    return 0
  fi

  # The container name, because loopback is the API server on the control plane only and a node's docker IP moves across restarts.
  # It resolves through docker's embedded DNS from the host netns, so it needs no CNI.
  local apiserver
  apiserver="$(cluster_name)-control-plane"
  step "installing Cilium (apiserver ${apiserver}:6443)"
  chart_deps infra/helm/platform/cilium
  h upgrade --install cilium infra/helm/platform/cilium -n kube-system \
    --set cilium.operator.replicas=1 \
    --set "cilium.k8sServiceHost=${apiserver}" \
    --set cilium.k8sServicePort=6443 \
    --timeout 5m
  k wait --for=condition=Ready node --all --timeout=600s

  # hubble-peer is backed by the agent's hostPort. On a stop/start Cilium quarantines the sole backend and never re-reconciles it, wedging hubble-relay. The chart exposes no knob.
  k -n kube-system patch svc hubble-peer --type merge \
    -p '{"spec":{"publishNotReadyAddresses":true}}' >/dev/null
  ok "Cilium installed; node Ready"
}

# `dev.localtest.me` is public DNS pointing at 127.0.0.1 — right on the host, wrong in a pod. Rewriting the name keeps the host and SNI the IngressRoutes match on.
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

# The namespaces and their Pod Security Admission profile (ADR-0200), from the same
# chart the GitOps tiers sync. Before anything is admitted: PSA is an admission
# check, so a label that lands after the pods governs the next admission, not these.
stage_namespaces() {
  step "applying the namespaces and their pod-security profile"
  h template namespaces infra/helm/platform/namespaces \
    -f infra/gitops/platform/local/values.yaml | k apply -f - >/dev/null
}

# Traefik (ADR-0305). kind ships no ingress controller, and the CRDs it carries must
# be registered before any IngressRoute is applied — by the glue stage below, or by
# the gateway Application on the full tier.
stage_edge() {
  if ! forced edge && h -n kube-system status traefik >/dev/null 2>&1 &&
    k -n kube-system rollout status deploy/traefik --timeout=0 >/dev/null 2>&1; then
    return 0
  fi
  step "installing Traefik (edge controller)"
  # No gitops overlay coalesces here: traefik is imperative-only, absent from the
  # platform ApplicationSet, so the chart's own values carry the NodePort mapping.
  chart_deps infra/helm/platform/traefik
  h upgrade --install traefik infra/helm/platform/traefik -n kube-system --timeout 5m
  k -n kube-system rollout status deploy/traefik --timeout=300s
}

# Per-machine edge glue, deliberately not GitOps-managed. The docker-bridge gateway moves across restarts, so this is re-stamped on every start.
stage_glue() { # [<name> <port>]
  k get crd ingressroutes.traefik.io >/dev/null 2>&1 ||
    fail "traefik.io CRDs are not registered — bring the cluster up first"

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
  ok "edge glue applied (${name} → host ${gw}:${port})"
}

# Postgres out of the shared dependency manifest. Temporal and OpenFGA live in the
# same file and are skipped by label — they are opt-in, added by the services that
# declare them. Postgres is in the floor because Kratos needs a store.
stage_postgres() {
  step "applying the postgres dependency stand-in (Kratos's store)"
  k apply -f infra/local/deps.yaml -l 'local.platform/component=postgres' >/dev/null
  k -n "$NS" rollout status deploy/postgres --timeout=180s
}

# Two passes: the CRDs are templates of the subchart, so a single render validates cert-manager.io/v1 objects against an API server that has never heard of the group.
stage_certs() {
  step "installing cert-manager + the self-signed wildcard issuer"
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

# Only the PriorityClasses (ADR-0204): the service chart sets priorityClassName
# unconditionally, so without them `cluster:add` fails at pod creation. The quotas,
# limit ranges and PDBs in that chart are sized for the full platform.
stage_priority() {
  step "applying the priority classes services are scheduled by"
  h template resource-governance infra/helm/platform/resource-governance \
    -f infra/gitops/platform/local/values.yaml |
    yq 'select(.kind == "PriorityClass")' | k apply -f - >/dev/null
}

# The shared edge middlewares (ADR-0305). Only middlewares.yaml — the rest of
# infra/gateway routes the ops tier, which this tier does not run.
stage_middlewares() {
  step "applying the edge middlewares"
  k apply -n "$NS" -f infra/gateway/middlewares.yaml >/dev/null
}

# Kratos's secrets from the committed local SOPS bundle, with the dsn pointed at the
# stand-in Postgres instead of CNPG.
stage_secrets() {
  # The template ships one local age key, so this mints a per-project one and re-encrypts the bundle. Ahead of the decrypt, which afterwards needs a key this repository no longer holds.
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

# Kratos + Oathkeeper, wired the way the platform ApplicationSet wires them: the
# canonical infra/auth overlays plus the string artefacts, never inlined into chart
# values (lint:auth-inline).
stage_ory() {
  step "installing kratos + oathkeeper"
  chart_deps infra/helm/platform/ory
  h upgrade --install ory infra/helm/platform/ory \
    -n "$NS" --create-namespace --timeout 8m --wait \
    -f infra/auth/kratos/values.yaml \
    -f infra/auth/oathkeeper/values.yaml \
    -f infra/gitops/platform/local/values.yaml \
    --set-file 'kratos.kratos.identitySchemas.user\.v1\.json=infra/auth/kratos/identity-schemas/user.v1.json' \
    --set-file 'oathkeeper.oathkeeper.accessRules=infra/auth/oathkeeper/access-rules.json'
}

# The committed test identities (ADR-0601) — the same ones the e2e suite uses.
stage_identities() { bash scripts/identity-seed.sh; }

# The bootstrap root of trust (ADR-0202): the committed throwaway local age key,
# planted as the Secret the sops-operator mounts.
stage_sopskey() {
  step "planting sops-age-key (local throwaway key)"
  k -n "$NS" create secret generic sops-age-key \
    --from-file=keys.txt=infra/gitops/platform/local/age.key \
    --dry-run=client -o yaml | k apply -f - >/dev/null
}

# Must precede the root app, or Argo creates pods for images that do not exist.
stage_images() {
  local reg="registry.localhost:5000"
  # Docker picks HTTP-vs-HTTPS from its insecure-registry CIDRs, so `registry.localhost` works only where NSS maps *.localhost to loopback. 127.0.0.1 is insecure on every daemon.
  local push_reg="127.0.0.1:5000"
  local rev
  rev="$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
  git diff --quiet 2>/dev/null || rev="${rev}-dirty"
  local build_id=(--build-arg "GIT_SHA=${rev}" --build-arg BUILD_VERSION=local
    --build-arg "BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)")

  build_push() { # <image-name> <dockerfile> <context> [build args…]
    local name="$1" dockerfile="$2" context="$3" attempt
    shift 3
    # Buildkit's fetch of the frontend + base images trips TLS-handshake timeouts on
    # a slow link; the layers it did get are cached, so a retry rides over it.
    for attempt in 1 2 3; do
      docker build -t "${push_reg}/${name}:local" -f "$dockerfile" "$@" "$context" &&
        docker push "${push_reg}/${name}:local" && return 0
      detail "build/push of ${name} attempt ${attempt} failed — retrying"
    done
    fail "could not build+push ${name} after 3 attempts"
  }

  step "building + pushing repo images to ${reg}"
  # Derived from the values files: the ApplicationSet generates one Application per file, so a file with no image built for it is stuck in ImagePullBackOff.
  local values svc
  for values in infra/gitops/services/local/values/*.yaml; do
    svc="$(basename "$values" .yaml)"
    # Apps have their own Dockerfile, context and build args; they are built below.
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
  # `output: "standalone"` freezes next.config into server.js, so the server-action
  # CSRF allowlist is decided at BUILD time — read from the values file the pod
  # reads it from at runtime (ADR-0306).
  build_push frontend apps/frontend/Dockerfile . \
    --build-arg "SERVICE_VERSION=${rev}" \
    --build-arg "EDGE_PUBLIC_ORIGIN=$(yq -r '.env.EDGE_PUBLIC_ORIGIN // ""' \
      infra/gitops/services/local/values/frontend.yaml)"
}

# ArgoCD, which cannot sync itself into existence. Excluded from the local platform
# ApplicationSet, so this release is authoritative.
stage_argocd() {
  # Kyverno's webhook is failurePolicy: Fail, so while the admission controller is unready every apply is rejected.
  # Keyed on the deployment, not the namespace: the namespaces stage creates the kyverno namespace in the prelude.
  if k -n kyverno get deploy kyverno-admission-controller >/dev/null 2>&1; then
    step "waiting for the Kyverno admission webhook to serve"
    k -n kyverno rollout status deploy/kyverno-admission-controller --timeout=300s
    # The rollout is the Deployment's view; the API server dials the endpoint, which
    # lags the pod going Ready.
    # shellcheck disable=SC2329  # invoked by name through wait_for.
    kyverno_endpoint_ready() {
      [ -n "$(k -n kyverno get endpointslice -l kubernetes.io/service-name=kyverno-svc \
        -o jsonpath='{.items[*].endpoints[?(@.conditions.ready==true)].addresses[0]}')" ]
    }
    wait_for "a ready kyverno endpoint" 120 kyverno_endpoint_ready
  fi

  step "installing ArgoCD"
  chart_deps infra/helm/platform/argocd
  # Machine-local values, written by proxy:setup and absent on a direct network. The
  # repo-server is the one component that reaches git and the chart repositories from
  # inside the cluster, so it is the one that needs the host's egress route.
  local overlay=()
  [ -f infra/local/proxy.local.yaml ] && overlay=(-f infra/local/proxy.local.yaml)
  h upgrade --install argocd infra/helm/platform/argocd -n argocd --create-namespace --timeout 8m "${overlay[@]}"
  k -n argocd rollout status deploy/argocd-server --timeout=300s
  k -n argocd rollout status deploy/argocd-repo-server --timeout=300s
  k -n argocd rollout status deploy/argocd-applicationset-controller --timeout=300s
}

# The local root App-of-Apps, then wait for Argo to converge. Grafana's dashboards
# and every ordering concern are Argo's job, by sync-wave.
stage_rootapp() {
  step "applying the local root application"
  k apply -f infra/gitops/local-bootstrap/root-application.yaml >/dev/null

  # argocd CLI in core mode talks straight to the Application CRDs (ADR-0201) and
  # derives its namespace from the kube-context, so it runs against a throwaway
  # kubeconfig rather than mutating the user's.
  local kubeconfig
  kubeconfig="$(mktemp)"
  # shellcheck disable=SC2064  # expand the path now, not at trap time
  trap "rm -f '$kubeconfig'" RETURN
  k config view --minify --flatten >"$kubeconfig"
  kubectl --kubeconfig "$kubeconfig" config set-context --current --namespace argocd >/dev/null
  ac() { KUBECONFIG="$kubeconfig" argocd --core "$@"; }

  # `cluster:stop` freezes a sync mid-flight; on resume the controller reuses the task plan it computed then, which can never converge against changed manifests.
  # `argocd app wait` reports only that it timed out, so the reason lives in pod events nothing prints.
  dump_unhealthy() {
    local app ns
    warn "applications that did not reach Synced + Healthy:"
    ac app list -o wide 2>/dev/null |
      awk 'NR==1 || $2!="Synced" || $3!="Healthy"' | sed 's/^/    /' >&2 || true
    # Pod-level detail for the namespaces those applications own. A CrashLoop, a
    # failed mount and an unschedulable pod are three different fixes and the app
    # status calls all three "Progressing".
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

  wait_apps() {
    local timeout="$1" app
    shift
    ac app wait "$@" --sync --health --operation --timeout "$timeout" && return 0
    warn "[$*] did not converge in ${timeout}s — terminating their operations (likely stale from a cluster:stop) and re-syncing"
    for app in "$@"; do ac app terminate-op "$app" || true; done
    for app in "$@"; do ac app sync "$app" --timeout "$timeout"; done
    # Half the budget on the retry: the first wait already proved the set does not settle on its own.
    ac app wait "$@" --sync --health --operation --timeout "$((timeout / 2))" && return 0
    dump_unhealthy
    fail "ArgoCD did not converge. The applications and pod events above are the reason; \`kubectl --context $(cluster_ctx) -n <ns> describe pod <pod>\` has the rest."
  }

  step "waiting for ArgoCD to converge (first run is slow)"
  wait_apps 600 local-root
  # Appset generation lags appset sync, so the set is re-listed until stable.
  local apps
  while :; do
    apps="$(ac app list -o name)"
    # shellcheck disable=SC2086  # newline-separated names, intentional split
    # 900, not 1800. With the mirror warmed every image is a local pull, so an application that has not settled in fifteen minutes is stuck rather than slow.
    wait_apps 900 $apps
    [ "$(ac app list -o name)" = "$apps" ] && break
  done
  ok "all ArgoCD applications Synced + Healthy"
}

# Fill the in-cluster zot's catalogue with the first-party images (ADR-0105). Best-effort: no pod's start depends on it.
stage_populatezot() {
  bash "$(dirname "${BASH_SOURCE[0]}")/../populate-zot.sh" ||
    warn "populate-zot did not complete — the in-cluster zot console may be empty (non-fatal)"
}
