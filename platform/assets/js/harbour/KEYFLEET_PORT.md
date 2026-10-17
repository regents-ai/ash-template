# Porting the agent harbour into Keyfleet's background

For the Keyfleet product agent. Sean asked (17 Oct 2026, 02:13Z) for the harbour's
sea and fleet to run as the background of every Keyfleet page, and answered the
open choices at 02:26Z. This lane does not write to the Keyfleet repository; this
file is the plan, and you do the port.

The source is ash-template's sample page `/animations/harbour/sea`, on branch
`dm/harbour-sea-horizon-1017` (this file's branch). It stacks on the v100 harbour
(`f28eb11`, `/animations/harbour`). Run it on that branch to see what you are
matching: the sea seen from the side out to the horizon, its grid square to the
page, solid panels over it, and the lift button at the top right. Blueprint look
only.

## Sean's answers

1. **Home keeps its hex field.** `/` keeps `#home-prism` and gets no sea.
2. **The sea is in the background, square to the page, out to the horizon.** The
   header, sidebar, reading column and cards stay solid paper; the sea shows around
   them.
3. **Pages outside a fleet** show the most recently active agents across all public
   fleets.
4. **The sea takes clicks.** Pressing the empty sea drops ripples that stop at the
   islands; pressing a ship opens its agent's card.
5. **A lift button at the top of every Keyfleet page** lifts the page, menus
   included, off the top so only the sea and ships show; the same button brings it
   all back.

## What it is

One ship per agent on a blueprint sea with three islands. A ship sails to the island
of its agent's last action and circles it until the agent does something else: the
inn for chat, the forge for work, the castle for proposals. Two small rocks make the
sea less regular. The sea swells on its own; clicks drop ripples that stop at the
islands.

## Files to copy

From `/Users/sean/Documents/regent/worktrees/design-motion/tpl/platform/` (or that
branch on GitHub), into the same paths under Keyfleet's `platform/`:

| File | Lines | Copy as |
| --- | --- | --- |
| `assets/js/harbour/sim.ts` | 187 | as is: ships, islands, steering, no GPU |
| `assets/js/harbour/meshes.ts` | 391 | as is: hulls, sails, islands, castle, inn, forge |
| `assets/js/harbour/shaders.ts` | 439 | as is: both seas, ripples, shadow, blueprint ink |
| `assets/js/harbour/renderer.ts` | 804 | as is; Keyfleet only uses the `"horizon"` view |
| `assets/js/hooks/harbour.ts` | 222 | rewrite as the backdrop hook (step 4) |
| `assets/css/pages/harbour.css` | 574 | take the `.sea` rules (stage, lift button, lifted state) |
| `lib/ash_template_web/live/harbour_live.ex` | 398 | reference only: its `:sea` render is the model |

The renderer already frames a full screen in the horizon view: the islands fill the
width with a margin, the horizon sits about a quarter of the way down, and the sea
runs out to it (`HORIZON_REACH` 320). No framing change is needed. Since Keyfleet
only draws the horizon, you may drop the chart view and `seaChartWgsl` from your
copies as a hard cutover; keep the `view` argument out of the hook if you do.

Leave behind the island pages (`/animations/harbour/inn|forge|castle`), the island
hover cards and the sample crew. They belong to the lab.

## Step 1: vgpu 0.6

Keyfleet pins `vgpu` 0.5.0 and has no `@vgpu/wgsl`. The harbour is written for 0.6:
`prepareShader` from `@vgpu/wgsl/prepare`, `gpu.lost`, `instances`, `pingPong`,
`sampler`. Pin both at exactly 0.6.0, then move Keyfleet's three existing GPU islands
(`home_prism`, `holographic_card`, `key_card/stage`) to 0.6 in the same change, as a
hard cutover. Read `npx vgpu docs cat /migrations/0.6.0.docs.md` first. Compare
Keyfleet's `assets/js/canvas_island.ts` with the template's copy and take the
template's if they differ; the harbour hook expects its `createCanvasIsland`,
`LoadRenderer` and `CanvasIslandController` types.

Check the three existing islands still draw (ready flag set, no `VGPU-*` console
errors) before adding the sea, so a broken upgrade isn't mistaken for a harbour bug.

## Step 2: one sea that survives navigation

Mount the sea once per tab, not once per page. Keyfleet's pages are separate
LiveViews and controller pages, so a canvas inside `shell.ex` would be torn down and
its GPU device rebuilt on every `navigate`, with a blank flash each time.

- Add a small LiveView, for example `KeyfleetWeb.HarbourSeaLive`, rendered from
  `layouts/root.html.heex` as the first child of `<body>`:
  `{live_render(@conn, KeyfleetWeb.HarbourSeaLive, id: "harbour-sea", sticky: true, session: ...)}`.
  A sticky LiveView keeps its process and its DOM across live navigation within a
  live session. Crossing between the `:home` and `:product_shell` live sessions, or to
  a controller page, is a full page load, and the sea simply starts again. Home does
  not render it (answer 1); neither does `/early`, whose own layout
  `layouts/early.html.heex` the root change does not reach.
- Pass the same sign-in context the shell's `on_mount` reads, so the backdrop reads
  the fleet as that visitor and shows nothing the page itself would not.
- It renders the stage (`phx-update="ignore"`, holding the canvas, the server's still
  picture and `data-harbour-crew` as JSON, with
  `phx-mounted={JS.ignore_attributes(["data-harbour-ready"])}` on its root, as the
  vgpu-island skill requires), the lift button (step 6) and the agent card (step 4).
  The stage itself is `aria-hidden="true"`; the button and card are not.

### Which fleet it shows

The sticky LiveView does not get the page's params. Tell it which fleet is on screen
from the page: render `data-fleet-id` on `#app-shell` (the fleet pages already know
it), and have the backdrop hook read it on `phx:page-loading-stop` and
`pushEvent("show_fleet", {id})`. The backdrop then unsubscribes from the old fleet's
topics, subscribes to the new one's, and sends the new crew.

Pages with no fleet (`/about`, `/account`, `/opportunities`, `/docs`, the legal
pages) send no id, and the backdrop shows the 16 most recently active keys across
all public fleets (answer 3), subscribed to each of their fleets' topics.

## Step 3: from activity to ships

`Agent = {id, place, color}` plus a `name` for the label. Build the crew on the server.

- **Identity.** One ship per key, `id` = `"<fleet_id>:<token_id>"`. The label is the
  agent's name, or `Key #<token_id>` when no agent is named.
- **Place.** Read `Keyfleet.Activity.page/3` newest first (`lib/keyfleet/activity.ex`
  documents every kind) and give each key the place of its newest action:
  - inn: `:post`, `:posts`, `:room_named`, and direct messages if you include them;
  - forge: `:created`, `:claimed`, `:unclaimed`, `:progress`, `:status`, `:revised`,
    `:archived`, `:linked`, and code pushes;
  - castle: `:proposed`, `:votes`, `:executed`, and polls.

  Sales, transfers and shards are not actions at a place; they never move a ship. A
  key whose only actions are those has no ship.
- **How many.** The renderer holds 16 ships (`MAX_SHIPS` in `sim.ts`, which also sizes
  the instance buffer). Keyfleet fleets have 1,024 to 2,000 keys, so show the 16 most
  recently active keys, the visitor's own keys first. Keep 16 unless Sean asks for
  more: ship-to-ship steering runs every pair each frame, so its cost grows with the
  square of the count, and a background should stay calm. Raising it is one constant.
- **Colour.** There is no colour field. Pick one of a fixed set of inks from the
  token id, so a key keeps its colour on every page. Do not add a column for it.
- **Live.** Subscribe through each module's own topic function:
  `Rooms.fleet_topic/1`, `Graph.head_topic/1`, `Proposals.topic/1`,
  `Polls.fleet_topic/1` and `Code.topic/1`. On any of them, read the
  first page again (the module's own advice: once for a burst, not once per message),
  rebuild the crew, and push it. The hook hands it to `renderer.setAgents`, and
  `syncFleet` turns ships that moved toward their new island; it never jumps them.

## Step 4: the backdrop hook and the agent card

Start from `hooks/harbour.ts`. Keep: `createCanvasIsland` with `continuous: true`,
`setAgents` on every new crew, `setLook` on theme change (keep the
`MutationObserver` on `data-theme`), `setCalm` on the reduced-motion query, and the
hand-off of `pause`/`resume`/`destroy` to the island. Keep the ship's name on hover
and the clicks (answer 4):

- pressing the empty sea calls `ripple(u, v)`;
- pressing a ship pushes `show_agent` with its id to the backdrop LiveView, which
  opens that agent's card;
- pressing an island does nothing (Keyfleet has no island pages); drop `islandAt`'s
  card and link handling.

The card is the lab's `agent_card` (name, key, and its last actions with where and
when), filled from `Keyfleet.Activity` for that key, and add a link to the key's own
page. The lab keeps the open card in the URL (`?agent=`); a sticky LiveView cannot
patch the page's URL, so keep it as backdrop state instead, and close it on Escape,
the close button, or navigation.

Reduced motion already gives one still picture that redraws only when an agent moves
or the theme changes. Follow `lib/keyfleet_web/motion.ex` for anything
else Keyfleet asks of motion.

## Step 5: let the sea show

Everything in Keyfleet paints its own ground today: `body`, `#app-shell`,
`#shell-header`, `#shell-sidebar` and many page panels use `--color-bg` or
`--color-surface`. The backdrop sits behind all of it.

- The stage is `position: fixed; inset: 0; z-index: 0` across the whole screen, the
  way `.sea__harbour` is in the lab. `#app-shell` keeps `isolation: isolate` and sits
  above it at `z-index: 1`.
- `html` keeps `--color-bg` (it shows while the sea loads, and with no WebGPU). `body`
  and `#app-shell` become transparent so the sea shows through.
- The header, sidebar, reading column and cards stay solid (answer 2). Do not use
  `backdrop-filter` blur over a moving canvas; it redraws every frame and costs more
  than the sea itself.
- Clicks: give `#app-shell` and its layout wrappers `pointer-events: none` and every
  solid panel `pointer-events: auto`, as `.sea__page > *` does in the lab, so a press
  on the open margin reaches the sea and a press on anything solid stays with the
  page. Check every link, button, input and scroll area afterwards (check 5).

### Colours

`setLook` takes `night` from `data-theme` and `haze` from the CSS variable
`--harbour-haze`, read as `#rrggbb`. Keyfleet's grounds are `#F6F4EA` (light) and
`#0B0B0B` (dark), which are the lab's `.sea` values already; set them per theme on the
stage literally, not through `var()`. The ink reads on both grounds in the lab.

## Step 6: the lift button

One button, top right of every page that has the sea. Pressed, the whole page (header
and sidebar included) slides up off the screen and fades, and only the sea and ships
are left. Pressed again, the page comes back exactly where it was.

- **Where it lives.** In the backdrop LiveView, not in the header: it must stay put
  while everything else lifts, and the sticky LiveView keeps it across navigation.
  It is `position: fixed` at the header's top right, 2.75rem square. Reserve an empty
  2.75rem slot at the right end of `#shell-header` (and on phones in the top bar) so
  it never covers a header control.
- **What it toggles.** A class on `<body>`, for example `sea-lifted`. `<body>` belongs
  to the root layout, which live navigation does not replace, so the lifted state and
  the button's `aria-pressed` stay in step across pages. A full page load resets
  both. Use the lab's commands, with the target changed:

  ```elixir
  JS.toggle_class("sea-lifted", to: "body")
  |> JS.toggle_attribute({"aria-pressed", "true", "false"})
  |> JS.toggle_attribute({"aria-label", "Bring the page back", "Show the sea"})
  |> JS.toggle_attribute({"title", "Bring the page back", "Show the sea"})
  ```

- **The lifted state.** Copy `.sea--lifted` and `.sea--lifted .sea__page` onto
  `body.sea-lifted` and `body.sea-lifted #app-shell`: `translate: 0 -100%`, opacity 0,
  then `visibility: hidden` once the slide ends, so the keyboard and screen readers
  skip the hidden page and land on the button and the sea. The body keeps the screen's
  height with no scroll while lifted. The arrow turns over to point down.
- **Less motion** drops the slide and the turn; the page simply goes and comes back.
- The button carries `aria-controls="app-shell"`; its label always says what the next
  press does.

## Step 7: the rest of the change

- Route handoff: no route is added. If you set `background_slot` to name the sea,
  rerun `mix keyfleet.route_handoff` and commit the catalog; `mix keyfleet.route_handoff --check` must pass.
- `/llms.txt` does not change (no new route). CSP does not change (same-origin
  script, no new origin).
- CHANGELOG.md, the public changelog and `platform/README.md` get a line.
- New tests need Sean's agreement before you add them. LiveView tests do not run
  hooks, so prove the sea in a browser.

## Checks

Headless Chromium only, with WebGPU on; never open tabs in Sean's Chrome. Record
WebKit as "not run on the Mac".

1. Every shell page shows the sea behind it once `data-harbour-ready` is set: desktop
   1440 wide, phone 390 and 320, light and dark. Home and `/early` show no sea.
2. Live navigation between shell pages keeps the same canvas (same element, no
   blank frame, the ready flag stays).
3. Moving between two fleets changes the crew; a new post in a room turns that key's
   ship to the inn within a moment, without a reload. A page outside a fleet shows
   recent agents from public fleets.
4. A press on the open sea draws a ripple; a press on a ship opens its card; a press
   on a panel does what it did before.
5. The lift button lifts the page and menus and brings them back, on every shell page,
   at every size; after a lift, Tab reaches only the button; navigating while the
   page is down keeps the button and the page in step.
6. Reduced motion shows a still sea that still updates when an agent moves, and the
   lift happens without the slide.
7. No sideways scroll, no `VGPU-*` console errors, text contrast 4.5:1 on the reading
   column.
8. The page stays smooth while scrolling a long room on a phone-sized window; note
   the frame time with and without the sea.
