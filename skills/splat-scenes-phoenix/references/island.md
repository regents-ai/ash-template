# The splat island

How a box starts and stops its GPU with the LiveView lifecycle, and when the still gives way to the live scene. The general rules for
every GPU picture on these sites are vgpu-island's (its three parts, the vgpu 0.6 rules, the pins and the offline docs); this note
says how the splat island follows them and where it differs.

## 1. Three parts

1. **The component**, `AshTemplateWeb.Components.SplatStage.stage/1`. The root is a focusable labelled group (`tabindex="0"`,
   `role="group"`, `aria-label` = the scene's label and how to move it) with `phx-hook="SplatIsland"`, `data-splats-scene` (the
   name) and `data-splats-file` (the file's address), and
   `phx-mounted={JS.ignore_attributes(["data-splats-ready"])}`, so a LiveView patch never strips the ready flag the browser set.
   Inside it, in order: a `<picture>` with the still (`<img class="splat-stage__still">`, and for a box that turns square a
   `<source media="(max-width: 36rem)">` with the square still); `<div id="<id>-stage" class="splat-stage__live"
   phx-update="ignore">` holding `<canvas data-splats-canvas>`, so a patch never replaces the canvas; and Zoom out, Zoom in and Reset
   view, each keeping its `aria-disabled` through `JS.ignore_attributes(["aria-disabled"])`.
2. **The hook**, `SplatIsland` in `platform/assets/js/hooks/splat_island.ts`: `createSplatIsland(root)` makes one canvas island
   (`createCanvasIsland` in `platform/assets/js/canvas_island.ts`) for the box, with its pointer, wheel, key and button wiring and
   the less-motion watch.
3. **The renderer**, `createSplatRenderer` in `platform/assets/js/splats/renderer.ts`, with the painter `createPainter` in
   `platform/assets/js/splats/painter.ts`.

## 2. The LiveView lifecycle

| Hook callback | What happens |
| --- | --- |
| `mounted` | `createSplatIsland(this.el)`, then `mount()`: the less-motion watch starts and the canvas island mounts (section 3) |
| `disconnected` | `pause()`: no more frames while the live connection is down; the renderer and its device are kept |
| `reconnected` | `resume()`: frames again, if the box is still on screen in a visible tab |
| `destroyed` | `destroy()`: every listener released, the renderer disposed (its surface, then its device), the flag removed |

There is no `updated`. vgpu-island's islands take new `data-*` state in `updated`; a splat box never changes scene. Each scene is its
own box with its own id: `splats-<name>` on the Splats page, `scene-<number>` on the Scenes page and on a scene's own page. A tab on
the Splats page is a `<.link patch>` to `?scene=<name>`, so the patch puts a box with a new id in place of the old one: LiveView
destroys the old hook, which gives back its device, and mounts the new one, which asks for a device only once it is on screen and two
frames have passed. Keep that: a page that shows another scene renders another box with another id, never new attributes on the
same box.

## 3. From the still to the first frame

What `createCanvasIsland` does for a box, in order. It owns all of this once for every GPU picture on the site, so the renderer builds
none of it: no frame loop, observer, visibility or motion listener, device retry or size cap of its own (vgpu-island).

1. **No WebGPU** (`navigator.gpu` missing): the flag is set to `"false"` at once and nothing else runs. The still stays, and the
   zoom buttons and Download GIF never show.
2. **Watch first.** A `ResizeObserver` on the canvas, an `IntersectionObserver` on the box and the page's `visibilitychange`, before
   anything loads: a box nobody can see never fetches its code or its file.
3. **Start.** Once the box is mounted, on screen, in a visible tab and not paused, it waits two animation frames (the second runs
   after the server's markup has painted), then imports `platform/assets/js/splats/renderer.ts` (a separate chunk, so vgpu never
   enters the page's first bundle) and calls `createSplatRenderer(view, size, lost, file)`. That starts the GPU and fetches the
   scene file together, decodes it, builds the painter and pre-warms its shaders against the canvas's surface.
4. **First frame.** The first frame is presented and the island waits for `settled()`, the GPU's own word that the work finished.
   Only then is the flag `"true"`: `splat_stage.css` fades the canvas and the zoom buttons in over the still, and the page shows
   Download GIF. A canvas or an adapter that merely exists never lifts the still.
5. **Out of sight.** Off screen, in a hidden tab, or paused: no frames, the renderer kept. Back in sight, frames resume. While it is
   active it draws every frame (`continuous: true`): the scene turns and plays by itself.
6. **Failure.** The code or the device does not come: the island retires, the flag is `"false"`, the still stays.
7. **Device lost.** The renderer is dropped, the flag removed (the still shows again) and a new device asked for, up to
   `DEVICE_RECOVERY_LIMIT` (3) times; a frame that lands gives the budget back. Past that it retires with `"false"`.

The markup and the stylesheet keep the still in place: the still and the canvas fill the same box (`object-fit: cover`,
`image-rendering: pixelated`), the live layer fades in over it under `[data-splats-ready="true"]`, and nothing round the box moves
when it does.

## 4. Size

The kind asks `maxDevicePixelRatio: 3` and `maxDrawingBufferPixels: 5_000_000`, past the island's usual 1.5 and 1,500,000, so every
art pixel is a square of whole device pixels on every screen; the longest side stays within 8192 (`MAX_DRAWING_BUFFER_SIDE`) and both
axes take the same scale. The painter fits the art grid to the canvas it is given (`gridFor`), so the scene keeps its grid at any
size.

## 5. Less motion

The kind is `motionSensitive: false`: with less motion asked for, the box still draws, held still. `still(root)`
(`platform/assets/js/hooks/motion/shared.ts`) is true when the device asks for reduced motion or a `[data-motion='reduced']` switch
is round the box. The hook watches both (a `matchMedia` listener and a `MutationObserver` on `data-motion` across the document) and
calls the renderer's `hold(calm)` on each change and when the renderer lands. Held, nothing moves by itself: it opens at the still's
view and moment (the scene's own yaw and tilt, the start of its loop), and a drag, a key, a zoom or Reset view lands at once and stays
where it is left. The fade-in has no transition under reduced motion.

## 6. Devices

- One device a box, opened by its renderer and given back on destroy. The Splats page shows one box at a time. The Scenes page has a
  box a scene; each starts only once it comes on screen and keeps its device while it is off screen until the page lets it go. The
  splat island does not use the value cards' shared device (vgpu-island).
- Download GIF draws on a device of its own while it works (`platform/assets/js/splats/gif.ts`), so the box carries on.
- The renderer follows vgpu-island's renderer rules: the GPU and the file together, the device disposed if either fails or
  construction throws; `gpu.lost` reported only while the renderer is in use; `surface(..., {autoResize: false, alphaMode:
  "opaque"})`; shaders prepared once with `prepareShader`, with the scene's numbers written in (the no-fog rule in SKILL.md);
  `compile(stage)` before the first frame; synchronous frame callbacks; `settled()` is `gpu.settled()`; `dispose` once.
