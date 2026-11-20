---
name: splat-scenes
description: Sculpt 3D Gaussian splat scenes in code with ink-studio, bake each into one small file, and play it on a web page with a WebGPU pixel-art player (vgpu 0.6) that turns under drag, touch and keys, with stills, a GIF and a proof that the page draws what the toolkit draws. Use when making, changing or baking a splat scene, putting one on a page, exporting its stills or GIF, or when a splat picture shows holes, popping, a wrong order, a jump at the loop or colours outside its palette.
---

# Splat scenes

A splat scene is a small 3D picture made of Gaussian splats: soft coloured blobs, each with a centre, a size and shape, a palette
colour and a density, drawn as crisp pixel art. You write the scene as code against **ink-studio** (an MIT-licensed toolkit: solids,
light, materials, hand-placed splats, rigs, cloth), this kit **bakes** it into one file, and the **player** draws that file in a
browser with WebGPU, turning slowly and following the pointer. Light is baked into colours, motion into a loop of a few seconds, so
the page does only cheap arithmetic each frame. Describe the result as "baked from code, drawn as pixel art": the splats are real
Gaussian splats, but not trained from photographs (references/splats.md).

This folder is complete on its own: copy it anywhere. It needs Node 18 or later, a download of ink-studio, and a browser with WebGPU.

## Setup

1. **ink-studio, in a folder you can write to.** The kit calls it from there and never copies it. Download the newest:

   ```sh
   mkdir -p /abs/path/ink-studio
   curl -sL https://github.com/siliconjungle/shapeshift-labs-ink-studio/archive/HEAD.tar.gz | tar xz -C /abs/path/ink-studio --strip-components 1
   ```

   Or install it as a package in a scratch folder, `npm install github:siliconjungle/shapeshift-labs-ink-studio`, and use
   `node_modules/@shapeshift-labs/ink-studio`. The folder must be writable: the download carries no `dist/`, and loading the toolkit
   writes `dist/standalone.js` (several MB) inside it on first use and after any change to its sources. Check it with
   `node /abs/path/ink-studio/cli/ink-studio.js help`.

   The notes in `references/` were checked against commit `cf35ff8` (`cf35ff83140164e33314d5293e1c3d87cd4ed7bf`, the newest on 20
   Nov 2026); put that in place of `HEAD` for exactly that copy. references/ink-studio.md maps every README section, guide and
   example of it, each marked with whether it survives the bake; for anything newer, bake it and the baker says whether it travels.
2. **The player's packages:** `npm install --prefix /abs/path/splat-scenes/player` (vgpu 0.6.0 and @vgpu/wgsl 0.6.0, pinned exactly).
   npm may warn that two packages' install scripts did not run (vgpu's Node adapter); the browser player does not need them.
3. **A browser with WebGPU:** desktop Chrome or Edge; headless Chromium with `--enable-unsafe-webgpu` (and `--use-angle=metal` on a
   Mac). Without WebGPU the player shows the scene's still picture.

## Notes for agents

- **Name the toolkit on every command.** Each command may run in a fresh shell, so an `export` does not reach the next one. Write
  `env INK_STUDIO=/abs/path/ink-studio node kit/bake.cjs ...` every time. A kit command run without it stops and says so.
- **Absolute paths** for the scene file, the outputs and ink-studio's `--out`; or run from this folder, as the commands below do.
- **Script files for anything with variables, loops or `$(...)`**: write a small `.sh` file and run it, rather than typing them into a
  shell that may refuse or forget them.
- **Out of the way:** `out/` in this folder is ignored by git; put bakes there or anywhere outside it.
- **Scene files** are plain CommonJS and can live anywhere; they reach the kit's loop helper by its path. Name them `.js`: the kit
  takes `.cjs` too, but ink-studio's command line does not.

## From a blank file to a scene on a page

1. **Check the pipeline** with ink-studio's own first example, `examples/sculpt.js` (a stone block with a ball carved out and a green
   ball on top): bake, prove, stills, play (Commands, below; a few seconds in all). It is a pipeline check, not a model of what
   a scene should look like: a real scene has many more parts, its own palette of colour ramps, light set on purpose, and things that
   move. ink-studio's `examples/cloth.js` also bakes, and checks the moving path.
2. **Write the scene file**: a module that takes the toolkit and returns `{ id, name, seed, build(seed) }`. Read the short list in
   references/ink-studio.md, 1, start from the skeleton in 2.1, and follow its order: palette and builder, light, a rig if parts
   move, solids and `S.bake()`, hand-placed splats, flames, motes, a cloth, then `B.finish({ cam, detail, radius, ... })` and the
   stage. 2.2 to 2.6 there cover light, every material field, hand-placed splats, things that move and the finish, and what of each
   the file carries; references/recipes.md has sizes, budgets, a far backdrop, lettering, neon, glass, interiors, and what to build
   instead of what the file cannot carry.
3. **Look while you sculpt** at the stage's size: ink-studio's `render --w 1440 --h 960`, `turn` and `stats` draw the scene with the
   same renderer the kit uses, and `--px1` gives the picture the kit's still will be (references/ink-studio.md, 2.7). Leave its look
   options off: the file does not carry them.
4. **Make it loop** (The loop, below).
5. **Bake** it. Read what the baker prints: splats, parts, frames, cloth dabs, the size raw and gzipped, how near every stored number
   is, and how far each part and the cloth are from where they began a loop on. When it refuses, it names the cause
   (references/format.md, 9): take that feature out or rebuild it from what the file carries.
6. **Prove** the file draws what the scene draws (`verify.cjs`): expect 0 or 1 art pixels of 21,600 a view for a still scene and a
   few hundredths of a percent with motion (ink-studio's `cloth.js`: 0.023%). It keeps the toolkit's pictures as the reference for
   any painter.
7. **Stills**: `still.png` is the page's picture until the live scene's first frame and without WebGPU; `sheet.png` and `moments.png`
   are six views and eight moments to look at.
8. **Play** it: serve the player and open it in a browser. A **GIF** of the loop comes from `gif.cjs`.
9. **Put it on a site**: references/hosting.md (the island pattern, serving, loading, orbit and touch), and prove it with
   references/proof.md.

## Commands

From this folder, with `INK_STUDIO` named on each line. `scenes/my-scene.js` stands for your scene file (for the pipeline check,
`/abs/path/ink-studio/examples/sculpt.js`).

| Step | Command | Makes |
| --- | --- | --- |
| Bake | `env INK_STUDIO=/abs/path/ink-studio node kit/bake.cjs scenes/my-scene.js 8 out/my-scene/scene.bin` | The file; `8` is the loop in seconds (a whole number of thirtieths) |
| Prove | `env INK_STUDIO=/abs/path/ink-studio node kit/verify.cjs scenes/my-scene.js out/my-scene/scene.bin out/my-scene/reference` | The toolkit's pictures and `reference.json`; prints the art pixels that differ |
| Stills | `env INK_STUDIO=/abs/path/ink-studio node kit/stills.cjs out/my-scene/scene.bin out/my-scene` | `still.png`, `sheet.png`, `moments.png` |
| GIF | `env INK_STUDIO=/abs/path/ink-studio node kit/gif.cjs out/my-scene/scene.bin out/my-scene/scene.gif` | One loop, once round, playing for ever |
| Play | `node player/serve.mjs out/my-scene/scene.bin out/my-scene/still.png 4173` | The player at http://127.0.0.1:4173/ (stop it with Ctrl-C) |
| Preview | `env INK_STUDIO=/abs/path/ink-studio node /abs/path/ink-studio/cli/ink-studio.js render scenes/my-scene.js --w 1440 --h 960 --out /tmp/look.png` | ink-studio's own picture of the live scene at stage size |

What ink-studio's `sculpt.js` gives on a Mac: 4,027 splats, a 0.08 MB file (0.02 MB gzipped), baked in 0.1 s, proved in 0.6 s (at
most 1 art pixel of 21,600 differs in any view), stills in 0.2 s, a GIF of 120 frames (0.41 MB) in 2 to 4 s. Its `cloth.js`: 1,413
splats and 396 cloth dabs, 0.89 MB (0.66 MB gzipped), baked in 2 s. A GIF takes about a second per thousand splats, more with big
splats on screen (references/gif.md).

In the player: it turns once every 30 seconds; drag to turn and tilt, flick to spin, arrow keys on the focused picture turn 20° and
tilt 12°; a finger only turns, so the page still scrolls; with reduced motion it holds still until moved.

## The loop

The file holds one loop of L seconds (the bake's second argument), and the player plays it for ever, so everything that moves must be
back where it started after L seconds.

- **Kinds of motion on single splats** (sway, bob, orbit, flicker, ...): end `build` with the kit's loop helper, which moves each speed
  to the nearest whole number of cycles a loop and changes nothing else:

  ```js
  const loopable = require('/abs/path/splat-scenes/kit/loop.cjs');
  // ... at the end of build(seed):
  return loopable(W, 8); // the same 8 as the bake
  ```

  The bake refuses a speed that is not whole cycles a loop. A sway's second motion never comes round exactly; the helper picks the
  cycle count that brings it nearest, and what is left is well under an art pixel.
- **Rigid parts** (`K.rig`): write each part's motion as a function of time that comes back in L, such as a turn of 2π k t / L or a
  swing of sin(2π k t / L). The bake prints how far each part is from where it began, a loop on: about 1e-11 is exact; anything you
  can see means a period that does not divide L.
- **A cloth** is simulated: the bake runs it for 15 loops first so it settles, stores every frame of the 16th, and prints how far it
  ends from where it began. Gusty wind never comes round exactly; calm wind and a small seam (well under an art pixel) do not show.

## The art grid

The player draws in art pixels q screen pixels square. On a stage h screen pixels high, at the opening view:

    q = round(h / (0.6887 × detail × dist)), kept within 1 to 18;   on a 960-high stage q = round(1394 / (detail × dist))

`detail × dist` from 399 to 557 gives q = 3: 480 by 320 art pixels on a 1440 by 960 stage (465, as `detail: 31` at `dist: 15`, sits
in the middle). Choose the grid first, then size things in art pixels: something s world units across at distance D from the eye is
about s × H / (0.6887 × D) art pixels wide (H the grid's height, 320 here), close to s × detail at the camera's target, plus a pixel
or two of splat edge. Readable needs at least 6 art pixels for a capital letter and about 20 for a face with eyes and a mouth. Worked
sizes, the table for other grids and how they were measured: references/recipes.md, 1.

## What a file can hold

Sculpted solids with baked light and their palette colours; glass; hand-placed splats; flames and motes; eight kinds of motion; rigid
parts; one cloth; fog, outline, contact shade and dither. Not: per-pixel looks, skies, live lights, water, bones and puppets, particles,
physics beyond one cloth, a camera that zooms or has its own field of view. The baker stops on any of those and names it, except the
field of view: it writes the toolkit's 38 degrees, and only the proof shows the difference. Details:
references/format.md, 9, and references/ink-studio.md, 2.5 and 2.6; what to build instead of each: references/recipes.md, 8.

A file holds at most **256 colours** (255 for a GIF), **256 parts**, **256 styles** (each different density, kind and flags, and part)
and **256 motions** (each different range and extra among moving splats). Every moving part multiplies the styles: ten densities in
30 parts are 300 styles, and the bake stops. So pick densities and ranges from a few values, and keep parts to what really moves;
references/recipes.md, 2, shows how to count splats per part.

## Folder

| Path | What it is |
| --- | --- |
| `kit/toolkit.cjs` | Loads ink-studio from `INK_STUDIO`, builds a scene file, walks its world through time |
| `kit/bake.cjs` | Scene file to baked file; prints cost and accuracy; refuses what the file cannot carry |
| `kit/format.cjs` | The file's layout and codecs, shared by the baker and the decoder |
| `kit/decode.cjs` | Reads a baked file back into ink-studio's rows at any frame |
| `kit/verify.cjs` | The proof: live scene against decoded file, drawn by ink-studio, plus the reference pictures |
| `kit/stills.cjs` | `still.png`, `sheet.png`, `moments.png` |
| `kit/gif.cjs` | The loop as a GIF, palette exact |
| `kit/loop.cjs` | `loopable(world, seconds)`: every kind's speed made whole cycles a loop |
| `player/index.html` | The page: still picture, canvas, ready flag, import map |
| `player/main.js` | Starting the GPU, cruise, drag, flick, keys, touch, reduced motion, device loss |
| `player/painter.js` | The WebGPU painter (vgpu): three passes a frame |
| `player/scene.js`, `camera.js`, `motion.js`, `order.js` | Reading the file, the camera and grid, motion on the processor, the far-to-near order |
| `player/serve.mjs` | Serves the player with one scene on 127.0.0.1 |
| `references/` | The topic notes below |

Each file's opening comment says what it owns.

## References

| Note | Read it for |
| --- | --- |
| references/ink-studio.md | Writing a scene: what to read first, the skeleton and lifecycle, light, every material field, groups, hand-placed splats, rigs and cloth, the finish, previewing at stage size; maps of ink-studio's README, every guide and every example, grouped by what you are making and each marked with whether it survives the bake |
| references/recipes.md | The art grid and readable sizes, budgets and counting splats per part, a far backdrop, lettering, neon, a glass case, an interior lit by one sun and a fill, and what to build instead of what the file cannot carry |
| references/format.md | The baked file byte by byte, every kind of motion's maths, how to draw a picture from it, costs, accuracy, what the baker refuses, notes for writing a painter |
| references/painter.md | How `player/painter.js` draws, the toolkit's rules a painter must follow, mistakes made and caught, performance |
| references/hosting.md | vgpu (version, offline docs), the GPU island pattern for putting a scene in a site, serving and loading, orbit and touch |
| references/proof.md | Proving a file, proving a painter against the toolkit pixel for pixel, browser checks |
| references/gif.md | The GIF from the command line, and a GIF button in a page |
| references/splats.md | What "true" splats means here, what stays offline, baking again, sources |
| references/random-scenes.md | Optional: a different scene for each seed |
