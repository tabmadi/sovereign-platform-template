#!/usr/bin/env bash
# Check that a tier is up and serving, per ADR-0600 and ADR-0601. It reports every failure, not only the first.
# Without VERIFY_HOST it checks the active local tier. With it, it checks the deployed environment at that host through the current kubectl context.
# There it also runs what the e2e suite cannot run: a purchase, the escalation probe, and mail.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=lib/cluster.sh
source "$LIB/cluster.sh"

HOST="${VERIFY_HOST:-}"
if [ -n "$HOST" ]; then
  kc() { kubectl "$@"; }
  base="https://${HOST}"
  ops() { printf 'https://%s.ops.%s/' "$1" "$HOST"; }
  tls=()
else
  require_cluster
  kc() { k "$@"; }
  base="https://${DOMAIN}:8443"
  ops() { printf 'https://%s.ops.%s:8443/' "$1" "$DOMAIN"; }
  # The local wildcard is self-signed.
  tls=(-k)
fi

failed=0
miss() {
  warn "$1: $2"
  failed=$((failed + 1))
}
expect() { # <label> <want> <got>
  if [ "$2" = "$3" ]; then ok "$1"; else miss "$1" "want ${2:-nothing}, got ${3:-nothing}"; fi
}
# Reached directly, because a workstation proxy would answer for the edge.
edge() { curl -s --noproxy '*' --max-time 20 "${tls[@]}" "$@"; }
code() { edge -o /dev/null -w '%{http_code}' "$@"; }
has() { kc -n "$NS" get "$@" >/dev/null 2>&1; }

pids=()
work="$(mktemp -d)"
cleanups=()
cleanup() {
  local c
  for c in "${cleanups[@]}"; do eval "$c"; done
  kill "${pids[@]}" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT
forward() { # <service> <local-port> <remote-port>
  kc -n "$NS" port-forward "svc/$1" "$2:$3" >/dev/null 2>&1 &
  pids+=("$!")
  local _
  for _ in $(seq 1 40); do
    curl -s --noproxy '*' -o /dev/null "http://127.0.0.1:$2/" && return 0
    sleep 0.5
  done
  miss "port-forward ${1}" "unreachable"
  return 1
}

step "platform"
expect "nodes Ready" 0 "$(kc get nodes --no-headers | awk '$2 != "Ready"' | wc -l | tr -d ' ')"
expect "pods not ready" 0 "$(kc get pods -A --no-headers |
  awk '$4 != "Completed" {split($3, a, "/"); if (a[1] != a[2] || $4 != "Running") n++} END {print n+0}')"
if kc get ns argocd >/dev/null 2>&1; then
  expect "Argo CD applications Synced and Healthy" 0 \
    "$(kc -n argocd get applications --no-headers 2>/dev/null | awk '$2 != "Synced" || $3 != "Healthy"' | wc -l | tr -d ' ')"
fi
if kc get crd certificates.cert-manager.io >/dev/null 2>&1; then
  expect "certificates Ready" 0 "$(kc get certificates -A --no-headers | awk '$3 != "True"' | wc -l | tr -d ' ')"
fi
if has clusters.postgresql.cnpg.io postgres; then
  expect "Postgres cluster" "Cluster in healthy state" \
    "$(kc -n "$NS" get clusters.postgresql.cnpg.io postgres -o jsonpath='{.status.phase}')"
fi

step "edge"
storefront="$(code "${base}/")"
case "$storefront" in
2?? | 3??) ok "storefront answers, ${storefront}" ;;
*) miss "storefront" "answered ${storefront:-nothing}" ;;
esac
if has svc catalog-server; then
  expect "catalog, public" 200 "$(code "${base}/api/products")"
fi
for api in orders orgs charges; do
  has svc "${api/charges/payment}-server" || continue
  expect "/api/${api} without a session" 401 "$(code "${base}/api/${api}")"
done
# Every ops route whose backend exists. A route to an absent component is intended, see infra/gateway/ingressroutes.yaml.
while read -r tool svc ns; do
  kc -n "$ns" get svc "$svc" >/dev/null 2>&1 || continue
  expect "${tool}.ops without a session" 401 "$(code "$(ops "$tool")")"
done < <(kc -n "$NS" get ingressroutes.traefik.io -o json 2>/dev/null |
  jq -r --arg ns "$NS" '.items[] | select(.metadata.name | startswith("ops-")) | .spec.routes[0].services[0] as $s |
    "\(.metadata.name | ltrimstr("ops-")) \($s.name) \($s.namespace // $ns)"')
if [ -n "$HOST" ] && has ingressroutes.traefik.io registry; then
  expect "registry without credentials" 401 "$(code "https://registry.${HOST}/v2/")"
fi

if has svc prometheus; then
  step "telemetry"
  if forward prometheus 19090 9090; then
    expect "scrape targets down" 0 "$(curl -s --noproxy '*' 'http://127.0.0.1:19090/api/v1/query?query=count(up%3D%3D0)' |
      jq -r '.data.result[0].value[1] // "0"')"
  fi
  if has svc alertmanager && forward alertmanager 19093 9093; then
    expect "alerts firing" "" "$(curl -s --noproxy '*' 'http://127.0.0.1:19093/api/v2/alerts?active=true&silenced=false&inhibited=false' |
      jq -r '[.[] | .labels.alertname | select(. != "Watchdog" and . != "InfoInhibitor")] | unique | join(", ")')"
  fi
fi

if has clusters.postgresql.cnpg.io postgres &&
  [ "$(kc -n "$NS" get clusters.postgresql.cnpg.io postgres -o jsonpath='{.spec.backup}')" != "" ]; then
  step "backups"
  expect "WAL archiving" True "$(kc -n "$NS" get clusters.postgresql.cnpg.io postgres \
    -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}')"
  if [ -n "$HOST" ]; then
    # A deployed environment is judged by its schedule's output, never by a backup that this run adds.
    last="$(kc -n "$NS" get clusters.postgresql.cnpg.io postgres -o jsonpath='{.status.lastSuccessfulBackup}')"
    age=$(($(date +%s) - $(date -d "${last:-1970-01-01T00:00:00Z}" +%s)))
    if [ "$age" -lt 129600 ]; then ok "a base backup within 36h"; else miss "base backup" "last one ${last:-never}"; fi
  else
    # A backup setting that is on but never used is configuration, not coverage.
    name="verify-$(date +%s)"
    kc -n "$NS" apply -f - >/dev/null <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: ${name}
  namespace: ${NS}
spec:
  cluster:
    name: postgres
EOF
    cleanups+=("kc -n '$NS' delete backup '$name' --ignore-not-found >/dev/null")
    phase=""
    for _ in $(seq 1 150); do
      phase="$(kc -n "$NS" get backup "$name" -o jsonpath='{.status.phase}' 2>/dev/null)"
      [ "$phase" = completed ] && break
      sleep 2
    done
    expect "a base backup completes" completed "$phase"
  fi
fi

if [ -n "$HOST" ] && has svc catalog-server && has svc ory-kratos-admin; then
  step "purchase, through every service"
  forward catalog-server 18091 80
  forward ory-kratos-admin 14434 80
  product="$(curl -s --noproxy '*' -X POST -H 'x-user-id: admin-console' -H 'Content-Type: application/json' \
    -d "{\"name\":\"verify-$(date +%s)\",\"price\":{\"amount\":\"1.00\",\"currency\":\"EUR\"}}" \
    http://127.0.0.1:18091/products | jq -r '.id // ""')"
  if [ -n "$product" ]; then
    ok "catalog created a product"
    cleanups+=("curl -s --noproxy '*' -o /dev/null -X DELETE -H 'x-user-id: admin-console' http://127.0.0.1:18091/products/${product}")
  else
    miss "catalog" "no product id"
  fi

  # Throwaway identities: the committed e2e identities never reach a deployed environment.
  shopper="verify-$(date +%s)@example.com"
  probe="verify-probe-$(date +%s)@example.com"
  for e in "$shopper" "$probe"; do
    cleanups+=("for i in \$(curl -s --noproxy '*' 'http://127.0.0.1:14434/admin/identities?credentials_identifier=${e}' | jq -r '.[].id'); do curl -s --noproxy '*' -o /dev/null -X DELETE http://127.0.0.1:14434/admin/identities/\$i; done")
  done
  password="Verify-Harbor-$(date +%s)-Lantern!"
  flow() { edge -H 'Accept: application/json' "${base}/auth/self-service/$1/api" | jq -r '.id'; }
  submit() { edge -H 'Content-Type: application/json' -H 'Accept: application/json' -X POST "${base}/auth/self-service/$1?flow=$2" -d "$3"; }

  r="$(submit registration "$(flow registration)" "$(jq -nc --arg e "$shopper" --arg p "$password" \
    '{method: "password", password: $p, traits: {email: $e}}')")"
  expect "Kratos registered a shopper" yes "$(jq -r 'if .identity.id then "yes" else "no" end' <<<"$r")"
  r="$(submit registration "$(flow registration)" "$(jq -nc --arg e "$probe" --arg p "$password" \
    '{method: "password", password: $p, traits: {email: $e, operator: true}}')")"
  expect "self-service cannot claim operator" "" "$(jq -r '.identity.id // ""' <<<"$r")"

  # The browser flow, for the cookie: the edge authenticates an API call by the session cookie, per ADR-0305.
  jar="${work}/cookies"
  login="$(edge -b "$jar" -c "$jar" -H 'Accept: application/json' "${base}/auth/self-service/login/browser")"
  r="$(edge -b "$jar" -c "$jar" -H 'Accept: application/json' -H 'Content-Type: application/json' -X POST \
    "${base}/auth/self-service/login?flow=$(jq -r .id <<<"$login")" \
    -d "$(jq -nc --arg e "$shopper" --arg p "$password" \
      --arg c "$(jq -r '.ui.nodes[] | select(.attributes.name == "csrf_token") | .attributes.value' <<<"$login")" \
      '{method: "password", csrf_token: $c, identifier: $e, password: $p}')")"
  expect "Kratos logged the shopper in" yes "$(jq -r 'if .session.id then "yes" else "no" end' <<<"$r")"

  # A workflow that the registration hook starts assigns the org, and an order needs it.
  # A checkout answers with the workflow's handle, and the order is at its result_url.
  order=""
  for _ in $(seq 1 30); do
    order="$(edge -b "$jar" -H 'Content-Type: application/json' \
      -H "Idempotency-Key: verify-${product}" -X POST "${base}/api/orders" \
      -d "{\"product_id\":\"${product}\",\"quantity\":1}" | jq -r '.result_url // ""')"
    [ -n "$order" ] && break
    sleep 2
  done
  status=""
  for _ in $(seq 1 30); do
    status="$(edge -b "$jar" "${base}/api/orders/${order##*/}" | jq -r '.status // ""')" # lint:comments-allow
    case "$status" in confirmed | failed) break ;; esac
    sleep 2
  done
  expect "the saga confirmed the order: orders → catalog → payment, on Temporal" confirmed "$status"

  # The shopper's example.com address publishes a null MX, so maddy refuses it after Kratos authenticates and submits.
  # DMARC reports show delivery beyond maddy, per ADR-0307.
  if has statefulset maddy; then
    seen=0
    for _ in $(seq 1 20); do
      seen="$(kc -n "$NS" logs maddy-0 --since=10m 2>/dev/null | grep -c "\"rcpt\":\"${shopper}\"")"
      [ "$seen" -gt 0 ] && break
      sleep 3
    done
    expect "Kratos submitted the verification mail to maddy" yes "$([ "$seen" -gt 0 ] && echo yes || echo no)"
  fi
fi

echo
[ "$failed" -eq 0 ] || fail "${failed} check(s) failed"
ok "the tier is up and serving"
