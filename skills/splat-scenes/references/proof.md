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
differ. The last line gives the most any view differs, as a percentage of its art pixels.

- **Expect:** on ink-studio's `sculpt.js` (nothing moves) 0 to 1 art pixels of 21,600 a view; with parts or a cloth, a few
  hundredths of a percent (`cloth.js` 0.023%).
  More than a fraction of a percent means the file and the scene disagree: read the row lines to see which field.
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
`node player/serve.mjs <scene.bin> <still.png> [port]` and check:

- **Draws:** the ready flag on `.stage` becomes `"true"` (a finished first frame), with no console errors or warnings (a vgpu
  error starts `VGPU-`; WebGPU warns of a draw of nothing).
- **Plays:** two screenshots 2 s apart differ.
- **Drag:** a mouse drag across the canvas changes the picture while held.
- **Keys:** focus the canvas, press an arrow key: the picture changes.
- **Less motion** (`reducedMotion: 'reduce'` on the browser context): two screenshots 1.5 s apart are the same; a drag changes it and
  it stays where left.
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
