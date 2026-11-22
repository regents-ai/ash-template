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
differ, how many of those are lone (no differing neighbour above, below or to either side), the longest run of them on one row, and
the biggest clump (differing art pixels joined edge to edge):

    night-stall_yaw28.6_pitch10.3_t0.00: 360x240 art pixels of 4, 55 differ, 51 lone, longest run on a row 2, biggest clump 2

The last line gives the most any view differs, as a percentage of its art pixels.

- **Expect:** on ink-studio's `sculpt.js` (nothing moves) 0 to 1 art pixels of 21,600 a view; with parts or a cloth, a few
  hundredths of a percent (`cloth.js` 0.023%, every differing pixel lone). A small moving scene with stars, dust or swaying grass
  reads about 0.1%: a trial scene of 32,806 splats gave at most 79 of 86,400 (0.091%), its opening view 55, 51 of them lone, longest
  run 2. A large scene with a painted backdrop or thin water seen edge-on reads higher. Three trial scenes of 260,000 to 390,000
  splats gave 0.115% (a throne-hall scene), 0.346% (a lighthouse scene) and 0.14% to 0.53% (a mansion-grounds scene): the
  differences were lone pixels, scattered mostly over the far sky, the sea's glitter and colour edges, with no run or patch on the
  subject (the lighthouse scene's front view: 495 differing, 356 of them lone). A trial scene of 213,405 splats with a painted
  backdrop, thin water, rig parts and a cloth gave at most 622 of 153,600 (0.405%), 71% to 96% of them lone. A trial scene of
  344,697 splats whose backdrop is many flat colour bands gave the most yet, all harmless: 1,180 of 153,600 (0.768%) in its
  opening view, 64% to 96% lone over its views, longest run 5, biggest clump 9, the differing pixels in dotted lines along the
  band edges.
- **The difference picture.** Beside each of the toolkit's pictures the proof writes `<the same name>_differ.png`, blown up as a
  stage shows it: the toolkit's picture faded to a dark grey, with every art pixel that differs in magenta. Open the view with the
  most differing pixels first. Magenta specks scattered one by one, even thick over fine repeated detail, and short lines along
  the edge between two flat colours, are the harmless kind; a solid magenta clump or a cluster of lines on the subject is where
  the file and the scene disagree.
- **Lone pixels or a fault.** The lone share (lone over differing, per view) never decides on its own: harmless files gave 64% to
  97% lone and real faults 27% to 98%. Read the row lines first, then where the clumps sit and how big. Checked on three harmless
  files (trial scenes of 213,405 and 344,697 splats and a throne-hall scene of 371,821, each proved against its own bake; 480 by
  320 art pixels, 153,600 a view) and on four faults made by changing one thing in scratch copies of the 213,405-splat scene and
  proving each copy against the file baked before the change.
  1. **The row lines.** On a file baked from this scene, every moment's line gives 0 differing densities, colours, kinds and
     motion numbers, positions within about 1e-3 world units, and a shape figure: the most any splat's covariance differs, as a
     share of its size. Without a cloth it is the bake's `whole shape` (about 0.1%, up to 0.3% with flat splats); with one, 0.96%
     to 1.38%, because each dab's facing is stored in two bytes a frame, within about 0.94° (references/format.md, 7). Differing
     colours or kinds, a position error of whole units, or `NaN`, mean the file is not this scene's: bake again. Both moved solids
     were caught here: a crate moved 0.02 units gave `rows within 1.42e+2 world units` and 16,269 differing colours, a tank moved
     0.04 `rows within NaN` and 15,136. The crate's pixels (at most 643 differing a view, 66% to 80% lone, longest run 8) looked
     almost like a harmless file's: the rows catch a changed solid; the pixels may not.
  2. **Where the clumps sit and how big.** With clean rows, open the difference picture of the view with the biggest clump. On the
     three harmless files the biggest clump in any view was 16, 9 and 4 art pixels, and every clump of more than a few lay on flat
     colour: in dotted lines along the edges between bands of a far backdrop or a cloud's edge, or a ring round a snowflake; their
     longest runs (8, 5 and 2) lay on the same edges, so run length alone does not decide. Specks spread over the whole picture,
     thickest on fine repeated detail (a grid of panels). The moved tank gave clumps of 35 to 100 art pixels on the tank in the
     five views that see it (4 in the one that does not) and a run of 14 seen from above; the moved crate a clump of 22 on the
     crate seen from above. A clump over 16, or a clump of any size that sits on the subject, is where the file and the scene
     disagree.
  3. **A count well above the last proof's**, with clean rows and no bigger clump, is a finish that differs (contact shade,
     dither, fog or outline changed since the bake): the rows hold no finish. The two tried raised the count in every view with
     the same biggest clump (16, on the backdrop): contact shade's range 0.50 to 0.52 gave at most 1,018 differing (0.663%), 77% to
     95% lone; dither 0.30 to 0.32 at most 1,478 (0.962%), 83% to 98% lone, against 622 for the scene's own file. Bake again and
     prove; it drops back when the file was stale.
  4. **Otherwise it is harmless**, whatever its lone share: the trial scene of 344,697 splats read 1,180 differing in its opening
     view, 64% to 65% lone, with clean rows and its biggest clump 9 on a band edge.

  For scale, scenes drawn at the wrong moment: a trial scene of 32,806 splats 984 differing, 272 lone, longest run 5, all on its
  swaying grass; `cloth.js` 913 of 21,600, none lone, a run of 29. `still.png` (from `kit/stills.cjs`) is the baked file at the
  opening view and the start of the loop, and the reference picture named for the opening view at time 0 (yaw and pitch in degrees,
  such as `my-scene_yaw28.6_pitch9.2_t0.00.png`) is the live scene at the same view and size.
- **The live scene is walked frame by frame** to each moment, as the bake walked it: a cloth remembers every step, so a different walk
  would leave it a hair elsewhere.
- **The reference.** It keeps ink-studio's pictures of the live scene: each at its art-pixel size (`<id>_yaw.._pitch.._t...png`) and
  blown up as a stage shows it (`..._x<px>.png`), with `reference.json` giving the canvas, the field of view, and each picture's yaw,
  pitch, distance, target, art pixel, grid, loop time and difference picture (`..._differ.png`). That folder is what a painter is
  checked against.

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
`cloth.js`, and a trial scene of 32,806 splats: ready within 0.3 s, a 1438 by 958 canvas, playing, no errors; a trial scene of
213,405 splats with a cloth the same, ready in 0.9 s.

**Playwright for it.** It is not one of the player's packages. Add it to the player folder you installed the packages into (SKILL.md,
Setup, 2: in place when this folder is yours to write in; your copy when it is shared or read-only), then its Chromium:

```sh
npm install --prefix /abs/path/splat-scenes/player --no-save playwright@1.64.1
/abs/path/splat-scenes/player/node_modules/.bin/playwright install chromium
```

With a copy, put its path in place of `/abs/path/splat-scenes/player`. `--no-save` leaves `package.json` and `package-lock.json` as
they were, so the pinned install stays as it is. Playwright 1.64 needs Node 20 or later; any version with Chromium's WebGPU will do.
The packages are about 18 MB. The browser goes into Playwright's own cache (`~/Library/Caches/ms-playwright` on a Mac): a download
of about 300 MB on a Mac (Chrome for Testing 195 MB, its headless shell 104 MB, FFmpeg 1.4 MB), about 570 MB on disk once unpacked,
and nothing when that version's Chromium is already there. To see what it would fetch first:

```sh
/abs/path/splat-scenes/player/node_modules/.bin/playwright install --dry-run chromium
```

It prints each browser's install folder and download address, downloads nothing and exits 0; when those folders already exist, the
browser is there. Run `check.mjs` from the folder Playwright went into (`node /abs/path/splat-scenes/player/check.mjs ...`): it finds
Playwright in the folder it sits in.

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
