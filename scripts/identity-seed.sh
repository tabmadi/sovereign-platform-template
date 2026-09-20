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

identities="$(bun --silent -e \
  'console.log(JSON.stringify((await import("./test/e2e/fixtures/identities.ts")).IDENTITIES))')"

step "seeding the committed test identities into Kratos"
k port-forward svc/ory-kratos-admin 4434:80 >/dev/null &
pf=$!
trap 'kill "$pf" 2>/dev/null || true' EXIT
sleep 3
admin="http://localhost:4434"

for i in $(seq 0 "$(($(jq length <<<"$identities") - 1))"); do
  id="$(jq -c ".[$i]" <<<"$identities")"
  email="$(jq -r .email <<<"$id")"
  existing="$(curl -fsS \
    "${admin}/admin/identities?credentials_identifier=$(jq -rn --arg e "$email" '$e|@uri')" |
    jq -r --arg e "$email" 'map(select(.traits.email == $e)) | .[0].id // empty')"
  if [ -n "$existing" ]; then
    detail "${email} already exists (${existing})"
    continue
  fi
  # Kratos hashes the password on import and does not run the sign-up policy, so committed deterministic credentials are fine.
  # The address is pre-verified, and the `operator` trait is the coarse ops-tier claim (ADR-0306).
  body="$(jq -n --argjson i "$id" '{
    schema_id: "user_v1",
    traits: { email: $i.email, operator: $i.operator },
    credentials: { password: { config: { password: $i.password } } },
    verifiable_addresses: [{ value: $i.email, via: "email", verified: true, status: "completed" }]
  }')"
  created="$(curl -fsS -H 'Content-Type: application/json' -X POST "${admin}/admin/identities" -d "$body" |
    jq -r .id)"
  detail "created ${email} (${created})"
done

# The import path runs no self-service flow, so the `after` web_hook never fires and the identity would have no org or X-Org-Id (ADR-0304).
# Idempotent twice over: the workflow id is derived from the identity, and the activities are re-runnable.
# Only where orgs is running — the inner-loop floor has no application services, and a seed that insisted would fail the tier.
if k get svc orgs-server >/dev/null 2>&1; then
  step "running the post-registration process for each identity"
  k port-forward svc/orgs-server 18093:80 >/dev/null 2>&1 &
  orgs_pf=$!
  trap 'kill "$pf" "${orgs_pf:-}" 2>/dev/null || true' EXIT
  sleep 3

  for i in $(seq 0 "$(($(jq length <<<"$identities") - 1))"); do
    id="$(jq -c ".[$i]" <<<"$identities")"
    email="$(jq -r .email <<<"$id")"
    identity_id="$(curl -fsS \
      "${admin}/admin/identities?credentials_identifier=$(jq -rn --arg e "$email" '$e|@uri')" |
      jq -r --arg e "$email" 'map(select(.traits.email == $e)) | .[0].id // empty')"
    [ -n "$identity_id" ] || continue
    curl -fsS -H 'Content-Type: application/json' -X POST "http://localhost:18093/identity-created" \
      -d "$(jq -n --arg id "$identity_id" --arg e "$email" '{identity_id: $id, email: $e}')" >/dev/null
    detail "post-registration process enqueued for ${email}"
  done
else
  detail "orgs is not running in this tier — seeded identities have no org yet"
fi

# The coarse ops gate is the `operator` trait (ADR-0306); group:operator membership feeds the fine gate and the admin console (ADR-0304, ADR-0401).
# Gated on the real platform OpenFGA: the inner-loop stand-in has no store to grant against.
if k get secret openfga-creds >/dev/null 2>&1; then
  step "granting group:operator membership in OpenFGA"
  k port-forward svc/openfga 18080:8080 >/dev/null 2>&1 &
  fga_pf=$!
  trap 'kill "$pf" "${orgs_pf:-}" "$fga_pf" 2>/dev/null || true' EXIT
  sk="$(k get secret openfga-creds -o jsonpath='{.data.preshared_key}' | base64 -d)"
  sleep 3
  sid="$(curl -fsS -H "Authorization: Bearer ${sk}" "http://localhost:18080/stores" |
    jq -r '.stores[] | select(.name=="platform") | .id' | head -n1)"
  if [ -n "$sid" ]; then
    for i in $(seq 0 "$(($(jq length <<<"$identities") - 1))"); do
      id="$(jq -c ".[$i]" <<<"$identities")"
      [ "$(jq -r '.operator // false' <<<"$id")" = "true" ] || continue
      email="$(jq -r .email <<<"$id")"
      identity_id="$(curl -fsS \
        "${admin}/admin/identities?credentials_identifier=$(jq -rn --arg e "$email" '$e|@uri')" |
        jq -r --arg e "$email" 'map(select(.traits.email == $e)) | .[0].id // empty')"
      [ -n "$identity_id" ] || continue
      # Idempotent across three answers: OpenFGA rejects a duplicate tuple with a 400. `-sS` without `-f` keeps the body, which separates that 400 from a real failure.
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
    done
  else
    detail "no OpenFGA store 'platform' — skipping the operator grant"
  fi
else
  detail "no openfga-creds secret — skipping the operator grant"
fi

ok "test identities present (credentials: test/e2e/fixtures/identities.ts)"
