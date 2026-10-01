-- migrate:up
-- The order total uses the shared money type, per ADR-0300 and ADR-0003: `numeric`
-- in the column, and a decimal string with its currency on the wire. The catalog
-- migration of the same name states why numeric(19,4) is used and why the currency
-- travels with the amount.
alter table orders add column total numeric(19, 4);
alter table orders add column currency text;

update orders set total = total_cents::numeric / 100, currency = 'EUR' where total is null;

alter table orders alter column total set not null;
alter table orders alter column currency set not null;
alter table orders add constraint orders_total_nonnegative check (total >= 0);
alter table orders add constraint orders_currency_iso4217 check (currency ~ '^[A-Z]{3}$');

comment on column orders.total is 'pii:none';
comment on column orders.currency is 'pii:none';

-- total_cents stays until nothing reads it, as the catalog migration states.

-- migrate:down
alter table orders drop constraint orders_currency_iso4217;
alter table orders drop constraint orders_total_nonnegative;
alter table orders drop column currency;
alter table orders drop column total;
