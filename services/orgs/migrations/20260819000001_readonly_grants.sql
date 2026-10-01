-- migrate:up
-- The read-only inspector role, per ADR-0401.
--
-- ADR-0401 states that pgweb and psql are read-only AT THE DATABASE-ROLE LEVEL, not
-- by convention. The user cannot UPDATE. pgweb's own `--readonly` flag is one layer.
-- This is the other layer, and it still holds when someone reaches the same
-- database with psql.
--
-- Grants live in each service's migrations, because each service owns its schema.
-- The role is cluster-global and created once. But WHAT it may read is a per-database
-- fact that changes with every table change. `postInitApplicationSQL` cannot carry
-- the grants: it runs in one database at bootstrap, and these tables arrive later.
--
-- `ALTER DEFAULT PRIVILEGES` keeps the grants correct for new tables. Without it, a
-- table from the next migration is invisible to the inspector. The failure is then
-- an empty panel and not an error.
do $$
begin
  if exists (select from pg_roles where rolname = 'readonly') then
    execute 'grant usage on schema public to readonly';
    execute 'grant select on all tables in schema public to readonly';
    execute 'alter default privileges in schema public grant select on tables to readonly';
  end if;
end
$$;

-- migrate:down
do $$
begin
  if exists (select from pg_roles where rolname = 'readonly') then
    execute 'alter default privileges in schema public revoke select on tables from readonly';
    execute 'revoke select on all tables in schema public from readonly';
    execute 'revoke usage on schema public from readonly';
  end if;
end
$$;
