# ADR-0400: Frontend Stack and Conventions

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0100](0100-language-and-runtime.md), [ADR-0101](0101-monorepo.md), [ADR-0201](0201-gitops.md), [ADR-0302](0302-temporal.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0304](0304-identity-and-authorization.md), [ADR-0305](0305-edge-auth-and-traffic-policy.md), [ADR-0306](0306-trust-tiers-and-urls.md), [ADR-0401](0401-internal-admin.md), [ADR-0500](0500-observability.md), [ADR-0501](0501-operator-uis-and-dashboards.md), [ADR-0600](0600-local-development-loop.md), [ADR-0601](0601-testing-strategy.md)
- **Decides:** One Next.js app with route groups, server components by default, and `shadcn/ui` on Tailwind wired CSS-first, with every screen reading its data through one seam.

## Context

One Next.js app under `apps/frontend/` is the front door. It holds the landing pages, the authenticated product panel, and the developer portal, all as route groups. The internal admin console is a separate application, per [ADR-0401](0401-internal-admin.md). Earlier ADRs pin the language, runtime, deployment, codegen, and auth integration. None of them pins how the app is built day to day.

This ADR is the single entry point for a newcomer who works on the frontend.

### Pinned by earlier ADRs

| Concern | Decision | ADR |
| --- | --- | --- |
| App count and route groups | one app, with the route groups `(landing\|panel\|devportal)` | [ADR-0101](0101-monorepo.md) |
| Language and runtime | TypeScript, with Bun as the only JS runtime | [ADR-0100](0100-language-and-runtime.md) |
| Workspaces | Bun workspaces, no Turborepo | [ADR-0101](0101-monorepo.md) |
| API clients | generated from each service's spec | [ADR-0303](0303-api-contracts-and-lifecycle.md) |
| Login UI | custom Next.js that drives Kratos self-service flows | [ADR-0304](0304-identity-and-authorization.md) |
| Container | standalone output, deployed through the shared service chart | [ADR-0101](0101-monorepo.md), [ADR-0201](0201-gitops.md) |
| Cross-route-group imports | forbidden by lint | [ADR-0101](0101-monorepo.md) |

## Decision drivers

1. **One stack for every route group.** Landing, panel, and devportal share the same primitives. A new route group decides nothing new.
2. **A server that the platform runs calls the generated SDK.** A public marketing page, an authenticated panel, and an API console have different rendering needs. The API credential never reaches the browser for any of them.
3. **Design is authored in this repository**, not in a design tool with a hand-off, per [ADR-0701](0701-product-design-and-discovery.md). So the primitive library is judged on how easily a person or an LLM reads and edits it in place. Fidelity to an external file does not count.
4. **It runs as a container in this cluster**, with no build-time or runtime dependency on the vendor's hosting.
5. **Governance is recorded, not decisive**, per principle 4 of [ADR-0000](0000-platform-foundations.md). Exit cost sets how much a vendor relationship can weigh.

## Considered options

### Framework

Every option below is MIT and can be self-hosted as a container. So the important column is what self-hosting *costs*: which features silently assume the vendor's platform.

| Option | Server rendering model | Cost of self-hosting | Governance | Verdict |
| --- | --- | --- | --- | --- |
| **Next.js, App Router** | Server Components by default, with an opt-in client boundary | `output: standalone` is a first-party target. Image optimisation and incremental regeneration need a cache and a resizer, which the vendor supplies otherwise | **Vercel** | **Chosen.** The server-first model makes driver 2 the default, not an assembly job. Its self-hosting gaps are a cache and a resizer. Both are replaceable, and both run inside the cluster *(documented)* |
| TanStack Start | client-first, with server functions | no vendor path to depend on | TanStack, vendor-neutral and community-funded | **The strongest alternative on driver 5.** It is the only option here outside the orbit of a hosting vendor. It is younger. Its server model is server functions, not a component-level boundary, so the author handles driver 2 again on every page |
| React Router, which absorbed Remix | loaders and actions per route, with client rendering by default | none, because it was built to run anywhere | Shopify | Mature, and it uses a data-router model, not a server-component model. Choosing it accepts a larger client bundle on the marketing routes, and the panel gains nothing from that |
| SvelteKit | server load functions, compiled output, the smallest bundles | none. Adapters target plain Node | Svelte, whose creator works for **Vercel** | The best bundle sizes in the field. It is not React, so the console of [ADR-0401](0401-internal-admin.md), the component library, and the hiring pool all change with it |
| Nuxt | Vue, with server routes through Nitro | none. Nitro targets a plain Node server | Nuxt is MIT and independently governed. **Vercel acquired NuxtLabs in 2025** | The same as SvelteKit: a different component ecosystem, with no gain the panel can name. On driver 5, choosing it does not move away from Vercel |
| Astro | islands, static by default | none | Astro Technology Company | Correct for the landing routes and wrong for the panel. Adopting it means two frameworks, against driver 1 |
| A single-page app and a separate static site | none | none | not applicable | The honest baseline. It has two build pipelines and two deploy targets, and the API credential can live only in the browser |

**Driver 5 does not save any of them.** Vercel employs the Next.js team and Svelte's creator, and it acquired NuxtLabs. So three of the six options are in one vendor's orbit, and only TanStack Start is outside it. Every option is MIT and runs as a container here. So the governance column records a relationship, not a dependency. The exit from Next.js is a rewrite of routing and data loading. That exit is expensive because of the framework's shape, not because of who funds it.

### Design system

By exit cost, this is Tier 1, per [ADR-0002](0002-tool-adoption.md). It is the design-system contract, not only a component library. Every screen is built from it, and a replacement means new markup for the whole surface. The comparison uses the two properties that matter after that observation:

- where the source lives
- how easy that source is to read for the person who edits it, which under driver 3 is the design surface itself

| Option | Where the component source lives | Legibility of the source | Accessibility base | Licence | Verdict |
| --- | --- | --- | --- | --- | --- |
| **shadcn/ui** | **vendored into the repository as source** by a CLI that fetches one component at a time. It is edited like first-party code | one file per primitive, plain Tailwind classes, and a variant table, with no wrapper API to learn. It is the most widely copied React component source that exists, so an LLM's edits to it are predictable *(documented)* | Radix primitives underneath | MIT, with no commercial tier above it | **Chosen.** Driver 3 asks which source is the cheapest to read and change in place. Every contributor, human or model, already knows this one |
| Untitled UI React and Tailwind | vendored as source, the same model | a deep folder tree, index barrels, and its own helpers such as `cx`, `sortCx`, and `isReactComponent` to learn before editing a component | React Aria Components underneath | MIT for the React library. **The Figma kit and the PRO component tiers are commercial** | **The displaced choice, with the same shape.** It won an earlier form of driver 3: fidelity to its Figma kit. That assumed design came from that tool. With design authored here, the kit is not a capability, and its layer of house helpers is a cost |
| Mantine | an installed package | a component API, not source. Edits are props and overrides, not markup | its own, good | MIT | A complete library with its own styling engine. That is a second engine next to Tailwind, against principle 5 |
| Park UI | vendored as source, over Ark UI | similar to the choice, with a smaller ecosystem | Ark UI underneath | MIT | The closest structural match. Its primitive layer is younger, and much less is written about it |
| Material UI | an installed package | theme objects and `sx`, and the markup belongs to the library | its own, mature | MIT | It carries a strong visual language that a product design system then fights. Emotion is a second styling engine |
| Radix or React Aria and hand-written components | ours | the highest, because we wrote it | the primitives' | MIT or Apache-2.0 | The honest baseline. The chosen option is this baseline *plus* the components. Choosing the baseline means authoring the design system, which is the work the chosen option buys |

**Vendoring as source makes the exit affordable.** The components are in the repository, and they are edited there. So leaving upstream costs the updates, not the code. That keeps this Tier 1 exit cost at the low end of Tier 1.

**Upstream is kept verbatim.** `shadcn add` regenerates `src/components/ui/`, so a local edit to a primitive costs work on every bump. Deviations go in the token file, which no generator rewrites.

### Localisation

By exit cost, this is Tier 2, per [ADR-0002](0002-tool-adoption.md). The message catalogues are portable JSON. Leaving means a rewrite of the call sites, not of the copy. The comparison uses what a **server-first** app needs from the library. That is less than the feature lists suggest.

| Option | Server-component support | Locale in the URL | Message format | Verdict |
| --- | --- | --- | --- | --- |
| **next-intl** | first-class: the async API for pages, the hook for components, and the locale resolved from a route param *(documented)* | its own routing helpers, with no prefix on the default locale | ICU MessageFormat, so plurals and word order belong to the translator, not to the code | **Chosen.** It is the only option built for the App Router's rendering model, not adapted to it. It also keeps prerendering per locale |
| react-i18next | works, through a provider and a client boundary | written by hand | ICU through a plugin | The most widely deployed i18n library in React. Its server model here is a provider that it was not designed for. Adopting it means we own the routing and the split between server and client |
| Lingui | supported, with a compile step | written by hand | ICU, compiled to a runtime format | The best extraction in the field: messages come out of the source, not a catalogue kept by hand. It also adds a macro or compiler step to a build that this repo keeps free of one |
| Next's own `i18n` config | none, because it is a Pages Router feature | yes, and only there | none | Not available. It is listed because a reader expects to find it. The App Router replaced it with nothing |
| A hand-written dictionary and a hook | whatever we write | written by hand | whatever we write | The honest baseline. It is about 200 lines and no dependency. It stops being cheap at the first plural, the first date, and the first reader who needs `fa` |

**The catalogues are the exit.** They are plain JSON keyed by path, and every option above can read them. So a change of library costs only the call sites. That work is mechanical, and `lint:i18n` shows it while it is half-done.

### Everything else

| Concern | Chosen | Rejected, and why |
| --- | --- | --- |
| Router | **App Router** | Pages Router does not fit the goal of heavy server work and small bundles |
| Styling | **Tailwind, wired CSS-first** | CSS Modules and CSS-in-JS work, but the design contract is in Tailwind tokens. Mixing systems doubles the design-system surface |
| Primitives | **shadcn/ui**, vendored as source by its CLI, built on Radix | Untitled UI is the displaced choice, with the same shape: copied source over headless primitives. It won driver 3 only while design came from a Figma kit. Radix and Tailwind by hand is the same thing without the components. Mantine and Park UI ship their own design language, and this driver keeps that contract for the brand |
| Lint and format | **Biome only** | Biome with a minimal ESLint for the Next plugin is second-best. One tool wins. `next build`, Lighthouse CI, and the typed `next/image` and `next/font` APIs catch the Next-specific rules that matter |
| Unit test runner | **`bun test`** | Vitest and Jest duplicate a Jest-compatible runner that the only JS runtime already ships |
| Spec renderer | **Scalar** | Redoc's request console is behind a paywall. That breaks the same-origin try-it console that the URL layout was built for. A docs platform, such as Fern or Mintlify, is a separate stateful service that duplicates the SDK codegen. **Stoplight Elements** is the alternative with equal capability. The two are interchangeable, because both render the same committed spec |
| Access-denial UI | **the framework's `unauthorized.js` and `forbidden.js` interrupts** | An error boundary carries no status, misses the return path of a Server Action, and shows every denial as a crash. A per-page check is the same branch written once per route, and the forgotten one fails silently |
| Feature flags | **OpenFeature SDK, noop provider** | Vercel `flags` is specific to a runtime and wrong for an in-cluster Bun runtime |
| Component catalogue | **an in-repo kitchen-sink route**, which also shows the brand | Storybook is useful, but it is not load-bearing with one app. Design is authored in the repository, so there is no second place to see a primitive. So the route is the catalogue, not a copy of one. The deferral below holds the condition |
| i18n | **`next-intl`, from day one, enforced** | A retrofit of localisation means finding every string already shipped, and an extraction pass misses exactly the interpolated ones. Before the first screen, adoption costs a library and a message file. After it, adoption costs a sweep of the whole surface. The comparison is above |
| Server-state fetching | **TanStack Query** for client-side reads | With RSC only, every interactive refetch becomes a route transition. SWR is lighter, but it lacks the mutation and invalidation model that the panel uses |
| Client state | **Zustand** for the little state that outlives a component tree | Jotai and Valtio are equal at this size, so the question is which one, not whether. XState is right for flows with real state, and it is a modelling commitment the panel does not need. Redux and MobX are on nobody's shortlist here |
| Forms | **`react-hook-form`** | TanStack Form is the closer competitor, and it is younger. Conform is server-action-first, which couples form code to one framework's action model |
| Browser telemetry | **Grafana Faro** through the collector | The OTel web SDK alone has no session or web-vitals support. A Sentry browser SDK implies the error backend that [ADR-0503](0503-error-tracking.md) declines |

## Decision

### Rendering

Components are server components by default. `"use client"` is added at the smallest boundary that needs interactivity. Server Actions are permitted for form submission against the service that owns the route group. Cross-service mutations go through the service's REST API and the workflow-handle pattern, per [ADR-0302](0302-temporal.md).

Every route segment ships `loading.tsx` and `error.tsx`. Every route-group root also ships `not-found.tsx`.

### Data fetching

| Context | Mechanism |
| --- | --- |
| Server components | the generated SDKs, through an app-local server-only fetcher marked `import "server-only"`. It forwards the Kratos session cookie and the W3C trace context. Direct `fetch` to service URLs is not used |
| Client components | TanStack Query around the same SDKs, with query keys derived from `operationId` |
| Mutations | Server Actions for a single service. Otherwise, a `202 Accepted` workflow handle that the client polls |

The `server-fetch` directory has **no barrel**. Client code imports the client entry, and server code imports the server entry. So server-only modules never leak into a client bundle.

### Styling

The app follows shadcn/ui's integration exactly, so a component that the CLI fetches works without change.

| Element | Decision |
| --- | --- |
| System | Tailwind, wired CSS-first with no config file. CSS Modules and CSS-in-JS are not used in app code. Third-party components that ship their own styles are the exception |
| Tokens | `src/styles/theme.css`, imported by the global stylesheet. **There is no JS token mirror.** A TypeScript consumer that needs a raw value reads the CSS variable |
| Roles | every colour is a pair of `--<role>` and `--<role>-foreground`, declared in both palettes. [docs/brand.md](../brand.md) says what each role is for. The values live only here |
| Class composition | the `cn` package, which the generated components import. No second house helper is added next to it |
| Dark mode | `next-themes`, which writes `.dark` on the root element |

Token edits are PRs. `lint:contrast` scores the pairs on both palettes before a PR merges. The CLI's own configuration lives in `apps/frontend/components.json`. It names the style, the base colour, and the icon set, so `shadcn add` produces the same component for everyone.

### Code layout: one app, no first-party packages

The frontend code has exactly one consumer. Route groups are folders in that app, with one bundle and one `node_modules`. They are not independent build targets.

**A workspace package is worth its cost only for a second independent consumer, or for a generated artifact.** Splitting single-consumer code into packages gains nothing and costs real ceremony:

- dependencies per package
- peer dependencies to keep a single React instance
- transpile configuration
- path aliases

Under Bun's isolated linker, that ceremony is load-bearing. So a missing entry breaks the build. It is not a small lint issue.

| Code | Location |
| --- | --- |
| UI primitives | `src/components/{base,application,foundations}/` |
| Design tokens | `src/styles/` |
| `cx`, `sortCx`, and helpers | `src/utils/` |
| Server and client fetchers | `src/lib/server-fetch/` |
| Browser and server telemetry | `src/lib/observability/` |
| Feature flags | `src/lib/feature-flags.ts` |
| User-facing strings | `src/messages/<locale>.json`, one catalogue per locale |
| Generated API SDKs | `libs/ts/sdks/<service>/`, the **only** `libs/ts` members |

### Component library

Primitives live under `src/components/ui/`. `shadcn add` writes them there, and nobody writes them by hand. First-party components live next to that directory, in their own folder. Route groups compose both by explicit path and do not duplicate them. The heuristic: if two route groups would copy a component, it belongs under `src/components/`.

`shadcn/ui` ships source that the project owns. It is built on [Radix primitives](https://www.radix-ui.com/primitives) for accessibility, and it is vendored as committed source, not fetched at runtime. `src/components/ui/` stays verbatim by design. So a new component or a bump is a clean diff, not a rewrite. That is why a deviation belongs in the token file.

**The kitchen-sink page** is the design catalogue. It shows the brand first: colour roles, chart ramp, type scale, radius, and elevation. Then it shows every primitive once. It is the cheap alternative to Storybook: one route, no separate toolchain, gated by the devportal session. Every primitive added under `src/components/ui/` gets a section there in the same PR. The e2e suite finds the sections on the rendered page. So a new section is scanned and baselined without a test edit.

### Localisation

Localisation is enforced from day one, because the retrofit is the expensive version. [ADR-0701](0701-product-design-and-discovery.md) makes the same argument about design.

| Concern | Decision |
| --- | --- |
| Locales | `en`, `de`, `fa`. The set has a right-to-left locale by design. Mirroring is a case the design system passes on every commit. Without `fa`, nothing keeps the classes logical |
| URL shape | `localePrefix: "as-needed"`. The default locale has no prefix, as in `/panel`. Every other locale carries its tag, as in `/de/panel`. There is one URL per language, and the English addresses, e2e paths, and Lighthouse targets do not change |
| Catalogues | `src/messages/<locale>.json`, one file per locale, ICU MessageFormat |
| Locale resolution | `next/root-params` in `src/i18n/request.ts`, not `setRequestLocale`. The reason is below |
| Negotiation | the `NEXT_LOCALE` cookie first. Then `Accept-Language`, matched by RFC 4647 lookup. Then the default. An explicit choice ranks above a header the reader never set |
| Middleware | the proxy owns locale resolution and the rewrite. next-intl's middleware is not used |
| Fonts | one token, two faces: Inter for Latin locales and Vazirmatn for `fa`, chosen in the locale layout. Inter has no Persian coverage. A translated page in a fallback face is only half localised |
| Direction | `dir` on `<html>` comes from the locale. Layout classes are logical, so the mirror is free |

**The proxy resolves the locale.** next-intl ships a middleware that does the job well, but it owns the rewrite. `src/proxy.ts` also owns the rewrite: it stamps a per-request CSP nonce onto the headers of the rewritten request, per [ADR-0305](0305-edge-auth-and-traffic-policy.md). Two middlewares cannot both rewrite one request, and the response of a second middleware discards those headers. The auth redirects settle the question. A German reader whose session expired belongs on `/de/auth/login`. Only code that already knows the locale can build that URL. The matching is *not* written by hand: `Accept-Language` is parsed and matched with the same library that next-intl uses inside.

**The locale comes from `next/root-params`, not from `setRequestLocale`.** Four files render in every route's shell and receive no props: `loading.tsx`, `not-found.tsx`, `forbidden.tsx`, and `unauthorized.tsx`. They carry copy, so they read messages. next-intl caches its resolved configuration on the **first** call in a request. With `setRequestLocale`, the shell that renders first pins every later message on the page to the default locale. `/de` then serves German markup with English copy. `setRequestLocale` in a layout cannot prevent this, because a file with no props has no locale to pass. Root params are readable anywhere in the render. They fix the correctness bug and also keep prerendering per locale. Upstream deprecates `setRequestLocale` in favour of exactly this.

**A catch-all under the segment**, `[locale]/[...rest]`, turns an unmatched path into a `notFound()` inside the locale tree. Without it, such a path falls out of the segment to Next's own built-in 404. That page is unstyled and English for every reader.

**The design catalogue is exempt**, and `biome.jsonc` says so. Its labels name primitives and show states, so they are not product copy. Fixtures are exempt for the same reason: mock row data is content, not chrome, per [ADR-0701](0701-product-design-and-discovery.md).

### Accessibility

**The target is [WCAG 2.2 level AA](https://www.w3.org/TR/WCAG22/)** across every route group. EN 301 549 and Section 508 reference AA, so a procurement question or a regulator asks about AA. AAA is not adopted. WCAG itself does not recommend AAA as a whole-site target, because content cannot always meet some of its criteria.

Radix supplies keyboard behaviour, focus management, and ARIA semantics for the primitives. That is the floor, not the target. Contrast, heading structure, landmark semantics, and error association are composition decisions, and no primitive library makes them.

| Surface | Claim |
| --- | --- |
| `(landing)`, `(panel)`, `(devportal)` | WCAG 2.2 AA |
| The kitchen-sink page | AA per primitive. A primitive's conformance is proven once here, not again in every consumer |
| Scalar's rendered console | not claimed. It is a vendored island with its own theme. The route group around it is AA |
| Operator tooling: Lowdefy, Grafana, pgweb, per [ADR-0401](0401-internal-admin.md) and [ADR-0501](0501-operator-uis-and-dashboards.md) | not claimed. These are third-party UIs behind an operator session, and the exclusion is stated, not assumed |

**Enforcement is `@axe-core/playwright`** inside the existing e2e suite, per [ADR-0601](0601-testing-strategy.md). There is no second toolchain. Every kitchen-sink section and every product journey is scanned. A `serious` or `critical` violation fails the merge. Colour contrast is also checked against the design-token file, not per component, because a token change moves every surface at once.

### Developer portal renderer

The devportal route group renders the OpenAPI specs through **Scalar**. Scalar is embedded as a client island, never as a separate service.

| Property | Detail |
| --- | --- |
| Why Scalar | a free, built-in request console. It is same-origin with `/api`, per [ADR-0306](0306-trust-tiers-and-urls.md). So the try-it console calls the real edge with the caller's session and needs no CORS |
| What it renders | a **pre-filtered projection**, not the raw specs. `gen:openapi-public` merges the service specs and filters on the `x-audience` ladder. So the renderer sees only what its audience may see. The strip is real, not a UI hide, per [ADR-0303](0303-api-contracts-and-lifecycle.md) |
| Self-hosted | the build bundles the package, and no CDN serves it. Default web fonts are off, so nothing is fetched at runtime |
| CSP fit | its inline styles are covered by `style-src`. It self-hosts its fonts, covered by `font-src 'self'`. Its console fetches same-origin, covered by `connect-src 'self'` |
| Visual island | Scalar ships its own theme, and the portal does not reuse the design system's primitives. This is accepted for one route group. Matching a spec renderer to the design system is not worth the maintenance, and the console is worth more than exact visual match |

The **public docs portal** is anonymous, with no login, which is the norm for public API documentation. It renders only `public` operations. It ships only when a public API ships. Credential management is a separate authenticated surface, per [ADR-0306](0306-trust-tiers-and-urls.md). Reading docs never requires an account. Only key management does.

### Forms, state, and auth wiring

| Concern | Decision |
| --- | --- |
| Forms | `react-hook-form` for orchestration and `zod` for schemas. Schemas for spec operations are generated, committed, and drift-checked in CI. shadcn/ui's `Field` composes the label, the control, its description, and its error, so the ARIA wiring between them is written once. Field markup written by hand blocks review |
| URL state | `nuqs` for filters, pagination, and tab selection |
| Client-only state | Zustand, for state that outlives a component tree. Redux and MobX are not used |
| React Context | only theming and per-route-group session bootstrapping, never cross-cutting state |
| Session | the Next.js proxy checks the Kratos session on `(panel)` and `(devportal)`. `(landing)` is public except for its auth subtree. The proxy forwards a session-id header to server components, and they never call Kratos directly |
| Tokens | the frontend never mints, decodes, or validates JWTs. Server-component calls attach the user's cookie, and Oathkeeper validates it at the edge |
| Sign-in navigation | a redirect into or out of the auth subtree replaces the history entry and never pushes one. The proxy answers with an HTTP redirect. Client code uses `router.replace` or `location.replace`. After a login, Kratos leaves the used flow in the history. So when the login UI finds an existing session, it replaces its own entry with the destination. The back button then never bounces a user between the login flow and the app. A redirect that depends on the session carries `Cache-Control: no-store`. Otherwise the back and forward buttons can replay a redirect from an earlier session state. An example is a redirect to login after the user signed in |

### Access denials

[RFC 9110](https://www.rfc-editor.org/rfc/rfc9110#section-15.5.2) separates the two failures, and the separation decides the UI.

| Failure | Means | Answer |
| --- | --- | --- |
| 401 | the request carries no usable session | redirect to the login flow, with the path and query. Signing in is the fix |
| 403 | the session is valid, and the resource is refused | render at the denied address. Signing in does not help, and the user gives the address to whoever grants access |

The fetch clients raise the denial, not each caller. To a generated client, a 403 is an empty result, not an exception. A page that renders it looks like a service that returned no data. That is [CWE-280](https://cwe.mitre.org/data/definitions/280.html), which the [OWASP Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html) names.

The decision itself stays on the server side, at the edge and in the service, per [ADR-0304](0304-identity-and-authorization.md) and [ADR-0305](0305-edge-auth-and-traffic-policy.md). This follows [ASVS](https://owasp.org/www-project-application-security-verification-standard/) V1.4.1 and V4.1.1. The frontend renders the answer and computes no permission.

**A streamed response cannot carry the status.** The status line comes before the body. So a denial raised after the first `await` below a Suspense boundary arrives inside a `200`, per [Next.js `loading.js`](https://nextjs.org/docs/app/api-reference/file-conventions/loading#status-codes). `notFound()` behaves the same way, so this property belongs to interrupts, not to authorization.

So the status is set where it can be set before a render, in the proxy's session check. Where it cannot be set, it is conceded.

### Content Security Policy

CSP is a frontend responsibility, because a strong policy needs a per-request nonce. The policy follows [CSP Level 3](https://www.w3.org/TR/CSP3/). `strict-dynamic` and nonce sources come from that level. Host-allowlist policies are not used.

- **The proxy generates the nonce** per request. It sets the nonce on both the request header and the response header, with `script-src 'nonce-<x>' 'strict-dynamic'`, `object-src 'none'`, and `base-uri 'self'`. Next propagates it to its own scripts. Inline scripts are not used.
- **`connect-src` allowlists first-party telemetry.** A missing entry breaks browser RUM with no signal, so the kitchen-sink page exercises it.
- **The edge duplicates static hardening** as defence in depth. A Traefik middleware sets the directives that never vary, per [ADR-0305](0305-edge-auth-and-traffic-policy.md). So every route gets them, not only Next pages.

### CSRF

CSRF protection applies to state changes authenticated by a cookie. The browser does not attach bearer tokens, so bearer-token traffic is not exposed.

| Layer | Mechanism |
| --- | --- |
| Cookie | `SameSite=Lax`, `Secure`, `HttpOnly`, per [ADR-0304](0304-identity-and-authorization.md). This alone blocks the classic cross-site POST |
| Kratos self-service flows | Kratos's built-in anti-CSRF cookie and token. The custom login UI does not disable them |
| Server Actions | Next's built-in `Origin` and `Host` check, with allowed origins pinned in config. No hand-written CSRF tokens are added on top |
| Other mutations authenticated by a cookie | rejected at the edge by an Origin allowlist, per [ADR-0305](0305-edge-auth-and-traffic-policy.md) |

### Lint, test, and gates

| Concern | Decision |
| --- | --- |
| Lint and format | **Biome only**, configured at the repo root. `recommended` and `correctness` are at error level. Strict additions include `noExplicitAny`, `noNonNullAssertion`, `useExhaustiveDependencies`, `noFloatingPromises`, and `noConsole`. ESLint is not installed |
| Unit and component tests | `bun test` with Testing Library and `happy-dom`, with coverage thresholds per route group |
| Mocking in tests | MSW, an in-process double scoped to the test runner |
| End-to-end and visual | owned by [ADR-0601](0601-testing-strategy.md), and driven by Playwright from the repo-root workspace. MSW and the development API mock are both forbidden there |
| Bundle size | budgets per route group fail the build on regression |
| Web vitals | Lighthouse CI on every PR. It gates on **LCP under 2.5s**, **INP under 200ms**, and **CLS under 0.1** on the mobile profile. It beats WebPageTest and Calibre, which are hosted and so fail principle 3. It also beats bundle-size checks alone, which measure a proxy, not the metric |
| Images and fonts | `next/image` and `next/font`. Raw `<img>` and `@font-face` are not used |

### Observability

This section wires the browser side of [ADR-0500](0500-observability.md).

- OpenTelemetry web tracing and fetch instrumentation start from a client-only entry. Trace IDs propagate on outbound fetches and join the same trace as the upstream services.
- **Grafana Faro** is the browser RUM agent. It forwards web vitals, JS errors, and session traces to the collector's Faro receiver. They go through an ingest route behind Traefik, on a vendor-neutral path, and land in the same backends as the services. Locally, the dev server runs on the host with no edge, so a dev-only route handler stands in for that path.
- **Faro's session tracking is configured in memory**, not against `sessionStorage` or `localStorage`. The session id lives for the page's lifetime and is never persisted. So the ops path stays clear of ePrivacy `Art. 5(3)` and outside the consent gate, per [ADR-0700](0700-analytics.md). A persistent identifier on this path is a defect, not a feature.
- Server logs are structured JSON to stdout, enriched with the active trace id. Lint forbids `console.log`.
- The build embeds the version, so traces and errors can be attributed to a version, per [ADR-0103](0103-release-and-versioning.md).

### Deferred capabilities

| Capability | Trigger | Seam | Cost if adopted late |
| --- | --- | --- | --- |
| A concrete feature-flag backend | a change must reach some users before others | ✓ application code already calls flags through the OpenFeature API against a noop provider. So only the provider changes | nothing important. That is why the noop provider is wired on day one, and the API is not added later |
| Storybook and a hosted visual review UI | someone who does not run the app edits a component, or a visual regression reaches `master` twice | ⚠ **a bet.** Both use the same committed components, but that is an input format, not a slot. Nothing renders a component in isolation now. So adopting Storybook means writing the stories, not turning on a path | the component set has grown to the size where the kitchen-sink route stops working. Every story is then written at once, against components never designed to render alone |

### Build and local development

The build produces standalone output, and the container runs it under Bun. It uses a multi-stage Dockerfile whose runtime stage installs no Node, per [ADR-0100](0100-language-and-runtime.md). The image deploys through the shared service chart, with route-group ingress paths in the environment's values.

Locally, the dev server runs against `cluster:up`, and the edge is how a developer reaches it. Work on authenticated surfaces uses the real Traefik, Kratos, and Oathkeeper. The API mock serves the application data, per [ADR-0600](0600-local-development-loop.md). **The app's auth path is the same as in production.** The session path has no development-only session, no bypass, and no branch that depends on the environment.

## Consequences

### Positive

- The whole frontend design is one ADR and its citations.
- Server-first rendering keeps bundles small and keeps the design system.
- A single design-token source moves every surface at once, and one gate scores it.
- Biome only is the smallest possible TypeScript toolchain: install, format, and lint in one binary.
- Form, fetch, and state primitives are app-wide, so route groups do not fork them.
- Browser traces continue the same trace id as upstream services.

### Negative and Risks

- **Biome lacks Next-specific lints.** `next build`, Lighthouse CI, and the typed asset APIs mitigate this. It is a different enforcement surface, not a gap in behaviour.
- **shadcn/ui source is vendored and committed**, so a bump is a real PR. The mitigation is to keep `src/components/ui/` verbatim and put every deviation in the token file, which no generator rewrites.
- **The OpenTelemetry web SDK is heavier than Faro alone.** This is accepted. Trace continuity from browser to service is worth the bytes, and the performance gates keep the cost in check.
- **Every route renders per locale.** So the count of prerendered pages is the route count times the locale count. This is accepted. The pages are prerendered at build, not per request. A locale that nobody visits costs build time, not serving cost.
- **A third locale is a third translation of every string.** That is the cost of the decision, not a defect in it. `lint:i18n` shows it at the gate, not on a reader's screen.
- **RTL support means every new class is logical.** `lint:i18n -- -fix` catches and fixes the mechanical cases. Some layouts are wrong only when mirrored, such as an icon that must not flip or a chart axis. No linter judges those.
- **A green axe run is not WCAG conformance.** Automated scanning catches only the part of the success criteria that a machine can check. A tool cannot detect the rest: useful alt text, a sensible reading order, and whether a keyboard can complete a flow. The AA claim depends on correct primitives and on the keyboard pass. The gate only prevents regressions in the part a machine can see.
- **AA is claimed for first-party surfaces and refused for vendored ones.** A user who needs it meets an accessible product panel and an inaccessible Grafana. This is honest, not good. It is the direct cost of not building operator tooling.
- **The Lighthouse thresholds move with the speed of the machine that runs them.** A comparison of two runs is valid only when one session measured both. `environment.benchmarkIndex` in each report shows whether that is true.
- **The 401 page carries no `WWW-Authenticate` header**, which [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110#section-15.5.2) requires for a 401. No registered scheme names a login form, and a `Basic` challenge opens the browser's own credential dialog in place of the form. The mitigation is that the header has no consumer on this surface. A browser with a cookie reaches the page, not a client that could act on a challenge. The form that carries information is [RFC 6750](https://www.rfc-editor.org/rfc/rfc6750#section-3) `Bearer error="invalid_token"`. It belongs to `/api`, where a client holds a refreshable token.
- **A Server Action is an implicit endpoint.** What the function accepts defines its surface, not a spec. So it is limited to single-service mutations, and it never becomes an ad-hoc API for another consumer.

## Rules

- The frontend is one Next.js App-Router application. Pages Router is not used.
- Server Components are the default, and `"use client"` is added at the smallest interactivity boundary.
- Server Actions are permitted only for mutations against the service that owns the route group. Cross-service mutations use the REST API and the workflow-handle pattern.
- Every route segment ships `loading.tsx` and `error.tsx`. Every route-group root also ships `not-found.tsx`. `(CI: ci:lint)`
- First-party frontend code lives in the app. A `libs/ts/*` package is created only for a second consumer or a generated artifact.
- A screen reads and writes through `src/lib/data/`, never through `src/lib/server-fetch/`, a generated SDK, or `src/fixtures/` directly. `(CI: lint:ts)`
- Inside that seam, server components fetch through the server-only fetcher, and client components use TanStack Query over the generated SDKs. Direct `fetch` to service URLs is not used. `(CI: ci:lint)`
- Hand-written request and response types are not declared. Only generated types are used, and form schemas are generated from the spec. `(CI: ci:gen)`
- Tailwind is the styling system, wired CSS-first with no config file. CSS Modules, CSS-in-JS, and inline `<style>` are not used in app code. `(CI: ci:lint)`
- Design tokens come from `apps/frontend/src/styles/theme.css`. There is no JS token mirror, and tokens are not redefined per route group.
- Class composition uses the `cn` package, because the generated components import it. A second helper is not added. `(CI: ci:lint)`
- Primitives are the vendored `shadcn/ui` source under `src/components/ui/`. `shadcn add` writes them, and they are composed by explicit path and never duplicated. A primitive is not edited by hand. A deviation goes in the token file.
- A primitive added under `src/components/ui/` is added to the kitchen-sink page in the same PR. That PR includes a keyboard-only pass of the new section.
- Every route group targets WCAG 2.2 AA. The Scalar console and vendored operator UIs are excluded, and the exclusion is stated, not assumed. `(ref: WCAG 2.2 AA)`
- Every kitchen-sink section and every product journey is scanned with `@axe-core/playwright`. A `serious` or `critical` violation fails the merge. `(CI: e2e)`
- Colour contrast is verified against the design-token file in both palettes, not per component. `(CI: lint:contrast)`
- Icons come from `lucide-react`, the icon set that `components.json` names. Another set requires an ADR amendment.
- Forms use react-hook-form and zod, and every field is composed with `Field` from `src/components/ui/field.tsx`.
- URL state uses `nuqs`, and client-only state uses Zustand. Redux and MobX are not used. `(CI: ci:lint)`
- The proxy enforces the Kratos session on the authenticated route groups. The frontend never mints, decodes, or validates JWTs. `(CI: lint:auth-inline)`
- An access denial is answered by its kind. No session redirects to the login flow with the current path and query. A session without permission renders in place, at the denied URL. `(ref: RFC 9110 §15.5)`
- Denials are raised once, in the fetch clients, and rendered by the framework's `unauthorized.tsx` and `forbidden.tsx`. A route has no auth branch of its own. The frontend computes no permission, and the service decides, per [ADR-0304](0304-identity-and-authorization.md). `(ref: OWASP ASVS V4.1.1)`
- Browser calls to the API go through TanStack Query. A React boundary does not catch what an event handler throws, so a denial raised outside a render reaches no one.
- CSP is set in the proxy with a per-request nonce. Inline scripts are not used, and `connect-src` allowlists the telemetry ingest origin. `(ref: CSP Level 3)`
- CSRF protection rests on the SameSite cookie, Kratos's built-in protection, and the Origin check of Server Actions. Hand-written CSRF tokens are not added.
- Biome is the only lint and format tool. ESLint is not installed. `(CI: ci:lint)`
- `bun test` covers unit and component tests. Vitest and Jest are not used.
- The frontend contains no development-only authentication code. `(CI: lint:auth-inline)`
- Browser observability is OpenTelemetry web and Faro, exporting through the edge to the collector. Faro's session id is in memory and per page. The ops path writes nothing to client-side storage, per [ADR-0700](0700-analytics.md).
- Server logs are structured JSON to stdout. `(CI: ci:lint)`
- A client provider mounts at the route group that uses it. Only providers that must wrap every route belong in the root layout.
- A browser SDK that first paint does not need is loaded with a dynamic `import()`. A static import decides when a bundle is downloaded and parsed, and a deferred call does not change that. So nothing in the initial graph statically imports one.
- A redirect that can be decided before rendering comes from the proxy, not from a page. Behind a `loading.tsx` boundary, a page-level redirect ships as a rendered 200.
- A redirect into or out of the auth subtree replaces the history entry and never pushes one. When the login UI finds an existing session, it replaces its own entry with the destination.
- A redirect that depends on the session carries `Cache-Control: no-store`.
- Server components do not call the identity provider. Browser flows reach it through the edge, per [ADR-0304](0304-identity-and-authorization.md). That is the only path the network policy allows.
- Bundle budgets and the Lighthouse thresholds are merge gates.
- Images go through `next/image`, and fonts go through `next/font`. `(CI: ci:lint)`
- Every string that a reader sees comes from `src/messages/<locale>.json` through next-intl. A literal in JSX or in an attribute that carries copy blocks the merge. `(CI: lint:ts)`
- Every catalogue has identical keys, and the locale set includes at least one right-to-left locale. `(CI: lint:i18n)`
- Layout classes are logical, such as `ms-`, `pe-`, `text-start`, and `start-`, and never physical. Centring fractions are the stated exception. `(CI: lint:i18n)`
- A sentence broken by a link or a `<code>` stays one key, interpolated with `t.rich`. It is never split into two keys.
- The locale is resolved from the `[locale]` root param, and the default locale is served with no prefix.
- Internal navigation uses the helpers in `src/i18n/navigation.ts`, so no href carries a locale prefix written by hand.
- Feature flags go through the OpenFeature API with a noop provider.
- The container runs the standalone build under Bun and installs no Node. `(CI: lint:node-scope)`
