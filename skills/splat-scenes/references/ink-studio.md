# ink-studio: what to read, and what travels into a baked file

ink-studio is the toolkit the scenes are sculpted with: signed-distance solids baked into pixel-art Gaussian splats, plus animation,
particles, physics, procedural tools, simulated worlds and two renderers (a CPU one for Node and the command line, a WebGL 2 one for
browsers). It is MIT licensed (README, License) and needs Node 18 or later with no runtime dependencies. The kit calls it from the
folder `INK_STUDIO` names and never copies it.

The working knowledge (section 2) was last checked against commit `983d91f` (22 Nov 2026), the newest then: the 28 examples that
bake give the same splat counts as at `cf35ff8` (20 Nov), five of six test bakes came out byte for byte the same (the sixth moved
the shape of 4 splats), and the rig, cloth, sculptor and renderer rules used here are unchanged. The maps (sections 3 and 4) cover
what `cf35ff8` had, all still there: 28 README sections, 185 guides in `docs/` and 385 files in `examples/`. `983d91f` added 3
README sections (section 3), 89 guides and 264 example files, not mapped here. Its README and guides are the authority; this page
says what to read first, what the kit's file carries, and where each guide and example stands.

Contents: 1. Read these first. 2. Working knowledge (scene file, light, solids and materials, hand-placed splats, things that move,
the finish, previewing). 3. Map of the README. 4. Guides and examples by what you are making.

## 1. Read these first

In this order; together they are enough to write a scene that bakes.

1. README, **First sculpted scene**, with `examples/sculpt.js`: the shape of a scene file and the first commands.
2. README, **Scene lifecycle and splat data**: the order a scene is built in, and the 16 numbers of a splat.
3. README, **Geometry and materials**: the sculptor's solids, joins and options.
4. `src/sculpt.js`: its opening comment (how light is baked), the comment above `light()` (surface attributes and ramp rules), then
   `light()` itself, which reads every material field (2.3 here).
5. README, **Animation and puppets**, the `K.rig` part: the only skeleton that travels (2.5).
6. `docs/procedural.md`: terrain, rivers, routes, streets, buildings, rooms, growth, fracture and placement, all made at build. 24 of
   its examples bake as they are.
7. `docs/typography.md` and README, **Editable 3D drawing**: lettering and drawn marks (references/recipes.md, 4).
8. `docs/randomness.md`: named seeded streams, so adding one flower does not reshuffle every tree.

Then references/recipes.md for sizes, budgets, a far backdrop, lettering, neon, glass, interiors and what to build in place of what
the file cannot carry.

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
    const rig = K.rig(B, S);                // only if parts move (2.5)
    // light, and tags before the solids they must catch (2.2, 2.5)
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

The kit takes a scene file ending in `.js` or `.cjs`; ink-studio's command line takes `.js` only (a `.cjs` gives "no diorama
called ..."). `load()` writes `dist/standalone.js` inside the ink-studio folder on first use or after a source change, so that folder
must be writable (SKILL.md, Setup).

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

A lamp only moves colours along a ramp, or onto the material's lamp ramp `g` where it outweighs the other light (2.3), so a warm glow
needs warm colours there; in daylight a lamp barely shows, at dusk or night it does. The light is fixed at bake: turning the camera
does not move shadows, which suits a scene that orbits, and a rig part's colours turn with it. `globalThis.INK_BOUNCE = true` at the
top of the scene file bakes indirect light too (the command line's `--bounce`); it is carried, being colour. An interior lit by one
sun and a fill: references/recipes.md, 7.

### 2.3 Solids and materials

The core sculptor has `ball`, `box`, `lathe`, `torus`, `tube`, `rock`, `ground` and vegetation helpers; the extended one adds joins,
folds, warps, shells, extrusion, revolution, strokes and fills, text and grid operations (README, Geometry and materials; Editable 3D
drawing). `S.box` takes half-extents. Join kinds: `union`, `cut`, `common`, `round`, `chamfer`, `stairs`, `columns`, `pipe`,
`engrave`, `groove`, `tongue`. Each helper's inputs are in the comment just above it in `src/sculpt.js` (search for `S.tree =`):
read that before using one. `S.tree(x, y, z, { h, r, lean, nb, spread, cr, bark, leaf, leaves, roots, res })` and
`S.crown(clusters, mat, count, { scale })` (clusters `{ p, r: [rx, ry, rz] }`) size their leaves for a full tree, up to half a unit
at `scale` 1 (read from source), so a small tree or hedge comes out in large blobs: pass `scale` below 1 (a mansion-grounds scene's
hedges: 0.55).

**Options** (the last argument of a solid):

| Option | Effect |
| --- | --- |
| `res` | Sampling spacing: smaller means more splats and slower bakes. Near an art pixel or finer, or the surface shows gaps; finer still for lettering |
| `tag` | Ownership; names a rig part when a rig exists (2.5) |
| `objectId` | A label for counting and inspection (references/recipes.md, 2); it makes no part and changes no splat |
| `whole` | The solid keeps all of its own surface, found from its own distance alone, even where it touches another: for a part that will move, so no gap shows where it touched something (read from `src/sculpt.js`) |
| `neg`, `hold` | Subtract it; or keep it as an operand for a join, not drawn itself |
| `ghost` | Drawn on its own: no part in joins or shadows (glass, things in the sky, glowing shapes) |
| `ax` | An orientation frame; `S.AX` and `S.AZ` lay a long axis along X or Z |

**Groups.** `S.grp(k)` makes a group whose members melt into each other over distance k. Pass the group as the options, or spread it
into them with others; nest it and it is ignored. Checked on one pair of solids:

| How the group is given | Result |
| --- | --- |
| `S.ball(c, r, mat, grp)` or `S.ball(c, r, mat, { ...grp, res })` | Melted (1,405 splats, against 1,320 apart) |
| `{ grp, res }` or `{ g: grp }` | Silently ignored: drawn, not melted (1,320) |
| In the material's place, or spread into a material without `r` | Nothing drawn |
| `{ k: grp }` | The bake stops ("Invalid array length") |

**Materials.** A ramp lists **palette places, not colours**: `{ r: [1, 2, 3, 4] }` names entries 1 to 4 of the palette, dark to light,
and the surface's light t (0 to 1) picks one. (Hand-placed splats take the builder's colour for a place, `B.P[i]`, 2.4.) Every field
`light()` reads, checked by baking a test block and counting the palette places of its splats, top and sides:

| Field | What it does | Checked |
| --- | --- | --- |
| `r` | The ramp | Ramp 1 to 4: top mostly 3, sides mostly 2 |
| `b` | Added to t before the ramp is read | +0.3: top to 3 and 4; −0.3: sides all 1 |
| `mod(x, y, z, ny, A)` | Returns a tone shift added to t, per point (`A`: the surface attributes) | −0.3 gave the same as `b` −0.3 |
| `rf(x, y, z, A)` | Returns a ramp for this point; a falsy return keeps `r` | Half the block took another ramp |
| `top: { min, r, ... }` | Another material where the surface faces up: where ny > min + 0.35 (noise − 0.5). It is chosen **after** the parent's `b` and `mod` have shifted t; its own `b` and `mod` are ignored; its `r`, `s`, `g`, `tex`, `gloss`, `blade`, `fl`, `motionAt`, `a` and rules are used | Top all at the top ramp's place 7; with the parent's −0.3, at 6; the top's own −0.3 changed nothing |
| `s` | A sunlit ramp, used where the sun's light on the surface is over 0.2 | Sunlit faces took it |
| `g` | A lamp ramp, used where the lamps' light is over 0.8 times the other light | None in daylight; near the lamp at night |
| `em`, `v` | Fixed light: the ramp at place v (1, the brightest, unless given), unshaded, no fog | All at place 4; with `v: 0.5`, all at 3 |
| `tex(x, y, z, ny, t, nx, nz, A)` | Returns a palette place used as it is, unshaded; −1 drops that splat; `undefined` keeps the shaded colour | Returning 10: all flat colour 10; −1: half the splats dropped |
| `gloss: { c, at, c2, at2 }` | Highlight colour c where the surface faces `S.view` most (beyond `at`, 0.95), c2 beyond `at2` (0.88); baked, so it stays put as the scene turns | 37 of 727 splats took c |
| `blade: { h, w }` | Grass blades of height h and width w on faces with ny > 0.45; they sway (kind 11) unless `still: true` | 1,976 of 2,460 splats swaying; with `still`, none; under a `top`, blades on top only |
| `fl` | A motion (2.4's `an`) for every splat of the solid | `{ k: 6, ... }`: every splat bobbing |
| `motionAt(x, y, z)` | A motion per point, or none | Half the block swaying |
| `a` | Density (3 unless given; under 1 a haze) | |
| `by`, `wear`, `grime`, `root` | Rules that move t or swap the ramp by surface attributes (curvature, hollowness, how far along a limb); the comment above `light()` gives each | Read from source, not run |
| `leaf`, `fur`, `sss`, `form`, `fat` | Leaves, fur strands, light through thin parts, a shading normal of your own, bigger dabs | Read from source, not run |

Not carried, because they work per pixel or over time: `pixelStyle`, `surface`, `line`, `fine` and `optical` (looks drawn by
ink-studio's renderers), `born` and `wet` (the bake refuses their flags). `983d91f` also reads `brush`, `stipple`, `footprint`,
`engraving` and `screenPrint`; none was checked here, so bake one before relying on it.

`K.look.glass(ramp, { a })` is `{ r, a, glass: true }` (a 0.1 unless given); with `{ ghost: true }` on the solid it makes glass the
format carries (references/recipes.md, 6). `K.look.wax`, `jelly` and `fur` exist too; the bake names anything it cannot carry.

Higher-level helpers that produce ordinary sculpted splats, and so bake: `K.curve` and `K.sweep` (paths, ribbons, planks), `K.grow`
(scatter, species, branching, vines, rocks, creepers), `K.form` (crystals, columns, stalactites, steps, fences, plants), `K.build`
(pillars, stairs, arches, pipes), `K.erode`, `K.fracture` (cells, settled), imported meshes (`K.mesh`, README, Importing meshes),
`S.implicitForm` for any field (`docs/fractal-forms.md`), `S.stroke` and `S.fill`, and the procedural fields and placements of
`docs/procedural.md` fed into the sculptor. Depth maps (`KIT.depth`, README, Importing depth maps) can too, but the depth-map
example's splats take colours off the palette, which the bake refuses: map colours to palette places first.

Splat count and art-pixel size go together: references/recipes.md, 1 and 2. `ink-studio stats <scene>` reports counts, extents and
palette use.

### 2.4 Hand-placed splats

For grass, sparks, glints, petals, water flecks, eyes and anything smaller than a solid, push splats straight into the builder.
`col` is a palette colour as the builder holds it, `B.P[index]`; `a` is the density, 1 or more solid (3 is usual), under 1 a soft
haze (0.2 to 0.6); `an` sets motion and flags (below).

| Call | Splat |
| --- | --- |
| `B.iso(x, y, z, s, col, a, an)` | A round blob of standard deviation s |
| `B.stick(x, y, z, axis, halfLength, width, col, a, an)` | A needle along `axis` |
| `B.disc(x, y, z, normal, radius, thickness, col, a, an)` | A flat disc facing `normal` |

All sizes are standard deviations: a solid splat (density 3) shows its crisp edge about 1.9 sizes out, so it is about 3.8 sizes
across (references/recipes.md, 1). `B.describeSplats(from, to, { object })` labels a run of them for counting.

The builder's own seeded randomness keeps a scene the same for the same seed: `B.R()` (0 to 1), `B.rr(a, b)`, `B.pick(list)`, noise
`B.n3` and `B.fbm`, and `B.norm`, `B.UP`. Never `Math.random`. `K.random` gives named streams (`docs/randomness.md`).

`an` fields: `k` the kind of motion, `ph` phase, `sp` speed, `rg` range, `ex` extra, `em` fixed light (skips fog), `nd` no depth
(hides nothing behind it, draws no outline), `gl` glass. The kinds the format carries are 1 flicker, 2 fall, 3 rise, 4 blink, 5
orbit, 6 bob, 7 pulse and 11 sway; references/format.md, section 4, gives each one's maths. `bk`, `wind` (the wind flag), `as`,
`born` and `wet` are not carried. Densities and ranges count against the file's 256 styles and 256 motions: pick them from a few
values (references/recipes.md, 2).

`flame(B, x, y, z, size, [outer, inner, core])` and `motes(B, count, [x0, x1, y0, y1, z0, z1], colours, size)` are `load()` exports:
a flickering flame with a soft glow (bob and pulse) and drifting bright specks (bob). Both bake, but `motes` gives every speck its
own random range, so each is one of the file's 256 motions: 300 specks stopped the bake. For more, place your own bobbing specks
with ranges from a few values (references/recipes.md, 2).

### 2.5 Things that move

Three kinds of movement travel into the baked file. Everything else is refused at bake, naming the cause (references/format.md,
section 9).

1. **Kinds of motion** on single splats (2.4): worked by the player from the clock, so they cost 4 bytes a splat and nothing a frame.
   Vegetation helpers and grass blades already sway (kind 11).
2. **Rigid parts** with `K.rig`. Make the rig with the builder and the sculptor, `const rig = K.rig(B, S);`, before baking the solids
   it must catch; a solid's `tag` names its part, or wrap code in `rig.own(name, () => { ... })` to give a part everything built
   inside, hand-placed splats included. After the finish:

   ```js
   const st = K.stage(W);
   rig.bind(st);
   st.add({
     update(dt, t) {
       rig.set('wheel', K.M.rot([0, 0, 1], (2 * Math.PI * t) / 8), [0, 1.2, 0], [0, 1.2, 0]); // x' = A (x - o) + p
       rig.child('arm', 'wheel', K.M.rot([0, 0, 1], 0.4 * Math.sin((2 * Math.PI * t) / 4)), [0.6, 1.2, 0]);
       rig.apply();
     }
   });
   ```

   `rig.child(name, parent, A, o)` hangs a part on another (checked: a wheel turning about a level axis carrying a swinging arm came
   round exactly and proved at 0.005%). `K.M` has `id`, `rot(axis, angle)`, `mul`, `app`, `tr`, `aim`. A part's motion must be a
   function of t that comes back in the loop; the bake prints how far each part is from where it began a loop on. Parts count
   against the file's 256 and multiply its styles (references/recipes.md, 2).
3. **One cloth**, `K.cloth(B, { at, u, v, nu, nv, pins, wind, pattern, sdf, sun })` before the finish and `K.stage(W).add(cloth)`
   after (README, Physics and persistent effects; every option is in the opening comment of `src/kit/ks-xpbd.js`). Every frame of it
   is stored, 9 bytes a dab a frame. A worked cape: references/recipes.md, 12.
   - **Shape**: `pattern(u, v)`, with u and v from 0 to 1 across and down, returns the ramp for the cloth there, or `null` to leave
     that part out: a cape narrow at the shoulder and ragged at the hem is a rectangle with `null` outside its outline.
   - **Shading**: each dab takes the colour at floor(l × ramp length) of its ramp, l = `amb` + `sunK` × how squarely it faces `sun`
     (0.3 and 0.75 unless given). Square to the sun, l passes 1 and the top colour shows: end the ramp at the brightest colour you
     want, or repeat its middle colours (a cape whose ramp ended in a pale tone came out skin-pale).
   - **Loop**: the wind must repeat every loop, built from sines of 2π k t / L with whole k; `K.xpbd.gust` never repeats. The bake
     prints how far the cloth is from where it began a loop on and does not stop on it. Measured on one cloak (20 by 12 points),
     with an art pixel about 0.035 units, at `damp` 0.6 (the default) and 4.5: at `density` 0.3 (the default is 0.25) it closed to
     0.006 and 0.003; at 0.6 it missed by 0.16 and 0.23; at 1.0 by 0.48 and 0.05. Keep the cloth light.
   - **Outlines**: its dabs draw no depth (`nd`), so the outline and contact shade of whatever is behind show through it, here and in
     ink-studio's own pictures. No setting changes that: hang it before a plain surface, or keep the outline off.

Not carried: bones and puppets (`K.puppet`, `K.bones`, `K.creature`, `K.character`, clips that bend splats), particles and pools
(`K.pool`, `K.particles`), splats redrawn each frame (`K.frameSplats`) or moved by a stage system of the scene's own, physics
(`K.breaker`, `K.jelly`, `K.sand`, `K.mpm`, `K.sandbox`, `K.voxels`, a second cloth, hair, ropes), flocks, morphs, growth you can
watch. references/recipes.md, 8, says what to build instead of each.

Then make every kind's speed whole cycles a loop: `return loopable(W, 8);` with `kit/loop.cjs` (SKILL.md, The loop).

### 2.6 The finish

`B.finish({...})` takes the camera and the look; the toolkit's defaults apply where a field is left out (`src/builder.js`, `finish`).

| Field | Default | Meaning |
| --- | --- | --- |
| `cam` | none | `{ target: [x, y, z], dist, pitch, yaw }`, radians; the player opens here and turns about `target`. Leave out `fov`: the baker writes the toolkit's 38 degrees, and a scene with its own fails the proof |
| `detail` | none | Sets the art grid with `dist` (references/recipes.md, 1) |
| `radius` | 14 | The scene's radius R: depth runs from dist − R to dist + R, and fog, shade and outline are measured against it. Set it to the scene's real size; splats beyond it make a clean backdrop (references/recipes.md, 3) |
| `dither` | 1 | Ordered dither strength (0.25 is gentle) |
| `fog` | `{ c: 0, start: 1, max: 0 }` | Fog colour place, where it starts (0 to 1 of depth), full strength (off as given) |
| `outline` | `{ c: 0, edge: 0 }` | Outline colour place and the depth step that draws it, world units (off as given) |
| `ao` | none | Contact shade `{ k, range }` (k 0.5 and range 0.6 when given empty) |
| `refract` | 6 | How far glass bends what is behind it |

These are all the finish fields the format carries. `look` (per-pixel materials, tone and stipple, colour stacks, ink, effects),
`skyEnvironment`, `aerialPerspective`, `liveSun`, `volumeLighting`, `atmosphere`, `water`, `spriteSurfaces` and the rest draw only in
ink-studio's own renderers; the bake names each one it finds.

### 2.7 Previewing while sculpting

ink-studio's command line draws a scene file with the same CPU renderer the kit uses, so a plain render at the stage's size is what
the player will show. Each command below starts as the first one does (`...` stands for that start), with absolute `--out` paths:

| Look | Command | Checked on a test scene of about 41,000 splats |
| --- | --- | --- |
| The opening view at stage size | `env INK_STUDIO=/abs/path/ink-studio node /abs/path/ink-studio/cli/ink-studio.js render scene.js --w 1440 --h 960 --out /abs/stage.png` | 1440 by 960 |
| The same, one pixel an art pixel | `... render scene.js --w 1440 --h 960 --px1 --out /abs/native.png` | 480 by 320; the kit's `still.png` of the baked file differs in under 0.1% of pixels |
| Another angle, another moment | `... render scene.js --w 1440 --h 960 --yaw 2.4 --pitch 0.5 --t 3 --out /abs/angle.png` | Radians and seconds |
| All round | `... turn scene.js --n 4 --w 720 --h 480 --out /abs/turn.png` | Four views in one strip, 2880 by 480 |
| Closer, about one spot | `... render scene.js --w 1440 --h 960 --zoom 3 --target x,y,z --out /abs/zoom.png` | A finer grid than the player's: it shows detail the player will not |
| Counts and palette use | `... stats scene.js` | |

- **Zoomed crops at the player's grid**: crop the `--px1` picture and enlarge it by a whole number with nearest-neighbour scaling, in
  any image tool (with Pillow: `Image.open(p).crop(box).resize((w * 8, h * 8), Image.NEAREST)`). That is how letter, face and glass
  sizes in references/recipes.md were judged.
- **Side by side with the kit**: the `--px1` picture and the kit's `still.png` (from `kit/stills.cjs`, after a bake) are the same
  size; put them next to each other, or count the pixels that differ. ink-studio's own `compare <scene> <ref.png>` draws the scene
  beside a reference, but at its own frame size, not the stage's, so it does not line up with the kit's still (checked).
- Leave out `--colored`, `--fine`, `--clean`, `--tone`, `--follow` and the other look options when previewing a scene for the player:
  they change the picture in ways the baked file does not carry. `crisp`, `lint`, `values` and `ramps` measure pixel-art faults
  (isolated pixels, jaggies, banding, ramps that do not read) and are worth running on the plain render; `passes --channels
  depth,normal --px1` shows depth and normals on the same grid.

## 3. Map of the README

| Section | What it holds | Travels into a baked file |
| --- | --- | --- |
| Contents | Links to every section | |
| Install and run | Node 18+, no dependencies, install from GitHub, the `ink-studio` command | Setup (SKILL.md) |
| First sculpted scene | `examples/sculpt.js`, `render`, `turn`, `stats`; Y up, half-extents, `res` | Yes: the pipeline check |
| Using the library in Node | `load()` and its exports; `load()` writes `dist/standalone.js` | How the kit loads it (`kit/toolkit.cjs`) |
| Scene lifecycle and splat data | The order of building, the 16-float row, stages and fixed steps | Yes: 2.1 here; the bake walks the stage the same way |
| Geometry and materials | Sculptor operations, joins, options, material ramps, looks | Yes, except looks the bake names (2.3) |
| Scenes as JSON | Role-based materials, styles, parts and motion; `K.diorama.check`, `build`, `scene(spec)` | Yes, wrapped as a scene file: `module.exports = kit => kit.KIT.diorama.scene(spec)`. Its parts' `spin` and `bob` become rigid parts. A `tap` makes a particle pool, which is refused: leave it out. Pick each `speed` (2π k / loop) and `period` (loop / k) to come round in the loop (checked on `examples/scene.json` so changed: 1,578 splats, parts exact, proved at 0.007%) |
| Animation and puppets | `K.rig`, `K.creature`, `K.puppet`, clips, `K.acts`, deformation, the motion tools | `K.rig` only; puppets and bones are refused |
| Particles and interaction | Pools, `K.particles`, flows, `poke`; frame-local splat effects | No |
| Physics and persistent effects | Breakers, jelly, sand, MPM, sandbox, XPBD cloth and hair, voxels | One `K.cloth` only |
| Optional textured surfaces | Pixel-textured patches (`TexturedSurface`, `SpriteSurface`) attached as `world.spriteSurfaces` | No: the bake names `spriteSurfaces` |
| Importing meshes | OBJ, glTF, GLB to distance-field solids | Yes: they become sculpted solids |
| Exporting GLB models | Meshes, UVs, skins and clips out | No: a separate output |
| Round-trip asset interchange | `ink-studio interchange` for glTF, GLB, layered rasters and sprite atlases | No: a separate output |
| Importing depth maps | Depth PNG to splats and solids | At build, once its colours are palette places (2.3) |
| Procedural worlds | Fields, sampling, terrain, routes, buildings, layouts, growth, fracture, pixel materials, LOD, motion | The geometry and placement tools, yes; the live and pixel-material ones, no |
| Editable 3D drawing | `S.stroke` and `S.fill`: drawn paths and filled outlines as solids | Yes (checked: 3,230 splats of strokes and fills baked) |
| Retained authoring | JSON documents with stable ids, undo, groups, chunks; `ink-studio authoring` | Whatever it realises as solids |
| Rendering and command reference | Every command and render option | Previews (2.7); only the plain render matches the player |
| View-dependent surface materials | `KIT.surface` finishes evaluated per view | No |
| Projected and procedural effects | Animated rasters and patterns on surfaces | No |
| Reflections, ripples and atmosphere | Planar captures, ripples, fog volumes | No (the finish's simple `fog` is carried; references/recipes.md, 8) |
| Embedding and custom scene collections | `bundle()`, `demos()`, `ink-studio.config.js` | No: for ink-studio's own browser use |
| Browser renderer | The WebGL 2 `createRenderer` | No: the player is its own WebGPU painter |
| WebGPU graphs and Gaussian splat import (`983d91f`) | GPU texture and geometry graphs; a viewer and `render --raw` for trained splat files (PLY, SPZ) | No: a separate output (not baked here) |
| Live show control (`983d91f`) | Live audio, MIDI, timecode, projection and lighting control | No: a world run |
| CLI patch tooling (`983d91f`) | `ink-studio patch`: typed graph ports and signals | No: a separate output |
| Screen transitions | Full-screen WebGL transition presets | No |
| Module reference | What each `src/` file holds | Where to read an API's opening comment |
| Validation and development | `npm test`, `npm run lint`, `snap`, `check` | No |
| License | MIT | The kit calls ink-studio, never copies it |

## 4. Guides and examples by what you are making

Every guide in `docs/` and every file in `examples/` as of `cf35ff8` (the 89 guides and 264 example files `983d91f` added are not
here), grouped by what a scene-maker is after. Read the Travels column first: a feature that does not travel is still good for
pictures made with ink-studio itself, but the player will not draw it.

**Travels** (the guide's feature):

- **Yes**: what it makes are ordinary solids or splats.
- **At build**: it computes numbers, paths, patterns or colours while the scene builds; turn them into solids, splats, ramps or `tex`
  choices and those travel.
- **No** with a reason: look (per-pixel), sky, renderer (drawn per view or live), bones, particles, physics, a world run (simulated
  worlds, agents, sound), screen layer, export or browser (a separate output).
- **Tool**: works on scene files or pictures; nothing to bake. **Not run**: not tried for this map.

**Examples** were each baked with this kit (an 8-second loop; two minutes at most), then again with the world fields the format does
not carry deleted:

- **Bakes** (splats): as it is. 28 examples.
- **Solids only** (splats; what it loses): after the deletion. 112 examples; most lose only their per-pixel look.
- **No** (reason): refused even then. Bones; live motion (splats redrawn or moved each frame by the example's own code, particles or
  physics); off-palette colours; wind-field sways; growth; particles; flat splats; all look (nothing left once the look is gone); not
  proven (over two minutes). 71 examples.
- **Not a scene**: a command's input, a world run, a command script, or a script that needs its page. 143 files. **Page**: an HTML
  page and its scripts for ink-studio's browser renderer. 31 files.

**Most useful for a rich, dense, finished scene:**

- Shape: `procedural.md` above all (terrain, rivers, streets, roofs, rooms and caves, vegetation, fracture; 24 examples bake as they
  are), then `typography.md`, `fractal-forms.md`, `quasiperiodic-tilings.md` and `proportional-layout.md` for pavements and facades,
  and `adaptive-sculpt-sampling.md` for the same look in fewer splats.
- Surface: the material fields (2.3) first; then `wallpaper-frieze.md` (ornament as pigment or relief), `moire-gratings.md` and the
  cellular and field guides as patterns fed to `tex` and `rf`.
- Light and air: no guide travels. Bake light on purpose (2.2), use `S.lights` with `g` ramps, `em`, `INK_BOUNCE` and the finish's
  `ao` and `fog`; references/recipes.md, 3, 5 and 7.
- Colour: `palette-recipes.md` (ramps from two colours in OKLab, made at build into the palette) and `paint-mixing.md`.
- Motion: `route-followers.md` for poses along a path that can drive rig parts (not run here); `loop-authoring.md` and
  `motion-review.md` for loops that close.
- Randomness: `randomness.md`.
- Looking at work: `art-passes.md` (`passes`), `visual-sweeps.md` (one view across seeds and settings).

### Shape

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `adaptive-sculpt-sampling.md` | Fewer splats on broad faces, more on edges and tight curves | Yes | **Solids only:** `adaptive-lantern.js` (2,456; loses look) |
| `adaptive-transport.md` | Flow across a graph, for tube widths and colours | At build | **No:** `adaptive-transport-studies.js` (live motion) |
| `curvature-lines.md` | Principal-direction traces for ornament, shingles and scales | At build | **No:** `curvature-ornament-studies.js` (live motion) |
| `curve-analysis.md` | Nearest points and frames along curves | At build | **Not a scene:** `curve-analysis.js` (not a scene). **Page:** `curve-analysis.html` |
| `curve-families.md` | Parametric curves for sweeps, routes, lettering and cameras | At build | **Solids only:** `rolling-curve-gallery.js` (30,046; loses look). **No:** `gear-lantern.js` (live motion). **Not a scene:** `curve-families.js` (not a scene). **Page:** `curve-families.html` |
| `depth-maps.md` | Depth images to splats, fields and meshes | At build, with palette colours | **No:** `depth-map.js` (off-palette colours) |
| `differential-growth.md` | Curves and shells that grow and buckle | At build | **Solids only:** `differential-growth-studies.js` (23,961; loses look) |
| `field-fabrication.md` | Fields turned into shells, ribs and cut-throughs | Not run | **No:** `field-fabrication-studies.js` (live motion) |
| `field-visualization.md` | Geometry extracted from scalar and vector fields | Not run | none |
| `four-dimensional.md` | 4D polytopes and slices | At build | **No:** `fourth-gate.js` (live motion) |
| `fractal-forms.md` | Bounded 3D fractals for `S.implicitForm` | Yes | **Solids only:** `fractal-form-studies.js` (209,138; loses look) |
| `headless-authoring.md` | Typed procedural graphs | What it makes as solids | **Bakes:** `editable-passage.js` (7,900). **Solids only:** `flooded-shrine.js` (17,675; loses look, sky and air, its saved snapshot). **No:** `graph-study.js` (bones). **Not a scene:** `drawing-layout.cjs` (command script), `graph-3d-rig.cjs` (command script), `pixel-effects.cjs` (command script), `procedural-generation.cjs` (command script), `raster-composition.cjs` (command script), `raster-palette.cjs` (command script), `raster-simulations.cjs` (command script), `raster-warps.cjs` (command script) |
| `hyperbolic-mosaics.md` | Poincare-disk tilings and circle packing | Yes | **Solids only:** `disk-studies.js` (13,254; loses look) |
| `iterated-function-systems.md` | Fractal flames as points or density | At build | **Solids only:** `iterated-flame-studies.js` (47,378; loses look) |
| `orbit-attractors.md` | Attractor orbits as paths or density | At build | **Solids only:** `orbit-attractor-studies.js` (16,643; loses look) |
| `procedural.md` | Every procedural primitive: fields, sampling, terrain, routes, buildings, growth, fracture | Geometry and placement | **Bakes:** `adaptive-surface.js` (8,564), `branching-networks.js` (14,544), `colony-patterns.js` (67,178), `composed-fields.js` (9,446), `constraint-tiles.js` (46,483), `dual-surface-studies.js` (5,836), `flow-wake.js` (21,895), `fluid-grids.js` (27,173), `fracture-studies.js` (24,702), `persistent-weather.js` (27,867), `pinned-facade.js` (30,158), `poisson-patches.js` (7,353), `river-processes.js` (15,444), `rooms-and-caves.js` (23,554), `route-fields.js` (14,595), `sampling-detail.js` (6,815), `sculptural-fields.js` (37,407), `socket-walkway.js` (48,812), `street-layouts.js` (21,848), `terrain-route.js` (20,615), `texture-synthesis.js` (29,607), `vegetation-growth.js` (25,732), `watershed.js` (15,782), `weighted-roof.js` (82,361). **Solids only:** `contact-masks.js` (18,892; loses look), `material-masks.js` (21,634; loses look). **No:** `preview-lod.js` (off-palette colours), `surface-advection.js` (off-palette colours), `transport-morph.js` (off-palette colours). **Not a scene:** `biome-flood.js` (needs a host page), `biome-recipes.js` (needs a host page), `biome-world.js` (needs a host page), `procedural/build.js` (not a scene), `streamed-places.js` (needs a host page) |
| `proportional-layout.md` | Golden-ratio subdivision for facades, trim and shots | At build | **Solids only:** `proportional-facade.js` (31,138; loses look). **No:** `proportional-shots.js` (not proven, over two minutes) |
| `quasiperiodic-tilings.md` | Penrose and Ammann-Beenker pavements | Yes | **Solids only:** `quasiperiodic-plazas.js` (35,982; loses look) |
| `recursive-curves.md` | Koch, dragon, Hilbert and Peano curves | At build | **Solids only:** `recursive-curve-studies.js` (19,185; loses look) |
| `shared-field-outputs.md` | Named field samples shared between generators | At build | **No:** `shared-field-outputs.js` (off-palette colours) |
| `surface-phyllotaxis.md` | Golden-angle placements on spheres and charts | At build | **No:** `surface-phyllotaxis.js` (growth) |
| `topological-surfaces.md` | Mobius, Klein and minimal surfaces | Not run | **No:** `topological-surface-studies.js` (live motion) |
| `typography.md` | Lettering as solids, sprites or strokes (references/recipes.md, Lettering) | As solids | **Not a scene:** `typography.js` (not a scene). **Page:** `typography.html` |
| `weaving-braiding.md` | Strands with over-under crossings | At build | **No:** `interlacing-studies.js` (live motion) |

### Surface

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `boundary-potential-fields.md` | A solved potential as pigment, contours or flow | At build | **No:** `boundary-potential-studies.js` (not proven, over two minutes) |
| `cellular-lattices.md` | Cellular automata on lines, grids and voxels | At build | **Solids only:** `cellular-lattice-studies.js` (12,220; loses look) |
| `competitive-growth.md` | Growth fronts claiming a grid, with seams | At build | **Solids only:** `competitive-growth-studies.js` (23,612; loses look) |
| `complex-plane-fields.md` | Mandelbrot, Julia and Newton patterns | At build | **Solids only:** `complex-plane-studies.js` (16,650; loses look) |
| `continuous-cellular.md` | Lenia and SmoothLife fields | At build | **No:** `continuous-cellular-studies.js` (live motion) |
| `continuous-splat-coverage.md` | Opaque surfaces joined without gaps | No: look | **No:** `splat-surface-coverage.js` (flat splats) |
| `coupled-phase-changes.md` | Ice, liquid and pigment reactions on a grid | At build | **No:** `phase-change-studies.js` (live motion) |
| `deformation-materials.md` | Ink, wear and wetness kept in a rest chart | Not run | none |
| `edge-filter.md` | Coverage-filtered edges | No: look | **Solids only:** `selective-edge-filter.js` (6,350; loses look) |
| `glyph-grids.md` | Glyph grids and letterforms from cell rules | At build | **No:** `glyph-grid.js` (live motion) |
| `graph-automata.md` | Cell rules on connected objects | At build | **No:** `graph-automata-studies.js` (live motion) |
| `learned-cellular-growth.md` | A small neural cell rule growing ornament | At build | **No:** `learned-cellular-growth.js` (live motion) |
| `material-controls.md` | Roughness, metal, refraction and coatings | No: renderer | **Not a scene:** `material-controls.js` (not a scene). **Page:** `material-controls.html` |
| `math-fields.md` | Complex charts, vector fields and chaotic maps for materials and shapes | At build | **Not a scene:** `math-fields.js` (not a scene). **Page:** `math-fields.html` |
| `moire-gratings.md` | Line, dot and polar interference patterns | At build | **Solids only:** `moire-grating-studies.js` (26,328; loses look) |
| `persistent-spatial-fields.md` | Deposits kept in a chart or volume | At build | **No:** `persistent-spatial-fields.js` (live motion) |
| `pixel-look.md` | Tone, stipple, remaps, colour tables and stacks | No: look | **Solids only:** `authorized-dither-pairs.js` (43,398; loses look, sky and air), `look-blending.js` (48,865; loses look), `palette-constraints.js` (44,091; loses look), `palette-material-matching.js` (35,317; loses look, sky and air), `palette-placement.js` (44,101; loses look, sky and air), `protected-swatches.js` (37,558; loses look, sky and air), `provenance-relays.js` (56,042; loses look), `rgb-lut.js` (28,609; loses look), `shared-look-selectors.js` (24,533; loses look), `wet-spillway.js` (48,865; loses look) |
| `projected-effects.md` | Animated rasters and patterns on surfaces | No: look | **Solids only:** `palette-cycling.js` (56,006; loses look, sky and air). **No:** `banded-pigment.js` (live motion), `surface-effects.js` (live motion). **Not a scene:** `edge-shedding.js` (needs a host page) |
| `reaction-diffusion-brushing.md` | Gray-Scott patterns painted on charts | At build | **No:** `reaction-diffusion-brushing.js` (live motion) |
| `recursive-coordinate-transforms.md` | Mobius maps, inversion and Droste recursion | At build | **Solids only:** `recursive-coordinate-studies.js` (13,126; loses look) |
| `sandpiles-excitable.md` | Sandpiles and excitable media | At build | **No:** `sandpiles-excitable-studies.js` (live motion) |
| `scalar-wave.md` | Waves diffracting through gaps | At build | **Solids only:** `wave-propagation-studies.js` (33,126; loses look) |
| `sdf-assist.md` | Tracing sculpted surfaces at render time | No: renderer | **Solids only:** `sdf-gatehouse.js` (15,314; loses look, sky and air, live light) |
| `shared-domains.md` | One cell rule on images, charts, graphs and voxels | At build | **No:** `shared-domain-studies.js` (live motion) |
| `spectral-fields.md` | Fourier fields and membrane modes | At build | **No:** `spectral-wave-studies.js` (live motion) |
| `stable-detail.md` | Fine detail eased in and out by size | No: look | **Solids only:** `stable-detail.js` (3,290; loses look) |
| `stable-dithering.md` | Screen, world or object dither | No: look | **Solids only:** `palette-dither-scale.js` (42,304; loses look, sky and air, camera rig), `palette-dither-spaces.js` (42,304; loses look, sky and air), `stable-dithering.js` (88,073; loses look, sky and air) |
| `surface-materials.md` | View-dependent finishes | No: renderer | **Solids only:** `color-curves.js` (41,906; loses look), `material-bevel-highlights.js` (35,065; loses look), `material-lighting-ramps.js` (26,328; loses look), `surface-detail-courtyard.js` (34,177; loses look, sky and air, live light), `surface-gallery.js` (27,053; loses look), `thin-transmission.js` (31,625; loses look, sky and air, live light) |
| `textured-surfaces.md` | Optional pixel-textured patches | No: sprites | **Solids only:** `textured-surfaces.js` (6,580; loses look) |
| `trail-sensing-agents.md` | Agents that lay and follow trails | At build | **Solids only:** `trail-sensing-studies.js` (23,263; loses look) |
| `vector-field-painting.md` | Line integral convolution grain | At build | **No:** `vector-field-painting-studies.js` (not proven, over two minutes) |
| `wallpaper-frieze.md` | A motif repeated as pigment, relief or tiles | At build | **Solids only:** `wallpaper-frieze.js` (14,434; loses look) |

### Light

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `area-lights.md` | Rectangle and disc lights with soft shadows | No: renderer | **Solids only:** `shaped-lights.js` (15,083; loses look, live light) |
| `bounce-probes.md` | Local colour bleeding at render time (baked bounce, `INK_BOUNCE`, does travel) | No: renderer | **Solids only:** `bounce-probes.js` (27,882; loses look, sky and air, live light) |
| `contact-shadows.md` | Short contact shadows at render time (the finish's `ao` travels) | No: look | **Solids only:** `local-contact-shadows.js` (13,193; loses look) |
| `fog-lighting.md` | Spot and point lights in fog | No: renderer | **Solids only:** `light-cookies.js` (39,441; loses look, sky and air), `lighthouse-mist.js` (100,171; loses look, sky and air) |
| `geometric-caustics.md` | Coloured light through authored glass | No: renderer | **Solids only:** `geometric-caustic-studies.js` (31,379; loses look, sky and air, live light) |
| `light-emitters.md` | Line lights, cookies and shaped emitters | No: renderer | **Solids only:** `light-emitters.js` (38,051; loses look, sky and air, live light). **Page:** `light-emitters.html` |
| `live-sun.md` | A sun relit at render time (bake light with `S.sun`) | No: renderer | **Solids only:** `beacon-pool.js` (19,774; loses look, sky and air, live light), `bounce-light.js` (17,193; loses look, live light), `live-sun.js` (26,722; loses look, live light) |
| `scene-exposure.md` | Indoor and outdoor exposure zones | No: world field | **No:** `sheltered-arch.js` (wind-field sways) |
| `scene-optics.md` | Index of reflections, ripples and optics | No: renderer | **Solids only:** `cliff-depth-bands.js` (129,910; loses sky and air), `layered-transparency.js` (8,229; loses look, sky and air, live light, weather), `local-reflection-workshop.js` (48,958; loses look, sky and air, live light), `optical-look-bindings.js` (41,967; loses look, sky and air, live light), `water-garden.js` (32,252; loses look, live light). **Page:** `water-garden.html` |

### Colour and palette

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `effect-palettes.md` | Own ramps for fog, clouds, sky and glow | No: look | **Solids only:** `atmosphere-palette-fields.js` (100,171; loses look, sky and air), `effect-palettes-night-watch.js` (158,069; loses look, sky and air), `palette-composition.js` (47,900; loses look, sky and air, live light) |
| `paint-mixing.md` | Spectral paint mixing into ramps | At build | **Not a scene:** `paint-mixing.js` (needs a host page). **Page:** `paint-mixing.html` |
| `palette-recipes.md` | OKLab palette recipes, ramps and paths | At build | **Solids only:** `animated-palette-fields.js` (49,891; loses look, sky and air), `authored-lighting-ramps.js` (41,745; loses look, sky and air), `chroma-glazes.js` (45,563; loses look, sky and air), `grayscale-ramp-reliefs.js` (53,070; loses look, sky and air), `hue-brightness.js` (63,002; loses look, sky and air), `palette-chart-archive.js` (176,463; loses look, sky and air), `palette-coverage.js` (58,397; loses look, sky and air), `palette-field-weather.js` (56,810; loses look, sky and air, weather), `palette-space-plots.js` (30,583; loses look, sky and air), `polar-colour.js` (40,833; loses look, sky and air), `render-stages.js` (24,533; loses look), `spectrum-ramps.js` (103,467; loses look, sky and air), `surface-palette-roles.js` (41,224; loses look, sky and air). **Not a scene:** `palette-recipes.js` (not a scene). **Page:** `palette-recipes.html` |

### Motion and loops

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `animated-splat-fields.md` | World-space animated splat fields | No: renderer | **No:** `animated-splat-fields.js` (off-palette colours) |
| `cloth-review.md` | Pinning and reviewing a cloth | The cloth itself | **No:** `cloth-review.js` (bones). **Page:** `cloth-review.html` |
| `destruction.md` | Existing splats broken into rubble | No: physics | **No:** `destruction.js` (particles). **Page:** `destruction.html` |
| `field-particle-coupling.md` | Particles and a fluid grid moving each other | No: particles | **Solids only:** `field-particle-studies.js` (22,171; loses look) |
| `geometry-morphs.md` | Splat morphs between poses | No: morph | **No:** `geometry-morph-studies.js` (live motion) |
| `loop-authoring.md` | Finding repeats and fitting tracks to a loop | Tool | **No:** `loop-authoring-studies.js` (live motion) |
| `materialisation.md` | Splats detaching, flowing and rejoining | No: live motion | **No:** `materialisation.js` (live motion). **Page:** `materialisation.html` |
| `motion-afterimages.md` | Trails of past poses | No: look | none |
| `route-followers.md` | Vehicle poses along a path (they can drive rig parts) | Through rig parts | **No:** `route-followers.js` (live motion) |
| `shared-time-domains.md` | Separate simulation, animation and camera clocks | No: renderer | **Not a scene:** `shared-time-domains.js` (not a scene). **Page:** `shared-time-domains.html` |

### Characters

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `animation-events.md` | Events on clips and state graphs | No: bones | none |
| `animation-timeline.md` | One shot clock over a puppet | No: bones | **No:** `animation-timeline.js` (bones) |
| `authored-contacts.md` | Planted feet and props passed hand to hand | No: bones | **No:** `authored-contacts.js` (bones), `scene-contacts.js` (bones). **Page:** `authored-contacts.html` |
| `character-surfaces.md` | Characters on decks, ice and slopes | No: a world run | **Not a scene:** `ferry-spring-traversal.js` (not a scene) |
| `clip-sequence.md` | Trimming and retiming clips | No: bones | **No:** `clip-sequence.js` (bones). **Page:** `clip-sequence.html` |
| `motion-fx.md` | Stretch, smear and trails on a puppet | No: bones | **No:** `motion-fx.js` (bones). **Page:** `motion-fx.html` |
| `motion-layers.md` | Part-masked override clips | No: bones | **No:** `motion-layers.js` (bones) |
| `motion-retarget.md` | Clips moved to another puppet | No: bones | **No:** `retarget-courier.js` (bones), `retarget-guard.js` (bones) |
| `motion-review.md` | Loop pops, spacing and arcs (a good habit for rig parts too) | No: bones | **No:** `motion-review.js` (bones). **Page:** `motion-review.html` |
| `pose-blocking.md` | Pose shelf and blocking | No: bones | **No:** `pose-blocking.js` (bones). **Page:** `pose-blocking.html` |
| `traversal-links.md` | Rails, boosts and flows for a character | No: a world run | **Not a scene:** `traversal-links.js` (not a scene) |

### Weather and air

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `aerial-perspective.md` | Distant colour and extinction from the sky | No: sky | **Solids only:** `aerial-perspective.js` (132,728; loses sky and air) |
| `atmosphere-emitters.md` | Smoke, steam and spray from a socket | No: particles | **Solids only:** `atmosphere-railway.js` (135,453; loses look, sky and air, weather) |
| `celestial-tracks.md` | Suns, moons and stars on paths | No: sky | **Solids only:** `celestial-estuary.js` (241,557; loses look, sky and air) |
| `cloud-recipes.md` | Procedural cloud fields | No: sky | **Solids only:** `cloud-recipe-coast.js` (122,554; loses look, sky and air, live light) |
| `cloud-representations.md` | Clouds as cards and impostors by distance | No: sky | **No:** `cloud-flythrough.js` (particles) |
| `cloud-shadows.md` | Moving cloud coverage and shadows | No: sky | **Solids only:** `cloud-shadows.js` (122,554; loses look, sky and air, live light) |
| `conditional-weather.md` | Weather changes on cues | No: sky | none |
| `environment-packs.md` | Reusable sky and weather presets | No: sky | none |
| `geometry-shaped-atmosphere.md` | Fog and cloud shaped by geometry | No: sky | **Solids only:** `shaped-mist-ravine.js` (181,969; loses look, sky and air) |
| `interruptible-sky.md` | Sky transitions started mid-way | No: sky | **No:** `interruptible-sky.js` (wind-field sways) |
| `layered-horizon.md` | A painted far vista on cylinders (references/recipes.md has a far backdrop that travels) | No: world field | **Solids only:** `layered-horizon.js` (38,447; loses look, sky and air) |
| `lightning.md` | Timed lightning flashes | No: world field | **Solids only:** `lightning-headland.js` (120,602; loses look, sky and air) |
| `rain-impacts.md` | Rain hitting planes | No: weather | **Solids only:** `rain-cistern.js` (93,913; loses look, sky and air, live light, weather) |
| `retained-weather.md` | Wetness, snow and frost that stay | No: weather | **Solids only:** `wet-stone-finish.js` (41,173; loses look, sky and air, weather). **No:** `weather-traces.js` (kind 15) |
| `shared-sky-reflections.md` | One sky for backdrop and reflections | No: sky | **Solids only:** `shared-sky-reflections.js` (41,061; loses look, sky and air, live light) |
| `volume-cutouts.md` | Clear pockets in fog and cloud | No: sky | **No:** `volume-cutout-gate.js` (bones) |
| `weather-binding.md` | Weather profiles across systems | No: sky | **No:** `weather-courtyard.js` (wind-field sways) |
| `weather-fronts.md` | Fronts moving over the world | No: weather | none |
| `wind-field.md` | One wind for clouds, foliage and smoke (its sways are refused; plain sways travel) | No: world field | **No:** `windbreak.js` (wind-field sways) |
| `world-precipitation.md` | Rain and snow in world space | No: weather | **No:** `lantern-squall.js` (kind 15) |

### Composition

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `art-direction.md` | Look profiles (painted, storm, dawn) | No: look | **Solids only:** `art-direction-estuary.js` (241,557; loses look, sky and air). **No:** `motion-cadence.js` (wind-field sways) |
| `camera-atlas.md` | Several cameras into overlays and panels | No: renderer | **Solids only:** `camera-atlas.js` (16,722; loses look) |
| `camera-impulses.md` | Camera shake and handheld motion | No: camera | **No:** `directional-camera-impulses.js` (particles). **Page:** `directional-camera-impulses.html` |
| `camera-rigs.md` | Camera rigs and shot blends | No: camera | **Solids only:** `camera-staging.js` (38,025; loses look, sky and air, camera rig). **No:** `cinematic-camera.js` (colour changes). **Page:** `cinematic-camera.html` |
| `cutaways.md` | Clipping planes and depth windows | No: renderer | none |
| `data-bound-marks.md` | Marks drawn from data records | No: world field | none |
| `drawing-primitives.md` | Drawing over the finished picture | No: screen layer | none |
| `impostor-atlases.md` | Camera-facing cards and directional sprites | No: sprites | **Solids only:** `lantern-catch.js` (18,336; loses look, live light), `painted-scenery.js` (13,167; loses look, sky and air, live light), `relightable-impostor.js` (77,572; loses look, sky and air, live light) |
| `live-scene-hierarchy.md` | One hierarchy for geometry, lights and anchors (rig parts travel) | No: scene graph | **Not a scene:** `live-scene-hierarchy.js` (not a scene). **Page:** `live-scene-hierarchy.html` |
| `mixed-resolution.md` | Layers at their own resolutions | No: look | none |
| `parameter-bindings.md` | Shared controls and bindings | No: world field | none |
| `render-graph.md` | An editable graph of render passes | No: look | **Solids only:** `raster-millrace.js` (85,530; loses look, sky and air, live light). **No:** `raster-tidal-flats.js` (all `look`), `render-feedback.js` (all `look`). **Not a scene:** `render-effects.js` (not a scene). **Page:** `render-effects.html` |
| `scale-aware-previews.md` | Detail chosen by what the camera resolves | No: world field | **No:** `scale-aware-previews.js` (all `look`) |
| `scene-timeline.md` | One timeline for a diorama | No: world field | none |
| `silhouette-protection.md` | Fog and contrast kept off a chosen actor | No: look | **Solids only:** `market-shot-focus.js` (45,721; loses look, sky and air, live light, weather), `silhouette-protection.js` (69,389; loses look, sky and air) |
| `target-inspection.md` | Brackets, labels and magnifiers over a target | No: screen layer | **Not a scene:** `target-inspection.js` (not a scene). **Page:** `target-inspection.html` |
| `view-annotations.md` | Legends and labels in output pixels | No: screen layer | none |
| `world-reconstruction.md` | Reveal and rebuild tracks | No: look | none |

### Randomness

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `randomness.md` | Named seeded streams and keyed samples, stable under edits | At build | **Not a scene:** `randomness.js` (not a scene). **Page:** `randomness.html` |

### Looking at work

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `art-passes.md` | Depth, normal and emission passes on the art grid | Tool | **Solids only:** `art-effects.js` (590; loses look), `art-pipeline.js` (19,774; loses look, sky and air, live light), `emissive-finishes.js` (43,410; loses look, sky and air, live light), `selective-ink.js` (38,025; loses look, sky and air). **No:** `weather-front.js` (wind-field sways) |
| `comparison-views.md` | Two sources at one camera and time | Tool | none |
| `environment-inspector.md` | Explains the sky and weather at a point | Tool | none |
| `environment-review-shots.md` | Three review shots of a sky | Tool | **Solids only:** `review-beacon.js` (26,722; loses look, sky and air, live light, weather), `review-cliff-path.js` (129,910; loses sky and air), `review-sheltered-market.js` (45,721; loses look, sky and air, live light, weather) |
| `reel.md` | Captures in one offline page | Tool | none |
| `shot-recipes.md` | Saved inputs behind a review render | Tool | none |
| `transition-review.md` | A shot checked at export size | Tool | **No:** `transition-review.js` (wind-field sways) |
| `visual-sweeps.md` | One view across settings and seeds | Tool | **No:** `visual-sweep-attractor.js` (live motion) |

### World runs

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `acoustic-queries.md` | Sound through rooms and openings | No: a world run | none |
| `action-windows.md` | Timed actions and contact outcomes | No: a world run | **Not a scene:** `action-windows.js` (not a scene) |
| `adaptive-music.md` | A score that follows the world | No: a world run | none |
| `agent-decisions.md` | Agents choosing activities | No: a world run | none |
| `agent-needs.md` | Agent needs and shifts | No: a world run | none |
| `agent-orders.md` | Agent orders and tasks | No: a world run | none |
| `agent-storage.md` | Agent rosters, births and removals | No: a world run | none |
| `aggregate-simulation.md` | Coarser simulation far away | No: a world run | none |
| `batch-spatial-queries.md` | Proximity and occupancy queries | No: a world run | none |
| `boarding.md` | Seats on carts and ferries | No: a world run | **Not a scene:** `boarding-traversal.js` (not a scene) |
| `budgeted-route-requests.md` | Route requests per tick | No: a world run | none |
| `carry.md` | Carrying objects between places | No: a world run | **Not a scene:** `carry-workshop.js` (not a scene) |
| `contact-effects.md` | Measured contacts with surfaces | No: a world run | none |
| `crowds-and-bottlenecks.md` | Walkers avoiding each other | No: a world run | none |
| `ecology.md` | Habitat channels, fire and recovery | No: a world run | **No:** `ecology.js` (colour changes). **Page:** `ecology.html` |
| `editable-simulation-inputs.md` | Pins, brushes and injections on a timeline | No: a world run | **No:** `editable-simulation-inputs.js` (live motion) |
| `event-actions.md` | Timeline cues to commands | No: a world run | none |
| `faction-perception.md` | What a faction has seen | No: a world run | none |
| `first-divergence.md` | Where two world runs first differ | Tool | **Not a scene:** `world-worker-estate.js` (world run) |
| `gameplay-state.md` | Timers, objectives and state graphs | No: a world run | none |
| `group-formations.md` | Groups of agents sharing a destination | No: a world run | none |
| `headless-worlds.md` | Declarative simulated worlds, queries and replay | No: a world run | **Bakes:** `conservative-transfer.js` (44,413). **No:** `spatial-field-wind.js` (live motion). **Not a scene:** `canal-traversal.js` (not a scene), `interactable-locks.js` (needs a host page), `spatial-rebuild.js` (not a scene) |
| `interaction-components.md` | Reusable controls for interactables | No: a world run | none |
| `job-reservations.md` | Shared jobs and capacity | No: a world run | none |
| `navigation-flow.md` | Shared destination fields | No: a world run | none |
| `navigation-tiles.md` | Walking routes on tiles | No: a world run | none |
| `physical-work.md` | Stock, labour and construction | No: a world run | none |
| `population.md` | Households and residents | No: a world run | none |
| `portals.md` | Travel between named places | No: a world run | **Not a scene:** `place-portals.js` (needs a host page), `portable-workshop.js` (not a scene) |
| `prefab-upgrades.md` | Moving placed assemblies to new revisions | No: a world run | **Not a scene:** `world-prefab-upgrade.js` (world run) |
| `public-influence.md` | Public priorities and rewards | No: a world run | none |
| `puzzles.md` | Inputs combined into doors and gates | No: a world run | none |
| `region-revisions.md` | Region-scoped state per tick | No: a world run | none |
| `simulation-checkpoints.md` | Snapshots, forks and resets | No: a world run | **Not a scene:** `world-checkpoint-branch.js` (world run) |
| `simulation-chunks.md` | Systems owned by chunks | No: a world run | none |
| `simulation-scrubbing.md` | Scrubbing a world run | No: a world run | none |
| `simulation-workers.md` | World runs on worker threads | No: a world run | none |
| `spatial-audio.md` | A spatial sound mix | No: a world run | none |
| `targeted-interactions.md` | Verbs agents perform on targets | No: a world run | none |
| `world-scaling.md` | Indexing large worlds | No: a world run | none |

### Tools and output

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `asset-interchange.md` | glTF, GLB and atlas round trips | No: export | none |
| `browser-renderer.md` | ink-studio's WebGL 2 renderer | No: browser | **Solids only:** `coverage-aware-glass.js` (27,925; loses look), `environment-test-scene.js` (13,338; loses sky and air). **Page:** `water-bodies.html` |
| `linked-views.md` | Charts, maps and scenes on one clock | No: browser | none |
| `project-bundles.md` | A JSON scene and its assets in one file | No: export | none |
| `scene-editor.md` | Editing JSON dioramas without a page | Tool | none |
| `scene-publishing.md` | Publishing a scene to a folder | No: export | none |
| `transitions.md` | Full-screen WebGL transitions | No: browser | **Page:** `transitions/index.html` |
| `typed-data-inputs.md` | Typed datasets for scenes and worlds | No: world field | none |
| `viewer-input.md` | Remappable browser input | No: browser | none |

### Other examples

| Kind | Files |
| --- | --- |
| Inputs to commands and tools | `atmosphere-depth-bands.json`, `blue-shadow.cube`, `coastal-environment-pack.json`, `coastal-pack-beacon.json`, `coastal-pack-jetty.json`, `complementary-field.json`, `copperwind-looks.json`, `curve-family.json`, `desaturation-field.json`, `driven-look-forge-actions.json`, `driven-look-forge.json`, `editable-passage.edits.json`, `environment-review-camera.js`, `grayscale-ramp.json`, `half-gain-legal.cube`, `headless-array-graph.json`, `headless-array-sweep.json`, `headless-graph-group.json`, `headless-graph.json`, `hue-brightness-field.json`, `lantern-dusk.json`, `learned-harbor-mark.json`, `lighting-ramp-palette.json`, `look-assets.json`, `look-prefabs.json`, `ornament-pattern.json`, `paint-mixture.json`, `palette-charts.json`, `palette-check-courier.json`, `palette-coverage-field.json`, `palette-dither-fit.json`, `palette-recipe.json`, `palette-space-plot.json`, `palette-weather-beacon.json`, `physical-materials.pack.json`, `polar-colour-field.json`, `primary-ramp.json`, `procedural/authoring-example.js`, `procedural/gallery.js`, `readability-courier.json`, `relay-look-pack.json`, `shared-sky-profiles.json`, `spatial-bed-edit.json`, `spatial-wind-transect.json`, `spatial-yard-queries.json`, `spectrum-ramp.json`, `train-neural-cellular.py`, `visual-sweep-attractor.plan.json` |
| Scenes and pages | **Bakes:** `cloth.js` (1,413), `sculpt.js` (4,027). **Solids only:** `breakable-parts.json` (24,342; loses breakable parts), `color-runoff.js` (10,759; loses look), `copperwind-crossing.json` (81,122; loses look), `palette-remap.json` (21,028; loses look), `signal-observatory.json` (35,566; loses look, timeline), `stipple.json` (12,390; loses look). **No:** `particles.js` (live motion), `puppet.js` (bones), `scene.json` (particles), `splat-effects.js` (live motion). **Page:** `procedural/gallery.html`, `transitions/gallery.css`, `transitions/gallery.mjs`, `transitions/scenes.mjs` |
| World runs (input to the world commands) | `world-acoustic-hatch.json`, `world-adaptive-music.json`, `world-agent-orders.json`, `world-agent-roster.json`, `world-aggregate-estuary.json`, `world-causal-mill.json`, `world-cellar-flood.json`, `world-conditional-weather.json`, `world-construction-bridge.json`, `world-contact-effects.json`, `world-continuous-colliders.json`, `world-crossing.json`, `world-crowd-bridge.json`, `world-deformable-yard.commands.json`, `world-deformable-yard.json`, `world-estuary-households.json`, `world-expedition-formation.json`, `world-flow-ford.json`, `world-ford-shift.json`, `world-harvest-logistics.json`, `world-hydraulic-yard.commands.json`, `world-hydraulic-yard.json`, `world-influence-yard.json`, `world-interaction-yard.json`, `world-lightwell-workshop.json`, `world-live-volumes.json`, `world-lookout-memory.json`, `world-material-fatigue.commands.json`, `world-material-fatigue.json`, `world-multi-rate.json`, `world-persistent-valley.json`, `world-physical-materials.json`, `world-physical-work.json`, `world-pocket-moon.json`, `world-prefab-upgrade.migration.json`, `world-puzzle-gate.actions.json`, `world-puzzle-gate.json`, `world-region-revisions.json`, `world-resident-shelter.json`, `world-rotating-dock.json`, `world-route-queue.json`, `world-routed-workshop.commands.json`, `world-routed-workshop.json`, `world-sediment-ford.json`, `world-sediment-gate.json`, `world-shelter-reservations.json`, `world-spatial-fields.json`, `world-spatial-yard.json`, `world-storm-canopy.json`, `world-surface-state.json`, `world-thawing-ford.json`, `world-tiled-ford.json`, `world-transfers.json`, `world-ventilated-shelter.json`, `world-watershed.json`, `world-windmill-workshop.json` |

Each example's first lines say what it shows; `ink-studio catalog <words>` searches every feature the toolkit has and points at its
source.
