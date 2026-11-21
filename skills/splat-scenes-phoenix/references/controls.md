# Controls and Download GIF

How a box moves under the pointer, the keys and the zoom, and how Download GIF works. The pointer, key and button wiring is
`platform/assets/js/hooks/splat_island.ts`; the motion and its numbers are `platform/assets/js/splats/renderer.ts` and
`platform/assets/js/splats/camera.ts`. The turn, tilt and release are the sibling skill's player's (splat-scenes
references/hosting.md, Orbit and touch); the zoom is the site's own.

## 1. Turn and tilt

- At rest it turns once every 30 seconds (`CRUISE`) while the scene plays its loop.
- A mouse or pen dragged across turns it, one to one, so the scene's near edge keeps up with the pointer; dragged up or down it
  tilts, clamped to 86 degrees either way (`TILT_LIMIT`), so the view never flips.
- Let go, it carries on at the speed of the last 100 ms (`RELEASE_WINDOW`), at most a turn a second and half a turn for the tilt;
  the turn eases back to the cruise, the tilt coasts and goes back to rest from 0.8 s after the release.
- A finger only turns: the box is `touch-action: pan-y`, so every upright swipe scrolls the page. Tilt on a touch screen is the
  keyboard's.
- Focused, the arrow keys turn 20 degrees and tilt 12 degrees a press, eased in (`KEY_SETTLE`, 0.18 s). A focus ring shows on
  keyboard focus; `cursor: grab`, `grabbing` while held.

## 2. Zoom

- From the scene's own framing up to four times nearer (`ZOOM_LIMIT`), and it stays where it is left.
- A pinch on a trackpad, or a wheel turned with Ctrl or Cmd held, zooms at the pointer: the point of the scene under it stays under
  it. A plain wheel scrolls the page. Two fingers on a touch screen pinch at their midpoint until both have lifted.
- Focused, `+` or `=` zooms in a step, `-` out, `0` goes back to the opening view; with Ctrl, Cmd or Alt held those keys are the
  browser's own zoom. A step is the square root of two, on the middle of the stage.
- A double-click or a double tap, and Reset view, go back to the opening view: zoom, aim and tilt; the turn carries on.
- While zoom keeps coming the slow turn stops; 0.8 s after the last, it eases back in.
- The three buttons are found by `button[data-splats-zoom="in"]`, `"out"` and `"home"` (Zoom in, Zoom out, Reset view). Each is
  `aria-disabled="true"` while it has nothing left to do; the server sends Zoom out and Reset view disabled, as the opening view
  has them, and the hook keeps each one up to date from then on. A press or drag on a button is the button's alone, never the scene's.

## 3. Less motion

With reduced motion on the device, or a `[data-motion='reduced']` switch round the box, the scene holds still at the still's view
and moment. Drags, keys, zoom and Reset view still move it, landing at once instead of easing, and it stays where it is left. A
flick does not carry on. The box's label says how to move it whatever the setting (`@moving` in `splat_stage.ex`).

## 4. Download GIF

- A page offers it by placing `SplatStage.gif/1` with `for` set to the box's id; a page that places none offers none. A scene's
  own page has none.
- The page shows it only once its box has drawn: the Splats and Scenes pages' styles keep it hidden, holding its place, until
  `:has(...[data-splats-ready="true"])` is true. So it is never offered without WebGPU, and every press finds a drawn scene.
- A press (the `SplatGif` hook, `platform/assets/js/hooks/splat_gif.ts`) loads `platform/assets/js/splats/gif.ts` on the first
  press, takes the scene from the box's renderer (`rendererOf`), and draws one loop on a device of its own while the box carries on:
  160 frames (`FRAMES`) of 5 hundredths of a second (`DELAY`), 8 seconds, the camera once round at the resting tilt while the loop
  plays once, so the last frame runs on into the first. Each frame is drawn for an 864 by 576 stage (`STAGE`) and scaled up by 2
  (`SCALE`). The colour table is the scene's palette plus one entry for an unchanged pixel, so the palette must be at most 255
  colours; nothing is matched or dithered again.
- While it works the button reads Making with a count in place, a screen reader hears each quarter, and a second press does
  nothing. Then it reads Download GIF again and the file is saved, named after the box's `data-splats-scene` with a prefix written in
  `splat_gif.ts` (a site that takes the island writes its own there). A failure shows "Could not make the GIF. Try again." beside the
  button, in a place kept for it, so nothing moves. Choosing another scene or leaving the page removes the control, which stops it.
- The button, its words and its failed line share one place (`splat_stage.css`), so it keeps the widest and the row never moves. The
  count is `Regent.Primitives.figure`, which the hook finds by its `data-count`.
