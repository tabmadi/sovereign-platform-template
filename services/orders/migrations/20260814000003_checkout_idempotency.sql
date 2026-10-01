-- migrate:up
-- A retried checkout must not place a second order, per ADR-0003. The client sends an
-- `Idempotency-Key`, and the column carries it. So the database enforces uniqueness,
-- and two handlers that read before they write cannot race. payment uses the same shape.
--
-- Nullable, because rows written before this migration have no key, and the
-- constraint must accept them. A UNIQUE index ignores NULLs, so every real key is
-- still unique. New orders always carry a key, because the handler requires the header.
alter table orders add column idempotency_key text;
create unique index orders_idempotency_key_idx on orders (idempotency_key);

comment on column orders.idempotency_key is 'pii:none';

-- migrate:down
drop index orders_idempotency_key_idx;
alter table orders drop column idempotency_key;
