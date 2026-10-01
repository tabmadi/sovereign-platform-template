-- migrate:up
-- Every column has a class, per ADR-0301 and ADR-0700. In the analytics store, a
-- claim of no personal data would be false for the whole table. So each column
-- states its class, and the columns with no personal data say so explicitly.
comment on column events.session_id is 'pii:identifier';
comment on column events.identity_id is 'pii:identifier';
-- The event's own fields. First-party code writes a funnel step's properties, and
-- they must not carry personal data. But the column cannot enforce that, and a
-- field that a caller fills can hold anything.
comment on column events.properties is 'pii:free_text';
-- A class, not a user agent. It is tagged `device` because it comes from a user
-- agent, and an erasure request needs to know that.
comment on column events.device_class is 'pii:device';
comment on column events.name is 'pii:none';

comment on column consent.session_id is 'pii:identifier';
comment on column consent.identity_id is 'pii:identifier';
comment on column consent.state is 'pii:none';
comment on column consent.purpose_version is 'pii:none';
comment on column consent.source is 'pii:none';

-- migrate:down
comment on column events.session_id is null;
comment on column events.identity_id is null;
comment on column events.properties is null;
comment on column events.device_class is null;
comment on column events.name is null;
comment on column consent.session_id is null;
comment on column consent.identity_id is null;
comment on column consent.state is null;
comment on column consent.purpose_version is null;
comment on column consent.source is null;
