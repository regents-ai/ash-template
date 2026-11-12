# Value cards

A row of cards, one for each thing a product does. Each card is dark in both themes: a
square panel of small coloured glyphs that moves and follows a mouse, the feature's name
in the card's colour, one line, one sentence and the action. Every card there is stands
at `/animations/value-cards` on the template, product by product, with its panel's name
under it.

## Take a card into a site

Copy, keeping the paths:

| Piece | Path in `platform/` |
| --- | --- |
| The row and its words | `lib/<site>_web/components/value_cards.ex` |
| Styles | `assets/css/components/value_cards.css`, imported in `app.css` |
| Hook | `assets/js/hooks/value_card.ts`, registered where the page's hooks are |
| Drawing | `assets/js/value_cards/renderer.ts`, `shared_device.ts`, `panel.ts`, `stills.mjs` |
| The panels wanted | `assets/js/value_cards/panels/<name>.ts`, and their lines in `index.ts` |
| Their still frames | `priv/static/images/value-cards/<name>.webp` |
| Script | `"stills:value-cards"` in `package.json` |
| Tests | `assets/test/value_cards.test.ts` |

`canvas_island.ts` is already in every site. Then give the row its cards:

```elixir
<.value_cards
  id="home-cards"
  label="Features"
  cards={[
    %{
      id: "seats",
      name: "Keys",
      headline: "A Key is your seat.",
      line: "A Key puts you and your agents in a fleet's rooms, workspace and votes.",
      tint: "#e8a15b",
      action: "Buy Key",
      href: ~p"/keys"
    }
  ]}
/>
```

The words and tint of every card are in `ValueCardsLive` on the template. Keep a card's
words true to the feature as its own page describes it: no promise of returns, no figure
that is not read live, nothing about how the site is built.

## Write a new panel

One file in `panels/`, named for the panel, plus its line in `index.ts`:

```ts
import type {ValuePanel} from "../panel"

export const level: ValuePanel = {
  colours: ["#6b1f4a", "#ffab2e", "#fff1cc"], // deep, main, bright
  pitch: [9, 12],                             // one cell, in a panel 340 across
  stillAt: 3.1,                               // the second the still frame shows
  body: /* wgsl */ `...`,
}
```

- The body is the inside of the fragment shader. It starts with the grid `g`, the pointer
  `p` (x, y up, how present it is), the seconds `t` and the cell's place `x`, `y`
  (0 to 1, y up). It ends with `return emit(g, distance, colour, amount);`.
- Take colour only from `ramp(0..1)`, the card's gradient mixed in OKLab. Glyph shapes
  are `sdBox`, `sdPlus`, `sdDiamond`, `sdSlash`, `sdAngle`, `sdSeg` or a circle
  (`length(g.local) - r`). `dith(g.id, v)` is the ordered dither.
- Random values come from `hash`, which is integer arithmetic, so every GPU draws the
  same picture as the still. Never `fract(sin(...))`.
- `from`, `active`, `ptr` and other WGSL reserved words cannot name a value.
- The pointer must change the picture (`p.z` is 0 with no pointer, 1 with one), and the
  picture must still read with none.
- Do not add `@vshaders/*` packages: they are a third party's, not vgpu's.

Then draw its still (`npm run stills:value-cards -- <name>`, Node 22.18 or newer), give
the card a `tint` that reads at 4.5:1 on `#0b0b0c` (the main colour, or a lighter step of
it) and run `npm test`.

## Rules the cards keep

- The panel is square at every width and laid out as if 340 pixels across, so the still
  frame always matches the moving panel.
- Every panel on a page draws on one GPU device (`shared_device.ts`).
- Reduced motion, no WebGPU and no JavaScript all show the still frame.
- A name is one or two words, a headline one line of about 26 characters ending with a
  full stop, a sentence about 60 characters, an action two words.
