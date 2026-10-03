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
-- A decision replaces the previous one for the session and keeps the row. Withdrawal
-- is a state and not a deletion. Erasing it would erase the evidence that consent
-- was once given, and GDPR Art. 7(1) requires proof of that.
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
-- One row per event name over a window, with its distinct sessions. It is a plain aggregate, because a panel
-- first shows what is happening.
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
-- Each session's first occurrence of each named step in the window. The caller walks them in definition order,
-- because in SQL the query's shape would depend on the number of steps. It uses `name = any($3::text[])` and not
-- a join. The funnels are committed configuration in infra/analytics/funnels.yaml, not a table.
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
-- A recompute REPLACES a bucket. So a pass over a window that is still filling is
-- safe to run again. That is the normal case, because the most recent bucket is
-- always incomplete.
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
-- The panel's read: one funnel over a range of buckets, in bucket and then step
-- order. The panel renders in this order.
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
-- Rows in the events table from a point in time, for the deferral trigger that watches the store's growth, per
-- ADR-0700. `occurred_at` limits it. `events` is partitioned by month, so a `count(*)` over all rows would scan
-- every month ever written, on every scrape.
select count(*)::bigint as rows_since
from events
where occurred_at >= $1;

-- name: EraseSubjectAnalytics :one
-- Erasure, per ADR-0301. It covers the subject's whole sessions, so the events before sign-in too.
-- Identifiers are anonymised, one replacement per session, so the aggregates still count distinct sessions.
-- `free_text` and `device` are deleted, which here means set to the column's empty value.
with subject_sessions as materialized (
  select events.session_id from events
  where events.identity_id = sqlc.arg(identity_id)::text
  union
  select consent.session_id from consent
  where consent.identity_id = sqlc.arg(identity_id)::text
),

replacement as materialized (
  select
    subject_sessions.session_id,
    sqlc.arg(pseudonym)::text || '-' || gen_random_uuid()::text as anonymous_id
  from subject_sessions
),

erased_events as (
  update events set
    session_id = replacement.anonymous_id,
    identity_id = case when events.identity_id is null then null else sqlc.arg(pseudonym)::text end,
    properties = '{}'::jsonb,
    device_class = 'unknown'
  from replacement
  where events.session_id = replacement.session_id
  returning 1
),

erased_consent as (
  update consent set
    session_id = replacement.anonymous_id,
    identity_id = case when consent.identity_id is null then null else sqlc.arg(pseudonym)::text end
  from replacement
  where consent.session_id = replacement.session_id
  returning 1
)

select
  (select count(*) from erased_events)::bigint as events,
  (select count(*) from erased_consent)::bigint as consents;

-- name: ExportSubjectEvents :many
-- Subject access, per ADR-0301: every event of every session that the subject is known in.
select
  session_id,
  name,
  properties,
  device_class,
  occurred_at
from events
where
  session_id in (
    select e.session_id from events as e where e.identity_id = sqlc.arg(identity_id)::text
    union
    select c.session_id from consent as c where c.identity_id = sqlc.arg(identity_id)::text
  )
order by occurred_at;

-- name: ExportSubjectConsent :many
select
  session_id,
  state,
  purpose_version,
  source,
  decided_at,
  updated_at
from consent
where
  session_id in (
    select e.session_id from events as e where e.identity_id = sqlc.arg(identity_id)::text
    union
    select c.session_id from consent as c where c.identity_id = sqlc.arg(identity_id)::text
  )
order by decided_at;

-- name: ListAnalyticsSubjects :many
-- One page of the identities that this store holds data for, after a cursor. The retention sweep reads every page,
-- per ADR-0301. An identity that erasure already replaced has the `erased-` prefix and is not a subject.
select subjects.identity_id::text as identity_id
from (
  select events.identity_id from events
  where events.identity_id is not null and events.identity_id > sqlc.arg(after)::text
  union
  select consent.identity_id from consent
  where consent.identity_id is not null and consent.identity_id > sqlc.arg(after)::text
) as subjects
where subjects.identity_id not like 'erased-%'
order by subjects.identity_id
limit sqlc.arg(page_size)::bigint;
