-- name: ListOrgs :many
select
  id,
  name
from orgs
order by created_at desc limit 100;

-- name: CreateOrg :one
insert into orgs (id, name) values ($1, $2) returning id, name;

-- name: GetOrg :one
select
  id,
  name
from orgs
where id = $1;

-- name: UpdateOrg :one
update orgs set name = $2
where id = $1
returning id, name;

-- name: DeleteOrg :exec
delete from orgs where id = $1;

-- name: AddMember :exec
insert into org_members (org_id, user_id, role) values ($1, $2, $3)
on conflict do nothing;

-- name: EraseSubjectMemberships :execrows
-- Erasure, per ADR-0301. `user_id` is an identifier, so it is anonymised and not deleted. The membership keeps the
-- org's history whole. One pseudonym per erasure keeps the primary key unique, because a user is in an org once.
update org_members set user_id = sqlc.arg(pseudonym)::text
where user_id = sqlc.arg(identity_id)::text;

-- name: ExportSubjectMemberships :many
select
  orgs.id,
  orgs.name,
  org_members.role
from org_members
join orgs on org_members.org_id = orgs.id
where org_members.user_id = $1
order by orgs.created_at;

-- name: ListMemberSubjects :many
-- One page of the users that this store holds memberships for, after a cursor. An erased user is not a subject.
select distinct user_id
from org_members
where user_id > sqlc.arg(after)::text and user_id not like 'erased-%'
order by user_id
limit sqlc.arg(page_size)::bigint;

-- name: LockIdentity :exec
-- Serialises the writes for one identity until the transaction ends, so two activity attempts cannot both insert.
select pg_advisory_xact_lock(hashtextextended(sqlc.arg(identity_id)::text, 0));

-- name: FindPersonalOrg :one
select orgs.id
from orgs
join org_members on orgs.id = org_members.org_id
where
  org_members.user_id = sqlc.arg(identity_id)::text
  and org_members.role = 'admin'
  and orgs.name = sqlc.arg(name)::text
order by orgs.created_at
limit 1;
