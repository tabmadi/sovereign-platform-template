#!/usr/bin/env bash
# Walk every image pinned in committed values, verify its SBOM attestation, and file what is in it (ADR-0104, ADR-0103).
set -euo pipefail

source "$(dirname "$0")/lib/log.sh"
source "$(dirname "$0")/lib/loki-push.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PUB_KEY="infra/auth/cosign/cosign.pub"
# The template commits an EMPTY cosign.pub (see scripts/secrets-cosign.sh), so a
# generated project that has not run the bootstrap has nothing to verify against.
# Say that once and stop, rather than reporting every image as unverifiable.
if [ ! -s "$PUB_KEY" ]; then
  # The template has no signing key: one here would be inherited by every generated project, with a private half no adopter can decrypt.
  # `copier.yml` is the discriminator — the template carries it, and `_exclude` drops it from everything generated.
  if [ -f copier.yml ]; then
    ok "no signing key, and none belongs here — the template publishes no environment images"
    exit 0
  fi
  fail "no public key at ${PUB_KEY} — run 'mise run secrets:cosign' once, at bootstrap"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Every values file that pins an image, and the environment it speaks for. `local`
# is skipped: it pins :local tags built on the developer's own machine, which are
# neither signed nor pushed anywhere an inventory could read them.
mapfile -t files < <(find infra/gitops/services -mindepth 3 -path '*/values/*.yaml' ! -path '*/local/*' | sort)
[ "${#files[@]}" -gt 0 ] || fail "no committed service values found under infra/gitops/services"

total=0
verified=0

for path in "${files[@]}"; do
  env="$(basename "$(dirname "$(dirname "$path")")")"

  # `.image.repository` + `.image.tag` is the shape every service values file uses.
  # A file may also pin a digest instead (prod does, ADR-0201), in which case the
  # tag is absent and `.image.digest` carries it.
  repo="$(yq -r '.image.repository // ""' "$path")"
  tag="$(yq -r '.image.tag // ""' "$path")"
  digest="$(yq -r '.image.digest // ""' "$path")"
  [ -n "$repo" ] || continue

  if [ -n "$digest" ]; then
    ref="${repo}@${digest}"
  elif [ -n "$tag" ]; then
    ref="${repo}:${tag}"
  else
    continue
  fi

  service="$(yq -r '.name // ""' "$path")"
  [ -n "$service" ] || service="$(basename "$path" .yaml)"
  total=$((total + 1))

  step "${env}/${service}: ${ref}"

  if cosign verify-attestation \
    --key "$PUB_KEY" \
    --type spdxjson \
    --insecure-ignore-tlog \
    "$ref" >"$work/att.json" 2>"$work/err.txt"; then

    # cosign prints one JSON envelope per attestation; the SPDX document is the
    # base64 payload's `.predicate`. `head -1` because a re-signed image carries
    # more than one envelope and they describe the same digest.
    packages="$(head -1 "$work/att.json" |
      jq -r '.payload' | base64 -d |
      jq -r '(.predicate.packages // []) | length')"
    resolved="$(head -1 "$work/att.json" |
      jq -r '.payload' | base64 -d |
      jq -r '.subject[0].digest["sha256"] // ""')"
    verified=$((verified + 1))
    detail "verified — ${packages} packages"
    line="$(jq -cn \
      --arg ref "$ref" --arg digest "sha256:${resolved}" \
      --argjson packages "${packages:-0}" \
      --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{event: "inventory", ref: $ref, digest: $digest, sbom_verified: true, packages: $packages, at: $at}')"
  else
    # A pinned image that does not verify is the finding, not an error to abort on: the walk's value is the whole picture.
    warn "attestation did NOT verify"
    detail "$(head -3 "$work/err.txt" | tr '\n' ' ')"
    line="$(jq -cn \
      --arg ref "$ref" \
      --arg reason "$(head -3 "$work/err.txt" | tr '\n' ' ')" \
      --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{event: "inventory", ref: $ref, sbom_verified: false, reason: $reason, at: $at}')"
  fi

  loki_push \
    "$(jq -cn --arg service "$service" --arg env "$env" \
      '{service: $service, env: $env, job: "supply-chain-inventory"}')" \
    "$line"
done

# Non-zero when something pinned cannot be verified. Reported as one line either way — a ✓ followed by a ✗ is a script arguing with itself.
if [ "$verified" -eq "$total" ]; then
  ok "inventory: all ${total} pinned images carry a verifiable SBOM"
else
  fail "inventory: $((total - verified)) of ${total} pinned images have no verifiable SBOM"
fi
