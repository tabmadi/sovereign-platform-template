#!/usr/bin/env bash
# Resolve a tag to the immutable index digest a values file pins to, reading the registry's own `Docker-Content-Digest` (ADR-0101, ADR-0104).
set -euo pipefail
# shellcheck source=lib/log.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

ref="${1:-}"
[[ -n "$ref" ]] || fail "usage: mise run image:digest -- <registry>/<repo>:<tag>"

case "$ref" in
*@sha256:*) fail "already digest-pinned: $ref" ;;
*:*)
  tag="${ref##*:}"
  name="${ref%:*}"
  ;;
*) fail "no tag in reference: $ref — a floating reference has nothing to pin" ;;
esac

case "$name" in
*/*/*)
  registry="${name%%/*}"
  repo="${name#*/}"
  ;;
*)
  registry="registry-1.docker.io"
  repo="library/${name}"
  ;;
esac

accept='application/vnd.oci.image.index.v1+json'
accept+=',application/vnd.docker.distribution.manifest.list.v2+json'
accept+=',application/vnd.oci.image.manifest.v1+json'
accept+=',application/vnd.docker.distribution.manifest.v2+json'

step "resolving ${ref}" >&2
digest="$(curl -fsSL -o /dev/null -D - -H "Accept: ${accept}" \
  "https://${registry}/v2/${repo}/manifests/${tag}" |
  tr -d '\r' | awk 'tolower($1) == "docker-content-digest:" { print $2 }')"

[[ -n "$digest" ]] || fail "registry returned no digest for ${ref}"
ok "${name}:${tag}@${digest}" >&2
printf '%s\n' "$digest"
