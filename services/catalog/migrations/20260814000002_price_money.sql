-- migrate:up
-- A monetary amount is `numeric` in the database and a string on the wire. It is
-- never a float and never an integer of minor units, per ADR-0300 and ADR-0003.
-- `price_cents` is an integer of minor units. It is a valid form in general, but
-- this platform did not choose it.
--
-- numeric(19,4): 4 fractional digits cover every ISO 4217 minor unit, including
-- the 3-digit ones and the 4-digit UYW. 19 total digits fit a 64-bit-safe range
-- without numeric's unbounded form, which indexes handle badly. The currency travels
-- with the amount, because an amount with no currency is not a quantity of anything.
alter table products add column price numeric(19, 4);
alter table products add column currency text;

-- Backfill from the integer minor units, then make both columns the contract. The
-- currency is EUR, because every committed example and fixture in this repo means
-- EUR by `_cents`. No second currency was ever used.
update products set price = price_cents::numeric / 100, currency = 'EUR' where price is null;

alter table products alter column price set not null;
alter table products alter column currency set not null;
alter table products add constraint products_price_nonnegative check (price >= 0);
alter table products add constraint products_currency_iso4217 check (currency ~ '^[A-Z]{3}$');

comment on column products.price is 'pii:none';
comment on column products.currency is 'pii:none';

-- price_cents stays in this migration. Do not drop a column and rewrite every reader
-- in one migration. That turns a deploy window into an outage, because the old code
-- still runs while the new schema arrives. A later migration drops it when nothing reads it.

-- migrate:down
alter table products drop constraint products_currency_iso4217;
alter table products drop constraint products_price_nonnegative;
alter table products drop column currency;
alter table products drop column price;
