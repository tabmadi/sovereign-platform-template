#!/usr/bin/env bash
# Apply each service's migrations to the local Postgres (ADR-0300).
set -euo pipefail

# The CNPG cluster publishes role-suffixed services (postgres-rw is the primary);
# there is no plain `postgres` service to forward to.
kubectl -n platform port-forward svc/postgres-rw 5432:5432 >/dev/null &
pf=$!
trap 'kill "$pf" 2>/dev/null || true' EXIT
sleep 2

for svc in orders catalog orgs payment; do
  dir="services/$svc/migrations"
  [[ -d "$dir" ]] || continue
  echo "→ migrating $svc"
  DATABASE_URL="postgres://dev:dev@localhost:5432/${svc}?sslmode=disable" \
    DBMATE_MIGRATIONS_DIR="$dir" DBMATE_NO_DUMP_SCHEMA=true \
    dbmate up
done

echo "✓ migrations applied"
