# admin: the admin console

The internal admin tool, per [ADR-0401](../../docs/adr/0401-internal-admin.md). It is a Next.js app in the root Bun workspace, and Node.js runs it.

| Path | Holds |
| --- | --- |
| `_generated/manifest.json` | the pages, from `tabkit gen admin`. **Do not edit** |
| `src/app/[page]/page.tsx` | the generic list, create, edit, and action pages |
| `src/app/actions.ts` | the one Server Action that makes the call of each form |
| `src/app/page.tsx` | the hand-written dashboard across services |
| `src/lib/` | the manifest types, the service client, the form helpers, and the fixed text |

`tabkit gen admin` writes the manifest from the service OpenAPI specs. Two spec markers drive it:

- A tag with `x-admin: crud` makes a list page for that resource. It adds a create page when the collection `POST` returns `201`, and an edit page on `PUT` or `DELETE`. An async `202` workflow create stays list-only.
- An operation with `x-admin: action` makes a page with one form and one button.

Run `just gen-admin` to regenerate. `just gen` includes it, and CI checks the output for drift.

The edge enforces auth, per ADR-0305. The console server calls each service in-cluster with `X-User-Id: admin-console`, which the OpenFGA seed grants `group:operator`.

## Standard tasks

```sh
just admin-build   # the production build
just admin-run     # next dev on :3001. ADMIN_SERVICE_URL points it at a service
just admin-lint    # the type check
just test-ts       # the unit tests, with the shared libraries
```
