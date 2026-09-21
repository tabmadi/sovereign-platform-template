#!/usr/bin/env bash
# Seed the committed deterministic test identities into Kratos (ADR-0601, ADR-0600).
set -euo pipefail

source "$(dirname "$0")/lib/log.sh"

CLUSTER="${CLUSTER:-platform}"
source "$(dirname "$0")/lib/cluster.sh"
NS="platform"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
k() { kubectl --context "$(cluster_ctx)" -n "$NS" "$@"; }

admin="http://localhost:4434"
identities="$(bun --silent -e \
  'console.log(JSON.stringify((await import("./test/e2e/fixtures/identities.ts")).IDENTITIES))')"

last_index() { echo "$(($(jq length <<<"$identities") - 1))"; }
identity_at() { jq -c ".[$1]" <<<"$identities"; }

identity_id_for() {
  curl -fsS "${admin}/admin/identities?credentials_identifier=$(jq -rn --arg e "$1" '$e|@uri')" |
    jq -r --arg e "$1" 'map(select(.traits.email == $e)) | .[0].id // empty'
}

# Kratos hashes the password on import and skips the sign-up policy, so committed credentials are fine (ADR-0306).
create_identity() {
  local body
  body="$(jq -n --argjson i "$1" '{
    schema_id: "user_v1",
    traits: { email: $i.email, operator: $i.operator },
    credentials: { password: { config: { password: $i.password } } },
    verifiable_addresses: [{ value: $i.email, via: "email", verified: true, status: "completed" }]
  }')"
  curl -fsS -H 'Content-Type: application/json' -X POST "${admin}/admin/identities" -d "$body" | jq -r .id
}

seed_identities() {
  local i id email existing created
  for i in $(seq 0 "$(last_index)"); do
    id="$(identity_at "$i")"
    email="$(jq -r .email <<<"$id")"
    existing="$(identity_id_for "$email")"
    if [ -n "$existing" ]; then
      detail "${email} already exists (${existing})"
      continue
    fi
    created="$(create_identity "$id")"
    detail "created ${email} (${created})"
  done
}

# The import path runs no self-service flow, so the `after` web_hook never fires and the identity would have no
# org or X-Org-Id (ADR-0304). The workflow id is derived from the identity, so a re-run is a no-op.
run_post_registration() {
  local i id email identity_id
  step "running the post-registration process for each identity"
  k port-forward svc/orgs-server 18093:80 >/dev/null 2>&1 &
  orgs_pf=$!
  trap 'kill "$pf" "${orgs_pf:-}" 2>/dev/null || true' EXIT
  sleep 3

  for i in $(seq 0 "$(last_index)"); do
    id="$(identity_at "$i")"
    email="$(jq -r .email <<<"$id")"
    identity_id="$(identity_id_for "$email")"
    [ -n "$identity_id" ] || continue
    curl -fsS -H 'Content-Type: application/json' -X POST "http://localhost:18093/identity-created" \
      -d "$(jq -n --arg id "$identity_id" --arg e "$email" '{identity_id: $id, email: $e}')" >/dev/null
    detail "post-registration process enqueued for ${email}"
  done
}

# OpenFGA rejects a duplicate tuple with a 400, so `-sS` without `-f` keeps the body that separates it from a real failure.
grant_operator() {
  local sid=$1 identity_id=$2 email=$3 resp code body
  resp="$(curl -sS -w '\n%{http_code}' -H "Authorization: Bearer ${sk}" \
    -H 'Content-Type: application/json' \
    -X POST "http://localhost:18080/stores/${sid}/write" \
    -d "$(jq -n --arg u "user:${identity_id}" \
      '{writes:{tuple_keys:[{user:$u,relation:"member",object:"group:operator"}]}}')")"
  code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  if [ "$code" = "200" ]; then
    detail "group:operator granted to ${email}"
  elif grep -q "already exist" <<<"$body"; then
    detail "group:operator already granted to ${email}"
  else
    echo "$body" >&2
    fail "OpenFGA write failed for ${email} (HTTP ${code})"
  fi
}

# group:operator membership feeds the optional fine gate and the admin console (ADR-0304, ADR-0401); the coarse
# gate is the `operator` trait set above.
grant_operator_membership() {
  local sid i id email identity_id
  step "granting group:operator membership in OpenFGA"
  k port-forward svc/openfga 18080:8080 >/dev/null 2>&1 &
  fga_pf=$!
  trap 'kill "$pf" "${orgs_pf:-}" "$fga_pf" 2>/dev/null || true' EXIT
  sk="$(k get secret openfga-creds -o jsonpath='{.data.preshared_key}' | base64 -d)"
  sleep 3
  sid="$(curl -fsS -H "Authorization: Bearer ${sk}" "http://localhost:18080/stores" |
    jq -r '.stores[] | select(.name=="platform") | .id' | head -n1)"
  if [ -z "$sid" ]; then
    detail "no OpenFGA store 'platform' — skipping the operator grant"
    return 0
  fi
  for i in $(seq 0 "$(last_index)"); do
    id="$(identity_at "$i")"
    [ "$(jq -r '.operator // false' <<<"$id")" = "true" ] || continue
    email="$(jq -r .email <<<"$id")"
    identity_id="$(identity_id_for "$email")"
    [ -n "$identity_id" ] || continue
    grant_operator "$sid" "$identity_id" "$email"
  done
}

step "seeding the committed test identities into Kratos"
k port-forward svc/ory-kratos-admin 4434:80 >/dev/null &
pf=$!
trap 'kill "$pf" 2>/dev/null || true' EXIT
sleep 3

seed_identities

# Only where orgs is running: a seed that insisted would fail the whole tier on a service it never claimed to run.
if k get svc orgs-server >/dev/null 2>&1; then
  run_post_registration
else
  detail "orgs is not running in this tier — seeded identities have no org yet"
fi

# Gated on the real platform OpenFGA: the inner-loop stand-in has no store to grant against.
if k get secret openfga-creds >/dev/null 2>&1; then
  grant_operator_membership
else
  detail "no openfga-creds secret — skipping the operator grant"
fi
