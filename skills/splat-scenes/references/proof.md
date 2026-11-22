# Proving a scene and a page

Three things can be proved: that the baked file draws what the scene draws (`kit/verify.cjs`), that a painter in a browser draws what
the toolkit draws (the match), and that the page behaves (browser checks). Prove the first after every bake, and the other two after
any change to the player or the page around it.

## 1. The file against the scene

```sh
env INK_STUDIO=/path/to/ink-studio node kit/verify.cjs scenes/my-scene.js out/my-scene/scene.bin out/my-scene/reference
```

It builds the live scene with ink-studio, reads the baked file back with `kit/decode.cjs`, and has ink-studio's renderer draw both
from six views (the opening view and the other three quarter turns, nearly straight above, nearly straight below) at three moments of
the loop (0, 5/16 and 11/16 of it), on a 1440 by 960 stage. For each moment it prints how far the decoded splats are from the live
ones (position, shape, phase; how many densities, colours, kinds and motion numbers differ) and for each picture how many art pixels
differ, how many of those are lone (no differing neighbour above, below or to either side) and the longest run of them on one row:

    night-stall_yaw28.6_pitch10.3_t0.00: 360x240 art pixels of 4, 55 differ, 51 lone, longest run on a row 2

The last line gives the most any view differs, as a percentage of its art pixels.

- **Expect:** on ink-studio's `sculpt.js` (nothing moves) 0 to 1 art pixels of 21,600 a view; with parts or a cloth, a few
  hundredths of a percent (`cloth.js` 0.023%, every differing pixel lone). A small moving scene with stars, dust or swaying grass
  reads about 0.1%: a trial scene of 32,806 splats gave at most 79 of 86,400 (0.091%), its opening view 55, 51 of them lone, longest
  run 2. A large scene with a painted backdrop or thin water seen edge-on reads higher. Three trial scenes of 260,000 to 390,000
  splats gave 0.115% (a throne-hall scene), 0.346% (a lighthouse scene) and 0.14% to 0.53% (a mansion-grounds scene): the
  differences were lone pixels, scattered mostly over the far sky, the sea's glitter and colour edges, with no run or patch on the
  subject (the lighthouse scene's front view: 495 differing, 356 of them lone).
- **Lone pixels or a fault.** Read each view's numbers. Most of the differing pixels lone and the longest run 1 or 2 is a splat
  tipped between two near shades here and there: nothing to fix. Few of them lone, a long run, or one view far above the others
  means the file and the scene disagree there, and a row line well above the others names the field. For scale, the same scenes
  drawn at the wrong moment, which is what a disagreement looks like: the trial scene 984 differing, 272 lone, longest run 5, all on
  its swaying grass; `cloth.js` 913 of 21,600, none lone, a run of 29. To see where they fall: `still.png` (from `kit/stills.cjs`)
  is the baked file at the opening view and the start of the loop, and the reference picture named for the opening view at time 0
  (yaw and pitch in degrees, such as `my-scene_yaw28.6_pitch9.2_t0.00.png`) is the live scene at the same view and size.
- **The live scene is walked frame by frame** to each moment, as the bake walked it: a cloth remembers every step, so a different walk
  would leave it a hair elsewhere.
- **The reference.** It keeps ink-studio's pictures of the live scene: each at its art-pixel size (`<id>_yaw.._pitch.._t...png`) and
  blown up as a stage shows it (`..._x<px>.png`), with `reference.json` giving the canvas, the field of view, and each picture's yaw,
  pitch, distance, target, art pixel, grid and loop time. That folder is what a painter is checked against.

## 2. A painter against the toolkit (the match)

Draw the painter in a headless browser at every view in `reference.json`, read its art-pixel picture back, and compare it with the
toolkit's picture pixel for pixel. Report for each view the art pixels that differ, how many of those are lone (no differing neighbour
up, down, left or right), how many are off the palette (must be 0), and whether the grids agree; put the front view's pair side by side
with the differences marked. Quickest check: `still.png` from `kit/stills.cjs` is the reference's front view at the start of the
loop, so the two PNGs can be compared directly.

The core of it, in a page served from `player/` with the player's import map, `scene.bin` beside it and the reference pictures under
`ref/`:

```js
import { frame, init } from 'vgpu';
import { createPainter } from './painter.js';
import { loadScene } from './scene.js';

const reference = await (await fetch('ref/reference.json')).json();
const gpu = await init(), scene = await loadScene('scene.bin'), painter = createPainter(gpu, scene);
painter.resize(reference.canvas.w, reference.canvas.h);
await painter.compile();
const palette = new Set(Array.from(scene.blocks.palette, v => v & 0xffffff));
for (const p of reference.scene.pictures) {
  frame(gpu, f => painter.encode(f, { yaw: p.yaw, pitch: p.pitch, seconds: p.loopTime }));
  await gpu.settled();
  const ours = await painter.picture.color.read({ mipLevel: 0, region: 'all' }); // RGBA bytes, the art-pixel grid
  const bitmap = await createImageBitmap(await (await fetch('ref/' + p.native)).blob(), { colorSpaceConversion: 'none' });
  const g = new OffscreenCanvas(bitmap.width, bitmap.height).getContext('2d', { colorSpaceConversion: 'none' });
  g.drawImage(bitmap, 0, 0);
  const theirs = g.getImageData(0, 0, bitmap.width, bitmap.height).data;
  let differ = 0, offPalette = 0;
  for (let i = 0; i < theirs.length; i += 4) {
    if (ours[i] !== theirs[i] || ours[i + 1] !== theirs[i + 1] || ours[i + 2] !== theirs[i + 2]) differ++;
    if (!palette.has((ours[i] << 16) | (ours[i + 1] << 8) | ours[i + 2])) offPalette++;
  }
  console.log(p.native, differ, offPalette);
}
gpu.dispose();
```

Turn colour-space conversion off on both the bitmap and the canvas, or the browser shifts the reference's colours and every pixel
differs.

- **Expect:** on ink-studio's examples 0 to 21 art pixels of 21,600 a view, nearly all lone, none off the palette, every grid the same.
  On scenes of a few hundred thousand splats about one art pixel in a hundred (references/painter.md says why and what would close it).
- **A run of differing pixels** (not lone) means a real fault: a part or cloth in the wrong place, a kind's motion, the finish. Crop
  the side-by-side at 100% where they cluster.

## 3. The page in a browser

Headless Chromium with WebGPU: `--enable-unsafe-webgpu`, and on a Mac `--use-angle=metal`. Serve the player with
`node player/serve.mjs <scene.bin> <still.png> [port]`; it prints its process number, so `kill <that number>` stops it from another
shell when no keyboard can send Ctrl-C.

**The quick check** does the first three below in one command:

```sh
node player/check.mjs out/my-scene/scene.bin out/my-scene/still.png out/my-scene/browser.png 4173
```

It starts the server on that port, opens the page in headless Chromium with WebGPU at the 1472 by 1056 window that gives the kit's
1440 by 960 stage, waits for the ready flag, checks that two pictures of the stage a second apart differ, saves a screenshot of the
page, prints the page's console errors and warnings, stops the server and confirms the port is free. It exits 0 only when the flag
is `"true"`, the pictures differ, nothing was printed to the console and the port is free. On ink-studio's `sculpt.js` and
`cloth.js`, and a trial scene of 32,806 splats: ready within 0.3 s, a 1438 by 958 canvas, playing, no errors.

**Playwright for it.** It is not one of the player's packages, so the pinned install stays as it is; add it to a copy of the player
you can write to (Setup, 2), then its Chromium:

```sh
npm install --prefix /abs/path/player --no-save playwright@1.64.1
/abs/path/player/node_modules/.bin/playwright install chromium
```

Playwright 1.64 needs Node 20 or later; any version with Chromium's WebGPU will do. The packages are about 18 MB; the browser is a
download into Playwright's own cache, about 570 MB on disk once unpacked on a Mac (Chrome for Testing and its headless shell),
and nothing when that version's Chromium is already there. Run `check.mjs` from that copy (`node /abs/path/player/check.mjs ...`):
it finds Playwright in the folder it sits in.

Check, with it or by hand:

- **Stage size:** the player's stage follows the window. It is as wide as the smaller of the page less its 16 px padding each side
  and (window height − 96 px) × 1.5, at 3 : 2, inside a 1 px border; the canvas fills it, and its drawing buffer is its own size at
  one device pixel a CSS pixel. Measured in headless Chromium: a 1472 by 1056 window gives the 1440 by 960 stage the kit's pictures
  assume (a 1438 by 958 canvas inside the border, the same art grid for `sculpt.js`); 1280 by 800 gives 1056 by 704; 1920 by 1200
  gives 1656 by 1104. Set the viewport to 1472 by 1056 when screenshots should line up with the kit's stills.
- **Draws:** the ready flag on `.stage` becomes `"true"` (a finished first frame), with no console errors or warnings (a vgpu
  error starts `VGPU-`; WebGPU warns of a draw of nothing).
- **Plays:** two screenshots 2 s apart differ.
- **Held still** (`reducedMotion: 'reduce'` on the browser context): the player holds the opening view at the start of the loop,
  the view and moment of `still.png`, so a screenshot can be set beside it; two screenshots 1.5 s apart are the same. Prove the drag
  and the keys here: while the scene turns by itself, a changed picture proves nothing.
- **Drag:** on the held scene, a mouse drag across the canvas changes the picture, and it stays where left.
- **Keys:** on the held scene, focus the canvas and press an arrow key: the picture changes and stays.
- **A finger** (a phone context with touch, 390 wide, three device pixels a CSS pixel): send touches through the DevTools protocol's
  `Input.dispatchTouchEvent`, and hold the finger still 300 ms before lifting, or the page flings and screenshots differ. An upright
  swipe leaves the picture alone (the page scrolls); a sideways swipe turns it. Check 390 and 320 wide for sideways overflow.
- **No WebGPU** (an init script that makes `navigator.gpu` undefined): the flag becomes `"false"`, the canvas is hidden, the still
  shows with its note.
- **In a site:** the picture survives the framework updating the page and a change of state (the ready flag and the canvas stay),
  and hiding and showing the tab stops and resumes drawing.
- **Loading** (a site): the DevTools protocol's `Network.emulateNetworkConditions` ("Fast 4G": 9 Mbit/s down, 1.5 up, 150 ms;
  "Slow 4G": 1.6, 0.75, 150 ms), bytes from each response's `encodedDataLength`, and the page's paint and resource timings. Open the
  site's other pages and check none asks for the `.bin` or the painter.
- **vgpu:** `npx vgpu check <file.wgsl>` validates a WGSL file. The player writes its shaders at run time from the file's header, so
  check them in the browser: a pipeline that fails to compile shows as a console error. In a site that prepares shaders at build time,
  prepare each one once in Node and confirm a version 2 artifact (`version: 2`, producer `@vgpu/wgsl/prepare-v2`). Read
  `npx vgpu docs cat /guides/shipping-to-production.docs.md` before calling a page done.

Playwright drives all of this; any version with Chromium's WebGPU will do. For a site with a test runner: some runners (Vitest among
them) resolve an import without an extension to `.mjs` before `.ts`, so never give a script a module's name.
