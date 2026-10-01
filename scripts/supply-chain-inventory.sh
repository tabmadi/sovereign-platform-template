#!/usr/bin/env bash
# Walk every image pinned in committed values, verify its SBOM attestation, and record its contents, per ADR-0104 and ADR-0103.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=lib/loki-push.sh
source "$LIB/loki-push.sh"

PUB_KEY="infra/auth/cosign/cosign.pub"
# The template commits an empty cosign.pub, see scripts/secrets-cosign.sh. A project that has not run the bootstrap has nothing to verify against.
# Report that once and stop, instead of reporting every image as unverifiable.
if [ ! -s "$PUB_KEY" ]; then
  # The template has no signing key: every generated project would inherit it, with a private half that no adopter can decrypt.
  # `copier.yml` tells them apart: the template has it, and `_exclude` drops it from every generated project.
  if [ -f copier.yml ]; then
    ok "no signing key, and none belongs here. The template publishes no environment images"
    exit 0
  fi
  fail "no public key at ${PUB_KEY}. Run 'mise run secrets:cosign' once, at bootstrap"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Every values file that pins an image, and its environment. `local` is skipped: it pins :local tags built on the developer's machine.
# Those are not signed and not pushed anywhere an inventory can read them.
mapfile -t files < <(find infra/gitops/services -mindepth 3 -path '*/values/*.yaml' ! -path '*/local/*' | sort)
[ "${#files[@]}" -gt 0 ] || fail "no committed service values found under infra/gitops/services"

total=0
verified=0

for path in "${files[@]}"; do
  env="$(basename "$(dirname "$(dirname "$path")")")"

  # `.image.repository` and `.image.tag` are the shape that every service values file uses.
  # A file can pin a digest instead, as prod does, per ADR-0201. Then the tag is absent and `.image.digest` holds it.
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
  # The committed placeholder names no image: an environment with no promotion yet has nothing to verify.
  if [ -z "$digest" ] && [ "$tag" = "0000000000000000000000000000000000000000" ]; then
    detail "${env}/${service}: not yet promoted"
    continue
  fi
  total=$((total + 1))

  step "${env}/${service}: ${ref}"

  if cosign verify-attestation \
    --key "$PUB_KEY" \
    --type spdxjson \
    --insecure-ignore-tlog \
    "$ref" >"$work/att.json" 2>"$work/err.txt"; then

    # cosign prints one JSON envelope for each attestation, and the SPDX document is the `.predicate` of the base64 payload.
    # `head -1`, because a re-signed image has more than one envelope, and they describe the same digest.
    packages="$(head -1 "$work/att.json" |
      jq -r '.payload' | base64 -d |
      jq -r '(.predicate.packages // []) | length')"
    resolved="$(head -1 "$work/att.json" |
      jq -r '.payload' | base64 -d |
      jq -r '.subject[0].digest["sha256"] // ""')"
    verified=$((verified + 1))
    detail "verified, ${packages} packages"
    line="$(jq -cn \
      --arg ref "$ref" --arg digest "sha256:${resolved}" \
      --argjson packages "${packages:-0}" \
      --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{event: "inventory", ref: $ref, digest: $digest, sbom_verified: true, packages: $packages, at: $at}')"
  else
    # A pinned image that does not verify is the finding, not a reason to stop. The walk is useful for the whole picture.
    warn "attestation did not verify"
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

# Non-zero when something pinned cannot be verified. One line is reported in both cases, because a ✓ followed by a ✗ contradicts itself.
if [ "$verified" -eq "$total" ]; then
  ok "inventory: all ${total} pinned images carry a verifiable SBOM"
else
  fail "inventory: $((total - verified)) of ${total} pinned images have no verifiable SBOM"
fi
