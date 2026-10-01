#!/usr/bin/env bash
# Bulk test data for the load suite, per ADR-0601.
set -euo pipefail
# The repository root: this file is three levels under it, at test/perf/seed/.
cd "$(cd "$(dirname "$0")/../../.." && pwd)"
source scripts/lib/log.sh

CLUSTER="${CLUSTER:-platform}"
source scripts/lib/cluster.sh
NS="platform"
PREFIX="perf-"

k() { kubectl --context "$(cluster_ctx)" -n "$NS" "$@"; }

# Find the CNPG primary by label, not by a fixed name. A failover renames the pod, for example postgres-1 → postgres-2,
# and with a fixed name the seed writes nothing and reports no error.
primary="$(k get pods -l 'cnpg.io/instanceRole=primary' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [ -z "$primary" ]; then
  fail "no CNPG primary found in namespace ${NS}. Check that the full tier is up: mise run cluster:up -- full"
fi

# psql over the pod's local socket as the superuser: no port-forward, no credentials to pass, and it works the same on every tier.
psql_catalog() { k exec "$primary" -c postgres -- psql -U postgres -d catalog -qtA "$@"; }

count_seeded() { psql_catalog -c "select count(*) from products where name like '${PREFIX}%';"; }

if [ "${1:-}" = "--clean" ]; then
  step "removing seeded products"
  before="$(count_seeded)"
  # Orders reference products by id but have no FK, because services are decoupled at the database, per ADR-0000 principle 7.
  # So this delete cannot cascade into another service's data.
  psql_catalog -c "delete from products where name like '${PREFIX}%';" >/dev/null
  ok "removed ${before} seeded products"
  # Orders are not removed. A checkout run creates real orders and workflow executions, and no order marker separates a load run from a human, per ADR-0601.
  # A guess can delete real rows.
  warn "orders from checkout runs stay in place, because they carry no perf marker. Create the environment again if the volume matters"
  exit 0
fi

n="${1:-5000}"
case "$n" in
'' | *[!0-9]*) fail "usage: mise run perf:seed -- [count|--clean], got ${n}" ;;
esac

step "seeding ${n} products into catalog, primary: ${primary}"
# One statement, generated on the server: 5,000 round-trips take minutes. The service mints ids, so the seed mints UUIDv7s of the same shape, per ADR-0003.
# Postgres 17 has no uuidv7(). Prices vary, so rows are not byte-identical. Identical rows would let Postgres and the JSON encoder perform better than real data.
psql_catalog -c "
  insert into products (id, name, price, currency)
  select (lpad(to_hex((extract(epoch from clock_timestamp()) * 1000)::bigint), 12, '0') || '7'
      || substr(md5(random()::text), 1, 3) || to_hex(8 + floor(random() * 4)::int)
      || substr(md5(random()::text), 1, 15))::uuid,
    '${PREFIX}' || g, ((g * 37) % 100000) / 100.0, 'EUR'
  from generate_series(1, ${n}) as g;
" >/dev/null

total="$(psql_catalog -c 'select count(*) from products;')"
detail "seeded:        $(count_seeded)"
detail "catalog total: ${total}"
ok "catalog seeded. Run \`mise run perf:seed -- --clean\` to undo"
