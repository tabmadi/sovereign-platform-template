# Designing a screen

This guide takes a screen from nothing to shipped, in one repository, with no hand-off, per [ADR-0701](../adr/0701-product-design-and-discovery.md).

## Before writing any markup

Answer two questions, in one sentence each:

- **Who is this screen for?** Name a role, not `the user`.
- **What must it prove?** Name the one thing a person must be able to do or see. A screen with three answers is three screens.

If the answers need research, put it in [`docs/product/`](../product/README.md) first. If they do not, skip this step.

## Build it

1. **Create the route at its final URL:** `src/app/[locale]/(<group>)/<path>/page.tsx`. Do not use a prototype path or a `-v2` suffix. Use the URL that the screen ships on.
2. **Add the seam and its fixture.** Put the function that the screen calls in `src/lib/data/<domain>.ts`. Put its return value in `src/fixtures/<domain>.ts` while the service does not exist. Keep the fixture deterministic: no `Math.random()` and no `new Date()` at render.
3. **Run with the switch on:** `NEXT_PUBLIC_FIXTURES=1 mise run dev:frontend`.
4. **Write the copy as keys, not as text.** Add every string to `src/messages/en.json`, `de.json`, and `fa.json` in the same change. If one is missing, `lint:i18n` fails on parity. A literal in the markup fails `lint:ts`. Use `t.rich` for a sentence that contains a link. Never split one sentence into two keys.
5. **Check the mirror.** Open the screen at `/fa/<path>` before you call it done. Use logical classes such as `ms-`, `pe-`, and `text-start`, so the layout mirrors with no extra work. `mise run lint:i18n -- -fix` converts the mechanical cases.
6. **Compose from `src/components/ui/`.** Use a primitive before you write markup. Add a missing primitive with `shadcn add <name>`. This also adds it to the job list of the design catalogue. Compose fields with `Field`. Never wire them by hand.
7. **Use the tokens:** `bg-card`, `text-muted-foreground`, `border-border`. A raw colour in a screen is a token that escaped. [docs/brand.md](../brand.md) gives the purpose of each role.

**Make the fixture full.** Use eight to fifteen rows, not two. Add long names, uneven numbers, and a failed row among the successful ones. Two tidy rows hide every layout decision that the real data forces. A screen designed against them breaks on the first production page.

**Say what you faked.** Write one line in the PR. State which numbers are invented, which states are unreachable, and what the empty case does. That line stops people from mistaking a demo for a feature.

## Iterating, and redesigning

A variant is a branch. Two candidates are two preview deployments of the real application, per [ADR-0205](../adr/0205-environment-parity.md). Each one is clickable, on a real URL, and on a phone if that matters. The repo keeps no committed menu of alternatives. The losing branch closes.

A redesign of a shipped screen uses the same method. Create a branch, delete the screen's files, and rebuild against the same seam. If the screen was promoted, point the seam back at a fixture on that branch while the shape changes.

## Promoting it

A screen is finished when all five rows are true:

| Step | What it means |
| --- | --- |
| Data | the seam calls the service. The fixture stays, for design and for previews |
| Copy | every string is a key in all three catalogues, and none is inline in the markup |
| Accessibility | a `test()` block for the journey in `test/e2e/platform/a11y.spec.ts`, and a manual keyboard-only pass |
| Visual | a baseline taken with `mise run e2e:visual -- --update-snapshots`, committed in the same PR |
| Catalogue | every new primitive has a kitchen-sink section |

Then delete nothing. The fixture and the seam stay. They let you design the screen again.

## What the gates stop

- A production build with `NEXT_PUBLIC_FIXTURES` set fails. Fixtures cannot ship.
- An import of `server-fetch`, a generated SDK, or a fixture from a page or a component fails `lint:ts`. Data goes through `src/lib/data/`.
- A token pair below WCAG AA in either palette fails `lint:contrast`.
- Copy in the markup fails `lint:ts`.
- A key missing from one catalogue fails `lint:i18n`. A physical layout class also fails it.
- A `serious` or `critical` axe violation on a promoted journey fails the merge.
