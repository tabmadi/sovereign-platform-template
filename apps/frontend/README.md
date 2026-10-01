# frontend

The single Next.js application, per [ADR-0101](../../docs/adr/0101-monorepo.md#one-frontend-app). Route groups separate audiences inside one deploy unit. The admin console is a separate app, `apps/admin`, per ADR-0401:

```text
src/app/[locale]/(landing)/    : public marketing, sign-in
src/app/[locale]/(panel)/      : authenticated customer panel
src/app/[locale]/(analytics)/  : product analytics, gated by an OpenFGA relation check
src/app/[locale]/(devportal)/  : third-party API docs
```

`[locale]/(landing)/auth/{login,register,recovery,settings,verification,error}` render the Kratos self-service flows through the shared `components/auth/KratosFlow` component, per ADR-0304. They ship in every environment. They must match the `selfservice.flows.*.ui_url` values in the Ory chart values, `infra/helm/platform/ory/values.yaml`.

Run it locally with `mise run dev:frontend`. This is the host `next dev` that the local edge routes `/` to. Another start method, such as an IDE run config or a debugger, needs the same env: copy `.env.example` to `.env.local`. See [docs/dev-loop.md](../../docs/dev-loop.md).

Route groups must not import from each other, per the ADR-0101 lint rule. Generated TS clients are under `libs/ts/sdks/<service>/`, and code imports them as `@sdks/<service>`. The `tsconfig.json` paths define this.
