-- migrate:up
-- The CONTRACT half of the expand and contract that introduced `products.price`,
-- per ADR-0300. The expand migration added the money columns and backfilled them
-- from `price_cents`. This migration removes the column, because nothing reads it.
--
-- It is a SEPARATE migration on purpose, and the separation is the point. Suppose a
-- release stops writing a column and also drops it. An instance that still runs the
-- previous image then writes to a column that no longer exists. That is an outage
-- during a rolling deploy. Two migrations in two releases put a deploy boundary
-- between the two steps.
--
-- `lint:money` allows this column on purpose up to this migration. After this
-- migration, the column is a finding and not a leftover.
alter table products drop column price_cents;

-- migrate:down
-- The rollback restores the column and rebuilds it from the money column. So a
-- revert gives a schema that the previous image can write to. It is not null with a
-- default of 0, not a plain add. The old code writes it on every insert, and a
-- nullable column would accept a row that the old code cannot read.
alter table products add column price_cents integer not null default 0;
update products set price_cents = (price::numeric * 100)::integer;
