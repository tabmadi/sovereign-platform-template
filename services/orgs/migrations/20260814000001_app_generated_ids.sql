-- migrate:up
-- The service mints the primary key, not the column, per ADR-0003. With no default,
-- two things are true. First, the identifier exists BEFORE the insert. So a handler
-- can log it, tag its span, and report it on a write that fails. Second, the value
-- is a UUIDv7 from `libs/go/id`, not the UUIDv4 that `gen_random_uuid` returns. So
-- the key has a time prefix, and the index appends and does not scatter. Any default
-- would be a second generator with neither property. Only the inserts that forgot
-- to pass an id would use it.
alter table orgs alter column id drop default;

-- migrate:down
alter table orgs alter column id set default gen_random_uuid();
