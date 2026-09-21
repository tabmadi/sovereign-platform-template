#!/usr/bin/env bash
# Sign a published image and attach its SBOM and provenance (ADR-0104).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=lib/loki-push.sh
source "$LIB/loki-push.sh"

IMAGE="${1:-}"
[ -n "$IMAGE" ] || fail "usage: mise run ci:sign -- <image>@sha256:<digest>"
case "$IMAGE" in
*@sha256:*) ;;
*) fail "refusing to sign a tag: pass an image by digest (ADR-0104). Got: ${IMAGE}" ;;
esac

PRIVATE="infra/auth/cosign/signing-key.enc.yaml"
[ -f "$PRIVATE" ] || fail "no signing key at ${PRIVATE} — run 'mise run secrets:cosign' once, at bootstrap"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"

step "decrypting the signing key"
sops -d "$PRIVATE" >"$work/secret.yaml"
yq -r '.stringData["cosign.key"]' "$work/secret.yaml" >"$work/cosign.key"
COSIGN_PASSWORD="$(yq -r '.stringData.COSIGN_PASSWORD' "$work/secret.yaml")"
export COSIGN_PASSWORD
rm -f "$work/secret.yaml"

# The cosign 2.x pin in .mise.toml is what keeps this flag available.
step "signing ${IMAGE}"
cosign sign --yes --tlog-upload=false --key "$work/cosign.key" "$IMAGE"

# A file, not a pipe: syft writes progress to stderr and the document to stdout, and
# a pipeline that swallows one loses the other's failure with it.
step "generating the SPDX SBOM"
syft "$IMAGE" -o "spdx-json=$work/sbom.spdx.json"

step "attaching the SBOM and the provenance"
cosign attest --yes --tlog-upload=false --key "$work/cosign.key" \
  --type spdxjson --predicate "$work/sbom.spdx.json" "$IMAGE"

# The predicate is assembled from the forge's environment: the builder is `docker/build-push-action`, and the claim recorded is this pipeline's.
# `startedOn` defaults to now: the predicate parses as a protobuf Timestamp, and "" is not one.
jq -n \
  --arg repo "${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-unknown}" \
  --arg sha "${GITHUB_SHA:-unknown}" \
  --arg ref "${GITHUB_REF:-unknown}" \
  --arg run "${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-unknown}/actions/runs/${GITHUB_RUN_ID:-0}" \
  --arg started "${BUILD_STARTED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}" \
  '{
     buildDefinition: {
       buildType: "https://github.com/actions/runner",
       externalParameters: { repository: $repo, ref: $ref },
       resolvedDependencies: [ { uri: $repo, digest: { gitCommit: $sha } } ]
     },
     runDetails: {
       builder: { id: $run },
       metadata: { invocationId: $run, startedOn: $started }
     }
   }' >"$work/provenance.json"

cosign attest --yes --tlog-upload=false --key "$work/cosign.key" \
  --type slsaprovenance1 --predicate "$work/provenance.json" "$IMAGE"

# Filed here, not as a separate step: the record claims "this digest was signed and attested", which is only true at this line.
# Labelled by `service` and `env` only — Loki builds one stream per label set, so a digest-keyed label would mint a stream per build.
# `env` is where the image was published from, not where it runs (ADR-0103).
step "filing the supply-chain record"
name="${IMAGE##*/}"
name="${name%@*}"
loki_push \
  "$(jq -cn --arg service "$name" --arg env "${SUPPLY_CHAIN_ENV:-dev}" \
    '{service: $service, env: $env, job: "supply-chain-build"}')" \
  "$(jq -cn \
    --arg image "${IMAGE%@*}" \
    --arg digest "${IMAGE##*@}" \
    --arg commit "${GITHUB_SHA:-unknown}" \
    --arg ref "${GITHUB_REF:-unknown}" \
    --arg run "${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-unknown}/actions/runs/${GITHUB_RUN_ID:-0}" \
    --arg signed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{event: "signed", image: $image, digest: $digest, commit: $commit, ref: $ref, run: $run, signed_at: $signed_at, sbom: true, provenance: true}')"

ok "signed, SBOM and provenance attached: ${IMAGE}"
