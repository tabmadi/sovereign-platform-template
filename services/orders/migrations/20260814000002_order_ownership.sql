-- migrate:up
-- Every protected resource belongs to an org, and a user acts only through a role
-- in an org, per ADR-0304. An order without these columns records neither. Then
-- `order#read: owner or write from org` in model.fga cannot resolve, and no handler can ask.
--
-- Authorisation reads the OpenFGA tuple, never these columns. With these columns,
-- the tuples can be rebuilt from the system of record. A collection for one buyer
-- also has a column to filter on.
alter table orders add column owner_id text;
alter table orders add column org_id uuid;

-- NOT VALID enforces the constraint on every insert and update, but does not check
-- rows written before ownership existed. Those rows have no tuple either, so only an
-- operator can read them. That is correct for an order with no recorded buyer.
alter table orders add constraint orders_owner_id_present check (owner_id is not null) not valid;
alter table orders add constraint orders_org_id_present check (org_id is not null) not valid;

comment on column orders.owner_id is 'pii:identifier';
comment on column orders.org_id is 'pii:none';

-- migrate:down
alter table orders drop constraint orders_org_id_present;
alter table orders drop constraint orders_owner_id_present;
alter table orders drop column org_id;
alter table orders drop column owner_id;
