# Porting the agent harbour into Keyfleet's background

For the Keyfleet product agent. Sean asked (17 Oct 2026, 02:13Z) for the harbour's
sea and fleet to run as the background of every Keyfleet page. This lane does not
write to the Keyfleet repository; this file is the plan, and you do the port.

The source is ash-template's `/animations/harbour`, on branch
`dm/agent-harbour-v100-1017` at `f28eb119e4a5e6ee6b660bf3469ee31c100786f2` (ships as
template v100 once Sentinel and Sean say go). Run it on any template checkout at
`/animations/harbour` to see the look you are matching: blueprint only.

Decisions Sean has not made yet are marked **Open** and listed at the end with the
default this plan takes. Build on the defaults; each one is a small change if he picks
otherwise.

## What it is

One ship per agent on an isometric blueprint sea with three islands. A ship sails to
the island of its agent's last action and circles it until the agent does something
else: the inn for chat, the forge for work, the castle for proposals. Two small rocks
make the sea less regular. The sea swells on its own; clicks drop ripples that stop at
the islands.

## Files to copy

From `/Users/sean/Documents/regent/worktrees/design-motion/tpl/platform/` (or that
branch on GitHub), into the same paths under Keyfleet's `platform/`:

| File | Lines | Copy as |
| --- | --- | --- |
| `assets/js/harbour/sim.ts` | 187 | as is: ships, islands, steering, no GPU |
| `assets/js/harbour/meshes.ts` | 391 | as is: hulls, sails, islands, castle, inn, forge |
| `assets/js/harbour/shaders.ts` | 434 | as is: sea, ripples, shadow, blueprint ink |
| `assets/js/harbour/renderer.ts` | 671 | as is, plus the framing change below |
| `assets/js/hooks/harbour.ts` | 219 | rewrite as a background hook (below) |
| `assets/css/pages/harbour.css` | 326 | take only the stage and still-picture rules |
| `lib/ash_template_web/live/harbour_live.ex` | 282 | reference only; the backdrop LiveView is new |

Leave behind the island pages (`/animations/harbour/inn|forge|castle`), the island
hover cards, the agent card panel and the sample crew. They belong to the lab page.

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
  a controller page, is a full page load, and the sea simply starts again.
- Pass the same sign-in context the shell's `on_mount` reads, so the backdrop reads
  the fleet as that visitor and shows nothing the page itself would not.
- The backdrop renders a `div` stage with `phx-update="ignore"` holding the canvas,
  the server's still picture, and `data-harbour-crew` as JSON. Put
  `phx-mounted={JS.ignore_attributes(["data-harbour-ready"])}` on its root, as the
  vgpu-island skill requires.
- It renders no text and is `aria-hidden="true"`.

### Which fleet it shows

The sticky LiveView does not get the page's params. Tell it which fleet is on screen
from the page: render `data-fleet-id` on `#app-shell` (the fleet pages already know
it), and have the backdrop hook read it on `phx:page-loading-stop` and
`pushEvent("show_fleet", {id})`. The backdrop then unsubscribes from the old fleet's
topics, subscribes to the new one's, and sends the new crew.

**Open (decision 3):** pages that are not inside a fleet (`/about`, `/account`,
`/opportunities`, `/docs`, the legal pages). Default: the most recently active agents
across all public fleets.

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

## Step 4: the background hook

Start from `hooks/harbour.ts` and keep only: `createCanvasIsland` with
`continuous: true` and `motionSensitive: true`, `setAgents` on every new crew,
`setLook` on theme change (keep the `MutationObserver` on `data-theme`), and the
hand-off of `pause`/`resume`/`destroy` to the island. Drop the ship labels, island
cards and click handling unless decision 4 says otherwise.

Reduced motion already gives one still picture that redraws only when an agent moves
or the theme changes. Follow `lib/keyfleet_web/motion.ex` for anything else Keyfleet
asks of motion.

## Step 5: let the sea show

Everything in Keyfleet paints its own ground today: `body`, `#app-shell`,
`#shell-header`, `#shell-sidebar` and many page panels use `--color-bg` or
`--color-surface`. The backdrop sits behind all of it.

- The stage is `position: fixed`, `z-index: 0`, under the header and to the right of
  the sidebar on desktop, and under the header across the full width on phones.
  `#app-shell` keeps `isolation: isolate` and sits above it at `z-index: 1`.
- `html` keeps `--color-bg` (it shows while the sea loads, and with no WebGPU). `body`
  and `#app-shell` become transparent so the sea shows through.
- The header and sidebar stay solid, so navigation stays readable over a moving
  picture.
- **Open (decision 2):** text-heavy pages (rooms, DMs, workspace, proposals, polls,
  account, legal). Default: the reading column and cards stay solid paper and the sea
  shows in the margins around them. Do not use `backdrop-filter` blur over a moving
  canvas; it redraws every frame and costs more than the sea itself.
- Pointer events: the stage is `pointer-events: none` by default, so nothing on the
  page changes behaviour. See decision 4.

### Framing

The lab frames the three islands and their rings inside its own box and crops 16%
when the box is narrower than 1.3:1. A full-screen box is wider and taller, so add one
small framing change to `renderer.ts` and keep everything else: fit the islands into
the middle of the stage with a margin, and let the extra sea run to the edges
(`SEA_SIZE` 44 already reaches past any screen shape). On phones the islands sit in
the upper half, behind the page title, rather than under the content.

### Colours

`setLook` takes `night` from `data-theme` and `haze` from the CSS variable
`--harbour-haze`, read as `#rrggbb`. Keyfleet's grounds are `#F6F4EA` (light) and
`#0B0B0B` (dark). Set `--harbour-haze` to those two hex values per theme on the
stage, literally, not through `var()`. The lab was tuned on `#161616` (dark) and
`#e5e3d2` (light), so look at the blueprint ink on Keyfleet's grounds and lift it if
the lines fade.

## Step 6: home and /early

- **Open (decision 1):** home already has its own GPU backdrop, `#home-prism`
  (`HomePrism`, `home.css` line 39, z-index -1), and runs in its own live session.
  Default: home keeps its prism and gets no sea, so no page runs two moving GPU
  pictures. If Sean wants the sea on home too, it replaces the prism's quiet squares
  field behind the hero.
- `/early` uses its own layout, `layouts/early.html.heex`, for the sale countdown.
  Default: no sea there, because the root layout change does not reach it; the sale
  page keeps the visitor's eyes on the keys.

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

1. Every page in the router shows the sea behind it once `data-harbour-ready` is set:
   desktop 1440 wide, phone 390 and 320, light and dark.
2. Live navigation between shell pages keeps the same canvas (same element, no
   blank frame, the ready flag stays).
3. Moving between two fleets changes the crew; a new post in a room turns that key's
   ship to the inn within a moment, without a reload.
4. Reduced motion shows a still sea that still updates when an agent moves.
5. No sideways scroll, no `VGPU-*` console errors, every link and button still
   clickable, text contrast 4.5:1 on the reading column.
6. The page stays smooth while scrolling a long room on a phone-sized window; note
   the frame time with and without the sea.

## Open decisions for Sean

1. Home page: a) home keeps its prism and gets no sea (default) b) the sea replaces
   the prism's squares field on home too.
2. Text-heavy pages: a) reading column and cards stay solid paper, sea in the margins
   (default) b) a soft wash over the sea under the text c) no sea on those pages.
3. Pages outside a fleet: a) the most recently active agents across all public fleets
   (default) b) a still, empty sea with no ships.
4. Clicks on the background: a) look only, no clicks (default) b) clicks on empty sea
   drop ripples and a ship opens its agent's card.
