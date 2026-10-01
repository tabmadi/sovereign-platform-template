# orgs

The B2B multi-tenancy service, per ADR-0304. It owns organisations and memberships.

For every new identity, it receives an east-west webhook from Kratos at `POST /identity-created`. The route has `x-audience: cluster`, per ADR-0303, so it is off the edge and in neither docs portal.

The handler starts the `RegisterUser` Temporal workflow, per ADR-0302. The workflow runs two activities:

1. Create the personal org and the admin membership.
2. Write the matching OpenFGA `org#admin` tuple.

The authz-relevant dual write must not half-apply, per ADR-0304. So it never runs as a bare DB write in the handler. The `cmd/server` binary enqueues the workflow. `cmd/worker` runs the workflow and dials OpenFGA.
