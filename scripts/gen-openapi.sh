#!/usr/bin/env bash
# Regenerate Go servers and clients, and TS clients, from every service's OpenAPI spec.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

shopt -s nullglob

for spec in services/*/openapi.yaml; do
  service=$(basename "$(dirname "$spec")")
  go_out="libs/go/sdks/${service}"
  ts_out="libs/ts/sdks/${service}"
  # The ogen package name must be a valid Go identifier, for example `_template` becomes `template`.
  pkg=$(printf '%s' "$service" | tr -cd '[:alnum:]')

  step "$service: Go SDK with ogen"
  # `ogen --clean` overwrites and removes orphans itself. The directory stays full, so a concurrent go or lint pass never sees it empty.
  # `gen:clean` deletes it.
  mkdir -p "$go_out"
  ogen --target "$go_out" --package "$pkg" --clean "$spec"

  step "$service: TS client"
  mkdir -p "$ts_out"

  bun x openapi-typescript@7.13.0 "$spec" --output "$ts_out/index.d.ts"

  # A package.json makes the generated SDK a real workspace package.
  # With only a tsconfig path alias, every import is an undeclared dependency, which Biome rejects.
  cat >"$ts_out/package.json" <<JSON
{
  "name": "@sdks/${service}",
  "version": "0.0.0",
  "private": true,
  "description": "Generated TypeScript client types for ${service}, per ADR-0303. Do not edit.",
  "type": "module",
  "exports": {
    ".": "./index.d.ts"
  },
  "types": "./index.d.ts"
}
JSON
done

# The block above wrote workspace manifests. CI installs with `--frozen-lockfile`, which rejects a lockfile that does not know them.
bun install >/dev/null 2>&1 || true
