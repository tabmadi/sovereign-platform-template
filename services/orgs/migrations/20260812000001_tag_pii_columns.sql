-- migrate:up
-- org_members.user_id is the Kratos identity of a person, per ADR-0304. It is
-- pseudonymous and not directly identifying. It still resolves to a natural person
-- through the identity store, so erasure and DSAR must reach it. The tag makes this
-- queryable from pg_description, per ADR-0301.
--
-- The tag is in a later migration than the column, because a dbmate migration is
-- immutable once applied. The tag travels with the schema in both cases.
comment on column org_members.user_id is 'pii:identifier';

-- The other columns carry no personal data. The explicit tag shows a considered
-- decision, not a column that nobody checked.
comment on column orgs.name is 'pii:none';

-- migrate:down
comment on column org_members.user_id is null;
comment on column orgs.name is null;
