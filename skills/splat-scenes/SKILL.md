---
name: splat-scenes
description: Sculpt 3D Gaussian splat scenes in code with ink-studio, bake each into one small file, and play it on a web page with a WebGPU pixel-art player (vgpu 0.6) that turns under drag, touch and keys, with stills, a GIF and a proof that the page draws what the toolkit draws. Use when making, changing or baking a splat scene, putting one on a page, exporting its stills or GIF, or when a splat picture shows holes, popping, a wrong order, a jump at the loop or colours outside its palette. For an Elixir, Phoenix and LiveView site that shows scenes through its vgpu island, use the sibling skill splat-scenes-phoenix after baking here.
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

0. **This folder**, if you do not have it yet. Either way gives the same files, about 0.3 MB:

   - **One script** (Node 18 or later; no git, no sign-in; 1 to 4 s):

     ```sh
     curl -sLO https://raw.githubusercontent.com/regents-ai/ash-template/main/skills/splat-scenes/get.mjs
     node get.mjs /abs/path/splat-scenes
     ```

     It asks GitHub once for the repository's file list, keeps the files under `skills/splat-scenes/` (none of the sibling
     `skills/splat-scenes-phoenix`), downloads each into the folder named and prints how many it wrote.
   - **The repository archive**, unpacked to just this folder: an 83 MB download for those 0.3 MB.

     ```sh
     mkdir -p /abs/path/splat-scenes
     curl -sL -o /abs/path/ash-template.tar.gz https://github.com/regents-ai/ash-template/archive/refs/heads/main.tar.gz
     tar xzf /abs/path/ash-template.tar.gz -C /abs/path/splat-scenes --strip-components 3 '*/skills/splat-scenes/*'
     ```

     Tested with the Mac's own tar (bsdtar 3.5); the slash after `splat-scenes` keeps out the sibling folder.
1. **ink-studio, in a folder you can write to.** The kit calls it from there and never copies it. Download the newest, read which
   commit it is, and unpack it:

   ```sh
   mkdir -p /abs/path/ink-studio
   curl -sL -o /abs/path/ink-studio.tar.gz https://github.com/siliconjungle/shapeshift-labs-ink-studio/archive/HEAD.tar.gz
   gzip -dc /abs/path/ink-studio.tar.gz | git get-tar-commit-id
   tar xzf /abs/path/ink-studio.tar.gz -C /abs/path/ink-studio --strip-components 1
   ```

   The download is about 13 MB and unpacks to about 40 MB. The third line prints the commit (`package.json` says 0.1.0 in every
   copy); without git, `gzip -dc /abs/path/ink-studio.tar.gz | head -c 2048 | grep -a -o "comment=[0-9a-f]*"` prints it as
   `comment=<commit>`. The folder must be writable: the download carries no `dist/`, and loading the toolkit writes
   `dist/standalone.js` (about 11 MB) inside it on first use and after any change to its sources. Check it with
   `node /abs/path/ink-studio/cli/ink-studio.js stats /abs/path/ink-studio/examples/sculpt.js`: a pass builds the toolkit's first
   example, prints its counts (the `splats` line reads 4027), ends with `no warnings` and exits 0, in about a second.

   references/ink-studio.md was last checked against commit `22c23d8` (22 Nov 2026). A newer copy may add features the notes do
   not name: bake one, and the baker says whether it travels.
2. **The player's packages** (vgpu 0.6.0 and @vgpu/wgsl 0.6.0, pinned exactly). Install in place when this folder is yours to
   write in:

   ```sh
   npm install --prefix /abs/path/splat-scenes/player
   ```

   Copy the player out only when this folder is shared or read-only (a link into a repository, say): `cp -R
   /abs/path/splat-scenes/player /abs/path/player`, then install into and serve from that copy (`--prefix /abs/path/player`,
   `node /abs/path/player/serve.mjs`). Either way npm writes `node_modules/` and `package-lock.json` into the player folder it
   installs into. It installs about 99 MB, 68 MB of it the `webgpu` package behind vgpu's Node adapter. npm warns that two
   packages' install scripts did not run (that adapter and `webgpu`) and reports high-severity vulnerabilities in
   `@modelcontextprotocol/server`, which vgpu's own command line uses to serve its docs; the browser player loads none of them.
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
   instead of what the file cannot carry. The tables are the common parts; for a shape or effect they do not cover, first find the
   toolkit's own guide or example in the map in references/ink-studio.md, 4, and read it, then read the source file named there,
   then bake a small test and let the baker say whether it travels.
3. **Look while you sculpt** at the stage's size: ink-studio's `render --w 1440 --h 960`, `turn` and `stats` draw the scene with the
   same renderer the kit uses, `--px1 --t 120` gives the picture the kit's still will be (for an 8 s loop: the kit draws 15 loops
   in), and `--zoom`, `--target`, `--yaw`, `--pitch` and `--t` give close looks at any angle and moment (Commands, below;
   references/ink-studio.md, 2.7). Leave its look options off: the file does not carry them. These are for looking; the proof
   (step 6) is the test.
4. **Make it loop** (The loop, below).
5. **Bake** it. Read what the baker prints: on its first line splats, colours (at most 256; 255 for a GIF), styles, motions, parts,
   frames and cloth dabs; then the size raw and gzipped, how near every stored number is, and how far each part and the cloth are
   from where they began a loop on. Its `shape:` line ends `whole shape within 0.31% (0.084% on average)`: how far each splat's
   shape, rebuilt from its stored sizes and turn, is from the toolkit's, at most and on average. Round splats give about 0.1%; a
   flat one takes the stored turn's error harder (that 0.31% was a splat 4.5 times longer than thick); a cloth's dabs count at
   their first frame (`cloth.js`: 0.19%). When it refuses, it names the cause (references/format.md, 9): take that feature out or
   rebuild it from what the file carries.
6. **Prove** the file draws what the scene draws (`verify.cjs`). For each view it prints the art pixels that differ, how many of
   them are lone, the longest run of them on a row and the biggest clump (differing art pixels joined edge to edge). Expect 0 or 1
   of 21,600 a view for a still scene and a few hundredths of a percent with motion (ink-studio's `cloth.js`: 0.023%). A small
   moving scene with stars, dust or swaying grass reads about 0.1% (a trial scene of 32,806 splats: at most 79 of 86,400, 0.091%;
   its opening view 55, 51 of them lone, longest run 2, biggest clump 2). A large scene with a painted backdrop, thin water or snow
   reads higher, up to about three quarters of a percent (0.115%, 0.346%, 0.14% to 0.53%, 0.405% for a trial scene of 213,405
   splats, 0.768% for one of 344,697), as lone pixels and small clumps over the far backdrop and along its bands' edges. Beside each
   of the toolkit's pictures it writes a `_differ.png`: that picture faded to a dark grey with every differing art pixel in magenta,
   so specks on the backdrop and a patch on the subject show at a glance. references/proof.md, 1, says how to tell the harmless kind
   from a fault: the row lines first, then where the clumps sit and how big they are; the share that is lone never decides it on
   its own. Each moment's row line gives the same shape figure as the bake, for the live scene against the decoded file at that
   moment: the bake's own for ordinary splats, but 0.96% to 1.38% with a cloth (`cloth.js` and three larger scenes), because each
   dab's facing is stored in two bytes a frame, within about 0.94°. It keeps the toolkit's pictures as the reference for any
   painter.
7. **Stills**: `still.png` is the page's picture until the live scene's first frame and without WebGPU; `sheet.png` and `moments.png`
   are six views and eight moments to look at.
8. **Play** it: serve the player and open it in a browser, or let `player/check.mjs` open it in a browser with no window and
   check it draws and plays. A **GIF** of the loop comes from `gif.cjs`.
9. **Put it on a site**: references/hosting.md (the page's parts, static files and the import map, serving and loading, orbit and
   touch), and prove it with references/proof.md.

## Commands

From this folder, with `INK_STUDIO` named on each line. `scenes/my-scene.js` stands for your scene file (for the pipeline check,
`/abs/path/ink-studio/examples/sculpt.js`).

| Step | Command | Makes |
| --- | --- | --- |
| Bake | `env INK_STUDIO=/abs/path/ink-studio node kit/bake.cjs scenes/my-scene.js 8 out/my-scene/scene.bin` | The file; `8` is the loop in seconds (a whole number of thirtieths) |
| Prove | `env INK_STUDIO=/abs/path/ink-studio node kit/verify.cjs scenes/my-scene.js out/my-scene/scene.bin out/my-scene/reference` | The toolkit's pictures, a `_differ.png` beside each, and `reference.json`; prints per view the art pixels that differ, how many are lone, the longest run, the biggest clump |
| Stills | `env INK_STUDIO=/abs/path/ink-studio node kit/stills.cjs out/my-scene/scene.bin out/my-scene` | `still.png`, `sheet.png`, `moments.png` |
| GIF | `env INK_STUDIO=/abs/path/ink-studio node kit/gif.cjs out/my-scene/scene.bin out/my-scene/scene.gif` | One loop, once round, playing for ever: 120 frames for an 864 by 576 stage, the grid's whole art pixels, so up to an art pixel less one over in each direction (`sculpt.js`: 865 by 580) |
| Play | `node player/serve.mjs out/my-scene/scene.bin out/my-scene/still.png 4173` | The player at http://127.0.0.1:4173/; stop it with Ctrl-C, or with the `kill` and process number it prints |
| Browser check | `node player/check.mjs out/my-scene/scene.bin out/my-scene/still.png out/my-scene/browser.png 4173` | Serves the player, opens it in headless Chromium with WebGPU, checks it draws and plays with no console errors, saves a screenshot, stops the server; needs Playwright in the player folder (references/proof.md, 3) |
| Opening picture | `env INK_STUDIO=/abs/path/ink-studio node /abs/path/ink-studio/cli/ink-studio.js render scenes/my-scene.js --w 1440 --h 960 --out /abs/path/out/my-scene/opening.png` | ink-studio's picture of the live scene at the opening view, 1440 by 960 |
| Close look | `env INK_STUDIO=/abs/path/ink-studio node /abs/path/ink-studio/cli/ink-studio.js render scenes/my-scene.js --w 1440 --h 960 --zoom 3 --target 0,1,0 --t 2 --out /abs/path/out/my-scene/close.png` | Three times nearer, aimed at a point, 2 s in; add `--yaw` and `--pitch` (radians) for another side. The picture is whole art pixels, so it can come out a few pixels over the size asked (1442 by 966 here) |

What ink-studio's `sculpt.js` gives on a Mac: 4,027 splats in 7 colours, a 0.08 MB file (0.02 MB gzipped), at most 1 art pixel of
21,600 differing in any view, a GIF of 120 frames of 865 by 580 (0.41 MB). Each step takes a few seconds: baked in 0.1 to 0.4 s,
proved in 0.6 to 2.3 s, stills in 0.2 to 1.1 s, the GIF in 2 to 8 s (the longer times on a busy machine). Its `cloth.js`: 1,413
splats and 396 cloth dabs, 0.89 MB (0.66 MB gzipped), baked in 2 to 2.4 s. A trial scene of 213,405 splats with a cloth: baked in
8 s, proved in 84 s, stills in 25 s, the GIF in 4 minutes; one of 344,697 with a cloth and falling snow: 9 s, 122 s, 87 s and 6
minutes. For a large scene, time the GIF from the proof: the proof took about a third as long as the GIF on three large scenes, and
the stills a tenth (a quarter on the 344,697 one). Finished scenes of 260,000 to 390,000 splats took 4 to 9 minutes for a GIF and
made 5 to 11 MB (references/gif.md, 1).

In the player: it turns once every 30 seconds; drag to turn and tilt, flick to spin, arrow keys on the focused picture turn 20° and
tilt 12°; a finger only turns, so the page still scrolls. With reduced motion it holds the still's view and moment, and a drag or
key turns it and stays; open it that way (in Playwright, `reducedMotion: 'reduce'`) to hold it still for a browser check
(references/proof.md, 3).

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
- **A cloth** is simulated: the bake runs it for 15 loops first so it settles, stores every frame of the 16th, and does not stop on
  how far it ends from where it began. Read its `cloth:` line: it ends `a whole loop on, it is 0.0000 world units from where it
  began` when the loop has closed exactly. **It passes under half an art pixel**: an art pixel is 1 / detail world units at the
  camera's target, so the mark is 0.5 / detail (0.016 units at `detail: 31`). Checked by eye on a flag at `detail: 31`, drawn as
  the GIF draws its frames but with the camera held still, the last frames and the first side by side: no jump at 0.037 units (1.2
  art pixels) on a flag barely stirring, where a jump shows most, nor at 0.089 and 0.135 (2.8 and 4.2) in a stronger wind; the tip
  jumped at 0.341 (10.6). Half an art pixel is under the smallest of those by more than twice; the cloths of a throne-hall scene and
  the trial scene of 344,697 splats closed to 0.0030 and 0.0036 (about a tenth). A seam that large is a jump in the player and the
  GIF alike, and the GIF's own seam check can miss it (a flag 0.34 units out gave a GIF seam inside its frames' range). To close
  it, build the wind from sines of 2π k t / L with whole k, so it repeats every loop (`K.xpbd.gust` never does), keep the cloth
  light and the wind gentle, then raise the cloth's `damp` (how fast its motion dies away, 0.6 a second unless given) and bake a
  few values: the seam does not shrink steadily with any of them. A flag
  in a gentle wind missed by 0.015 to 0.030 units up to `damp: 4.5`, 0.007 at 6 and 0.0000 at 8; in twice that wind by 0.13 to
  0.40 at every `damp` from 0.6 to 8 but 3. A trial scene of 213,405 splats went from 0.118 at the default to 0.0000 at 4.5.
  references/ink-studio.md, 2.5, has the measurements and every cloth option.

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
references/recipes.md, 2, shows how to count what each solid and section costs. ink-studio's `stats` warns past 150,000 splats
("heavy on a phone") and 48 colours ("the page can only use 48"): that is advice for its own pages. Its `picture` line gives the
grid of its own 900 by 620 frame, not the stage's (the trial scene: 300 by 207 art pixels of 3 there, 360 by 240 of 4 on the
stage). The limits here are the ones that hold for this kit's file and player.

## Folder

| Path | What it is |
| --- | --- |
| `get.mjs` | Fetches this folder from GitHub (Setup, 0) |
| `kit/toolkit.cjs` | Loads ink-studio from `INK_STUDIO`, builds a scene file, walks its world through time |
| `kit/bake.cjs` | Scene file to baked file; prints cost, colours and accuracy; refuses what the file cannot carry |
| `kit/format.cjs` | The file's layout and codecs, shared by the baker and the decoder |
| `kit/decode.cjs` | Reads a baked file back into ink-studio's rows at any frame |
| `kit/verify.cjs` | The proof: live scene against decoded file, drawn by ink-studio; per view the art pixels that differ, how many lone, the longest run, the biggest clump; plus the reference pictures and a difference picture for each view |
| `kit/stills.cjs` | `still.png`, `sheet.png`, `moments.png` |
| `kit/gif.cjs` | The loop as a GIF, palette exact |
| `kit/loop.cjs` | `loopable(world, seconds)`: every kind's speed made whole cycles a loop |
| `player/index.html` | The page: still picture, canvas, ready flag, import map |
| `player/main.js` | Starting the GPU, cruise, drag, flick, keys, touch, reduced motion, device loss |
| `player/painter.js` | The WebGPU painter (vgpu): three passes a frame |
| `player/scene.js`, `camera.js`, `motion.js`, `order.js` | Reading the file, the camera and grid, motion on the processor, the far-to-near order |
| `player/serve.mjs` | Serves the player with one scene on 127.0.0.1, and prints how to stop it |
| `player/check.mjs` | The browser check: serves, opens headless Chromium with WebGPU, checks it draws and plays, screenshots, stops the server; needs Playwright installed into the player folder |
| `references/` | The topic notes below |

Each file's opening comment says what it owns.

## References

| Note | Read it for |
| --- | --- |
| references/ink-studio.md | Writing a scene: what to read first, the skeleton and lifecycle, light, every material field, groups, hand-placed splats, rigs and cloth, the finish, previewing at stage size; maps of ink-studio's README, every guide and every example, grouped by what you are making and each marked with whether it survives the bake |
| references/recipes.md | The art grid and readable sizes, budgets and counting what costs splats, a far backdrop and its limits, lettering, neon, a glass case, an interior lit by one sun and a fill, what to build instead of what the file cannot carry, water, small figures, dusk light, a cape |
| references/format.md | The baked file byte by byte, every kind of motion's maths, how to draw a picture from it, costs, accuracy, what the baker refuses, notes for writing a painter |
| references/painter.md | How `player/painter.js` draws, the toolkit's rules a painter must follow, mistakes made and caught, performance |
| references/hosting.md | vgpu (version, offline docs, the 0.6 rules), putting the player on a website: its parts, the still, serving gzipped and loading, orbit, touch and less motion |
| references/proof.md | Proving a file and reading its lone pixels and runs, proving a painter against the toolkit pixel for pixel, browser checks, `player/check.mjs` and getting Playwright for it |
| references/gif.md | The GIF from the command line, and a GIF button in a page |
| references/splats.md | What "true" splats means here, what stays offline, baking again, sources |
| references/random-scenes.md | Optional: a different scene for each seed |
