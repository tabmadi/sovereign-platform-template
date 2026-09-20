-- name: GetConsent :one
select
  session_id,
  identity_id,
  state,
  purpose_version,
  source,
  decided_at
from consent
where session_id = $1;

-- name: UpsertConsent :one
-- A decision replaces the previous one for the session and keeps the row, because
-- withdrawal is a state rather than a deletion: erasing it would erase the evidence
-- that consent was once given, which is what GDPR Art. 7(1) asks to be demonstrable.
insert into consent (session_id, identity_id, state, purpose_version, source)
values ($1, $2, $3, $4, $5)
on conflict (session_id) do update set
identity_id = excluded.identity_id,
state = excluded.state,
purpose_version = excluded.purpose_version,
source = excluded.source,
updated_at = now()
returning session_id, identity_id, state, purpose_version, source, decided_at;

-- name: InsertEvent :exec
insert into events (
  id, session_id, identity_id, name, properties, device_class, occurred_at
)
values ($1, $2, $3, $4, $5, $6, $7);

-- name: SummariseEvents :many
-- One row per event name over a window with its distinct sessions — a plain aggregate, because the first
-- question a panel answers is what is happening at all.
select
  name,
  count(*) as occurrences,
  count(distinct session_id) as sessions
from events
where occurred_at >= $1
group by name
order by occurrences desc
limit 50;

-- name: FunnelStepFirstSeen :many
-- Each session's first occurrence of each named step in the window; the caller walks them in definition order,
-- because in SQL the query's shape would depend on the number of steps. `name = any($3::text[])` rather than a
-- join: the funnels are committed configuration, not a table (infra/analytics/funnels.yaml).
select
  session_id,
  name,
  min(occurred_at)::timestamptz as first_seen
from events
where
  occurred_at >= $1
  and occurred_at < $2
  and name = any($3::text [])
group by session_id, name;

-- name: UpsertFunnelRollup :exec
-- Recomputing a bucket REPLACES it. A pass over a window that is still filling is
-- therefore safe to re-run, and re-running is the normal case: the most recent
-- bucket is always incomplete.
insert into funnel_rollup (
  funnel, step_index, step_name, bucket_start, bucket_end, sessions
)
values ($1, $2, $3, $4, $5, $6)
on conflict (funnel, bucket_start, step_index) do update set
step_name = excluded.step_name,
bucket_end = excluded.bucket_end,
sessions = excluded.sessions,
computed_at = now();

-- name: GetFunnelRollup :many
-- The panel's read: one funnel over a range of buckets, in bucket then step order,
-- which is the order it renders.
select
  funnel,
  step_index,
  step_name,
  bucket_start,
  bucket_end,
  sessions
from funnel_rollup
where
  funnel = $1
  and bucket_start >= $2
  and bucket_start < $3
order by bucket_start desc, step_index asc;

-- name: CountEventsSince :one
-- Rows in the events table from a point in time, for the deferral trigger watching the store's growth (ADR-0700).
-- Bounded by `occurred_at`: `events` is partitioned by month, so a `count(*)` over everything would scan every
-- month ever written, on every scrape.
select count(*)::bigint as rows_since
from events
where occurred_at >= $1;
