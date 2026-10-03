-- migrate:up
-- Erasure, export, and the retention sweep find a subject's orders by owner, per ADR-0301.
create index orders_owner on orders (owner_id) where owner_id is not null;

-- migrate:down
drop index orders_owner;
