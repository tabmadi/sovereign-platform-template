#!/usr/bin/env bash
# The route allowlist gate, per ADR-0305. A limited caller uses only operations that the spec marks `x-audience: cluster`.
# No allow on the whole port may hide the rule.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

step "checking the route allowlists of services"

problems=()
checked=0

for file in infra/gitops/services/*/values/*.yaml; do
  svc="$(basename "$file" .yaml)"
  env="$(basename "$(dirname "$(dirname "$file")")")"
  [ "$(yq '.networkPolicy.allowFromRoutes | length' "$file")" != 0 ] || continue
  checked=$((checked + 1))

  spec="services/${svc}/openapi.yaml"
  if [ ! -f "$spec" ]; then
    problems+=("${env}/${svc}: allowFromRoutes needs ${spec}, which does not exist")
    continue
  fi

  # A path parameter is any one segment, the same as the regular expression in the values.
  cluster="$(yq -o=json '.paths' "$spec" | jq -r '
    to_entries[] | .key as $path | .value | to_entries[]
    | select((.value | type) == "object" and .value["x-audience"] == "cluster")
    | "\(.key | ascii_upcase) \($path | gsub("\\{[^}]+\\}"; "[^/]+"))"')"

  while IFS= read -r route; do
    grep -qxF "$route" <<<"$cluster" ||
      problems+=("${env}/${svc}: '${route}' is not an x-audience: cluster operation in ${spec}")
  done < <(yq -o=json '.networkPolicy.allowFromRoutes[] | .name as $n | .routes[] | "\(.method) \(.path)"' "$file" | jq -r '.')

  while IFS= read -r caller; do
    yq -e ".networkPolicy.allowFrom | contains([\"${caller}\"])" "$file" >/dev/null 2>&1 &&
      problems+=("${env}/${svc}: '${caller}' is in allowFrom and allowFromRoutes. The allow on the whole port hides the routes")
  done < <(yq '.networkPolicy.allowFromRoutes[].name' "$file")
done

if [ "${#problems[@]}" -gt 0 ]; then
  printf '  · %s\n' "${problems[@]}" >&2
  fail "fix the allowlists above"
fi
ok "${checked} route allowlist(s) use only cluster operations"
