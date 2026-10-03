-- migrate:up
-- The read-only inspector role, per ADR-0401, the same grant as every other service. pgweb and the source side of
-- restore verification log in as `readonly`, and without this grant neither sees a table here.
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
