---
name: splat-scenes
description: Make small looping pixel-art scenes out of Gaussian splats placed by code, and play them in the browser with WebGPU. Use when asked to build, change or add to a splat scene, write a new piece for one (a ground, a thing, a character, weather, sky, palette, light, camera or finish), bake a scene file, check how one looks, play one on a page, or deal random scenes from a library of pieces. Everything needed is in this folder plus an ink-studio download.
---

# Splat scenes

A scene is a few hundred thousand real 3D Gaussian splats. They are placed by code, not trained from photographs. ink-studio
sculpts, lights and draws them offline; the kit bakes them into one file of a few megabytes; the player draws that file in the
browser as pixel art: 48 colours, outlines, an ordered dither, and an 8-second loop that every motion comes round in. People turn it
by dragging, touching or pressing the arrow keys.

A scene is made of pieces. Each piece is one short file of a known kind, and a scene file lists the pieces.

| Path | What it is |
| --- | --- |
| `kit/run.cjs` | the one runner: setup, stand, build, check, deal |
| `kit/example.json` | the example scene: a grassy isle in the air with a tree, a lamp, a pool, a walker, rain and sky |
| `kit/pieces/` | the example's pieces, one folder per kind |
| `player/` | the browser player and its local server |
| `references/contract.md` | what each kind of piece exports and the rules it is held to |
| `references/format.md` | the baked file, for anyone reading or drawing it |

Run every command below from this folder, except the download in Setup.

## Setup

1. Install Node 18 or newer.
2. From any folder outside this one, download ink-studio (MIT, github.com/siliconjungle/shapeshift-labs-ink-studio) at commit
   433ab1d, the version this kit was proven with:

   ```sh
   mkdir ink-studio
   curl -fsSL https://github.com/siliconjungle/shapeshift-labs-ink-studio/archive/433ab1d.tar.gz | tar -xz --strip-components=1 -C ink-studio
   ```

3. Point the kit at it, with the folder's absolute path, in every shell you use:

   ```sh
   export INK_STUDIO=/absolute/path/to/ink-studio
   ```

4. Check ink-studio loads and install the player's two packages (vgpu and @vgpu/wgsl 0.6.0):

   ```sh
   node kit/run.cjs setup
   ```

## Build the example

```sh
node kit/run.cjs build kit/example.json out/example
```

It prints each step's time, the splat count and the file size, then the look report, and exits with an error when there is a
fault. It writes to `out/example/`:

- `stills/`: seven views at the start of the loop (`hero.png` is the opening view; then `000`, `090`, `180`, `270`, `above`,
  `below`) and `sheet.png` with six of them.
- `moments.png`: the opening view at eight moments through the loop.
- `scene.bin`: the baked scene.
- `look.md`: the look measures, what each piece costs against its share, and every fault.

Open `stills/sheet.png` and `moments.png` and look at them. The numbers catch a piece that is missing, hidden or too big; only your
eyes catch one that looks wrong.

## Play it

```sh
node player/serve.mjs out/example/scene.bin out/example/stills/hero.png
```

Open http://127.0.0.1:4173/ in a browser with WebGPU, such as a recent Chrome. A third argument changes the port. The scene turns
slowly and plays its loop. Drag to turn and tilt it, or use the arrow keys. With reduced motion asked for, it holds still at the
opening view until dragged. Without WebGPU the page shows the still picture.

To put a scene on a site, serve `player/` with its `node_modules/` from any static file server, with the scene and a still beside
`index.html` as `scene.bin` and `still.png`. There is no build step.

## Make a new piece

1. Read `references/contract.md`.
2. Copy the example piece nearest to what you want into a pieces folder and rename it. Keep the comment at its top to one to three
   sentences saying what the piece is.
3. Write it. Take every colour from `pal`, stay inside the place you are given, and make every motion come round in the loop.
4. Try it on a stand: the example's palette, light, camera, finish and ground with your piece in place, or in place of the example's
   own piece of the same kind.

   ```sh
   node kit/run.cjs stand kit/pieces/thing/lamp.cjs out/stand-lamp
   ```

   It writes `out/stand-lamp/sheet.png` (your piece from several sides and moments), prints what it costs against its share and how
   many art pixels it adds, and lists every fault that names it. Add a scene file as a third argument to stand it in another scene.
5. Tune its spacing (`res`) and counts until it uses 70 to 100% of its share and no fault names it. Look at the sheet each time.
6. Add it to a scene file and build that scene.

To check a built scene again without drawing the stills, run `node kit/run.cjs check kit/example.json out/example`. It composes
the scene, runs the look checks, reads `out/example/scene.bin` back and rewrites `look.md`.

## Make a new scene

Write a scene file like `kit/example.json`: a seed and the piece paths, relative to the scene file. It needs exactly one palette,
light, camera, finish and ground, at most one sky and one character, any weather, and things up to the ground's places of each size.
Things take the places of their size in list order. Then build it as above.

To change the look of every piece at once, change the palette, light, camera or finish pieces. The camera frames the ground, the
things and the character by itself; `dist`, `pitch` and `yaw` adjust it.

## Random scenes (optional)

Skip this unless you want scenes dealt at random. Put interchangeable pieces in one folder (any layout; every `.cjs` file in it is a
piece). Deal a scene from it with a whole-number seed:

```sh
node kit/run.cjs deal kit/pieces 1 out/dealt-1.json
node kit/run.cjs build out/dealt-1.json out/dealt-1
```

A deal picks one palette, light, camera, finish and ground; a sky and a character when the folder has any; no weather or one; and
for each place on the dealt ground a thing of that size while any are left, each thing at most once. The same seed and folder deal
the same scene. Every piece in the folder must work with every other, so give a library of pieces one shared scale: the place sizes
and shares in the contract are that scale. The example pieces alone deal nearly the same scene each time; add alternatives to see
the seeds differ.

## Rules the kit holds you to

- Shares: each kind of piece has a ceiling of splats, styles, motions and moving parts, and should use at least 70% of its splats.
- Places: things stand on the ground's places, the character on its stage; a piece may not reach or stand past its place's size.
- Loop: every motion makes a whole number of cycles in 8 seconds, and every moving part is back where it began after 8 seconds.
- Palette: 48 colours in 13 roles, each ramp dark to light, every splat one of them.
- Errors that stop a build, and faults in `look.md`, start with the piece at fault.

## Known limits

- The offline drawing is slow: the example takes about two minutes to build, most of it drawing the stills, the moments and the look
  checks. A scene of more splats, or a bigger picture, takes longer. Use `stand` while working on a piece; build the whole scene
  when the piece is done.
- Pieces do not see each other. A character that walks off its stage passes through whatever stands in its way, so keep a
  character's path on its stage, or have the piece route around the places it knows of.
- The player draws one scene with one camera. It has no zoom and no sound, and the scene's loop is fixed at bake time.
- The baked file holds at most 256 styles, 256 motions and 256 moving parts, and the kit stops the build past them.
