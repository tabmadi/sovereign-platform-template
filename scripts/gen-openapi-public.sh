#!/usr/bin/env bash
# Emit the developer-portal spec projections Scalar consumes — one merged document per portal, not a file per service (ADR-0303, ADR-0306).
set -euo pipefail

shopt -s nullglob

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

out_dir="apps/frontend/public/devportal/openapi"

# Resolve each operation's effective audience (op override → service default →
# cluster) onto the operation, so the merged document filters on one per-op label.
resolve='.info.x-audience as $svc | (.paths.[].[] | select(tag == "!!map")) |= (.x-audience = (.x-audience // $svc // "cluster"))'
# Deep-merge all documents into one (single emit; `*` collapses the identical shared
# components, replaces arrays last-wins).
merge='(. as $item ireduce ({}; . * $item))'
# Recursively drop every `x-` extension key at any depth (info, operations, schemas).
strip_ext='(.. | select(tag == "!!map")) |= with_entries(select(.key | test("^x-") | not))'
# Unify the merged document: one title, the flat server, and a tag list derived from
# the operations that remain (auto-pruning tags orphaned by the audience filter).
envelope='.openapi = "3.1.0"
  | .info = {"title": "API reference", "version": "1.0.0"}
  | .servers = [{"url": "/api"}]
  | .tags = ([.paths[][].tags // [] | .[]] | unique | map({"name": .}))'
drop_empty_paths='del(.paths.* | select(tag == "!!map" and length == 0))'
# Drop schemas no longer referenced once the audience filter has removed operations: an all-`cluster` service would otherwise leak its schemas into the merged components.
# `$refs` covers paths and the schemas themselves, so schema-to-schema references keep their targets.
prune_orphan_schemas='([.. | select(tag == "!!map" and has("$ref")) | .["$ref"]]) as $refs
  | .components.schemas |= with_entries(.key as $k | select($refs | any_c(. == "#/components/schemas/" + $k)))'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

resolved=()
for spec in services/*/openapi.yaml; do
  service=$(basename "$(dirname "$spec")")
  # _template is scaffolding, not a live service — never documented.
  [ "$service" = "_template" ] && continue
  yq "$resolve" "$spec" >"$tmp/${service}.yaml"
  resolved+=("$tmp/${service}.yaml")
done

rm -rf "$out_dir"
mkdir -p "$out_dir"

echo "→ dev portal projection (audience >= internal)"
yq ea -o=json "${merge}
  | del(.paths.*.* | select(tag == \"!!map\" and .x-audience == \"cluster\"))
  | ${drop_empty_paths} | ${prune_orphan_schemas} | ${envelope} | ${strip_ext}" \
  "${resolved[@]}" >"$out_dir/internal.json"

echo "→ public docs projection (audience == public)"
yq ea -o=json "${merge}
  | del(.paths.*.* | select(tag == \"!!map\" and .x-audience != \"public\"))
  | ${drop_empty_paths} | ${prune_orphan_schemas} | ${envelope} | ${strip_ext}" \
  "${resolved[@]}" >"$out_dir/public.json"

# Belt-and-suspenders: fail loudly if any x- extension survived into the output, so
# a future yq change can never silently reintroduce the editor warnings.
for out in "$out_dir"/*.json; do
  n=$(yq -o=json '[.. | select(tag == "!!map") | keys.[] | select(test("^x-"))] | length' "$out")
  if [ "$n" != "0" ]; then
    echo "✗ x- extension key leaked into ${out} (strip_ext failed)" >&2
    exit 1
  fi
done
