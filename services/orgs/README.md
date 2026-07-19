# orgs

B2B multi-tenancy service (ADR-0010). Owns organisations + memberships.
Receives an east-west webhook from Kratos at `POST /identity-created`
(`x-audience: cluster`, ADR-0008 — off the edge, in neither docs portal) for every
new identity. The handler starts the `RegisterUser` Temporal workflow (ADR-0006),
which creates the personal org + admin membership and writes the matching OpenFGA
`org#admin` tuple as two activities — the authz-relevant dual-write must not
half-apply (ADR-0010), so it never runs as a bare DB write in the handler. The
`cmd/server` binary enqueues; `cmd/worker` runs the workflow and dials OpenFGA.
