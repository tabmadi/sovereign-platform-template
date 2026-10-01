#!/usr/bin/env bash
# Emit the developer-portal spec projections that Scalar reads, per ADR-0303 and ADR-0306.
# One merged document for each portal, not a file for each service.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

shopt -s nullglob

out_dir="apps/frontend/public/devportal/openapi"

# Resolve each operation's effective audience onto the operation: the op override, then the service default, then cluster.
# The merged document then filters on one label for each op.
resolve='.info.x-audience as $svc | (.paths.[].[] | select(tag == "!!map")) |= (.x-audience = (.x-audience // $svc // "cluster"))'
# Deep-merge all documents into one, in one emit. `*` collapses the identical shared components, and for arrays the last one wins.
merge='(. as $item ireduce ({}; . * $item))'
# Drop every `x-` extension key at any depth: info, operations, and schemas.
strip_ext='(.. | select(tag == "!!map")) |= with_entries(select(.key | test("^x-") | not))'
# Unify the merged document: one title, the flat server, and a tag list from the remaining operations.
# This removes the tags that the audience filter leaves with no operation.
envelope='.openapi = "3.1.0"
  | .info = {"title": "API reference", "version": "1.0.0"}
  | .servers = [{"url": "/api"}]
  | .tags = ([.paths[][].tags // [] | .[]] | unique | map({"name": .}))'
drop_empty_paths='del(.paths.* | select(tag == "!!map" and length == 0))'
# Drop the schemas that nothing references after the audience filter removes operations.
# Otherwise an all-`cluster` service leaks its schemas into the merged components. `$refs` covers paths and schemas, so schema references keep their targets.
prune_orphan_schemas='([.. | select(tag == "!!map" and has("$ref")) | .["$ref"]]) as $refs
  | .components.schemas |= with_entries(.key as $k | select($refs | any_c(. == "#/components/schemas/" + $k)))'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

resolved=()
for spec in services/*/openapi.yaml; do
  service=$(basename "$(dirname "$spec")")
  # _template is scaffolding, not a live service, so it is never documented.
  [ "$service" = "_template" ] && continue
  yq "$resolve" "$spec" >"$tmp/${service}.yaml"
  resolved+=("$tmp/${service}.yaml")
done

rm -rf "$out_dir"
mkdir -p "$out_dir"

step "dev portal projection, audience >= internal"
yq ea -o=json "${merge}
  | del(.paths.*.* | select(tag == \"!!map\" and .x-audience == \"cluster\"))
  | ${drop_empty_paths} | ${prune_orphan_schemas} | ${envelope} | ${strip_ext}" \
  "${resolved[@]}" >"$out_dir/internal.json"

step "public docs projection, audience == public"
yq ea -o=json "${merge}
  | del(.paths.*.* | select(tag == \"!!map\" and .x-audience != \"public\"))
  | ${drop_empty_paths} | ${prune_orphan_schemas} | ${envelope} | ${strip_ext}" \
  "${resolved[@]}" >"$out_dir/public.json"

# A second check: fail if any x- extension is in the output, so a future yq change cannot bring back the editor warnings.
for out in "$out_dir"/*.json; do
  n=$(yq -o=json '[.. | select(tag == "!!map") | keys.[] | select(test("^x-"))] | length' "$out")
  if [ "$n" != "0" ]; then
    fail "x- extension key leaked into ${out}. strip_ext failed"
  fi
done
