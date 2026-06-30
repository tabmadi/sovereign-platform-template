#!/usr/bin/env bash
# Anti-spoofing gate (ADR-0009, Phase 8). Every IngressRoute that authenticates
# via the Oathkeeper forwardAuth middleware MUST also apply strip-identity-headers
# BEFORE it, so a client cannot inject X-User-* / X-Org-Id / X-Roles on any route
# (anonymous routes especially). Fails CI if a forward-auth route is missing the
# strip, or applies it after forwardAuth.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

# Render the gateway + per-service /api route, then feed the manifests to the
# single-binary Go gate (no ambient Python). The Go tool reads YAML from stdin.
{
  kubectl kustomize infra/gateway
  echo '---'
  # The per-service /api route (chart template) — render with ingress on.
  helm template svc infra/helm/service \
    --set name=svc --set image.repository=svc --set image.tag=dev \
    --set ingress.enabled=true --set ingress.host=example.com
} | go run ./tools/lint-strip-headers
