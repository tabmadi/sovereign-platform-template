#!/bin/sh
# Seed the first operator of an environment, per ADR-0304. The Job in templates/first-operator.yaml runs it.
# It writes the same three facts as the admin console: the Kratos identity with the operator claim, its org, and group:operator.
set -eu

KRATOS="${KRATOS_ADMIN_URL:-http://ory-kratos-admin.platform.svc.cluster.local}"
OPENFGA="${OPENFGA_URL:-http://openfga.platform.svc.cluster.local:8080}"
ORGS="${ORGS_URL:-http://orgs-server.platform.svc.cluster.local}"
CREDENTIAL_DIR="${CREDENTIAL_DIR:-/first-operator}"
SECRET_WAIT="${SECRET_WAIT_SECONDS:-120}"
WAIT="${WAIT_SECONDS:-300}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The sops-operator can render the Secret after this pod starts, and the kubelet then fills the optional volume.
n=0
until [ -s "$CREDENTIAL_DIR/email" ] && [ -s "$CREDENTIAL_DIR/password" ]; do
  if [ "$n" -ge "$SECRET_WAIT" ]; then
    echo "no first-operator Secret in this environment. Nothing to seed"
    exit 0
  fi
  n=$((n + 2))
  sleep 2
done
EMAIL="$(cat "$CREDENTIAL_DIR/email")"
PASSWORD="$(cat "$CREDENTIAL_DIR/password")"

wait_for() { # <label> <url>
  n=0
  until curl -sf -o /dev/null "$2"; do
    if [ "$n" -ge "$WAIT" ]; then
      echo "ERROR $1 did not answer in ${WAIT}s" >&2
      exit 1
    fi
    n=$((n + 2))
    sleep 2
  done
}

identity_for_email() {
  curl -sSf -G "$KRATOS/admin/identities" --data-urlencode "credentials_identifier=$EMAIL" |
    jq -c --arg e "$EMAIL" 'map(select(.traits.email == $e)) | .[0] // empty'
}

# Follows the `next` link of each page, so an operator on a later page still counts.
operator_exists() {
  url="$KRATOS/admin/identities?page_size=250"
  while [ -n "$url" ]; do
    curl -sSf -D "$work/headers" -o "$work/page" "$url"
    if jq -e 'any(.[]; .metadata_public.operator == true)' "$work/page" >/dev/null; then
      return 0
    fi
    next="$(tr -d '\r' <"$work/headers" | grep -i '^link:' | tr ',' '\n' | grep 'rel="next"' |
      sed -n 's/.*<\([^>]*\)>.*/\1/p' | head -n1)"
    case "$next" in
    "") url="" ;;
    http*) url="$next" ;;
    *) url="$KRATOS$next" ;;
    esac
  done
  return 1
}

# Kratos hashes the password on import and skips the sign-up flow. The address is imported as verified, so no mail is sent.
create_identity() {
  jq -n --arg e "$EMAIL" --arg p "$PASSWORD" '{
    schema_id: "user_v1",
    state: "active",
    traits: { email: $e },
    metadata_public: { operator: true },
    credentials: { password: { config: { password: $p } } },
    verifiable_addresses: [{ value: $e, via: "email", verified: true, status: "completed" }]
  }' >"$work/identity"
  curl -sSf -H 'Content-Type: application/json' -X POST "$KRATOS/admin/identities" -d @"$work/identity" | jq -r .id
}

# The import path runs no self-service flow, so the registration web_hook never fires. This call does the same work.
# The workflow id comes from the identity, so a second call is a no-op.
ensure_org() {
  n=0
  until curl -sf -o /dev/null -H 'Content-Type: application/json' -X POST "$ORGS/identity-created" \
    -d "$(jq -n --arg id "$1" --arg e "$EMAIL" '{identity_id: $id, email: $e}')"; do
    if [ "$n" -ge "$WAIT" ]; then
      echo "ERROR the orgs service did not accept the identity in ${WAIT}s" >&2
      exit 1
    fi
    n=$((n + 5))
    sleep 5
  done
  echo "org ensured for $EMAIL"
}

# The store comes from the openfga-seed Job, so this waits for it. Only the duplicate-write error is accepted.
ensure_grant() {
  if [ -z "${OPENFGA_KEY:-}" ]; then
    echo "no openfga-creds Secret. Skipping the group:operator grant"
    return 0
  fi
  n=0
  sid=""
  while [ -z "$sid" ]; do
    sid="$(curl -sS -H "Authorization: Bearer $OPENFGA_KEY" "$OPENFGA/stores" 2>/dev/null |
      jq -r '.stores[]? | select(.name == "platform") | .id' 2>/dev/null | head -n1)"
    [ -n "$sid" ] && break
    if [ "$n" -ge "$WAIT" ]; then
      echo "ERROR no OpenFGA store named platform in ${WAIT}s" >&2
      exit 1
    fi
    n=$((n + 5))
    sleep 5
  done
  code="$(curl -sS -o "$work/grant" -w '%{http_code}' -X POST "$OPENFGA/stores/$sid/write" \
    -H "Authorization: Bearer $OPENFGA_KEY" -H 'Content-Type: application/json' \
    -d "$(jq -n --arg u "user:$1" '{writes: {tuple_keys: [{user: $u, relation: "member", object: "group:operator"}]}}')")"
  if [ "$code" = "200" ]; then
    echo "group:operator granted to $EMAIL"
  elif grep -q 'already exist' "$work/grant"; then
    echo "group:operator already granted to $EMAIL"
  else
    echo "ERROR OpenFGA write failed, HTTP $code: $(cat "$work/grant")" >&2
    exit 1
  fi
}

wait_for "Kratos" "$KRATOS/admin/health/ready"

existing="$(identity_for_email)"
if [ -n "$existing" ]; then
  id="$(printf '%s' "$existing" | jq -r .id)"
  if [ "$(printf '%s' "$existing" | jq -r '.metadata_public.operator // false')" != "true" ]; then
    echo "ERROR $EMAIL is registered and is not an operator. Promote it with ops:grant, or choose another address" >&2
    exit 1
  fi
  echo "$EMAIL already exists as $id"
elif operator_exists; then
  echo "this environment already has an operator. Nothing to seed"
  exit 0
else
  id="$(create_identity)"
  echo "created $EMAIL as $id"
fi

ensure_org "$id"
ensure_grant "$id"
echo "the first operator is ready. The first login enrols a second factor"
