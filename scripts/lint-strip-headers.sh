#!/usr/bin/env bash
# Anti-spoofing gate, per ADR-0305: a forwardAuth IngressRoute must apply strip-identity-headers before it.
# So a client cannot inject X-User-*, X-Org-Id, or X-Roles.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

step "checking every forward-auth route strips identity headers first"
# Render the gateway and the per-service /api route, then give the manifests to the single-binary Go gate. The Go tool reads YAML from stdin.
{
  # Every manifest in infra/gateway, which the gateway Application applies from its directory source. So the gate reads what the cluster gets.
  # The separator keeps two files from parsing as one document.
  for manifest in infra/gateway/*.yaml; do
    echo '---'
    cat "$manifest"
  done
  echo '---'
  # The per-resource /api route from the chart template. Render it with ingress on and a resource declared, as real services do.
  # The route is flat: /api/<resource>, per ADR-0306.
  helm template svc infra/helm/service \
    --set name=svc --set image.repository=svc --set image.tag=dev \
    --set ingress.enabled=true --set ingress.host=example.com \
    --set 'ingress.resources={svc}'
} | go run ./tools/lint-strip-headers
