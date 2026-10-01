# Product research

This directory holds dated observations of the outside world: what else exists, what the words mean, and who the product is for. **It is evidence, not law**, per [ADR-0701](../adr/0701-product-design-and-discovery.md).

The whole convention is three rules:

1. **Every file has an `as-of` date and its sources.** Start from [`_template.md`](_template.md). A claim about another product is true on one date, and not after it.
2. **Nothing here binds anything.** A research file cannot be the stated reason for a change. A finding binds only when an ADR cites it. Then the ADR is the law.
3. **Add only what this product needs.** No file here is required. An empty directory is a normal state.

## Files a product may add

These names exist so that a second author picks the same filename. No file is expected.

| File | Answers |
| --- | --- |
| `landscape.md` | what else exists, and what each product optimises for |
| `terminology.md` | the words this domain uses, and which of them we adopt |
| `personas.md` | who the product is for, what their job is, and what they use today |
| `positioning.md` | the wedge, the claims, and what we refuse to do |
| `flows.md` | the journeys, in words, before they become screens |
| `surfaces.md` | the screens, who each screen is for, and what each must prove |

## Competitor evidence

Screenshots and copy from another product go in `evidence/`. Each item has a line that says where and when it came from. They are the marks of that company, and we keep them for internal research. **Nothing here is reachable from a public surface.** This covers:

- the marketing site
- a deck that leaves the company
- a published artifact
