# Product research

Dated observations of the outside world: what else exists, what the words mean, who this is for. **Evidence, not law** ([ADR-0701](../adr/0701-product-design-and-discovery.md)).

Three rules, and they are the whole convention:

1. **Every file carries an `as-of` date and its sources.** Start from [`_template.md`](_template.md). A claim about another product is true on a date and not after it.
2. **Nothing here binds anything.** A research file cannot be the stated reason for a change. A finding becomes binding by an ADR citing it, and then the ADR is the law.
3. **Add only what this product needs.** No file here is required, and an empty directory is a normal state.

## Files a product may add

Named so that a second author reaches for the same filename, not because any is expected:

| File | Answers |
| --- | --- |
| `landscape.md` | what else exists, and what each of them optimises for |
| `terminology.md` | the words this domain uses, and which of them we adopt |
| `personas.md` | who this is for, what their job is, what they use today |
| `positioning.md` | the wedge, the claims, and what we refuse to do |
| `flows.md` | the journeys, in words, before they are screens |
| `surfaces.md` | the screens, who each is for, and what each must prove |

## Competitor evidence

Screenshots and copy from another product go in `evidence/`, with a line naming where and when each came from. They are that company's marks, kept for internal research: **nothing here is reachable from a public surface** — not the marketing site, not a deck that leaves the building, not a published artifact.
