# Brand

What each design token is *for*. The values are in `apps/frontend/src/styles/theme.css` and nowhere else; the rendered version is the kitchen-sink route, which shows this brand in both palettes as the product draws it ([ADR-0400](adr/0400-frontend.md)).

This file carries no colour values. One source for a value means one place to change it, and a document that restated the palette would be a second source that drifts silently ([ADR-0001](adr/0001-documentation-and-output-conventions.md)).

**A generated project rebrands by editing `:root` and `.dark` in that file.** Everything below describes what the roles mean, so an editor knows which one to move.

## Colour roles

Each role is a couple: a surface, and the foreground used on it. Every role appears in both palettes, and `mise run lint:contrast` scores every pair in both before a change merges.

| Role | The surface it paints | The foreground beside it |
| --- | --- | --- |
| `background` | the page | all body text |
| `card` | anything raised off the page — cards, popovers, dialogs | text on that raised surface |
| `primary` | the one action a screen wants taken | text on that action |
| `secondary` | an action that is available but not the point | text on it |
| `muted` | a recessed area, and the colour of explanatory text on any surface | secondary text |
| `accent` | a hover or selected state, not a brand statement | text in that state |
| `destructive` | deletion and failure, as a fill and as text | text on the fill |
| `border` | edges and dividers | — |
| `input` | the boundary of a form control | — |
| `ring` | which control has focus | — |
| `sidebar*` | the navigation frame, when a product has one | its own text and accents |
| `chart-1…5` | series in a chart, in order | — |

Three of these carry a constraint rather than a preference:

- **`input` and `ring` are the only visual information identifying a control's boundary and its focus**, so WCAG 2.2 SC 1.4.11 asks 3:1 of them against the page. They are darker here than shadcn/ui's defaults for that reason, and the gate holds it.
- **`border` is decoration** — card edges, table rules, separators — never the sole indicator of a component or a state, so it is not scored against 3:1. Making it pass would turn every divider into a line the eye has to acknowledge.
- **`muted-foreground` is text**, so it takes SC 1.4.3's 4.5:1 on both `background` and `card` regardless of how quiet it is meant to look. Low prominence is not an exception the criterion grants.

## Type

One family per script, loaded by `next/font` and exposed as the same `--font-sans` token — Inter for Latin locales, Vazirmatn for Persian, because Inter has no Persian coverage and a translated page in a fallback face is half localised ([ADR-0400](adr/0400-frontend.md)); `--font-mono` is for identifiers, monetary amounts, and spec fragments — anything where character alignment carries meaning. The scale is Tailwind's default steps, used as: `4xl` for a display line, `2xl` for a page title, `lg` for a section, `base` for prose, `sm` for anything explanatory. A screen that needs a sixth step is usually a screen with an unclear hierarchy.

## Shape and motion

`--radius` sets one corner radius and the rest derive from it, so roundness is a single decision rather than a per-component opinion. Elevation is Tailwind's shadow scale, used sparingly: a shadow says "this floats above the page", and if everything floats nothing does. Motion comes from `tw-animate-css` through the primitives' own transitions; nothing animates that a user did not initiate.

## Voice

The product's copy follows [ADR-0001](adr/0001-documentation-and-output-conventions.md) — the same plain-language rules the documentation does. Specifically, on screen:

- Say what happened, not how the system feels about it. "Order confirmed", not "Great news!"
- An error names what to do next. If there is nothing to do, it names who is already looking.
- No exclamation marks, no "oops", no apologising for a state the user caused deliberately.
- A label is a noun; a button is a verb. "Products", and "Add product".

## What this brand does not do

- **No second accent colour** beyond the roles above. A screen that needs one is usually a screen that needs fewer things on it.
- **No per-route theming.** The token file is global; a route group that redefined a token would make the design system unreadable from any one place ([ADR-0400](adr/0400-frontend.md)).
- **No colour as the only signal.** A status is a word, optionally with a colour. Colour alone fails for anyone who cannot distinguish the pair.
- **No physical layout properties.** `ms-`/`me-`/`ps-`/`pe-`/`text-start`/`text-end`, never their left/right forms: the product ships a right-to-left locale, and a physical inset does not mirror. `lint:i18n` holds it.
- **No raw values in components.** A hex literal or an `oklch()` in a component is a token that escaped; it is caught by review and by `noHexColors`.
