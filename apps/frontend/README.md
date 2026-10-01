# frontend

The single Next.js application, per [ADR-0101](../../docs/adr/0101-monorepo.md#one-frontend-app). Route groups separate audiences inside one deploy unit:

```text
src/app/(landing)/    : public marketing, sign-in
src/app/(panel)/      : authenticated customer panel
src/app/(admin)/      : staff-only tile that links to /internal/admin, Lowdefy
src/app/(devportal)/  : third-party API docs
```

`(landing)/auth/{login,register,recovery,settings}` render the Kratos self-service flows through the shared `components/auth/KratosFlow` component, per ADR-0304. They ship in every environment. They must match the `selfservice.flows.*.ui_url` values in the Ory chart values, `infra/helm/platform/ory/values.yaml`.

Run it locally with `mise run dev:frontend`. This is the host `next dev` that the local edge routes `/` to. Another start method, such as an IDE run config or a debugger, needs the same env: copy `.env.example` to `.env.local`. See [docs/dev-loop.md](../../docs/dev-loop.md).

Route groups must not import from each other, per the ADR-0101 lint rule. Generated TS clients are under `libs/ts/sdks/<service>/`, and code imports them as `@sdks/<service>`. The `tsconfig.json` paths define this.
