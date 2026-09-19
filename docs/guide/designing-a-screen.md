# Designing a screen

How a screen goes from nothing to shipped, in one repository, with no hand-off ([ADR-0701](../adr/0701-product-design-and-discovery.md)).

## Before writing any markup

Answer two questions, in one sentence each:

- **Who is this screen for?** A role, not "the user".
- **What must it prove?** The one thing a person should be able to do or see. A screen with three answers is three screens.

If the answers need research, that goes in [`docs/product/`](../product/README.md) first. If they do not, skip it.

## Build it

1. **Create the route at its final URL.** `src/app/[locale]/(<group>)/<path>/page.tsx`. Not a prototype path, not a `-v2` suffix — the URL it will ship on.
2. **Add the seam and its fixture.** `src/lib/data/<domain>.ts` for the function the screen calls, `src/fixtures/<domain>.ts` for what it returns while the service does not exist. Deterministic: no `Math.random()`, no `new Date()` at render.
3. **Run with the switch on.** `NEXT_PUBLIC_FIXTURES=1 mise run dev:frontend`.
4. **Write the copy as keys, not as text.** Every string goes into `src/messages/en.json` and then into `de.json` and `fa.json` — all three, in the same change, or `lint:i18n` fails on parity. A literal in the markup fails `lint:ts`. Use `t.rich` for a sentence containing a link; never split one sentence into two keys.
5. **Check the mirror.** Open the screen at `/fa/…` before calling it done. Use logical classes (`ms-`, `pe-`, `text-start`) so it mirrors for free; `mise run lint:i18n -- -fix` converts the mechanical cases.
6. **Compose from `src/components/ui/`.** Reach for a primitive before writing markup; add a missing one with `shadcn add <name>`, which also adds it to the design catalogue's job list. Fields are composed with `Field`, never hand-wired.
7. **Use the tokens.** `bg-card`, `text-muted-foreground`, `border-border`. A raw colour in a screen is a token that escaped — what each role is for is [docs/brand.md](../brand.md).

**Make the fixture full.** Eight to fifteen rows, not two. Long names, ragged numbers, a failed row among the successful ones. Two tidy rows hide every layout decision the real data will force, and a screen designed against them breaks on the first production page.

**Say what you faked.** One line, in the PR: which numbers are invented, which states are unreachable, what the empty case does. That sentence is what stops a demo being mistaken for a feature.

## Iterating, and redesigning

A variant is a branch, and two candidates are two preview deployments of the real application ([ADR-0205](../adr/0205-environment-parity.md)) — clickable, on a real URL, on a phone if that matters. There is no committed menu of alternatives: the losing branch closes.

Redesigning a screen that already ships is the same motion. Branch, delete its files, rebuild against the same seam. If it was promoted, point the seam back at a fixture on that branch while the shape is in flux.

## Promoting it

A screen is finished when all five are true:

| Step | What it means |
| --- | --- |
| Data | the seam calls the service; the fixture stays, for design and for previews |
| Copy | every string is a key in all three catalogues, none inline in the markup |
| Accessibility | a `test()` block in `test/e2e/platform/a11y.spec.ts` for the journey, and a keyboard-only pass by hand |
| Visual | a baseline taken with `mise run e2e:visual -- --update-snapshots`, committed in the same PR |
| Catalogue | any new primitive has a kitchen-sink section |

Then drop nothing: the fixture and the seam stay. They are what make the screen designable again.

## What the gates will stop

- A production build with `NEXT_PUBLIC_FIXTURES` set fails outright. Fixtures cannot ship.
- Importing `server-fetch`, a generated SDK, or a fixture from a page or a component fails `lint:ts`. Data goes through `src/lib/data/`.
- A token pair below WCAG AA fails `lint:contrast`, in either palette.
- Copy in the markup fails `lint:ts`; a key missing from one catalogue, or a physical layout class, fails `lint:i18n`.
- A `serious` or `critical` axe violation on a promoted journey fails the merge.
