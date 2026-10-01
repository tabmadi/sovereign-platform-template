-- migrate:up
-- The analytics store, per ADR-0700. It is a PII store by definition. Every row
-- carries a session id, and an authenticated visitor's rows carry an identity id.
-- So it is treated as a PII store from this first migration.
--
-- Partitioned by month on `occurred_at`. Retention here drops a partition and does
-- not delete rows, per ADR-0301. A delete of a month's events from a single table
-- rewrites the table. An expensive retention job gets postponed.
create table events (
  id uuid not null,
  -- The Faro session id. It joins a funnel step to the exception and the RUM log
  -- from the same visit. It is pseudonymous, but it still resolves to a person
  -- through the consent record below, so erasure must reach it.
  session_id text not null,
  -- Present only when the visitor is authenticated. Null is the common case and is
  -- not a defect, because most of a funnel happens before anyone signs in.
  identity_id text,
  -- The reserved namespace that ADR-0700 gives marketing events. It is stored with no
  -- prefix. The collector uses the prefix to ROUTE them, and it is not part of the name.
  name text not null,
  -- The event's own fields. They are jsonb, because a funnel gains steps faster than
  -- someone can write a migration. The emitting wrapper constrains them, not the
  -- column.
  properties jsonb not null default '{}'::jsonb,
  -- A parsed class: `mobile`, `desktop`, or `tablet`. It is never the user-agent
  -- string, which is a fingerprinting surface. Ingest reduces it, so the raw value
  -- never reaches this table.
  device_class text not null default 'unknown',
  occurred_at timestamptz not null,
  created_at timestamptz not null default now()
) partition by range (occurred_at);

-- The primary key includes the partition key, because Postgres requires it. The
-- order puts `occurred_at` first, so a range scan over a window follows the
-- index's natural direction.
create unique index events_pkey on events (occurred_at, id);
create index events_session on events (session_id, occurred_at);
create index events_name on events (name, occurred_at);

-- The consent record, per ADR-0700 and GDPR Art. 7(1). It makes consent
-- DEMONSTRABLE later. So it carries the version of the purpose text shown and the
-- source of the signal, not a bare boolean.
create table consent (
  session_id text primary key,
  identity_id text,
  -- `granted`, `withdrawn`, or `refused`. Withdrawal is a state and not a deletion.
  -- Erasing the record would erase the evidence that consent was once given, and
  -- then nobody could prove it.
  state text not null check (state in ('granted', 'withdrawn', 'refused')),
  -- The version of the purpose text that the visitor saw. Consent is to a stated
  -- purpose, so a changed purpose is a new consent and not a continuing one.
  purpose_version text not null,
  -- How the signal arrived: `control` for the on-page control, `gpc` for a Global
  -- Privacy Control header. A `gpc` row is a refusal with no prompt.
  source text not null check (source in ('control', 'gpc')),
  decided_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- migrate:down
drop table consent;
drop table events;
