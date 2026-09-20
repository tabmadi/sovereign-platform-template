#!/usr/bin/env bash
# Generate the third-party image allow-list (ADR-0104).
set -euo pipefail

source "$(dirname "$0")/lib/log.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# `--check` regenerates into a scratch file and diffs, for CI. Same code path as
# the write, because a drift check that reimplements the generator checks the
# reimplementation.
CHECK=false
[ "${1:-}" != "--check" ] || CHECK=true

OUT="infra/gitops/platform/image-allowlist.yaml"
REFS_OUT="infra/local/image-refs.txt"
SHARED="infra/gitops/platform/shared-values.yaml"
# First-party repositories differ by environment — the local tier pulls from the local registry — so the list is per-environment.
ENV_NAME="local"

# Third-party images are collected across every environment: a chart gated off locally renders nothing here, and Kyverno still admits against it where the chart is enabled (ADR-0307).
ALL_ENVS="local dev staging prod"

# collect_images prints one image reference per line, from workload pod specs and from any `image`/`imageName`
# key anywhere — an operator building pods from a custom resource is invisible to a workload-only walk.
# The charset filter makes the generic pass safe: in a shipped CRD schema, `image` holds a field description.
collect_images() {
  local rendered
  rendered="$(cat)"

  {
    printf '%s' "$rendered" | yq -r '
      select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet"
          or .kind == "Job" or .kind == "ReplicaSet" or .kind == "Pod"
          or .kind == "CronJob")
      | [.spec.template.spec, .spec.jobTemplate.spec.template.spec, .spec]
      | .[] | select(. != null)
      | ((.containers // []) + (.initContainers // []) + (.ephemeralContainers // []))
      | .[] | .image // ""
    ' 2>/dev/null || true
    printf '%s' "$rendered" | yq -r '.. | select(has("imageName")) | .imageName' 2>/dev/null || true
    # A pod template inside a custom resource. Temporal's `WorkerDeployment` carries one, and no kind-based selector looks there.
    printf '%s' "$rendered" | yq -r '
      .. | select(has("template")) | .template.spec.containers // [] | .[] | .image // ""
    ' 2>/dev/null || true
    # An image inside a ConfigMap value: a controller that builds pods from a template it reads at runtime keeps that template as a string, which no structural walk reaches.
    printf '%s' "$rendered" | yq -r '
      select(.kind == "ConfigMap") | .data // {} | to_entries | .[] | .value
    ' 2>/dev/null | grep -oE '^[[:space:]]*image:[[:space:]]*\S+' |
      sed -E 's/^[[:space:]]*image:[[:space:]]*//' || true
    # Two shapes: one carrying a registry or namespace, and a bare Docker Hub official image such as `postgres:17-alpine`.
    # The bare form requires a tag, without which it matches any lower-case word.
  } | grep -E '^([a-z0-9][a-z0-9._-]*(:[0-9]+)?(/[a-z0-9._/-]+)+(:[A-Za-z0-9._-]+)?(@sha256:[a-f0-9]+)?|[a-z0-9][a-z0-9._-]*:[A-Za-z0-9._-]+)$' || true
}

# Chart.lock pins an exact version, so the answer is an exact filename. A chart with vendored dependencies has no lock, and there the committed tarball is the pin.
deps_satisfied() {
  local dir="$1" dep ver
  if [ -f "${dir}Chart.lock" ]; then
    while read -r dep ver; do
      [ -n "$dep" ] || continue
      [ -f "${dir}charts/${dep}-${ver}.tgz" ] || return 1
    done < <(yq -r '.dependencies[]? | .name + " " + .version' "${dir}Chart.lock" 2>/dev/null)
    return 0
  fi
  while read -r dep; do
    [ -n "$dep" ] || continue
    compgen -G "${dir}charts/${dep}-*.tgz" >/dev/null || return 1
  done < <(yq -r '.dependencies[]?.name' "${dir}Chart.yaml" 2>/dev/null)
  return 0
}

step "rendering every platform chart to collect its images"

images="$(mktemp)"
# The local environment's slice of the same render: what a local cluster will pull,
# and therefore what zot is warmed with.
local_images="$(mktemp)"
# The base tier's share of that slice. `cluster:up` warms the whole list today, so a
# base-tier bring-up fetches the observability stack, Temporal and Kyverno before
# starting a cluster that runs none of them.
base_images="$(mktemp)"
trap 'rm -f "$images" "$local_images" "$base_images"' EXIT

# Read from the stages that install them: a list here would be a second place to remember, and forgetting surfaces as a pod that cannot pull after the warm reported success.
base_stages="$(sed -n 's/^STAGES_base=(\(.*\))$/\1/p' scripts/cluster.sh)"
[ -n "$base_stages" ] || fail "cannot read STAGES_base from scripts/cluster.sh"
# The prelude runs for every tier, so its charts are base by definition.
prelude="$(sed -n 's/^PRELUDE=(\(.*\))$/\1/p' scripts/cluster.sh)"
base_charts=""
for stage in $prelude $base_stages; do
  base_charts+="$(sed -n "/^stage_${stage}()/,/^}/p" scripts/lib/cluster.sh |
    grep -oE 'infra/helm/platform/[a-z0-9-]+' | sed 's#.*/##' || true)"$'\n'
done
base_charts="$(printf '%s\n' "$base_charts" | grep -vE '^\s*$' | sort -u)"
[ -n "$base_charts" ] || fail "no base-tier charts found — the stage functions changed shape"
detail "base tier installs: $(printf '%s' "$base_charts" | tr '\n' ' ')"

for dir in infra/helm/platform/*/; do
  name="$(basename "$dir")"
  # A chart with no dependencies fetched yet renders nothing useful; the same
  # fallback cluster:up uses, for the same reason (a clean machine has no repos
  # registered, so `build` fails where `update` succeeds).
  if [ -f "${dir}Chart.yaml" ] && grep -q '^dependencies:' "${dir}Chart.yaml"; then
    # Only when the dependencies are not on disk: `helm dependency build` re-resolves the upstream index over the network every call, 165s of this task's 224s.
    if ! deps_satisfied "$dir"; then
      helm dependency build "$dir" >/dev/null 2>&1 ||
        helm dependency update "$dir" >/dev/null 2>&1 || true
    fi
  fi
  # `|| true`: the allow-list is a union, and a missing entry surfaces as a rejected pod rather than a silent hole.
  # The same fileParameters the ApplicationSets pass, relative to the chart — without them a template gated on one renders nothing and its image is missing.
  for env in $ALL_ENVS; do
    env_values="infra/gitops/platform/${env}/values.yaml"
    [ -f "$env_values" ] || continue
    rendered_images="$(helm template "$name" "$dir" -f "$SHARED" -f "$env_values" \
      --set-file "seed.model=infra/auth/openfga/model.json" \
      --set-file "policies.publicKey=infra/auth/cosign/cosign.pub" \
      --set-file 'kratos.kratos.identitySchemas.user\.v1\.json=infra/auth/kratos/identity-schemas/user.v1.json' \
      --set-file "oathkeeper.oathkeeper.accessRules=infra/auth/oathkeeper/access-rules.json" \
      2>/dev/null | collect_images || true)"
    printf '%s\n' "$rendered_images" >>"$images"
    if [ "$env" = "$ENV_NAME" ]; then
      printf '%s\n' "$rendered_images" >>"$local_images"
      # An image a base chart renders is warmed by every tier, even when a full-tier
      # chart renders it too: the earliest need wins, and a second entry would only
      # delay it.
      if printf '%s\n' "$base_charts" | grep -qx "$name"; then
        printf '%s\n' "$rendered_images" >>"$base_images"
      fi
    fi
  done
done

# The local stand-ins are plain manifests, not charts, and so are invisible to the loop above (infra/local/deps.yaml, ADR-0600).
# `base`, because the base tier applies the Postgres slice and nothing here belongs to the full tier alone.
for manifest in infra/local/deps.yaml infra/local/mock.yaml; do
  [ -f "$manifest" ] || continue
  local_stand_ins="$(collect_images <"$manifest" || true)"
  printf '%s\n' "$local_stand_ins" >>"$images"
  printf '%s\n' "$local_stand_ins" >>"$local_images"
  printf '%s\n' "$local_stand_ins" >>"$base_images"
done

# Once per service with that service's values, as the ApplicationSet renders it. A default render names one placeholder repository and misses every real `<registry>/<service>-server`.
for values in infra/gitops/services/"$ENV_NAME"/values/*.yaml; do
  [ -f "$values" ] || continue
  helm template "$(basename "$values" .yaml)" infra/helm/service \
    -f "$SHARED" -f "$values" 2>/dev/null |
    collect_images >>"$images" || true
done

target="$OUT"
if [ "$CHECK" = true ]; then
  target="$(mktemp)"
  step "checking ${OUT} is current"
else
  step "writing ${OUT}"
fi

# A trailing `:<tag>` counts only after the last `/` — `registry:5000/repo` is a port.
# `LC_ALL=C sort` for byte order, so the generated order is the same for everyone.
{
  cat <<'HEADER'
# GENERATED by `mise run gen:image-allowlist` — do not edit.
# Every image repository the platform's charts pull from (ADR-0104); Kyverno rejects anything else, and a new
# entry is a registry this platform has never used. Repositories, not references: the digest is pinned elsewhere.
policies:
  allowedImageSources:
HEADER
  sed -E 's/@sha256:.*$//; s/(:[^:/]+)$//' "$images" |
    grep -vE '^\s*$' | LC_ALL=C sort -u | sed 's/^/    - /'
} >"$target"

# Third-party only: the build stage pushes first-party images straight to the registry, and asking the mirror to fetch them from an upstream that never held them fails.
refs_target="$REFS_OUT"
[ "$CHECK" = false ] || refs_target="$(mktemp)"
{
  cat <<'HEADER'
# GENERATED by `mise run gen:image-allowlist` — do not edit.
#
# Every third-party image a LOCAL cluster pulls, as a full reference. `cluster:up`
# warms zot with this list before it creates the cluster (ADR-0105): the mirror
# fetches each image once, sequentially, with no pod waiting on it.
#
# The first column is the earliest tier that needs the image. `base` is warmed by
# every tier; `full` only by the full tier, which is the only one that runs ArgoCD
# and everything it deploys. One file rather than two, because the set is one
# decision and a second list is a second thing to keep in step.
HEADER
  # `join` needs both sides sorted, and `comm` splits them into "base" and "the rest"
  # in one pass.
  base_sorted="$(mktemp)"
  all_sorted="$(mktemp)"
  grep -vE '^registry\.localhost:5000/' "$base_images" | grep -vE '^\s*$' |
    LC_ALL=C sort -u >"$base_sorted"
  grep -vE '^registry\.localhost:5000/' "$local_images" | grep -vE '^\s*$' |
    LC_ALL=C sort -u >"$all_sorted"
  LC_ALL=C comm -12 "$all_sorted" "$base_sorted" | sed 's/^/base /'
  LC_ALL=C comm -23 "$all_sorted" "$base_sorted" | sed 's/^/full /'
  rm -f "$base_sorted" "$all_sorted"
} >"$refs_target"

if [ "$CHECK" = true ]; then
  if ! diff -u "$REFS_OUT" "$refs_target" >/dev/null 2>&1; then
    printf '✗ %s is stale — run `mise run gen:image-allowlist`\n' "$REFS_OUT" >&2
    diff -u "$REFS_OUT" "$refs_target" >&2 || true
    rm -f "$target" "$refs_target"
    exit 1
  fi
  rm -f "$refs_target"
  if ! diff -u "$OUT" "$target" >/dev/null 2>&1; then
    printf '✗ %s is stale — run `mise run gen:image-allowlist`\n' "$OUT" >&2
    diff -u "$OUT" "$target" >&2 || true
    rm -f "$target"
    exit 1
  fi
  rm -f "$target"
  ok "${OUT} and ${REFS_OUT} match what the charts render"
  exit 0
fi

ok "$(grep -c '^    - ' "$OUT") image repositories in ${OUT}"
ok "$(grep -cvE '^#|^$' "$REFS_OUT") image references in ${REFS_OUT}"
