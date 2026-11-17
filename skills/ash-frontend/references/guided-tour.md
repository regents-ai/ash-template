# Guided tour

A page's guided tour (`AshTemplateWeb.Components.Tour`, the `Tour` hook in
`assets/js/hooks/tour.ts`) rings one part of the page at a time, dims the rest and
shows a small card beside the ring: a one-word title, one sentence, Skip, Back and
Next, and a dot for each step. It plays by itself once in a browser and the Tour
button plays it again. The template's homepage carries a demo (`@tour` in
`home_live.ex`); a new site writes its own.

## Writing a step list

- Four to six steps, in the order a newcomer reads the page: the main action first,
  then the parts they will want next. A last step on the Tour button shows where to
  find the tour again.
- `target` is a CSS selector for one part that is on the page. Prefer an id, and give
  the part one when it has none (`#home-enter-app`). A heading is ringed round its
  words. A step whose part is not drawn is left out; a step with no `target` puts its
  card in the middle of the screen, so keep those rare.
- `title` is one word. `text` is one plain sentence in the reader's words: what the
  part is for or what a press on it does. No words about how the page is built.
- Point only at parts that stay put while the tour shows. A page that hides parts of
  itself holds them in sight from `tour:opened` until `tour:closed`, which bubble from
  the tour's element, as `hooks/datascape.ts` holds the homepage's glass panel open.

```heex
<Tour.tour id="home-tour" name="home" steps={@tour} />
<Tour.start_button for="home-tour" />
```

- The tour's element shows nothing; put it inside the page's own box, whose size the
  tour watches. `start_button/1` goes where it fits without crowding, such as the
  page's header.
- `name` is what the browser remembers as seen (`ash-template:tour:<name>`). A new
  name plays the tour once more for everyone.
- Every browser walk starts with each tour seen: add its key to `storageState` in
  `platform/playwright.config.ts` and to the saved sign-ins in
  `platform/test/browser/support/sign_in.exs`. The tour's own walk starts with nothing
  kept, and proves a button under the dimming takes its press.

## What the tour never does

- It only points. The dimming and the ring take no presses, and nothing waits on,
  stops or changes a press on the page, wallet buttons above all
  ([onchain-buttons](../../onchain-buttons/SKILL.md)). The card keeps off
  `[data-onchain-step]`, `[data-toast]` and the page's notices wherever there is room.
- It never opens over a window; one waiting starts as the last window closes. Escape
  closes an open window, not the tour under it.
- Motion is Anime.js through the motion kit; with less motion the tour is simply
  there. The light round the ring is a vgpu island and draws nothing without WebGPU.
