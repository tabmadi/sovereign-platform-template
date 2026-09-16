#!/usr/bin/env bash
# Generate the third-party image allow-list (ADR-0104).
#
#   mise run gen:image-allowlist            write both outputs
#   bash scripts/gen-image-allowlist.sh --check   drift-check them, for CI
#
# TWO outputs from one render, so they cannot disagree about what this platform
# pulls:
#
#   infra/gitops/platform/image-allowlist.yaml  repositories, for Kyverno (ADR-0104)
#   infra/local/image-refs.txt                  full references, for the local
#                                               cluster to warm zot from (ADR-0105)
#
# The render is slow — every chart, every environment — which is why the warm set is
# a committed file rather than something a bring-up derives. It is generated and
# drift-checked here, the same guarantee the allow-list has.
#
# ADR-0104 requires third-party images to be pinned by digest and ALLOW-LISTED. The
# list is the hard half: it is every image every upstream chart pulls, it changes on
# every chart bump, and a hand-maintained one is a list that is wrong the first time
# nobody notices a new sidecar.
#
# So it is derived from the charts themselves. Every platform chart is rendered the
# way ArgoCD renders it, every `image:` in the output is collected, and the
# REPOSITORIES (not the tags) become the list. A repository rather than a full
# reference because the digest is pinned separately, by lint:floating-tags on the
# values a human edits and by Kyverno on the pod spec a chart rendered — this list
# answers a different question: may this image be here at all.
#
# The output is a values fragment, reviewed as a diff. A new entry appearing in a
# chart bump is the review: someone has to look at a registry this platform has
# never pulled from before and say yes.
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
# The environment whose FIRST-PARTY image repositories the list carries. Those
# differ by environment — the local tier pulls them from the local registry where a
# deployed one pulls them from ghcr — so the list is per-environment by nature, and
# this is the one the template ships with.
ENV_NAME="local"

# Third-party images, though, are collected across EVERY environment's values, and
# that is not a refinement. A chart gated off in the local tier renders nothing
# here, so its image never reached the list — and the list is what Kyverno admits
# against, in the environment where the chart IS enabled. maddy is the case that
# showed it: production-only by decision (ADR-0307), and therefore invisible to a
# generator that reads one environment. The failure would have been an admission
# rejection in production for an image the platform ships on purpose.
ALL_ENVS="local dev staging prod"

# collect_images reads rendered YAML on stdin and prints one image reference per
# line, from two places.
#
# 1. WORKLOAD documents, by kind, reading their pod specs. Precise, and the only
#    place most images live.
# 2. Any `image` or `imageName` key anywhere in the document. This is the half that
#    catches an image reaching a pod through a CUSTOM RESOURCE rather than through a
#    pod spec — CNPG's `Cluster.spec.imageName` is the one that taught this: the
#    allow-list was generated without it, Kyverno rejected the operator's own
#    Postgres pod, and the failure surfaced as a PVC stuck WaitForFirstConsumer with
#    nothing in the operator's log. An operator that builds pods from a CR is exactly
#    the case a workload-only walk cannot see.
#
# The charset filter is what makes (2) safe: a chart that ships CRDs ships the
# Kubernetes API schema, where `image` is a field DESCRIPTION. "Container image
# name." is not a reference and does not survive the grep.
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
    # A pod template inside a CUSTOM RESOURCE. Temporal's `WorkerDeployment` carries
    # one, so every worker image lives here and nowhere a kind-based selector looks —
    # three of this platform's images, rejected by the allow-list they were missing
    # from. The generic walk is safe because of the charset filter below: a CRD ships
    # the Kubernetes schema, where `containers` is a property name and `image` holds
    # a sentence.
    printf '%s' "$rendered" | yq -r '
      .. | select(has("template")) | .template.spec.containers // [] | .[] | .image // ""
    ' 2>/dev/null || true
    # An image inside a ConfigMap VALUE. A controller that builds pods from a
    # template it reads at runtime keeps that template as a string, so no walk over
    # the document structure can reach it — the local-path provisioner's helper pod
    # is the case that taught this, and the failure is quiet: Kyverno rejects the
    # helper, the directory is never created, and the symptom is a PVC that stays
    # Pending with nothing in the provisioner's log naming a policy.
    #
    # Only `image:` keys, and only in ConfigMap data, so this reads the embedded
    # documents without treating every string in the chart as a candidate.
    printf '%s' "$rendered" | yq -r '
      select(.kind == "ConfigMap") | .data // {} | to_entries | .[] | .value
    ' 2>/dev/null | grep -oE '^[[:space:]]*image:[[:space:]]*\S+' |
      sed -E 's/^[[:space:]]*image:[[:space:]]*//' || true
    # Two shapes. The first has a namespace or a registry, so it carries at least one
    # `/`. The second is a bare Docker Hub official image — `postgres:17-alpine` — which
    # has neither, and which the first pattern therefore rejected: the local Postgres
    # stand-in every base bring-up applies was silently absent from the warm set.
    #
    # The bare form REQUIRES a tag. Without that it matches any lower-case word, and
    # this filter is the only thing standing between a stray string in a ConfigMap and
    # the allow-list Kyverno admits images against.
  } | grep -E '^([a-z0-9][a-z0-9._-]*(:[0-9]+)?(/[a-z0-9._/-]+)+(:[A-Za-z0-9._-]+)?(@sha256:[a-f0-9]+)?|[a-z0-9][a-z0-9._-]*:[A-Za-z0-9._-]+)$' || true
}

# Does charts/ already hold what this chart depends on?
#
# Chart.lock pins an exact version, so the answer is an exact filename. A chart
# whose dependencies are VENDORED has no lock — `.gitignore` carries an exception
# for exactly that, so ArgoCD can render it offline — and there the question is only
# whether each dependency is present, because the committed tarball IS the pin.
#
# A version that moved in Chart.lock leaves the old tarball on disk and the new one
# missing: a miss, and therefore a fetch, which is right.
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

# WHICH CHARTS THE BASE TIER INSTALLS, read from the stages that install them rather
# than listed here. A list would be a second place to remember, and the first symptom
# of forgetting is a pod that cannot pull — after the warm has already reported
# success. The stage functions name their chart directories, so they are the source.
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
    # Only when the dependencies are not already on disk. `helm dependency build`
    # re-resolves the upstream repository index over the network every time it is
    # called — 15s cold and still 6s against a populated charts/ — and this loop
    # calls it once per chart. Measured: 165s of `lint:image-allowlist`'s 224s, in a
    # task whose actual work (`helm template`) is 350ms a chart, and 98% of the wall
    # clock of `mise run check`.
    #
    # Chart.lock names what each chart needs; charts/ holds what it has. When those
    # agree there is nothing to fetch, and `helm template` resolves the subchart from
    # the tarball without any help.
    if ! deps_satisfied "$dir"; then
      helm dependency build "$dir" >/dev/null 2>&1 ||
        helm dependency update "$dir" >/dev/null 2>&1 || true
    fi
  fi
  # `|| true`: a chart that needs values this pass does not supply still contributes
  # whatever it did render. The allow-list is a union, and a missing entry surfaces
  # as a rejected pod rather than as a silent hole — Kyverno is the check, this is
  # its input.
  # The same fileParameters the ApplicationSets pass. Without them a template gated
  # on one of these values renders NOTHING and its image is missing from the list —
  # measured on the OpenFGA seed Job, which is gated on `seed.model` and pulls an
  # image no other template does. Kyverno then rejected the Job, the app never
  # became healthy, and the root app sat in its wave with no explanation.
  #
  # The paths are relative to the chart, as they are in the appsets. A chart that
  # does not declare the value ignores it.
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

# The local stand-ins, which are plain manifests rather than charts and so were
# invisible to the loop above: the ephemeral Postgres, Temporal and OpenFGA a service
# talks to on the inner loop (infra/local/deps.yaml, ADR-0600), and the Prism API mock
# (infra/local/mock.yaml). Every one of them is pulled by a kind node, which pulls
# only from the mirror — so leaving them out of the warm did not break anything, it
# just moved the fetch to the moment a pod was already waiting on it. That is the
# pile-up the warm stage exists to prevent.
#
# `base`, because the base tier applies the Postgres slice and nothing here belongs
# to the full tier alone.
for manifest in infra/local/deps.yaml infra/local/mock.yaml; do
  [ -f "$manifest" ] || continue
  local_stand_ins="$(collect_images <"$manifest" || true)"
  printf '%s\n' "$local_stand_ins" >>"$images"
  printf '%s\n' "$local_stand_ins" >>"$local_images"
  printf '%s\n' "$local_stand_ins" >>"$base_images"
done

# The service chart, once PER SERVICE with that service's values — the same way the
# services ApplicationSet renders it. Rendering it once with chart defaults gives
# one placeholder repository and misses every real one: the images are
# `<registry>/<service>-server`, so a five-service platform has ten repositories the
# default render never names. Kyverno then rejects every service Deployment, which
# is how this was found.
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

# Strip the tag or digest, leaving the repository. A trailing `:<tag>` only counts
# when it comes after the last `/` — `registry:5000/repo` is a port, not a tag.
#
# `LC_ALL=C sort`: byte order, so the generated order is the same for everyone. A
# locale that ignores punctuation orders `registry.localhost` before `reg.kyverno.io`
# and byte order does the reverse, which the drift check reads as staleness.
{
  cat <<'HEADER'
# GENERATED by `mise run gen:image-allowlist` — do not edit.
#
# Every image repository the platform's own charts pull from (ADR-0104). Kyverno
# rejects an image from anywhere else; a new entry here is a registry this platform
# has never used before, and the diff is the review.
#
# Repositories, not references: the DIGEST is pinned by lint:floating-tags on the
# values a human edits and by Kyverno on the pod spec a chart rendered. This list
# answers the other question — may this image be here at all.
policies:
  allowedImageSources:
HEADER
  sed -E 's/@sha256:.*$//; s/(:[^:/]+)$//' "$images" |
    grep -vE '^\s*$' | LC_ALL=C sort -u | sed 's/^/    - /'
} >"$target"

# The warm set: full references, third-party only. Images the platform builds itself
# are excluded — the build stage pushes them straight to the registry, and asking the
# mirror to fetch them from an upstream that never held them is what produced zot's
# `failed to sync image` noise for `admin:local`.
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
