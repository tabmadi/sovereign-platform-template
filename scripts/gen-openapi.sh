#!/usr/bin/env bash
# Regenerate Go servers/clients and TS clients from every service's OpenAPI spec.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

shopt -s nullglob

for spec in services/*/openapi.yaml; do
  service=$(basename "$(dirname "$spec")")
  go_out="libs/go/sdks/${service}"
  ts_out="libs/ts/sdks/${service}"
  # ogen package name must be a valid Go identifier (e.g. "_template" -> "template").
  pkg=$(printf '%s' "$service" | tr -cd '[:alnum:]')

  step "$service: Go SDK (ogen)"
  # `ogen --clean` overwrites and prunes orphans itself, and keeping the directory populated means a concurrent go/lint pass never sees it empty. `gen:clean` wipes it.
  mkdir -p "$go_out"
  ogen --target "$go_out" --package "$pkg" --clean "$spec"

  step "$service: TS client"
  mkdir -p "$ts_out"

  bun x openapi-typescript@7.13.0 "$spec" --output "$ts_out/index.d.ts"

  # A package.json, so the generated SDK is a real workspace package: a tsconfig path alias alone makes every import an undeclared dependency, which Biome rejects.
  cat >"$ts_out/package.json" <<JSON
{
  "name": "@sdks/${service}",
  "version": "0.0.0",
  "private": true,
  "description": "Generated TypeScript client types for ${service} (ADR-0303). Do not edit.",
  "type": "module",
  "exports": {
    ".": "./index.d.ts"
  },
  "types": "./index.d.ts"
}
JSON
done

# The block above wrote workspace manifests, and CI installs with `--frozen-lockfile`, which rejects a lockfile that does not know about them.
bun install >/dev/null 2>&1 || true
