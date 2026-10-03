-- migrate:up
-- Erasure, export, and the retention sweep find a subject's memberships by user, per ADR-0301. The primary key
-- starts with `org_id`, so it does not serve a lookup by user.
create index org_members_user on org_members (user_id);

-- migrate:down
drop index org_members_user;
