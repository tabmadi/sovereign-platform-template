-- name: ListOrders :many
select
  id,
  product_id,
  quantity,
  total,
  currency,
  status
from orders
order by created_at desc limit 100;

-- name: CreateOrder :one
-- The order starts with a zero total. The saga sets it when the price is known.
insert into orders (id, product_id, quantity, total, currency, status, owner_id, org_id, idempotency_key)
values ($1, $2, $3, 0, $4, 'pending', $5, $6, $7)
on conflict (id) do nothing
returning id, product_id, quantity, total, currency, status;

-- name: GetOrderByIdempotencyKey :one
select
  id,
  product_id,
  quantity,
  total,
  currency,
  status
from orders
where idempotency_key = $1;

-- name: SetOrderTotal :exec
update orders set total = $2, currency = $3
where id = $1;

-- name: GetOrder :one
select
  id,
  product_id,
  quantity,
  total,
  currency,
  status
from orders
where id = $1;

-- name: UpdateOrderStatus :exec
update orders set status = $2
where id = $1;

-- name: EraseSubjectOrders :execrows
-- Erasure, per ADR-0301. `owner_id` is an identifier, so it is anonymised and not deleted. The order itself has a
-- bookkeeping obligation that outlives the account. One pseudonym per erasure keeps the subject's orders together
-- without naming the person.
update orders set owner_id = sqlc.arg(pseudonym)::text
where owner_id = sqlc.arg(identity_id)::text;

-- name: ExportSubjectOrders :many
select
  id,
  product_id,
  quantity,
  total,
  currency,
  status
from orders
where owner_id = $1
order by created_at;

-- name: ListOrderSubjects :many
-- One page of the owners that this store holds orders for, after a cursor. An erased owner is not a subject.
select distinct owner_id::text as owner_id
from orders
where
  owner_id is not null
  and owner_id > sqlc.arg(after)::text
  and owner_id not like 'erased-%'
order by owner_id
limit sqlc.arg(page_size)::bigint;
