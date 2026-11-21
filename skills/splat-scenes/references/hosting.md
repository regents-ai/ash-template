# Putting a scene on a page

The player (`player/`) is a complete page for one scene and the reference for putting a scene on any website: plain files, no build
step, no framework. This note covers vgpu, the parts of the page, serving the file, and how the scene turns under the pointer.

## 1. vgpu: version, documentation and rules

- Pinned: `vgpu` **0.6.0** and `@vgpu/wgsl` **0.6.0**, exact versions (`player/package.json`). Upgrade both together. Before trusting
  a build, check that the installed copy matches the pin (`node_modules/vgpu/package.json`); a stale install builds against the wrong
  API.
- The docs ship inside the installed package and work offline. Read them before writing or reviewing a painter, and read the
  migration guide before any upgrade. From `player/` after `npm install`:

  ```sh
  npx vgpu docs ls                              # /guides, /vgpu, /migrations, ...
  npx vgpu docs cat getting-started.md
  npx vgpu docs cat /migrations/0.6.0.docs.md
  npx vgpu docs cat /vgpu/surface.docs.md       # likewise effect, frame, gpu, init
  npx vgpu docs cat /vgpu/core/texture.docs.md  # read() and readFloats(), for reading a picture back
  npx vgpu docs cat /guides/shipping-to-production.docs.md
  npx vgpu docs find effect
  npx vgpu examples search "gradient"
  npx vgpu check shader.wgsl                    # validate and reflect a WGSL file
  ```

  Online: https://vgpu.sh/docs, https://vgpu.sh/agents.md, https://vgpu.sh/llms.txt. The installed docs win over memory and over
  older code.
- The player runs without a bundler: an import map in `player/index.html` points `vgpu`, `@vgpu/core`, `@vgpu/wgsl` and
  `@vgpu/wgsl/prepare` at `player/node_modules`. A site with a bundler imports them by name instead.
- Code that draws with vgpu 0.6 starts, draws and stops like this (the player's `main.js` and `painter.js` do):

  ```js
  import { prepareShader } from '@vgpu/wgsl/prepare';
  import { effect, frame, init, surface } from 'vgpu';

  const gpu = await init();
  let disposed = false;
  gpu.lost.then(() => disposed || onDeviceLost()); // dispose also resolves it
  const stage = surface(gpu, canvas, { autoResize: false, alphaMode: 'opaque', label: 'name' });
  stage.resize([width, height]);                  // the page measured and capped the size
  const shader = effect(gpu, prepareShader(wgsl, 'name.wgsl'), { label: 'name.pass' });
  await shader.compile(stage);                    // pre-warm against the surface, before the first frame
  // each frame: shader.set({...complete uniform struct...}); frame(gpu, f => f.pass(stage, shader))
  // first frame: await gpu.settled()             // waits for submitted queue work too
  // stop: if (disposed) return; disposed = true; stage.dispose(); gpu.dispose()
  ```

  - Pre-warm with `compile(stage)` once the surface exists: it reads the surface's real format, depth and sample count.
    `compile({colors: [stage.format]})` is the older form, still valid in 0.6.
  - `gpu.settled()` already waits for submitted queue work; an explicit `onSubmittedWorkDone()` before it is redundant.
  - 0.6 rejects raw WGSL strings (`VGPU-SHADER-SOURCE-UNPREPARED`): pass a static `.wgsl` import from the build loader, or
    `prepareShader(source, name)` once, outside frames. The painter prepares its shaders once, with the scene's numbers written in.
  - Use `gpu.lost`, not the old `gpu.gpu.lost`. Loss disposes nothing. The player shows the still on loss.
  - Frame callbacks are synchronous: no `await` inside `frame()`.
  - The first `set()` of a uniform struct supplies every member with exact component counts.
  - A `Surface` is only ever a render destination, never a binding.
  - If construction throws after `init()`, call `gpu.dispose()` and rethrow (the player's `play()` does).

## 2. The parts of the page

The player has three parts, in plain modules: the markup (`index.html`), the code that starts, runs and stops the GPU (`main.js`), and
the painter that draws with vgpu (`painter.js`).

1. **Markup.** A stage element, a still picture in it from the first paint, and the canvas. The stage carries a ready flag
   (`data-ready` on the player's `.stage`): `"true"` once a first frame has really finished, `"false"` once the page knows it will not
   draw, absent while that is open. CSS shows the canvas only under `[data-ready="true"]` (the player fades it in over 240 ms, none
   under reduced motion) and the still otherwise. If anything on the page rewrites the stage's markup later, it must leave the flag
   and the canvas alone: losing the flag hides a working canvas. Text never sits under the scene.
2. **Starting and stopping.** The standalone player is the whole page, so it starts at once. In a page with other content, start the
   GPU when the stage comes on screen, stop drawing while the tab is hidden or the stage is off screen, and give the device back when
   the stage goes; load the drawing code with a dynamic `import()`, so vgpu is fetched only for a stage that is visible and never
   slows the page's first paint. A scene moves by itself, so it draws every frame while it is on screen. Reduced motion holds the
   scene at its opening view and moment (the player holds it and lets drags and keys move it).
3. **Painter.** Draws the file's splats on the art-pixel grid and scales the grid up to the canvas (references/painter.md).

## 3. What the page guarantees

Work runs only while the stage is on screen, in a visible tab and allowed by the motion setting. The drawing code is requested after
the page's first paint. The canvas's backing store is capped at 3 device pixels a CSS pixel, so the art pixels stay square and the
scene has the same grid on any screen. The still stays until a first frame really finished on the GPU (`settled()`), not when a
canvas or adapter merely exists. Without WebGPU the GPU is never started and the still remains.

The standalone player keeps the parts that matter for one scene: the still until a settled first frame, the ready flag, reduced
motion, the device-pixel cap of 3, the still on device loss or without WebGPU. `requestAnimationFrame` already stops in a hidden tab.
In a page with other content, add the on-screen check and the lazy import from section 2.

## 4. Serving and loading

- A baked file is static. Serve it gzipped (a `.bin` is not on every server's compress list: add it) under a name that changes with
  its content, with a long cache. Still splats gzip to about a quarter of their size (`sculpt.js` 0.08 to 0.02 MB), a cloth's frames
  hardly at all (`cloth.js` 0.89 to 0.66 MB), scenes of a few hundred thousand splats to about half.
- Only the page that shows a scene asks for its file. Load the player's modules when the stage is on screen, after first paint, and
  fetch the file while the GPU starts (the player asks for both together). Check with the built bundles that the site's main bundle
  holds no `RSPL` and no shader.
- The stage carries the still picture (`still.png`, from `kit/stills.cjs`, with its width and height, `image-rendering: pixelated`)
  from the first paint; the live scene fades in over it on its first frame, so nothing moves. Without WebGPU the still stays, with a
  line saying so.
- `player/serve.mjs` serves the player for checking on this machine: `node player/serve.mjs <scene.bin> <still.png> [port]`, on
  127.0.0.1 (port 4173 unless given), with the two named files answered as `/scene.bin` and `/still.png`.
- Cost, measured for scenes of 300,000 to 400,000 splats (3 to 4 MB gzipped) in headless Chromium with throttling: first live frame
  about 5 to 6 s on "Fast 4G" (9 Mbit/s) and about 20 s on "Slow 4G" (1.6 Mbit/s), with the still showing within about a second.
  Smaller files are the lever: fewer splats, a shorter loop for a cloth, fewer parts.

## 5. Orbit and touch

What `player/main.js` does, and what a site's scene should do:

- Turn without end; tilt clamped to ±86° (`TILT_LIMIT`), so the view never flips. At rest it turns once every 30 seconds.
- One to one: radians per CSS pixel = 1 / (focal x scale x radius x zoom / (device pixels per CSS pixel x camDist)), so the scene's
  near edge keeps up with the pointer.
- Let go: carry on at the speed of the last 100 ms (at most a turn a second, half a turn for tilt); the turn eases back to the
  30-second cruise, the tilt coasts and returns to rest from 0.8 s after the release.
- Mouse and pen turn and tilt. A finger only turns: `touch-action: pan-y` on the canvas hands every upright swipe to the page's scroll.
  Two-finger tilt is not built; on a touch screen, tilt is the keyboard's.
- Focusable (`tabindex="0"`, `role="img"`, and an `aria-label` that says what the scene holds and how to move it; change the player's
  generic label to name the scene): the arrow keys on the focused canvas turn 20° and tilt 12° a press. A focus ring shows on keyboard
  focus. `cursor: grab`, `grabbing` while held.
- Less motion (`prefers-reduced-motion: reduce`): it holds still at the still's view and moment; drags and keys still move it and it
  stays where left.
- One scene's GPU device at a time: when a page swaps scenes, end one device before the next begins.
- The player has no zoom and no sound, and its loop is the one baked into the file.
