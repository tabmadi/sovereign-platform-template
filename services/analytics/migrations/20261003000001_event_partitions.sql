-- migrate:up
-- `events` is partitioned by month, and a partitioned table with no partition refuses every insert. The retention
-- endpoint creates each month ahead of time and drops the expired ones, per ADR-0301. This migration creates the
-- current and the next month, so the store accepts events from its first deploy.
--
-- The default partition takes an event outside every monthly range, such as one from a client with a wrong clock.
-- Without it, that event would fail the whole batch.
create table events_default partition of events default;

do $$
declare
  first_month date := date_trunc('month', now() at time zone 'UTC')::date;
  offset_month integer;
  month_start date;
begin
  for offset_month in 0..1 loop
    month_start := (first_month + make_interval(months => offset_month))::date;
    -- Bounds in UTC, the same as the retention endpoint writes them, whatever the session's time zone.
    execute format(
      'create table if not exists %I partition of events for values from (%L) to (%L)',
      'events_' || to_char(month_start, 'YYYY_MM'),
      month_start::timestamp at time zone 'UTC',
      (month_start + interval '1 month')::timestamp at time zone 'UTC'
    );
  end loop;
end
$$;

-- Erasure, export, and the retention sweep find a subject by identity, so each needs an index on it.
create index events_identity on events (identity_id) where identity_id is not null;
create index consent_identity on consent (identity_id) where identity_id is not null;

-- migrate:down
drop index consent_identity;
drop index events_identity;

do $$
declare
  part regclass;
begin
  for part in select inhrelid::regclass from pg_inherits where inhparent = 'events'::regclass loop
    execute format('drop table %s', part);
  end loop;
end
$$;
