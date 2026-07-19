-- migrate:up
alter table orders drop constraint orders_status_check;
alter table orders add constraint orders_status_check check (status in ('pending', 'confirmed', 'failed', 'cancelled'));

-- migrate:down
alter table orders drop constraint orders_status_check;
alter table orders add constraint orders_status_check check (status in ('pending', 'confirmed', 'failed'));
