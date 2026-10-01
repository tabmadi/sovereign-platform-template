-- migrate:up
-- The funnel rollup, per ADR-0700 and ADR-0302.
--
-- A funnel question asks, for example, how many sessions that saw the product page
-- reached checkout. The answer needs a scan of every event in the window and an
-- order of each session's steps. That scan is cheap for a week of events and too
-- slow for a year, and the panel is interactive. So a schedule computes the answer
-- and stores it here. The panel reads a table whose row count grows with
-- FUNNELS × STEPS × BUCKETS, not with traffic.
--
-- Unlike `events`, this table is NOT partitioned, on purpose. A rollup row per funnel
-- step per day is a few thousand rows a year. Partitions make retention cheap, but
-- retention on this table already costs nothing.
create table funnel_rollup (
  -- The funnel's id from infra/analytics/funnels.yaml. It is not a foreign key. The
  -- definitions are committed configuration and not a table, so the database cannot
  -- check that the funnel exists. A rollup for a deleted funnel is history. Dropping
  -- it on the next pass would erase the record that the funnel ever ran.
  funnel text not null,
  -- The step's position, from zero. Order is the purpose of a funnel, and an index
  -- stays valid when a step is renamed.
  step_index integer not null,
  -- The event name that this step counts. It is denormalised, so a rollup row is
  -- readable without the definition file.
  step_name text not null,
  -- The bucket that this row covers: its start, half-open to the next bucket.
  bucket_start timestamptz not null,
  bucket_end timestamptz not null,
  -- Sessions that reached this step IN ORDER. Each reached every earlier step first,
  -- at or before this one. A session that opens checkout from a bookmark has not
  -- traversed the funnel. Counting it would make every funnel look flat.
  sessions bigint not null,
  computed_at timestamptz not null default now(),

  -- One row per funnel, step, and bucket. A recompute REPLACES a bucket, so the pass
  -- is safe to run again over a window that is still filling.
  primary key (funnel, bucket_start, step_index)
);

-- The panel's read: one funnel over a range of buckets, in step order.
create index funnel_rollup_lookup on funnel_rollup (funnel, bucket_start desc, step_index);

-- Every column has a class, per ADR-0301. A rollup is an AGGREGATE. Its smallest
-- unit is a session count, never a session. So every column here is `pii:none`.
-- The explicit tag shows that someone classified the column and found no personal data.
--
-- For the same reason, the rollup stays after an erasure. `EraseSubject` removes a
-- subject's events. It does not change these counts and does not need to, because a
-- count of sessions is not a record about any session. A rollup with session ids
-- would need a walk, and erasure would rewrite every bucket that had the subject.
comment on column funnel_rollup.funnel is 'pii:none';
comment on column funnel_rollup.step_index is 'pii:none';
comment on column funnel_rollup.step_name is 'pii:none';
comment on column funnel_rollup.bucket_start is 'pii:none';
comment on column funnel_rollup.bucket_end is 'pii:none';
comment on column funnel_rollup.sessions is 'pii:none';
comment on column funnel_rollup.computed_at is 'pii:none';

-- migrate:down
drop table funnel_rollup;
