# Brand

This file says what each design token is *for*. The values are in `apps/frontend/src/styles/theme.css` and nowhere else. The kitchen-sink route renders them. It shows this brand in both palettes, as the product draws it, per [ADR-0400](adr/0400-frontend.md).

This file has no colour values. One source for a value means one place to change it. A document that repeated the palette would be a second source, and it would drift with no warning, per [ADR-0001](adr/0001-documentation-and-output-conventions.md).

**A generated project changes its brand by editing `:root` and `.dark` in that file.** Everything below describes what the roles mean. So an editor knows which role to change.

## Colour roles

Each role is a pair: a surface, and the foreground on it. Every role appears in both palettes. `mise run lint:contrast` scores every pair in both palettes before a change merges.

| Role | The surface it paints | The foreground on it |
| --- | --- | --- |
| `background` | the page | all body text |
| `card` | anything raised above the page: cards, popovers, dialogs | text on that raised surface |
| `primary` | the one action that the screen asks the user to take | text on that action |
| `secondary` | an action that is available but is not the main one | text on it |
| `muted` | a recessed area, and the colour of explanatory text on any surface | secondary text |
| `accent` | a hover or selected state, not a brand statement | text in that state |
| `destructive` | deletion and failure, as a fill and as text | text on the fill |
| `border` | edges and dividers | none |
| `input` | the boundary of a form control | none |
| `ring` | the control that has focus | none |
| `sidebar*` | the navigation frame, when a product has one | its own text and accents |
| `chart-1` to `chart-5` | the series in a chart, in order | none |

Three of these roles have a constraint, not a preference:

- **`input` and `ring` are the only visual signs of a control's boundary and its focus.** So WCAG 2.2 SC 1.4.11 asks for 3:1 against the page. For this reason they are darker here than the `shadcn/ui` defaults, and the gate holds this.
- **`border` is decoration**: card edges, table rules, and separators. It is never the only sign of a component or a state, so it is not scored against 3:1. If it had to pass, every divider would become a line that the eye must notice.
- **`muted-foreground` is text.** So it needs the 4.5:1 of SC 1.4.3 on both `background` and `card`, however quiet it looks. The criterion makes no exception for low prominence.

## Type

Each script has one font family. `next/font` loads it and exposes it as the same `--font-sans` token:

- Inter for Latin locales.
- Vazirmatn for Persian. Inter does not cover Persian, and a translated page in a fallback face is only half localised, per [ADR-0400](adr/0400-frontend.md).

`--font-mono` is for identifiers, money amounts, and spec fragments: anything where character alignment carries meaning.

The scale is the default Tailwind steps:

| Step | Use |
| --- | --- |
| `4xl` | a display line |
| `2xl` | a page title |
| `lg` | a section |
| `base` | prose |
| `sm` | anything explanatory |

A screen that needs a sixth step usually has an unclear hierarchy.

## Shape and motion

`--radius` sets one corner radius, and the other radii come from it. So roundness is one decision, not a separate choice for each component. Elevation uses the Tailwind shadow scale, and uses it rarely. A shadow says that this element floats above the page. If everything floats, nothing does. Motion comes from `tw-animate-css` through the transitions of the primitives. Nothing moves unless a user started it.

## Voice

The copy in the product follows [ADR-0001](adr/0001-documentation-and-output-conventions.md). These are the same plain-language rules that the documentation follows. On screen, this means:

- Say what happened, not how the system feels about it. Write `Order confirmed`, not `Great news`.
- An error says what to do next. If there is nothing to do, it says who is already looking at the problem.
- No exclamation marks, no `oops`, and no apology for a state that the user caused on purpose.
- A label is a noun, and a button is a verb: `Products`, and `Add product`.

## What this brand does not do

- **No second accent colour** beyond the roles above. A screen that needs one usually needs fewer things on it.
- **No theme for each route.** The token file is global. A route group that redefined a token would make the design system impossible to read from one place, per [ADR-0400](adr/0400-frontend.md).
- **No colour as the only signal.** A status is a word, and it can also have a colour. Colour alone fails for anyone who cannot tell the two colours apart.
- **No physical layout properties.** Use `ms-`, `me-`, `ps-`, `pe-`, `text-start`, and `text-end`, never their left and right forms. The product ships a right-to-left locale, and a physical inset does not mirror. `lint:i18n` holds this.
- **No raw values in components.** A hex literal or an `oklch()` in a component is a token that escaped. Review and `noHexColors` catch it.
