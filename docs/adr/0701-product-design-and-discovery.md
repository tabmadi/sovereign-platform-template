# ADR-0701: Product Design and Discovery

- **Status:** Accepted
- **Date:** 2026-09-19
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0001](0001-documentation-and-output-conventions.md), [ADR-0205](0205-environment-parity.md), [ADR-0400](0400-frontend.md), [ADR-0601](0601-testing-strategy.md), [ADR-0700](0700-analytics.md)
- **Decides:** Design is authored in this repository against one data seam, and product research is dated evidence that binds nothing until an ADR cites it.

## Context

On any product, two kinds of work come before code: finding what to build, and deciding how it looks. Neither had a home here. The ADR set pinned the frontend stack and the testing gates. It also named an external design tool as the source of truth for the visual design. This platform has no path to receive a hand-off from that tool.

This ADR decides three things:

- where design happens
- what makes a screen designable before its API exists
- where research lives

Out of scope: how a product decides its own roadmap, and the content of any one product's research.

## Decision drivers

1. **One artefact, not two.** A design outside the repository is a second description of the product. The two disagree from the first sprint. This is principle 2: one way to do things.
2. **Design comes back for the life of the product.** The first screen is the cheap case. The expensive case is a redesign two years later, against changed components and a refined brand. So design uses the same path the product is built on, not a separate path that nobody maintains.
3. **A screen is designable before its service is.** Design and backend work at different speeds. If the API must come first, the design waits for it.
4. **Fixtures never reach production.** Invented data that looks real is a failure that a reviewer cannot see.
5. **Scope is per-product, and most of it is optional.** This follows the cost discipline of principle 7 in [ADR-0000](0000-platform-foundations.md). One product needs personas. The next goes straight to screens. A project deletes structure that assumes otherwise.

## Considered options

The question is where design is authored. By exit cost this is Tier 2, per [ADR-0002](0002-tool-adoption.md). Leaving means moving the work, not rewriting the product, so the table is short.

| Option | Cost of the first screen | Cost of the tenth redesign | How a design becomes code | Verdict |
| --- | --- | --- | --- | --- |
| **In this repository, at the screen's final URL** | a route, its fixtures, and the gates that already run | the same as the first: branch, edit, preview | it is already code *(reasoned)* | **Chosen.** Driver 2 is the whole decision. This is the only option where the second year costs the same as the first week |
| An external design tool, handed over | the lowest, with no toolchain at all | low in the tool, then paid again in translation, every time | a person reads the file and writes markup that is close to it | **The runner-up, on the first half of driver 1 only.** Every screen is authored twice, and the copies diverge. The platform also cannot gate what it cannot read |
| A separate prototype repository | the lowest of the three in week one: an empty repo and no gates | **the highest.** The components have diverged and the brand has changed. A new mock of a mature product is a rewrite | a port: markup is translated and tokens are matched again | Loses on driver 2, which describes most of a product's life |
| A prototype app or route group inside this repository | low | low | a file move and new wiring | The closest to the choice. The difference is a permanent exception zone in every gate. The data seam gives the same result without one |

**The chosen option's cost is not zero.** Sketching happens under strict TypeScript, Biome, and an axe scan. A throwaway sketch has none of these. This cost is accepted. The accessibility gates change layout decisions at the point where the change is still free. A hand-off lets exactly this class of defect through.

## Decision

### Design is authored here

No external design tool is a source of truth, and there is no design hand-off. A screen is built in `apps/frontend/` at the URL it ships on. It uses the real shell, the real tokens, and the real primitives, per [ADR-0400](0400-frontend.md).

Three artefacts hold the design system, and they do not overlap:

| Artefact | Holds | Form |
| --- | --- | --- |
| `apps/frontend/src/styles/theme.css` | every colour, radius, and font **value** | the only source, with no JS mirror |
| [docs/brand.md](../brand.md) | what each role is **for**, the voice, and what the brand refuses to do | prose, with no values |
| the kitchen-sink route | the brand and every primitive, **rendered**, in both palettes | a page, gated by the devportal session |

### Design mode is a data mode

A screen under design differs from a finished screen only in where its data comes from. Its location, its stack, and its gates are the same.

| Concern | Decision |
| --- | --- |
| The seam | `src/lib/data/<domain>.ts`. A screen calls it, and it resolves to the generated SDK or to a fixture |
| Fixtures | `src/fixtures/<domain>.ts`, committed and deterministic. No `Math.random()`, and no `new Date()` at render |
| The switch | `NEXT_PUBLIC_FIXTURES=1`, read in `src/lib/data/mode.ts` and nowhere else |
| The production guard | that module throws when the switch is set in a production build. This fails the build during prerender |
| Enforcement | `noRestrictedImports` in `biome.jsonc`. Nothing under `app/` or `components/` imports `server-fetch`, a generated SDK, or a fixture |

To promote a designed screen:

1. Point the seam at the service.
2. Key its copy in every message catalogue.
3. Add the journey to the axe suite.
4. Take a visual baseline.

The markup does not change, because it was never a translation.

**Two designs are compared as two preview deployments** of the real application. They run on the tier that [ADR-0205](0205-environment-parity.md) already defines. There is no menu of mock screens, and no prototype route to delete before launch.

### Product research is evidence

Research lives in `docs/product/`, and it is a genre of its own: dated observations of the outside world, with sources. It is not a decision, and it has no authority. A research document is never the reason for a change. A finding becomes binding when an ADR cites it in its Context. From then on, the decision is the law, not the evidence, per [ADR-0001](0001-documentation-and-output-conventions.md).

The template ships only that directory's README and a template. A product adds the files it needs, and no file is required. Examples are:

- landscape
- terminology
- personas
- positioning
- flows
- surfaces

Research that nobody needed is not a gap.

**Competitor evidence is internal.** Screenshots and copy from another product are that product's marks. They are kept for research and are never reachable from a public surface.

## Consequences

### Positive

- There is one description of the product: the code that ships.
- A redesign in year two is the same work as the design in week one.
- A screen can be built, reviewed on a real URL, and shown to a customer before its service exists.
- The clickable hi-fi demo is not a separate artefact. It is this application, with the switch on, on a preview deployment.
- The accessibility and contrast gates apply while a layout is still cheap to change.

### Negative and Risks

- **Sketching is slower than in a throwaway.** Strict types, Biome, and the axe scan all apply. This is accepted, and the options table states the trade: the port step disappears completely.
- **The seam decays as soon as a screen bypasses it.** A screen wired straight to the SDK can never be designed against a fixture again. The import restriction mitigates this: it fails `lint:ts`, so review does not have to catch it.
- **A fixture looks exactly like real data.** That makes it useful, and it also makes a shipped fixture invisible. The build-time guard mitigates this, not discipline.
- **Research goes stale without a signal.** A competitor's UI changes without notice. The only mitigation is the `as-of` line on every research document. This is a convention, and nothing enforces it.
- **`docs/product/` can stay empty for the life of a project.** This is accepted. An empty optional directory costs one line in an index. The alternative is six files about someone else's product.

## Rules

- Design is authored in this repository. No external design tool is a source of truth, and no file outside the repository specifies a screen.
- The design system's values live only in `apps/frontend/src/styles/theme.css`. What the roles are for lives only in [docs/brand.md](../brand.md). `(CI: lint:contrast)`
- A screen reads and writes through `src/lib/data/`. It does not import `src/lib/server-fetch/`, a generated SDK, or `src/fixtures/` directly. `(CI: lint:ts)`
- Fixtures are deterministic: no `Math.random()`, and no `new Date()` evaluated at render.
- Fixture mode is `NEXT_PUBLIC_FIXTURES`, resolved in `src/lib/data/mode.ts`. A production build with it set fails.
- A screen is promoted in one PR. The PR points its seam at the service and keys its copy in every message catalogue. It also adds its journey to the axe suite and takes a visual baseline.
- Two candidate designs are compared as two preview deployments, not as a committed menu of alternatives.
- Product research lives in `docs/product/` and carries an `as-of` date and its sources. It binds nothing until an ADR cites it.
- No research document is mandatory, and none is generated into a project that did not ask for it.
- Third-party screenshots and copy kept as research are not reachable from any public surface.
