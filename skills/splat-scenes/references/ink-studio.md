# ink-studio: what to read, and what travels into a baked file

ink-studio is the toolkit the scenes are sculpted with: signed-distance solids baked into pixel-art Gaussian splats, plus animation,
particles, physics, procedural tools and two renderers (a CPU one for Node and the command line, a WebGL 2 one for browsers). It is
MIT licensed (README, License) and needs Node 18 or later with no runtime dependencies. The kit calls it from the folder `INK_STUDIO`
names and never copies it. Everything below was checked against commit `433ab1d`; its README and `docs/` are the authority, and this
page says where to look and which parts survive the bake.

Contents: 1. The first scene. 2. Working knowledge (scene shape, light, materials, hand-placed splats, moving things, the finish,
previewing). 3. Map of the README. 4. Map of `docs/`. 5. Map of `examples/`.

## 1. The first scene

ink-studio's README section "First sculpted scene" is `examples/sculpt.js`: a ground disc, a stone box with a ball carved out of it and
a green ball on top, seven colours. It is this skill's pipeline check, because it is small, quick and needs nothing else. It is not a
model of what a scene should look like: a real scene has many more parts, its own palette of ramps, light set on purpose, and things
that move.

    env INK_STUDIO=<ink-studio folder> node <ink-studio folder>/cli/ink-studio.js render <ink-studio folder>/examples/sculpt.js --out /tmp/sculpt.png

## 2. Working knowledge

### 2.1 A scene file

A scene file is a CommonJS module that takes the toolkit (what `load()` returns) and returns `{ id, name, seed, build(seed) }`;
`build` returns the finished world (README, First sculpted scene). The kit's commands build it exactly so.

```js
module.exports = ({ makeBuilder, makeSculpt, KIT: K, flame, motes }) => ({
  id: 'my-scene',
  name: 'My scene',
  seed: 1,
  build(seed) {
    const B = makeBuilder(seed, PALETTE);    // PALETTE: an array of 0xRRGGBB, index 0 the empty background
    const S = K.sculpt(makeSculpt(B));      // the extended sculptor
    // light, a rig and tags before the solids they must catch (2.2, 2.5)
    // solids, then S.bake() (2.3)
    // hand-placed splats, flames, motes, a cloth (2.4, 2.5)
    const W = B.finish({ cam: { target: [0, 1, 0], dist: 12, pitch: 0.2, yaw: 0.45 }, detail: 14, radius: 5, dither: 0.25 });
    // a stage and its systems (2.5)
    return W;
  }
});
```

The lifecycle, in order (README, Scene lifecycle and splat data): builder and sculptor with a seed and palette; hooks such as a rig or
deformation tags **before** baking the solids they must capture; solids and `S.bake()`; pools, cloth and other splat-emitting systems
**before** `B.finish()` fixes the data; the finish with camera and look; then the stage. Bake still scenery before moving things when
the scenery must not hold their shadows. `S.bake()` may be called more than once: each call bakes the solids added since the last.

`load()` writes `dist/standalone.js` inside the ink-studio folder on first use or after a source change, so that folder must be
writable (SKILL.md, Setup).

A world is `data` (a `Float32Array`, 16 floats a splat: `[x, y, z, density] [c00, c01, c02, packedRGB] [c11, c12, c22, kind]
[phase, speed, range, extra]`), `count`, `pal`, `seed`, the finish's fields, and `anim` once a stage is attached. Positions are
`[x, y, z]` with Y up, in world units; angles are radians except clip pose rotations, which are degrees (README, Animation and
puppets).

### 2.2 Light is baked into colours

Each solid's splats are coloured when `S.bake()` runs, from its material's ramp by the surface's light: a sun with a cast shadow, sky
and ambient light, ambient occlusion and nearby lamps (`src/sculpt.js`, opening comment). Set these on the sculptor before baking:

| Setting | Default | Meaning |
| --- | --- | --- |
| `S.sun` | `norm([-0.5, 0.8, 0.45])` | Direction toward the sun (use `B.norm`) |
| `S.sunK` | 0.72 | Sun strength |
| `S.amb`, `S.sky` | 0.14, 0.26 | Ambient light, and light from above (scaled by how much a surface faces up) |
| `S.res` | 0.09 | Default sampling spacing for solids without their own `res` |
| `S.lights` | `[]` | Lamps: push `{ p: [x, y, z], r: reach, s: strength, sh: true }` (`sh` casts shadows) |

A lamp only brightens colours along its material's ramp, so a warm glow needs warm colours in the ramps it falls on. The light is
fixed at bake: turning the camera does not move shadows, which suits a scene that orbits. `globalThis.INK_BOUNCE = true` at the top of
the scene file bakes indirect light too (the CLI's `--bounce`); it is carried, being colour.

### 2.3 Solids and materials

The core sculptor has `ball`, `box`, `lathe`, `torus`, `tube`, `rock`, `ground` and vegetation helpers; the extended one adds joins,
folds, warps, shells, extrusion, revolution, text and grid operations (README, Geometry and materials). `S.box` takes half-extents.
Options: `res` (sampling spacing: smaller means more splats and slower bakes), `tag` (ownership; names a rig part), `neg`
(subtract), `hold` (an operand for a join, not drawn itself), `ghost`, `ax` (an orientation frame; `S.AX` and `S.AZ` lay a long axis
along X or Z), and `S.grp(k)` for members that melt into each other over distance k. Join kinds: `union`, `cut`, `common`, `round`,
`chamfer`, `stairs`, `columns`, `pipe`, `engrave`, `groove`, `tongue`.

A material is a ramp of palette places, dark to light: `{ r: [1, 2, 3, 4] }`. `em: true` makes it emissive: it takes its ramp at a
fixed light `v` (1, the brightest, unless given) instead of being shaded, and skips fog. Patterns, callbacks and surface attributes can choose ramps or shift tones per point (README, Geometry and materials; `K.tex`).
`K.look.glass(ramp, { a })` makes glass, which the format carries (it bends what is behind it). Other looks (`wax`, `jelly`, `fur`)
are worth trying; the bake names anything it cannot carry.

Higher-level helpers that produce ordinary sculpted splats, and so bake: `K.curve` and `K.sweep` (paths, ribbons, planks), `K.grow`
(scatter, species, branching, vines, rocks, creepers), `K.form` (crystals, columns, stalactites, steps, fences, plants), `K.build`
(pillars, stairs, arches, pipes), `K.erode`, `K.fracture` (cells, settled), imported meshes (`K.mesh`, README, Importing meshes) and
depth maps (`KIT.depth`), and the procedural fields and placements of `docs/procedural.md` fed into the sculptor.

Splat count and art-pixel size go together: `detail` art pixels a world unit at the camera's distance sets the grid (14 at distance 12
gives 180 by 120 art pixels on a 3:2 stage), and a solid's `res` should be near an art pixel or finer, or its surface shows gaps.
`ink-studio stats <scene>` reports counts, extents and palette use.

### 2.4 Hand-placed splats

For grass, sparks, glints, petals, water flecks and anything smaller than a solid, push splats straight into the builder. `col` is a
palette colour as the builder holds it, `B.P[index]`; `a` is the density, 1 or more solid (3 is usual), under 1 a soft haze (0.2 to
0.6); `an` sets motion and flags (below).

| Call | Splat |
| --- | --- |
| `B.iso(x, y, z, s, col, a, an)` | A round blob of standard deviation s |
| `B.stick(x, y, z, axis, halfLength, width, col, a, an)` | A needle along `axis` |
| `B.disc(x, y, z, normal, radius, thickness, col, a, an)` | A flat disc facing `normal` |

The builder's own seeded randomness keeps a scene the same for the same seed: `B.R()` (0 to 1), `B.rr(a, b)`, `B.pick(list)`, noise
`B.n3` and `B.fbm`, and `B.norm`, `B.UP`. Never `Math.random`.

`an` fields: `k` the kind of motion, `ph` phase, `sp` speed, `rg` range, `ex` extra, `em` emissive (skips fog), `nd` no depth (never
hides what is behind it, draws no outline), `gl` glass. The kinds the format carries are 1 flicker, 2 fall, 3 rise, 4 blink, 5 orbit,
6 bob, 7 pulse and 11 sway; references/format.md, section 4, gives each one's maths and what speed, range and extra mean. `bk`,
`wind`, `as`, `born` and `wet` are not carried.

`flame(B, x, y, z, size, [outer, inner, core])` and `motes(B, count, [x0, x1, y0, y1, z0, z1], colours, size)` are `load()` exports:
a flickering flame with a soft glow (bob and pulse) and drifting bright specks (bob). Both bake.

### 2.5 Things that move

Three kinds of movement travel into the baked file. Everything else is refused at bake, naming the cause (references/format.md,
section 9).

1. **Kinds of motion** on single splats (2.4): worked by the player from the clock, so they cost 4 bytes a splat and nothing a frame.
   Vegetation helpers already sway (kind 11).
2. **Rigid parts** with `K.rig`. Make the rig before baking the solids it must catch; a solid's `tag` names its part, or wrap code in
   `rig.own(name, () => { ... })` to give a part everything built inside, hand-placed splats included. After the finish:

   ```js
   const st = K.stage(W);
   rig.bind(st);
   st.add({
     update(dt, t) {
       rig.set('wheel', K.M.rot([0, 0, 1], (2 * Math.PI * t) / 4), [0, 1, 0], [0, 1, 0]); // x' = A (x - o) + p
       rig.apply();
     }
   });
   ```

   `rig.child(name, parent, A, o)` hangs a part on another. `K.M` has `id`, `rot(axis, angle)`, `mul`, `app`, `tr`, `aim`. A part's
   motion must be a function of t that comes back in the loop (here one turn in 4 s: twice in an 8 s loop); the bake prints how far
   each part is from where it began a loop on.
3. **One cloth**, `K.cloth(B, { at, u, v, nu, nv, pins, wind, pattern, sdf })` before the finish and `K.stage(W).add(cloth)` after
   (README, Physics and persistent effects). Every frame of it is stored, 9 bytes a dab a frame. Gusty wind does not come round in a
   loop; the bake prints the seam.

Not carried: bones and puppets (`K.puppet`, `K.bones`, `K.creature`, `K.character`, clips that bend splats), particles and pools
(`K.pool`, `K.particles`), frame-local effects (`K.frameSplats`), physics (`K.breaker`, `K.jelly`, `K.sand`, `K.mpm`, `K.sandbox`,
`K.voxels`, a second cloth, hair, ropes), flocks, morphs, growth you can watch. A puppet's motion can sometimes be rebuilt as rigid
parts (a head, an arm, a body each its own tag) when the splats need not bend.

Then make every kind's speed whole cycles a loop: `return loopable(W, 8);` with `kit/loop.cjs` (SKILL.md, The loop).

### 2.6 The finish

`B.finish({...})` takes the camera and the look; the toolkit's defaults apply where a field is left out (`src/builder.js`, `finish`).

| Field | Default | Meaning |
| --- | --- | --- |
| `cam` | none | `{ target: [x, y, z], dist, pitch, yaw }`, radians; the player opens here and turns about `target` |
| `detail` | none | Art pixels a world unit at the camera's distance |
| `radius` | 14 | The scene's radius R: depth runs from dist − R to dist + R, and fog, shade and outline are measured against it. Set it to the scene's real size |
| `dither` | 1 | Ordered dither strength (0.25 is gentle) |
| `fog` | `{ c: 0, start: 1, max: 0 }` | Fog colour place, where it starts (0 to 1 of depth), full strength (off as given) |
| `outline` | `{ c: 0, edge: 0 }` | Outline colour place and the depth step that draws it, world units (off as given) |
| `ao` | none | Contact shade `{ k, range }` (k 0.5 and range 0.6 when given empty) |
| `refract` | 6 | How far glass bends what is behind it |

These are all the finish fields the format carries. `look` (per-pixel materials, tone and stipple, colour stacks, ink, effects),
`skyEnvironment`, `aerialPerspective`, `liveSun`, `volumeLighting`, `atmosphere`, `water` and the rest draw only in ink-studio's own
renderers; the bake names each one it finds.

### 2.7 Previewing while sculpting

ink-studio's command line draws a scene file with the same CPU renderer the kit uses, so a plain render is what the player will show:

    env INK_STUDIO=<ink-studio folder> node <ink-studio folder>/cli/ink-studio.js render scene.js --t 0 --out /tmp/look.png
    env INK_STUDIO=<ink-studio folder> node <ink-studio folder>/cli/ink-studio.js turn scene.js --n 8 --out /tmp/turn.png
    env INK_STUDIO=<ink-studio folder> node <ink-studio folder>/cli/ink-studio.js stats scene.js

Give `--out` an absolute path: without it the pictures go into `studio/out/` under the working folder. Leave out `--colored`, `--fine`,
`--clean`, `--tone`, `--follow` and the other look options when previewing a scene for the player: they change the picture in ways the
baked file does not carry. `crisp`, `lint`, `values` and `ramps` measure pixel-art faults (isolated pixels, jaggies, banding, ramps
that do not read) and are worth running on the plain render. The kit's own `stills.cjs` draws the baked file the same way.

## 3. Map of the README

| Section | What it holds | Travels into a baked file |
| --- | --- | --- |
| Install and run | Node 18+, no dependencies, `npm install github:siliconjungle/shapeshift-labs-ink-studio`, the `ink-studio` command | Setup (SKILL.md) |
| First sculpted scene | `examples/sculpt.js`, `render`, `turn`, `stats`; Y up, half-extents, `res` | Yes: the pipeline check |
| Using the library in Node | `load()` and its exports; `load()` writes `dist/standalone.js` | How the kit loads it (`kit/toolkit.cjs`) |
| Scene lifecycle and splat data | The order of building, the 16-float row, stages and fixed steps | Yes: 2.1 here; the bake walks the stage the same way |
| Geometry and materials | Sculptor operations, joins, options, material ramps, looks | Yes, except looks the bake names |
| Scenes as JSON | Role-based materials, styles, parts and motion; `K.diorama.check`, `build`, `scene(spec)` | Yes, wrapped as a scene file: `module.exports = kit => kit.KIT.diorama.scene(spec)`. Its parts and their `spin` and `bob` become rigid parts. A `tap` makes a particle pool, which is refused: leave it out. Pick each `speed` (2π k / loop) and `period` (loop / k) to come round in the loop; `examples/scene.json`'s 0.8 and 3 do not, and the bake prints a part seam of 0.17 |
| Animation and puppets | `K.rig`, `K.creature`, `K.puppet`, clips, `K.acts`, deformation, the motion tools | `K.rig` only; puppets and bones are refused |
| Particles and interaction | Pools, `K.particles`, flows, `poke`; frame-local splat effects | No (refused) |
| Physics and persistent effects | Breakers, jelly, sand, MPM, sandbox, XPBD cloth and hair, voxels | One `K.cloth` only |
| Importing meshes | OBJ, glTF, GLB to distance-field solids | Yes: they become sculpted solids |
| Exporting GLB models | Meshes, UVs, skins and clips out | No: a separate output |
| Importing depth maps | Depth PNG to splats and solids | Yes, as splats or solids |
| Procedural worlds | Fields, sampling, terrain, routes, buildings, layouts, growth, fracture, pixel materials, LOD, motion | The geometry and placement tools, yes; the live and pixel-material ones, no |
| Retained authoring | JSON documents with stable ids, undo, groups, chunks | Indirectly: whatever it realises as solids |
| Headless world simulation | `docs/headless-worlds.md` | No |
| Rendering and command reference | Every command and render option | Previews (2.7); only the plain render matches the player |
| View-dependent surface materials | `KIT.surface` finishes evaluated per view | No |
| Projected and procedural effects | Animated rasters and patterns on surfaces | No |
| Reflections, ripples and atmosphere | Planar captures, ripples, fog volumes | No (the finish's simple `fog` is carried) |
| Embedding and custom scene collections | `bundle()`, `demos()`, `ink-studio.config.js` | No: for ink-studio's own browser use |
| Browser renderer | The WebGL 2 `createRenderer` | No: the player is its own WebGPU painter |
| Screen transitions | 49 WebGL transition presets | No |
| Module reference | What each `src/` file holds | Where to read an API's opening comment |
| Validation and development | `npm test`, `npm run lint`, `snap`, `check` | No |
| License | MIT | The kit calls ink-studio, never copies it |

## 4. Map of `docs/`

Read a guide when a scene needs what it covers, and check the last column first: a feature that does not travel is still useful for
pictures made with ink-studio itself, but the player will not draw it.

| Guide | What it covers | Travels |
| --- | --- | --- |
| `aerial-perspective.md` | Distant colour and extinction from the sky | No |
| `animation-timeline.md` | One shot clock over a puppet's clips | No (puppets) |
| `art-passes.md` | Diagnostic passes, selective ink, stable pixels, local ordering, sprite atlas | No; `passes` is useful for checking depth and coverage |
| `authored-contacts.md` | Pinned hands and feet, prop handoffs | No (puppets) |
| `browser-renderer.md` | ink-studio's WebGL 2 renderer | No |
| `clip-sequence.md` | Trimming and retiming clips | No (puppets) |
| `cloth-review.md` | Painting cloth pins, settled takes | The cloth itself, yes; a review take not tried |
| `cloud-shadows.md` | Moving cloud coverage and shadows | No |
| `depth-maps.md` | Depth images to splats, fields and meshes | Yes, as splats or solids |
| `fog-lighting.md` | Spot and point lights in fog volumes | No |
| `headless-authoring.md` | Typed graphs, attributes, layered artwork | Whatever it realises as solids |
| `headless-worlds.md` | Declarative simulated worlds, queries, replay | No |
| `live-sun.md` | A sun relit at render time | No (bake light with `S.sun`) |
| `motion-fx.md` | Stretch, smear and trails on a puppet | No |
| `motion-layers.md` | Part-masked override clips | No (puppets) |
| `motion-retarget.md` | Clips moved to another puppet | No (puppets) |
| `motion-review.md` | Loop pops, spacing, arcs, foot drift | No; its loop checks are a good habit for rigid parts too |
| `pixel-look.md` | Tone, stipple, palette remaps, LUTs, colour stacks | No |
| `portals.md` | Travel between named places | No |
| `pose-blocking.md` | Pose shelf and blocking | No (puppets) |
| `procedural.md` | Every procedural primitive | Geometry and placement, yes |
| `projected-effects.md` | Animated surface layers and emitters | No |
| `rain-impacts.md` | Rain hitting planes | No |
| `retained-weather.md` | Wetness, snow and frost that stay | No |
| `scene-optics.md` | Reflections, ripples, atmosphere | No |
| `shared-sky-reflections.md` | One sky for backdrop and reflections | No |
| `surface-materials.md` | View-dependent finishes and presets | No |
| `transitions.md` | Full-screen WebGL transitions | No |
| `weather-binding.md` | Weather profiles across systems | No |
| `weather-fronts.md` | Fronts moving over the world | No |
| `world-precipitation.md` | Rain and snow drawn in world space | No |
| `world-scaling.md` | Query and mechanics indexing | No |

## 5. Map of `examples/`

| Example | Bakes | Why look at it |
| --- | --- | --- |
| `sculpt.js` | Yes (4,027 splats) | The pipeline check |
| `cloth.js` | Yes (1,413 splats, 396 cloth dabs) | The one cloth the format carries |
| `puppet.js` | No: bones | Tags and deformation |
| `particles.js`, `splat-effects.js` | No: particles and frame-local splats | How pools and frame splats work |
| `material-masks.js`, `surface-gallery.js`, `color-curves.js`, `bounce-light.js` | No: per-pixel looks | Materials worth knowing, drawn only by ink-studio |
| `aerial-perspective.js` | No: sky and aerial perspective | |
| `weighted-roof.js`, `terrain-route.js`, `texture-synthesis.js`, `transport-morph.js` | Not tried | The README's procedural examples |

Each example's first lines say what it shows; `ink-studio catalog <words>` searches every feature and points at its source.
