# ADR-0701: Product Design & Discovery

- **Status:** Accepted
- **Date:** 2026-09-19
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0001](0001-documentation-and-output-conventions.md), [ADR-0205](0205-environment-parity.md), [ADR-0400](0400-frontend.md), [ADR-0601](0601-testing-strategy.md), [ADR-0700](0700-analytics.md)
- **Decides:** Design is authored in this repository against one data seam, and product research is dated evidence that binds nothing until an ADR cites it.

## Context

Two kinds of work precede code on any product: finding out what to build, and deciding what it looks like. Neither had a home here. The ADR set pinned the frontend stack and the testing gates, and named an external design tool as the authoring source of truth for the visual design — a hand-off this platform has no path to receive.

What is being decided is where design happens, what makes a screen designable before its API exists, and where research lives. What is out of scope: how a product decides its own roadmap, and the content of any particular product's research.

## Decision drivers

1. **One artefact, not two.** A design that lives outside the repository is a second description of the product, and the two disagree from the first sprint. Principle 2: one way to do things.
2. **Design is re-entered for the life of the product.** The first screen is the cheap case. The expensive case is redesigning a screen two years in, against components that have moved and a brand that has been refined — so the design path must be the same path the product is built on, not a separate one nobody maintains.
3. **A screen is designable before its service is.** Design pace and backend pace are different; requiring the API first makes the design wait for it.
4. **Fixtures must not reach production.** Invented data that looks real is the failure mode a reviewer cannot see.
5. **Scope is per-product, and most of it is optional** ([ADR-0000](0000-platform-foundations.md), principle 7's cost discipline). One product needs personas; the next goes straight to screens. Structure that assumes otherwise is structure a project deletes.

## Considered options

Where design is authored. Tier 2 by exit cost ([ADR-0002](0002-tool-adoption.md)) — leaving means re-siting the work, not rewriting the product — so a short table.

| Option | Cost of the first screen | Cost of the tenth redesign | How a design becomes code | Verdict |
| --- | --- | --- | --- | --- |
| **In this repository, at the screen's final URL** | a route, its fixtures, and the gates that already run | the same as the first: branch, edit, preview | it already is code *(reasoned)* | **Chosen.** Driver 2 is the whole decision, and this is the only option where the second year costs what the first week did |
| An external design tool, handed over | lowest — no toolchain at all | low in the tool, then paid again in translation, every time | a person reads the file and writes markup that approximates it | **The runner-up on driver 1's first half only.** Every screen is authored twice and the copies diverge; the platform also cannot gate what it cannot read |
| A separate prototype repository | lowest of the three in week one — an empty repo and no gates | **highest.** The components have diverged, the brand has moved, and re-mocking a mature product is a rewrite | a port: markup translated, tokens re-matched | Loses on driver 2, which is the driver that describes most of a product's life |
| A prototype app or route group inside this repository | low | low | a file move plus rewiring | Closest to the choice, and the difference it buys is a permanent exception zone in every gate. The data seam achieves the same thing without one |

**The chosen option's cost is not zero.** Sketching happens under strict TypeScript, Biome, and an axe scan, where a throwaway would have none. That is accepted: the accessibility gates in particular change layout decisions while changing them is still free, which is the class of defect a hand-off leaks.

## Decision

### Design is authored here

There is no external design tool that is a source of truth, and no design hand-off. A screen is built in `apps/frontend/` at the URL it will ship on, in the real shell, on the real tokens, out of the real primitives ([ADR-0400](0400-frontend.md)).

Three artefacts carry the design system, and they do not overlap:

| Artefact | Holds | Form |
| --- | --- | --- |
| `apps/frontend/src/styles/theme.css` | every colour, radius and font **value** | the only source; no JS mirror |
| [docs/brand.md](../brand.md) | what each role is **for**, the voice, and what the brand refuses to do | prose, no values |
| the kitchen-sink route | the brand and every primitive, **rendered**, in both palettes | a page, gated by the devportal session |

### Design mode is a data mode

What separates a screen under design from a finished one is where its data comes from. Nothing else — not its location, not its stack, not which gates apply.

| Concern | Decision |
| --- | --- |
| The seam | `src/lib/data/<domain>.ts`. A screen calls it; it resolves either the generated SDK or a fixture |
| Fixtures | `src/fixtures/<domain>.ts`, committed, deterministic — no `Math.random()`, no `new Date()` at render |
| The switch | `NEXT_PUBLIC_FIXTURES=1`, read in `src/lib/data/mode.ts` and nowhere else |
| The production guard | that module throws when the switch is set in a production build, which fails the build during prerender |
| Enforcement | `noRestrictedImports` in `biome.jsonc`: nothing under `app/` or `components/` imports `server-fetch`, a generated SDK, or a fixture |

Promoting a designed screen is: point the seam at the service, keying its copy in every message catalogue, add the journey to the axe suite, take a visual baseline. The markup does not change, because it was never a translation.

**Comparing two designs is two preview deployments** of the real application, on the tier [ADR-0205](0205-environment-parity.md) already defines. There is no menu of mock screens, and no prototype route to delete before launch.

### Product research is evidence

Research lives in `docs/product/`, and is a genre of its own: dated observations of the outside world, with sources. It is not a decision and carries no authority — a research document cannot be cited as the reason for a change. What makes a finding binding is an ADR citing it in its Context, at which point the decision, not the evidence, is the law ([ADR-0001](0001-documentation-and-output-conventions.md)).

The template ships that directory's README and a template, and nothing else. A product adds the files it needs — landscape, terminology, personas, positioning, flows, surfaces — and no file is required. Research that nobody needed is not a gap.

**Competitor evidence is internal.** Screenshots and copy from another product are that product's marks, kept for research and never reachable from a public surface.

## Consequences

### Positive

- One description of the product, which is the code that ships.
- Redesigning in year two is the same motion as designing in week one.
- A screen can be built, reviewed on a real URL, and shown to a customer before its service exists.
- The clickable hi-fi demo is not a separate artefact: it is this application, with the switch on, on a preview deployment.
- The accessibility and contrast gates apply while a layout is still cheap to change.

### Negative / Risks

- **Sketching is slower than in a throwaway.** Strict types, Biome, and the axe scan all apply. Accepted, and the trade is stated in the options table: the port step disappears entirely.
- **The seam decays the moment it is bypassed.** A screen wired straight to the SDK can never be designed against a fixture again. Mitigated by the import restriction, which fails `lint:ts` rather than review.
- **A fixture looks exactly like real data**, which is what makes it useful and what makes shipping it invisible. Mitigated by the build-time guard, not by discipline.
- **Research goes stale silently.** A competitor's UI changes without telling anyone. Mitigated only by the `as-of` line every research document carries — this is a convention, and nothing enforces it.
- **`docs/product/` may stay empty for the life of a project.** Accepted: an empty optional directory costs a line in an index, and the alternative is six files of someone else's product.

## Rules

- Design is authored in this repository. No external design tool is a source of truth, and no screen is specified by a file outside it.
- The design system's values live only in `apps/frontend/src/styles/theme.css`; what the roles are for lives only in [docs/brand.md](../brand.md). `(CI: lint:contrast)`
- A screen reads and writes through `src/lib/data/`. It does not import `src/lib/server-fetch/`, a generated SDK, or `src/fixtures/` directly. `(CI: lint:ts)`
- Fixtures are deterministic: no `Math.random()`, and no `new Date()` evaluated at render.
- Fixture mode is `NEXT_PUBLIC_FIXTURES`, resolved in `src/lib/data/mode.ts`, and a production build with it set fails.
- A screen is promoted by pointing its seam at the service, keying its copy in every message catalogue, adding its journey to the axe suite, and taking a visual baseline in the same PR.
- Two candidate designs are compared as two preview deployments, not as a committed menu of alternatives.
- Product research lives in `docs/product/`, carries an `as-of` date and its sources, and binds nothing until an ADR cites it.
- No research document is mandatory, and none is generated into a project that did not ask for it.
- Third-party screenshots and copy kept as research are not reachable from any public surface.
