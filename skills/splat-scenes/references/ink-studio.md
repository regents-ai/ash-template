# ink-studio: what to read, and what travels into a baked file

ink-studio is the toolkit the scenes are sculpted with: signed-distance solids baked into pixel-art Gaussian splats, plus animation,
particles, physics, procedural tools, simulated worlds and two renderers (a CPU one for Node and the command line, a WebGL 2 one for
browsers). It is MIT licensed (README, License) and needs Node 18 or later with no runtime dependencies. The kit calls it from the
folder `INK_STUDIO` names and never copies it.

The working knowledge (section 2) was last checked against commit `e8cef0c` (22 Nov 2026), the newest then: `examples/sculpt.js`,
`examples/cloth.js` and a trial scene of 213,405 splats with rig parts, sways and a cloth bake, prove and play with it; the solids
table, the solid, join, ground and cloth options in 2.3 and 2.5, and the outline and print fields 2.3 lists as not carried
(`brush` to `screenPrint`) were each built and baked with it. The maps (sections 3 and 4) cover all of `e8cef0c`: 31 README
sections, 355 guides in `docs/` and 987 files in `examples/`, of which 11 guides and 39 example files are new since `e80d985`.
Each new example was sorted with this kit, and every Bakes, Solids-only and No entry was baked again at `e8cef0c`: all 271 came
out as at `e80d985`. Its README and guides are the authority; this page says what to read first, what the kit's file carries,
and where each guide and example stands.

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
drawing). Each helper's inputs are in the comment just above it in `src/sculpt.js` (search for `S.tree =`); the ones these notes
use, read from the source at `e8cef0c` and each built and baked once with exactly the call shown (`stone` and `moss` ramps, `res`
as given):

| Solid | Inputs | Built once |
| --- | --- | --- |
| `S.ball(c, r, mat, o)` | c the centre; r a radius, or `[rx, ry, rz]` for an egg or a squashed ball | `S.ball([0, 1, 0], 0.6, stone, { res: 0.08 })`: 919 splats; with `[0.9, 0.5, 0.6]`: 1,116 |
| `S.box(c, h, mat, o)` | c the centre, h the half-sizes `[hx, hy, hz]`; `o.rd` rounds the edges to that radius | `S.box([0, 0.6, 0], [0.8, 0.6, 0.5], stone, { rd: 0.15, res: 0.08 })`: 1,486 |
| `S.lathe(c, h, rf, mat, o)` | A turned solid: c the centre of its base, h its height, rf its radius: a number, `[bottom, top]`, or a function of 0 (bottom) to 1 (top) | `S.lathe([0, 0, 0], 1.6, [0.6, 0.2], stone, { res: 0.08 })`: 996; with 0.4: 962; with `t => 0.3 + 0.2 * Math.sin(t * Math.PI)`: 946 |
| `S.torus(c, R, r, mat, o)` | A ring lying flat: R from the centre to the middle of the rim, r the rim's own radius; `ax` stands it up | `S.torus([0, 0.3, 0], 0.8, 0.2, stone, { res: 0.06 })`: 2,205, and the same standing with `ax: S.AZ` |
| `S.tube(pts, r0, r1, mat, o)` | A limb or branch through a list of points, radius r0 at the first to r1 at the last; or r0 a function of 0 to 1 (r1 then unused) | `S.tube([[0, 0, 0], [0.3, 1, 0], [0, 2, 0.2]], 0.25, 0.1, stone, { res: 0.06 })`: 958 |
| `S.ground(mat, o)` | Flat at `o.y`, or a height `o.h(x, z)`; only a ragged disc is drawn, radius `o.rad` (8 unless given) about `o.cx`, `o.cz`, squashed front to back by `o.zs`. `o.edge` is how ragged (0.16 unless given): the rim wanders in from `rad` by up to 2 × edge × rad, and 0 gives a clean round edge. `o.keep(x, z)` keeps only the points it returns true for | `S.ground(moss, { y: 0, rad: 3, res: 0.12 })`: 1,660, and the same with an `h`. In another scene (seed 1): 1,596; with `edge: 0` 2,253, `edge: 0.4` 834; with `keep: (x, z) => Math.hypot(x, z) > 1`, a hole in the middle, 1,348 |
| `S.rock(c, r, mat, o)` | A ball with a bumped surface; a radius r is made `[1.15 r, 0.8 r, r]`, or give three | `S.rock([0, 0.4, 0], 0.6, stone, { res: 0.06 })`: 2,459 |
| `S.tree(x, y, z, o)` | `{ h, r, lean, nb, spread, cr, bark, leaf, leaves, roots, res }`: trunk height and radius, lean `[x, z]`, limbs, their reach, leaf-cluster size, the two materials, leaf count, roots | `S.tree(0, 0, 0, { h: 3, bark: stone, leaf: moss, res: 0.06 })`: 7,735, 1,779 of them swaying leaves |
| `S.crown(clusters, mat, count, o)` | Leaves filling clusters `{ p, r: [rx, ry, rz] }`; `o.scale` sizes the leaves | `S.crown([{ p: [0, 1.5, 0], r: [0.8, 0.6, 0.8] }], moss, 400, { scale: 0.6 })`: 400, all swaying |
| `S.strokes(shape, c, depth, mat, o)` | Lettering: shape from `K.poly2.text(str, size)` (references/recipes.md, 4) | `S.strokes(K.poly2.text('AB', 0.6), [0, 1, 0], 0.08, stone, { res: 0.03 })`: 3,934 |
| `S.stroke(mark, mat, o)` | README, Editable 3D drawing: `points`, `width`, `depth`, `pressure`, `taper` | `S.stroke({ points: [[-0.8, 0.5, 0], [0, 1.4, 0], [0.8, 0.5, 0]], width: 0.2, depth: 0.1, taper: [1, 0.3] }, stone)`: 295 |
| `S.fill(mark, mat, o)` | The same section: `rings` (the outside, then holes) in a `frame` of `origin`, `u` and `v`; `depth` | `S.fill({ rings: [[[-0.6, 0], [0.6, 0], [0.6, 1.2], [-0.6, 1.2]]], frame: { origin: [0, 0.2, 0], u: [1, 0, 0], v: [0, 1, 0] }, depth: 0.1 }, stone)`: 530 |
| `S.implicitForm(source, mat, o)` | Any field: source `{ sd(x, y, z), bounds: { min, max } }`, negative inside; `o.res`, `o.cell` (`docs/fractal-forms.md`) | A ball of radius 0.6 given as a field, `{ res: 0.06 }`: 3,246 |

A tree's and a crown's leaves sway (kind 11), so a scene with them ends `build` with the kit's loop helper, or the bake refuses
their speeds. `S.tree` and `S.crown` size their leaves for a full tree, up to half a unit at `scale` 1 (read from source), so a small
tree or hedge comes out in large blobs: pass `scale` below 1 (a mansion-grounds scene's hedges: 0.55).

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
| `bump: [height, frequency]` | Roughens the surface with noise: it moves in and out by up to three quarters of `height`, and a higher `frequency` makes the bumps smaller and closer. Built once: `S.ball([0, 1, 0], 0.6, stone, { res: 0.08, bump: [0.08, 5] })` gave 1,436 splats against 919 smooth, its surface 0.543 to 0.655 from the centre |

Read from `add()` in `src/sculpt.js` at `e8cef0c` and not in this table: `surfaceId`, `target` and `model` name what ink-studio's own
renderers draw a solid as (`surfaceId: 'shell'` and `model: 'separate'` each baked to the same 919 splats as without);
`reach` and `lowerBound` tune how a solid is sampled; `born` the bake refuses.

**Joins.** `S.join(kind, a, b, o)` joins solids made with `hold: true` (or lists of them) into one. Kinds: `union`, `cut`, `common`;
rounded `round`, `cutRound`, `commonRound`; bevelled `chamfer`, `cutChamfer`, `commonChamfer`; stepped `stairs`, `cutStairs`,
`commonStairs`; `columns`, `cutColumns`; and `pipe`, `engrave`, `groove`, `tongue`. Its options, read from `src/kit/k3-shapes.js`
at `e8cef0c` and each built and baked once on a held box of half-sizes `[0.8, 0.6, 0.5]` and a held ball of radius 0.5 set into
its top corner, `res: 0.06` (a plain `cut` gave 3,603 splats):

| Option | Effect | Built once |
| --- | --- | --- |
| `r` | The rounding, bevel or step size (0.2 unless given) | `cutRound` with `r: 0.15`: 3,728 |
| `n` | How many steps or columns (3 unless given) | `stairs` with `r: 0.3, n: 4`: 3,813 |
| `mat` | One material for the whole result. Without it the result takes the first solid's, and, except for the cut kinds, `engrave` and `groove`, the second solid's ramp where that one is nearer | `union` with `mat: moss`: every splat moss |
| `inner` | For `cut` kinds, `engrave` and `groove`: a ramp for the faces the cut makes (within 0.06 of the cutting solid) | `cut` with `inner: [8, 9, 10]`: the hollow in that ramp, 1,303 of the 3,603 splats |
| `mask` | Samples each solid only where the other leaves it | `cut` with `mask: true`: 2,863 splats, and the same look |

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
ink-studio's renderers), `born` and `wet` (the bake refuses their flags); and `brush`, `footprint`, `engraving` and `screenPrint`,
with the sculptor's `S.stipple` (a material's `stipple: false` keeps it out), which give the splats drawn outlines
(`splatFootprints`) and the last two a print pass (`engraving`): the bake names those and stops (each checked on one ball at
`e8cef0c`, set as its guide sets it).

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
3. **One cloth**, `K.cloth(B, o)` before the finish and `K.stage(W).add(cloth)` after (README, Physics and persistent effects; the
   options are in the opening comment of `src/kit/ks-xpbd.js` and the table below). Every frame of it is stored, 9 bytes a dab a
   frame. A worked cape: references/recipes.md, 12.
   - **Shape**: `pattern(u, v)`, with u and v from 0 to 1 across and down, returns the ramp for the cloth there, or `null` to leave
     that part out: a cape narrow at the shoulder and ragged at the hem is a rectangle with `null` outside its outline.
   - **Shading**: each dab takes the colour at floor(l × ramp length) of its ramp, l = `amb` + `sunK` × how squarely it faces `sun`
     (0.3 and 0.75 unless given). Square to the sun, l passes 1 and the top colour shows: end the ramp at the brightest colour you
     want, or repeat its middle colours (a cape whose ramp ended in a pale tone came out skin-pale).
   - **Loop**: the wind must repeat every loop, built from sines of 2π k t / L with whole k; `K.xpbd.gust` never repeats. The bake
     prints how far the cloth is from where it began a loop on, `cloth: ... a whole loop on, it is 0.0000 world units from where it
     began` when it has closed, and does not stop on it. The GIF's seam check can miss an open loop: a flag 0.34 units out (over ten art
     pixels) gave 3,364 pixels changing from the last frame to the first, inside its 1,280 to 3,688 between neighbouring frames.
     `damp` (0.6 a second unless given) is how fast the cloth's motion dies away and `density` how heavy it is; neither closes the
     loop steadily, so bake a few values. Measured, each a loop on:
     - A flag of 1.6 by 1 units (22 by 14 points) on a pole, an art pixel 0.032 units, in a wind of 3 ± 1.2 units a second along
       it and 1 ± 0.8 across: 0.13 to 0.40 at every `damp` from 0.6 to 8 but 3 (0.0001); at `density` 0.6, 0.19 to 0.76 but 0.0000
       at 3. In half that wind: 0.015 to 0.030 up to `damp` 4.5, 0.007 at 6, 0.0000 at 8. In a quarter of it: 0.058 at the default,
       0.007 to 0.049 above it.
     - One cloak (20 by 12 points), an art pixel about 0.035 units, at `damp` 0.6 and 4.5: at `density` 0.3 it closed to 0.006 and
       0.003; at 0.6 it missed by 0.16 and 0.23; at 1.0 by 0.48 and 0.05.
     - The cloth of a trial scene of 213,405 splats, an art pixel about 0.037 units: 0.118 at the default `damp`, 0.0000 at 4.5.

     Keep the cloth light and the wind gentle, then try `damp` from 3 to 8.
   - **Outlines**: its dabs draw no depth (`nd`), so the outline and contact shade of whatever is behind show through it, here and in
     ink-studio's own pictures. No setting changes that: hang it before a plain surface, or keep the outline off.
   - **Options**, read from `src/kit/ks-xpbd.js` (its opening comment and `K.cloth`) at `e8cef0c` and each baked once on the flag
     above in half its wind (1,092 dabs; 0.0285 units a loop on). All of them bake: the file stores every frame of the cloth. Each
     moved where the cloth ends a loop on, either way (from 0.0000 with `bend: 1e-2` to 0.77 with `gravity: [0, -5, 0]`).

     | Option | Default | What it does | Baked once with |
     | --- | --- | --- | --- |
     | `at`, `u`, `v` | `[0, 2, 0]`, `[2, 0, 0]`, `[0, -1.3, 0]` | The top-left corner; the top edge and the side, as vectors | `[0.04, 2.6, 0]`, `[1.6, 0, 0]`, `[0, -1, 0]` |
     | `nu`, `nv` | 22, 14 | Points across and down | 30 by 18: 1,972 dabs |
     | `dabs` | 2 | Dabs across each cell | 3: 2,457 dabs |
     | `pins`, `pinAt` | the left edge | `pins(i, j)` true for held points; `pinAt(i, j, p0, t)` where they are held, for pins that move | The top edge; the left edge bobbing |
     | `pattern` | `[1, 2, 3]` everywhere | `pattern(u, v)`: a ramp, or `null` to leave that part out | Two ramps, top and bottom |
     | `amb`, `sunK`, `sun` | 0.3, 0.75, `[-0.5, 0.7, 0.5]` | The shading above | 0.4, 0.6, straight up: the dabs moved to their ramps' lighter places |
     | `wind`, `air` | none, 1.2 | `wind(x, y, z, t)` gives the air's velocity; `air` how hard it pushes | `air: 0.6` |
     | `density`, `mass` | 0.25 | How heavy, in kg a square metre; `mass` sets each point's own instead | 0.4; 0.002 |
     | `damp` | 0.6 | How fast its motion dies away, a second | 3 |
     | `stretch`, `shear`, `bend` | 1e-6, 1e-5, 2e-3 | Softness along, across and over the folds; higher is softer | 1e-4, 1e-3, 1e-2 |
     | `gravity` | `[0, -9.8, 0]` | | `[0, -5, 0]` |
     | `substeps` | 6 | Solver steps a frame | 10: baked in 6.9 s against 4.5 |
     | `sdf`, `thick` | none, 0.02 | A field it does not pass through (the sculptor's `S.sdf`) and how far it keeps off it | `S.sdf`, 0.05 |
     | `spheres`, `friction` | none, 0.4 | Balls `{ c, r }` it does not pass through (move `c` as they move); friction where it touches | One ball; 0.1 |
     | `tear` | none | A link breaks for good past `tear` times its length | 1.05 |

     Read and not baked: `sim` (one solver shared by several cloths; a second cloth is not carried), and the solver's hooks
     `acceleration`, `project`, `fixedStep`, `substepPins` and `onTear`, which the comment does not list.

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
| The same, one pixel an art pixel, at the kit's moment | `... render scene.js --w 1440 --h 960 --px1 --t 120 --out /abs/native.png` | 480 by 320; `--t 120` is 15 loops of 8 s (below) |
| Another angle, another moment | `... render scene.js --w 1440 --h 960 --yaw 2.4 --pitch 0.5 --t 3 --out /abs/angle.png` | Radians and seconds |
| All round | `... turn scene.js --n 4 --w 720 --h 480 --out /abs/turn.png` | Four views in one strip, 2880 by 480 |
| Closer, about one spot | `... render scene.js --w 1440 --h 960 --zoom 3 --target x,y,z --out /abs/zoom.png` | A finer grid than the player's: it shows detail the player will not. The picture is whole art pixels of the finer grid, so it can come out a few pixels over the size asked (1442 by 966 at `--zoom 3`) |
| Counts and palette use | `... stats scene.js` | Its `picture` line is for its own 900 by 620 frame, not the stage |

- **The kit's clock.** The bake walks the scene 15 loops before it stores a frame (so a cloth settles), and the kit's still, the
  proof's pictures and the GIF are drawn at that clock: 120 s for the start of an 8 s loop, 120 plus the time into the loop for any
  other moment. ink-studio's command line starts at 0, so pass `--t 120` (or 120 plus the moment) to see what the kit will show.
  Rigid parts and whole cycles of a kind look the same either way; a sway's second motion and a cloth do not. Measured against the
  kit's `still.png`: a trial scene (32,806 splats, swaying grass) differs in 55 of 86,400 art pixels at `--t 120`,
  51 of them lone, as the proof's own opening view does, and in 984 at the default 0, in runs on the grass; ink-studio's `cloth.js`
  in 4 of 21,600 at `--t 120` and 913 at 0, its cloth not yet settled; `sculpt.js` in none either way.
- **The preview is for looking; the proof is the test.** `kit/verify.cjs` is what says the baked file draws what the scene draws.
- **Zoomed crops at the player's grid**: crop the `--px1` picture and enlarge it by a whole number with nearest-neighbour scaling, in
  any image tool (with Pillow: `Image.open(p).crop(box).resize((w * 8, h * 8), Image.NEAREST)`). That is how letter, face and glass
  sizes in references/recipes.md were judged.
- **Side by side with the kit**: the `--px1 --t 120` picture and the kit's `still.png` (from `kit/stills.cjs`, after a bake) are the
  same size; put them next to each other, or count the pixels that differ. ink-studio's own `compare <scene> <ref.png>` draws the
  scene beside a reference, but at its own frame size, not the stage's, so it does not line up with the kit's still (checked).
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
| WebGPU graphs and Gaussian splat import | GPU texture and geometry graphs; a viewer and `render --raw` for trained splat files (PLY, SPZ) | No: a separate output (not baked here) |
| Live show control | Live audio, MIDI, timecode, projection and lighting control | No: a world run |
| CLI patch tooling | `ink-studio patch`: typed graph ports and signals | No: a separate output |
| Screen transitions | Full-screen WebGL transition presets | No |
| Module reference | What each `src/` file holds | Where to read an API's opening comment |
| Validation and development | `npm test`, `npm run lint`, `snap`, `check` | No |
| License | MIT; then notes on toolkit modules and links to the surface-mark guides (render grids, splat footprints, brush strokes, engraving, mosaics, screen print, stippling, contour ribbons, facets, cut paper, voxels, textiles, sprite reconstruction) | The kit calls ink-studio, never copies it; each mark guide's row is in section 4 |

## 4. Guides and examples by what you are making

Every guide in `docs/` and every file in `examples/` as of `e8cef0c`, grouped by what a scene-maker is after. Read the Travels column
first: a feature that does not travel is still good for pictures made with ink-studio itself, but the player will not draw it.

**Travels** (the guide's feature):

- **Yes**: what it makes are ordinary solids or splats.
- **At build**: it computes numbers, paths, patterns or colours while the scene builds; turn them into solids, splats, ramps or `tex`
  choices and those travel.
- **No** with a reason: look (per-pixel), sky, renderer (drawn per view or live), bones, particles, physics, a world run (simulated
  worlds, agents, sound), screen layer, sprites, flat splats, export or browser (a separate output).
- **Tool**: works on scene files or pictures; nothing to bake. **Not run**: not tried for this map.

**Examples** were each baked with this kit (an 8-second loop; two minutes at most), then again with the world fields the format does
not carry deleted:

- **Bakes** (splats): as it is. 29 examples.
- **Solids only** (splats; what it loses): after the deletion. 135 examples; most lose only their per-pixel look, and the
  curve-splat scene files their curve splats. Five bake only once the kit's loop helper (`kit/loop.cjs`) rounds their speeds to
  whole cycles of the loop, and say so.
- **No** (reason): refused even then. Bones; live motion (splats redrawn or moved each frame by the example's own code, particles or
  physics); off-palette colours; colour changes; wind-field sways; growth; particles; flat splats; kind 15; sprites it sets again
  as it plays; needs its camera rig; all look (nothing left once the look is gone); not proven (over two minutes). 107 examples.
- **Not a scene**: a command's input, a world run, a command script, or a script that needs its page. 651 files. **Page**: an HTML
  page and its scripts for ink-studio's browser renderer. 65 files.

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
- New since `cf35ff8`: none of the 170 guides travels as it is. Most are world runs and sound, per-pixel looks and marks, and
  renderer features; the 11 since `e80d985` work from recorded stories and world runs, apart from one renderer feature for
  imported splats.

### Shape

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `adaptive-sculpt-sampling.md` | Fewer splats on broad faces, more on edges and tight curves | Yes | **Solids only:** `adaptive-lantern.js` (2,456; loses look) |
| `adaptive-transport.md` | Flow across a graph, for tube widths and colours | At build | **No:** `adaptive-transport-studies.js` (live motion) |
| `contour-ribbons.md` | Fields traced into ribbons of surface marks | No: flat splats | **Not a scene:** `contour-ribbons.js` (needs a host page). **Page:** `contour-ribbons.html` |
| `curvature-lines.md` | Principal-direction traces for ornament, shingles and scales | At build | **No:** `curvature-ornament-studies.js` (live motion) |
| `curve-analysis.md` | Nearest points and frames along curves | At build | **Not a scene:** `curve-analysis.js` (not a scene). **Page:** `curve-analysis.html` |
| `curve-families.md` | Parametric curves for sweeps, routes, lettering and cameras | At build | **Solids only:** `rolling-curve-gallery.js` (30,046; loses look). **No:** `gear-lantern.js` (live motion). **Not a scene:** `curve-families.js` (not a scene). **Page:** `curve-families.html` |
| `curve-splats.md` | Paths drawn as joined splat segments | No: renderer | **Solids only:** `curve-splat-bundles.js` (375; loses curve splats, look, live light), `curve-splat-caps.json` (221; loses curve splats, look), `curve-splat-edges.json` (72; loses curve splats, look), `curve-splat-profiles.json` (505; loses curve splats, look), `curve-splat-scene.json` (41; loses curve splats, look), `curve-splat-sections.json` (286; loses curve splats, look). **No:** `curve-mode-signal-coil.js` (off-palette colours), `curve-quality-harp.js` (bones), `curve-splat-bindings.js` (live motion), `curve-splat-materials.json` (off-palette colours), `surface-bound-strokes.js` (off-palette colours). **Not a scene:** `curve-depth-crossings.cjs` (command script), `curve-distance-simplification.cjs` (command script), `curve-splat-bindings.cjs` (command script), `curve-splat-bundles.cjs` (command script), `curve-splat-caps.cjs` (command script), `curve-splat-coverage.cjs` (command script), `curve-splat-edges.cjs` (command script), `curve-splat-gallery.cjs` (command script), `curve-splat-lighting.cjs` (command script), `curve-splat-materials.cjs` (command script), `curve-splat-minimum-width.cjs` (command script), `curve-splat-profiles.cjs` (command script), `curve-splat-sections.cjs` (command script), `curve-stable-pigment.cjs` (command script), `surface-bound-strokes.cjs` (command script), `timed-curve-trails.cjs` (command script) |
| `depth-maps.md` | Depth images to splats, fields and meshes | At build, with palette colours | **No:** `depth-map.js` (off-palette colours) |
| `differential-growth.md` | Curves and shells that grow and buckle | At build | **Solids only:** `differential-growth-studies.js` (23,961; loses look) |
| `faceted-surfaces.md` | Surfaces rebuilt as flat facets | No: flat splats | **Not a scene:** `faceted-surfaces.js` (needs a host page). **Page:** `faceted-surfaces.html` |
| `field-fabrication.md` | Fields turned into shells, ribs and cut-throughs | Not run | **No:** `field-fabrication-studies.js` (live motion) |
| `field-visualization.md` | Geometry extracted from scalar and vector fields | Not run | none |
| `four-dimensional.md` | 4D polytopes and slices | At build | **No:** `fourth-gate.js` (live motion) |
| `fractal-forms.md` | Bounded 3D fractals for `S.implicitForm` | Yes | **Solids only:** `fractal-form-studies.js` (209,138; loses look) |
| `gaussian-part-proxies.md` | Strokes and meshes drawn among imported Gaussian splats | No: renderer | **Page:** `gaussian-part-proxies/demo.mjs`, `gaussian-part-proxies/index.html` |
| `headless-authoring.md` | Typed procedural graphs | What it makes as solids | **Bakes:** `editable-passage.js` (7,900). **Solids only:** `flooded-shrine.js` (17,675; loses look, sky and air, its saved snapshot). **No:** `graph-study.js` (bones), `mesh-index-scramble.js` (sprites it sets again as it plays), `stale-instance-transforms.js` (live motion). **Not a scene:** `bitplane-corruption.cjs` (command script), `block-substitution.cjs` (command script), `broadcast-patterns.cjs` (command script), `camera-motion-compensation.cjs` (command script), `cross-bank-tile-bleed.cjs` (command script), `dense-optical-flow.cjs` (command script), `drawing-layout.cjs` (command script), `graph-3d-rig.cjs` (command script), `indexed-plasma.cjs` (command script), `layer-clocks.cjs` (command script), `local-palette-fault.cjs` (command script), `masked-time-maps.cjs` (command script), `motion-driven-deformation.cjs` (command script), `palette-cycling.cjs` (command script), `persistent-region-tracking.cjs` (command script), `pixel-effects.cjs` (command script), `procedural-generation.cjs` (command script), `raster-composition.cjs` (command script), `raster-palette.cjs` (command script), `raster-simulations.cjs` (command script), `raster-warps.cjs` (command script), `region-lineage-events.cjs` (command script), `scanline-deformation.cjs` (command script), `scanline-repeat-dropout.cjs` (command script), `signal-recovery.cjs` (command script), `sprite-fragment-desync.cjs` (command script), `texture-addressing.cjs` (command script), `tile-address-scrambling.cjs` (command script), `tile-stride-slip.cjs` (command script), `tracked-drawing-anchors.cjs` (command script) |
| `hyperbolic-mosaics.md` | Poincare-disk tilings and circle packing | Yes | **Solids only:** `disk-studies.js` (13,254; loses look) |
| `iterated-function-systems.md` | Fractal flames as points or density | At build | **Solids only:** `iterated-flame-studies.js` (47,378; loses look) |
| `mosaic-surfaces.md` | Surfaces rebuilt as mosaic or stained-glass pieces | No: look | **Not a scene:** `mosaic-surfaces.js` (needs a host page). **Page:** `mosaic-surfaces.html` |
| `orbit-attractors.md` | Attractor orbits as paths or density | At build | **Solids only:** `orbit-attractor-studies.js` (16,643; loses look) |
| `paper-relief.md` | Layered cut-paper sheets with thickness | No: flat splats | **Not a scene:** `paper-relief.js` (needs a host page). **Page:** `paper-relief.html` |
| `procedural.md` | Every procedural primitive: fields, sampling, terrain, routes, buildings, growth, fracture | Geometry and placement | **Bakes:** `adaptive-surface.js` (8,564), `branching-networks.js` (14,544), `colony-patterns.js` (67,178), `composed-fields.js` (9,446), `constraint-tiles.js` (46,483), `dual-surface-studies.js` (5,836), `flow-wake.js` (21,895), `fluid-grids.js` (27,173), `fracture-studies.js` (24,702), `persistent-weather.js` (27,867), `pinned-facade.js` (30,158), `poisson-patches.js` (7,353), `river-processes.js` (15,444), `rooms-and-caves.js` (23,554), `route-fields.js` (14,595), `sampling-detail.js` (6,815), `sculptural-fields.js` (37,407), `socket-walkway.js` (48,812), `street-layouts.js` (21,848), `terrain-route.js` (20,615), `texture-synthesis.js` (29,607), `vegetation-growth.js` (25,732), `watershed.js` (15,782), `weighted-roof.js` (82,361). **Solids only:** `contact-masks.js` (18,892; loses look), `material-masks.js` (21,634; loses look). **No:** `preview-lod.js` (off-palette colours), `surface-advection.js` (off-palette colours), `transport-morph.js` (off-palette colours). **Not a scene:** `biome-flood.js` (needs a host page), `biome-recipes.js` (needs a host page), `biome-world.js` (needs a host page), `procedural/build.js` (not a scene), `streamed-places.js` (needs a host page) |
| `proportional-layout.md` | Golden-ratio subdivision for facades, trim and shots | At build | **Solids only:** `proportional-facade.js` (31,138; loses look). **No:** `proportional-shots.js` (not proven, over two minutes) |
| `quasiperiodic-tilings.md` | Penrose and Ammann-Beenker pavements | Yes | **Solids only:** `quasiperiodic-plazas.js` (35,982; loses look) |
| `recursive-curves.md` | Koch, dragon, Hilbert and Peano curves | At build | **Solids only:** `recursive-curve-studies.js` (19,185; loses look) |
| `shared-field-outputs.md` | Named field samples shared between generators | At build | **No:** `shared-field-outputs.js` (off-palette colours) |
| `surface-phyllotaxis.md` | Golden-angle placements on spheres and charts | At build | **No:** `surface-phyllotaxis.js` (growth) |
| `textile-rendering.md` | Raised yarn, stitches and weaves | No: look | **Not a scene:** `thread-studies.js` (needs a host page). **Page:** `thread-studies.html` |
| `topological-surfaces.md` | Mobius, Klein and minimal surfaces | Not run | **No:** `topological-surface-studies.js` (live motion) |
| `typography.md` | Lettering as solids, sprites or strokes (references/recipes.md, Lettering) | As solids | **Not a scene:** `typography.js` (not a scene). **Page:** `typography.html` |
| `voxel-surface.md` | Surfaces as voxel faces | No: look | **Not a scene:** `voxel-surface.js` (needs a host page). **Page:** `voxel-surface.html` |
| `weaving-braiding.md` | Strands with over-under crossings | At build | **No:** `interlacing-studies.js` (live motion) |

### Surface

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `boundary-cels.md` | Drawn cels along the seam between materials | No: look | **Not a scene:** `frost-boundaries.cjs` (not a scene) |
| `boundary-potential-fields.md` | A solved potential as pigment, contours or flow | At build | **No:** `boundary-potential-studies.js` (not proven, over two minutes) |
| `caused-marks.md` | Drips, scuffs, lichen and wear along a trail baked as paint layers | No: look | **Solids only:** `caused-marks.js` (75,901; loses look, sky and air). **Not a scene:** `event-surface-marks.js` (not a scene) |
| `cellular-lattices.md` | Cellular automata on lines, grids and voxels | At build | **Solids only:** `cellular-lattice-studies.js` (12,220; loses look) |
| `competitive-growth.md` | Growth fronts claiming a grid, with seams | At build | **Solids only:** `competitive-growth-studies.js` (23,612; loses look) |
| `complex-plane-fields.md` | Mandelbrot, Julia and Newton patterns | At build | **Solids only:** `complex-plane-studies.js` (16,650; loses look) |
| `contact-marks.md` | Drawn pixel effects at contact points | No: look | **No:** `contact-mark-studies.js` (all `look`) |
| `continuous-cellular.md` | Lenia and SmoothLife fields | At build | **No:** `continuous-cellular-studies.js` (live motion) |
| `continuous-splat-coverage.md` | Opaque surfaces joined without gaps | No: look | **Solids only:** `splat-surface-coverage.js` (8,760; loses look) |
| `coupled-phase-changes.md` | Ice, liquid and pigment reactions on a grid | At build | **No:** `phase-change-studies.js` (live motion). **Not a scene:** `spillway-phase.cjs` (not a scene) |
| `deformation-materials.md` | Ink, wear and wetness kept in a rest chart | Not run | none |
| `edge-filter.md` | Coverage-filtered edges | No: look | **Solids only:** `selective-edge-filter.js` (6,350; loses look) |
| `engraving.md` | Hatching, cross engraving and woodcut shading | No: look | **Not a scene:** `engraving.js` (needs a host page). **Page:** `engraving.html` |
| `glyph-grids.md` | Glyph grids and letterforms from cell rules | At build | **No:** `glyph-grid.js` (live motion), `signal-fall.js` (all `look`) |
| `graph-automata.md` | Cell rules on connected objects | At build | **No:** `graph-automata-studies.js` (live motion) |
| `learned-cellular-growth.md` | A small neural cell rule growing ornament | At build | **No:** `learned-cellular-growth.js` (live motion) |
| `material-controls.md` | Roughness, metal, refraction and coatings | No: renderer | **Not a scene:** `material-controls.js` (not a scene). **Page:** `material-controls.html` |
| `math-fields.md` | Complex charts, vector fields and chaotic maps for materials and shapes | At build | **Not a scene:** `math-fields.js` (not a scene). **Page:** `math-fields.html` |
| `moire-gratings.md` | Line, dot and polar interference patterns | At build | **Solids only:** `moire-grating-studies.js` (26,328; loses look) |
| `motional-coverage.md` | Thin splats kept steady as they cross pixels | No: look | **Solids only:** `motional-coverage.js` (12,406; loses look) |
| `persistent-spatial-fields.md` | Deposits kept in a chart or volume | At build | **No:** `persistent-spatial-fields.js` (live motion) |
| `pixel-look.md` | Tone, stipple, remaps, colour tables and stacks | No: look | **Solids only:** `authorized-dither-pairs.js` (43,398; loses look, sky and air), `look-blending.js` (48,865; loses look), `palette-constraints.js` (44,091; loses look), `palette-material-matching.js` (35,317; loses look, sky and air), `palette-placement.js` (44,101; loses look, sky and air), `protected-swatches.js` (37,558; loses look, sky and air), `provenance-relays.js` (56,042; loses look), `rgb-lut.js` (28,609; loses look), `shared-look-selectors.js` (24,533; loses look), `wet-spillway.js` (48,865; loses look) |
| `pixel-stamps.md` | Indexed pixel drawing and animated stamps | No: sprites | **Solids only:** `red-spring.js` (16,867; loses look), `starfall-window.js` (1,222; loses look). **No:** `glitter-burst-reel.js` (all `look`), `pixel-effect-presets.js` (all `look`). **Page:** `pixel-stamp-editor.html`, `pixel-stamp-editor.mjs` |
| `pixel-tiles.md` | Animated pixel tiles along a grid | No: sprites | **No:** `reconnecting-grids.js` (all `look`), `tile-pulse-studies.js` (all `look`) |
| `projected-effects.md` | Animated rasters and patterns on surfaces | No: look | **Solids only:** `palette-cycling.js` (56,006; loses look, sky and air). **No:** `banded-pigment.js` (live motion), `surface-effects.js` (live motion). **Not a scene:** `edge-shedding.js` (needs a host page) |
| `reaction-diffusion-brushing.md` | Gray-Scott patterns painted on charts | At build | **No:** `reaction-diffusion-brushing.js` (live motion) |
| `recursive-coordinate-transforms.md` | Mobius maps, inversion and Droste recursion | At build | **Solids only:** `recursive-coordinate-studies.js` (13,126; loses look) |
| `render-grids.md` | The picture as hexagon, triangle or diamond cells | No: look | **Not a scene:** `render-grid.js` (needs a host page). **Page:** `render-grid.html` |
| `rule-board.md` | Copper tracks and glyphs run as a cell rule | No: sprites | **Not a scene:** `rule-board.cjs` (not a scene) |
| `sandpiles-excitable.md` | Sandpiles and excitable media | At build | **No:** `sandpiles-excitable-studies.js` (live motion) |
| `scalar-wave.md` | Waves diffracting through gaps | At build | **Solids only:** `wave-propagation-studies.js` (33,126; loses look) |
| `screen-print.md` | Halftone and screen-printed plates | No: look | **Not a scene:** `screen-print.js` (needs a host page). **Page:** `screen-print.html` |
| `sdf-assist.md` | Tracing sculpted surfaces at render time | No: renderer | **Solids only:** `sdf-gatehouse.js` (15,314; loses look, sky and air, live light) |
| `shared-domains.md` | One cell rule on images, charts, graphs and voxels | At build | **No:** `shared-domain-studies.js` (live motion) |
| `spectral-fields.md` | Fourier fields and membrane modes | At build | **No:** `spectral-wave-studies.js` (live motion) |
| `splat-footprints.md` | Square, star, chipped or painted splat outlines | No: look | **Not a scene:** `splat-footprints.js` (needs a host page). **Page:** `splat-footprints.html` |
| `stable-detail.md` | Fine detail eased in and out by size | No: look | **Solids only:** `stable-detail.js` (3,290; loses look) |
| `stable-dithering.md` | Screen, world or object dither | No: look | **Solids only:** `palette-dither-scale.js` (42,304; loses look, sky and air, camera rig), `palette-dither-spaces.js` (42,304; loses look, sky and air), `stable-dithering.js` (88,073; loses look, sky and air), `view-direction-dithering.js` (46,069; loses look, sky and air) |
| `stippling.md` | Adaptive stipple and pointillist marks | No: look | **Not a scene:** `stippling.js` (needs a host page). **Page:** `stippling.html` |
| `surface-brush.md` | Brush strokes that follow the form | No: look | **Not a scene:** `surface-brush.js` (needs a host page). **Page:** `surface-brush.html` |
| `surface-brushwork.md` | A paint layer of strokes over a sculpt | No: look | **Solids only:** `surface-brushwork.js` (43,405; loses look, sky and air) |
| `surface-materials.md` | View-dependent finishes | No: renderer | **Solids only:** `color-curves.js` (41,906; loses look), `material-bevel-highlights.js` (35,065; loses look), `material-lighting-ramps.js` (26,328; loses look), `surface-detail-courtyard.js` (34,177; loses look, sky and air, live light), `surface-gallery.js` (27,053; loses look), `thin-transmission.js` (31,625; loses look, sky and air, live light) |
| `textured-surfaces.md` | Optional pixel-textured patches | No: sprites | **Solids only:** `textured-surfaces.js` (6,580; loses look). **No:** `material-projection.js` (all `look`), `uv-atlas-slip.js` (all `look`). **Not a scene:** `palette-resampling.cjs` (command script) |
| `tile-attributes.md` | Two-colour tiles from a palette map | No: look | **Not a scene:** `tile-attributes.cjs` (not a scene) |
| `trail-sensing-agents.md` | Agents that lay and follow trails | At build | **Solids only:** `trail-sensing-studies.js` (23,263; loses look) |
| `translucent-silhouettes.md` | Own coverage for steam, glass rims and foliage | No: look | **Solids only:** `translucent-silhouettes.js` (6,178; loses look) |
| `vector-field-painting.md` | Line integral convolution grain | At build | **No:** `vector-field-painting-studies.js` (not proven, over two minutes) |
| `visual-consequences.md` | Scorch, repair seams and trail wear from a simulated world's state | No: a world run | **Not a scene:** `visual-consequences/demo.cjs` (command script) |
| `wallpaper-frieze.md` | A motif repeated as pigment, relief or tiles | At build | **Solids only:** `wallpaper-frieze.js` (14,434; loses look) |

### Light

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `area-lights.md` | Rectangle and disc lights with soft shadows | No: renderer | **Solids only:** `shaped-lights.js` (15,083; loses look, live light) |
| `bounce-probes.md` | Local colour bleeding at render time (baked bounce, `INK_BOUNCE`, does travel) | No: renderer | **Solids only:** `bounce-probes.js` (27,882; loses look, sky and air, live light) |
| `contact-shadows.md` | Short contact shadows at render time (the finish's `ao` travels) | No: look | **Solids only:** `local-contact-shadows.js` (13,193; loses look) |
| `emission-bands.md` | Travelling bands of glow from a distance field | No: look | **No:** `tuning-gate.js` (all `look`) |
| `fog-lighting.md` | Spot and point lights in fog | No: renderer | **Solids only:** `light-cookies.js` (39,441; loses look, sky and air), `lighthouse-mist.js` (100,171; loses look, sky and air) |
| `geometric-caustics.md` | Coloured light through authored glass | No: renderer | **Solids only:** `geometric-caustic-studies.js` (31,379; loses look, sky and air, live light) |
| `highlight-cels.md` | Drawn highlights chosen by a light and the camera | No: look | **No:** `highlight-cel-bench.js` (live motion) |
| `light-emitters.md` | Line lights, cookies and shaped emitters | No: renderer | **Solids only:** `light-emitters.js` (38,051; loses look, sky and air, live light). **Page:** `light-emitters.html` |
| `live-sun.md` | A sun relit at render time (bake light with `S.sun`) | No: renderer | **Solids only:** `beacon-pool.js` (19,774; loses look, sky and air, live light), `bounce-light.js` (17,193; loses look, live light), `live-sun.js` (26,722; loses look, live light) |
| `painted-cutout-shadows.md` | Shadows cast through painted cutouts | No: renderer | **No:** `painted-cutout-shadows.js` (live motion), `painted-shadow-shells.js` (live motion) |
| `scene-exposure.md` | Indoor and outdoor exposure zones | No: world field | **No:** `sheltered-arch.js` (wind-field sways) |
| `scene-optics.md` | Index of reflections, ripples and optics | No: renderer | **Solids only:** `cliff-depth-bands.js` (129,910; loses sky and air), `layered-transparency.js` (8,229 with the kit's loop helper; loses look, sky and air, live light, weather), `local-reflection-workshop.js` (48,958; loses look, sky and air, live light), `optical-look-bindings.js` (41,967; loses look, sky and air, live light), `reflection-detail.js` (48,958; loses look, sky and air, live light), `water-garden.js` (32,252; loses look, live light). **Page:** `water-garden.html` |
| `shadow-band-paint.md` | Painted shifts of where shadow starts | No: look | **No:** `painted-shadow-bands.js` (live motion). **Page:** `painted-shadow-bands.html` |
| `shot-lighting.md` | A shaped key, fill and rim light for a shot | No: renderer | **Solids only:** `courier-shot-lighting.js` (43,848; loses look, sky and air, live light) |

### Colour and palette

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `cluster-coherence.md` | Highlight and shadow clusters kept steady through a shot | No: look | **Not a scene:** `cluster-coherence.cjs` (command script), `shot-correction.cjs` (not a scene) |
| `effect-palettes.md` | Own ramps for fog, clouds, sky and glow | No: look | **Solids only:** `atmosphere-palette-fields.js` (100,171; loses look, sky and air), `effect-palettes-night-watch.js` (158,069; loses look, sky and air), `palette-composition.js` (47,900; loses look, sky and air, live light) |
| `paint-mixing.md` | Spectral paint mixing into ramps | At build | **Not a scene:** `paint-mixing.js` (needs a host page). **Page:** `paint-mixing.html` |
| `palette-recipes.md` | OKLab palette recipes, ramps and paths | At build | **Solids only:** `animated-palette-fields.js` (49,891; loses look, sky and air), `authored-lighting-ramps.js` (41,745; loses look, sky and air), `chroma-glazes.js` (45,563; loses look, sky and air), `grayscale-ramp-reliefs.js` (53,070; loses look, sky and air), `hue-brightness.js` (63,002; loses look, sky and air), `palette-chart-archive.js` (176,463; loses look, sky and air), `palette-coverage.js` (58,397; loses look, sky and air), `palette-field-weather.js` (56,810; loses look, sky and air, weather), `palette-space-plots.js` (30,583; loses look, sky and air), `polar-colour.js` (40,833; loses look, sky and air), `render-stages.js` (24,533; loses look), `shadow-readability.js` (51,673; loses look, sky and air), `spectrum-ramps.js` (103,467; loses look, sky and air), `surface-palette-roles.js` (41,224; loses look, sky and air). **Not a scene:** `palette-recipes.js` (not a scene). **Page:** `palette-recipes.html` |

### Motion and loops

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `animated-splat-fields.md` | World-space animated splat fields | No: renderer | **No:** `animated-splat-fields.js` (off-palette colours) |
| `cloth-review.md` | Pinning and reviewing a cloth | The cloth itself | **No:** `cloth-review.js` (bones). **Page:** `cloth-review.html` |
| `destruction.md` | Existing splats broken into rubble | No: physics | **No:** `destruction.js` (particles). **Page:** `destruction.html` |
| `field-particle-coupling.md` | Particles and a fluid grid moving each other | No: particles | **Solids only:** `field-particle-studies.js` (22,171; loses look) |
| `geometry-morphs.md` | Splat morphs between poses | No: morph | **No:** `geometry-morph-studies.js` (live motion) |
| `jointed-sprite-chains.md` | Drawn pixel stamps on spring chains | No: sprites | **No:** `jointed-sprite-chains.js` (all `look`) |
| `loop-authoring.md` | Finding repeats and fitting tracks to a loop | Tool | **No:** `loop-authoring-studies.js` (live motion) |
| `materialisation.md` | Splats detaching, flowing and rejoining | No: live motion | **No:** `materialisation.js` (live motion). **Page:** `materialisation.html` |
| `motion-afterimages.md` | Trails of past poses | No: look | **Not a scene:** `subject-feedback.cjs` (command script) |
| `pixel-scanner.md` | Surfaces scanned by a moving emitter, kept as splats | No: live motion | **No:** `flooded-station-scan.js` (live motion) |
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
| `silhouette-tracks.md` | Drawn exposures for a scarf, brim or sleeve | No: sprites | **No:** `silhouette-tracks.js` (all `look`). **Not a scene:** `sprite-cel-preview.cjs` (not a scene) |
| `traversal-links.md` | Rails, boosts and flows for a character | No: a world run | **Not a scene:** `traversal-links.js` (not a scene) |

### Weather and air

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `aerial-perspective.md` | Distant colour and extinction from the sky | No: sky | **Solids only:** `aerial-perspective.js` (132,728; loses sky and air) |
| `atmosphere-emitters.md` | Smoke, steam and spray from a socket | No: particles | **Solids only:** `atmosphere-railway.js` (135,453; loses look, sky and air, weather) |
| `celestial-tracks.md` | Suns, moons and stars on paths | No: sky | **Solids only:** `celestial-estuary.js` (241,557; loses look, sky and air) |
| `cloud-recipes.md` | Procedural cloud fields | No: sky | **Solids only:** `cloud-recipe-coast.js` (122,554; loses look, sky and air, live light) |
| `cloud-representations.md` | Clouds as cards and impostors by distance | No: sky | **Solids only:** `beacon-cloud-self-shadows.js` (26,722; loses look, sky and air, live light, weather). **No:** `cloud-flythrough.js` (particles) |
| `cloud-shadows.md` | Moving cloud coverage and shadows | No: sky | **Solids only:** `cloud-shadows.js` (122,554; loses look, sky and air, live light) |
| `conditional-weather.md` | Weather changes on cues | No: sky | none |
| `environment-packs.md` | Reusable sky and weather presets | No: sky | none |
| `geometry-shaped-atmosphere.md` | Fog and cloud shaped by geometry | No: sky | **Solids only:** `shaped-mist-ravine.js` (181,969; loses look, sky and air) |
| `interruptible-sky.md` | Sky transitions started mid-way | No: sky | **No:** `interruptible-sky.js` (wind-field sways) |
| `layered-horizon.md` | A painted far vista on cylinders (references/recipes.md has a far backdrop that travels) | No: world field | **Solids only:** `layered-horizon.js` (38,447; loses look, sky and air) |
| `lightning.md` | Timed lightning flashes | No: world field | **Solids only:** `lightning-headland.js` (120,602; loses look, sky and air) |
| `material-histories.md` | Wear and weathering kept on surfaces | No: weather | **Solids only:** `material-histories.js` (61,436; loses look, sky and air, weather) |
| `rain-impacts.md` | Rain hitting planes | No: weather | **Solids only:** `rain-cistern.js` (93,913 with the kit's loop helper; loses look, sky and air, live light, weather) |
| `retained-weather.md` | Wetness, snow and frost that stay | No: weather | **Solids only:** `wet-stone-finish.js` (41,173; loses look, sky and air, weather). **No:** `weather-traces.js` (kind 15) |
| `shared-sky-reflections.md` | One sky for backdrop and reflections | No: sky | **Solids only:** `shared-sky-reflections.js` (41,061; loses look, sky and air, live light) |
| `shore-foam.md` | Drawn foam along water edges | No: sprites | none |
| `volume-cutouts.md` | Clear pockets in fog and cloud | No: sky | **No:** `volume-cutout-gate.js` (bones) |
| `weather-binding.md` | Weather profiles across systems | No: sky | **No:** `weather-courtyard.js` (wind-field sways) |
| `weather-fronts.md` | Fronts moving over the world | No: weather | none |
| `wind-field.md` | One wind for clouds, foliage and smoke (its sways are refused; plain sways travel) | No: world field | **No:** `windbreak.js` (wind-field sways) |
| `world-precipitation.md` | Rain and snow in world space | No: weather | **No:** `lantern-squall.js` (kind 15) |

### Composition

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `art-direction.md` | Look profiles (painted, storm, dawn) | No: look | **Solids only:** `art-direction-estuary.js` (241,557; loses look, sky and air). **No:** `motion-cadence.js` (wind-field sways) |
| `camera-atlas.md` | Several cameras into overlays and panels | No: renderer | **Solids only:** `camera-atlas.js` (16,722; loses look; its bake took 139 s). **No:** `composite-video.js` (all `look`) |
| `camera-impulses.md` | Camera shake and handheld motion | No: camera | **No:** `directional-camera-impulses.js` (particles). **Page:** `directional-camera-impulses.html` |
| `camera-rigs.md` | Camera rigs and shot blends | No: camera | **Solids only:** `camera-staging.js` (38,025; loses look, sky and air, camera rig). **No:** `cinematic-camera.js` (colour changes). **Page:** `cinematic-camera.html` |
| `cutaways.md` | Clipping planes and depth windows | No: renderer | none |
| `data-bound-marks.md` | Marks drawn from data records | No: world field | none |
| `direction-drawing.md` | Editable paths drawn through the camera | No: screen layer | **Not a scene:** `direction-drawing.cjs` (command script) |
| `drawing-primitives.md` | Drawing over the finished picture | No: screen layer | **Not a scene:** `drawing-falloff-studies.cjs` (command script) |
| `drawing-ray-fan.md` | Fans of fine rays in a drawing layer | No: screen layer | none |
| `drawing-registration-grid.md` | Registration guides and crosses | No: screen layer | none |
| `heightmap-flyover.md` | Terrain drawn column by column from height maps | No: renderer | **No:** `heightmap-flyover.js` (all `look`) |
| `impostor-atlases.md` | Camera-facing cards and directional sprites | No: sprites | **Solids only:** `lantern-catch.js` (18,336; loses look, live light), `painted-scenery.js` (13,167; loses look, sky and air, live light), `relightable-impostor.js` (77,572; loses look, sky and air, live light). **No:** `face-transition-cels.js` (all `look`), `sprite-overlay-masks.js` (all `look`), `tidekeeper-fringe.js` (all `look`) |
| `live-scene-hierarchy.md` | One hierarchy for geometry, lights and anchors (rig parts travel) | No: scene graph | **Not a scene:** `live-scene-hierarchy.js` (not a scene). **Page:** `live-scene-hierarchy.html` |
| `mixed-resolution.md` | Layers at their own resolutions | No: look | none |
| `parameter-bindings.md` | Shared controls and bindings | No: world field | none |
| `projected-routes.md` | Painted ribbons and props along a path | No: renderer | **No:** `projected-routes.js` (all `look`) |
| `projected-stage.md` | Painted stage layers under one camera | No: renderer | **No:** `projected-stage.js` (all `look`) |
| `render-graph.md` | An editable graph of render passes | No: look | **Solids only:** `raster-millrace.js` (85,530; loses look, sky and air, live light). **No:** `frame-age-mask.js` (not proven, over two minutes), `motion-smear.js` (all `look`), `raster-tidal-flats.js` (all `look`), `render-feedback.js` (all `look`), `tracked-source-windows.js` (all `look`). **Not a scene:** `block-video-corruption.cjs` (command script), `datamosh.cjs` (command script), `frame-banks.cjs` (command script), `programmable-exposure.cjs` (command script), `raster-schedule.cjs` (command script), `render-effects.js` (not a scene), `render-graph-bridge.cjs` (not a scene). **Page:** `render-effects.html` |
| `render-outputs.md` | One small render shared by atlases, monitors and graphs | No: renderer | **Solids only:** `shared-render-outputs.js` (24,907; loses look). **Not a scene:** `shared-render-inspector.cjs` (command script) |
| `scale-aware-previews.md` | Detail chosen by what the camera resolves | No: world field | **No:** `scale-aware-previews.js` (all `look`) |
| `scene-timeline.md` | One timeline for a diorama | No: world field | **Not a scene:** `beat-phrase-timing.cjs` (command script) |
| `sector-raycaster.md` | A floor plan drawn as rooms from inside | No: renderer | **Not a scene:** `sector-raycaster.cjs` (command script) |
| `silhouette-protection.md` | Fog and contrast kept off a chosen actor | No: look | **Solids only:** `market-shot-focus.js` (45,721 with the kit's loop helper; loses look, sky and air, live light, weather), `silhouette-protection.js` (69,389; loses look, sky and air) |
| `sprite-reconstruction.md` | Distant copies drawn from a directional atlas | No: sprites | **Not a scene:** `bake-sprite-reconstruction.cjs` (command script), `sprite-reconstruction.js` (needs a host page). **Page:** `sprite-reconstruction.html` |
| `sprite-scanline-budgets.md` | Sprite rows dropped past a per-row budget | No: look | **Not a scene:** `sprite-scanline-budget.cjs` (command script) |
| `target-inspection.md` | Brackets, labels and magnifiers over a target | No: screen layer | **Not a scene:** `target-inspection.js` (not a scene). **Page:** `target-inspection.html` |
| `tideline-looks.md` | Four looks over one lighthouse shot | No: look | **No:** `tideline-looks.js` (needs its camera rig). **Not a scene:** `render-tideline-looks.cjs` (command script) |
| `tile-raycaster.md` | A tile map drawn as a view from inside | No: renderer | **No:** `tile-raycaster.js` (all `look`). **Not a scene:** `tile-raycaster-preview.cjs` (command script) |
| `view-annotations.md` | Legends and labels in output pixels | No: screen layer | none |
| `world-reconstruction.md` | Reveal and rebuild tracks | No: look | none |

### Randomness

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `randomness.md` | Named seeded streams and keyed samples, stable under edits | At build | **Not a scene:** `randomness.js` (not a scene). **Page:** `randomness.html` |

### Looking at work

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `art-passes.md` | Depth, normal and emission passes on the art grid | Tool | **Solids only:** `art-effects.js` (590 with the kit's loop helper; loses look), `art-pipeline.js` (19,774; loses look, sky and air, live light), `edge-hierarchy.js` (53,322; loses look, sky and air), `emissive-finishes.js` (43,410; loses look, sky and air, live light), `harbor-compositing.js` (11,418; loses look, live light), `part-motion.js` (12,013; loses look), `selective-ink.js` (38,025; loses look, sky and air). **No:** `strand-inspection.js` (bones), `weather-front.js` (wind-field sways). **Not a scene:** `deep-composite.cjs` (command script) |
| `comparison-views.md` | Two sources at one camera and time | Tool | none |
| `environment-inspector.md` | Explains the sky and weather at a point | Tool | none |
| `environment-review-shots.md` | Three review shots of a sky | Tool | **Solids only:** `review-beacon.js` (26,722; loses look, sky and air, live light, weather), `review-cliff-path.js` (129,910; loses sky and air), `review-sheltered-market.js` (45,721 with the kit's loop helper; loses look, sky and air, live light, weather) |
| `reel.md` | Captures in one offline page | Tool | none |
| `shot-approval.md` | Approval checks over a shot | Tool | none |
| `shot-recipes.md` | Saved inputs behind a review render | Tool | none |
| `surface-probe.md` | Probes that light named points on a pose | No: look | **No:** `hadal-surface-probe.js` (all `look`) |
| `transition-review.md` | A shot checked at export size | Tool | **No:** `transition-review.js` (wind-field sways) |
| `visual-sweeps.md` | One view across settings and seeds | Tool | **No:** `visual-sweep-attractor.js` (live motion) |

### World runs

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `acoustic-queries.md` | Sound through rooms and openings | No: a world run | none |
| `action-windows.md` | Timed actions and contact outcomes | No: a world run | **Not a scene:** `action-windows.js` (not a scene) |
| `actor-performance.md` | Cast, poses, props and lettering driven by a recorded story | No: a world run | **Not a scene:** `actor-performance/demo.cjs` (command script) |
| `adaptive-music.md` | A score that follows the world | No: a world run | none |
| `adaptive-story-audio.md` | A soundtrack printed from a world recording | No: a world run | **Not a scene:** `adaptive-story-audio/demo.cjs` (command script) |
| `agent-decisions.md` | Agents choosing activities | No: a world run | none |
| `agent-needs.md` | Agent needs and shifts | No: a world run | none |
| `agent-orders.md` | Agent orders and tasks | No: a world run | none |
| `agent-storage.md` | Agent rosters, births and removals | No: a world run | none |
| `aggregate-simulation.md` | Coarser simulation far away | No: a world run | none |
| `aligned-simulation-review.md` | Two simulation outputs compared over one take | Tool | **Not a scene:** `aligned-simulation-review/demo.cjs` (command script) |
| `atmosphere-arranger.md` | Ambient sound layers placed around a score | No: a world run | none |
| `audio-editorial.md` | Recordings spotted to picture, events or the score | No: a world run | **Not a scene:** `music-production/editorial-workshop.cjs` (command script) |
| `audio-mixer.md` | Offline mixer routing and automation | No: a world run | **Not a scene:** `music-production/mixer-routing-workshop.cjs` (command script) |
| `audio-prints.md` | Graph audio printed to WAV and reused | No: a world run | **Not a scene:** `music-production/print-workshop.cjs` (command script) |
| `audio-racks.md` | Mixer graphs packaged as racks | No: a world run | **Not a scene:** `audio-racks/clap-smoke.cjs` (command script), `audio-racks/faust-probe.cjs` (command script), `audio-racks/workshop.cjs` (command script) |
| `audio-warp.md` | Recordings warped and repitched | No: a world run | **Not a scene:** `music-production/warp-workshop.cjs` (command script) |
| `audiovisual-takes.md` | Picture driven by an audio take | No: a world run | **Not a scene:** `audiovisual-take/demo.cjs` (command script) |
| `batch-spatial-queries.md` | Proximity and occupancy queries | No: a world run | none |
| `boarding.md` | Seats on carts and ferries | No: a world run | **Not a scene:** `boarding-traversal.js` (not a scene) |
| `boundary-conditions.md` | Shared simulation boundaries and sources | No: a world run | **Not a scene:** `simulation-boundary-conditions/demo.cjs` (command script) |
| `branched-domains.md` | Branched geometry for simulation models | No: a world run | **Not a scene:** `simulation-branched-domains/demo.cjs` (command script) |
| `budgeted-route-requests.md` | Route requests per tick | No: a world run | none |
| `carry.md` | Carrying objects between places | No: a world run | **Not a scene:** `carry-workshop.js` (not a scene) |
| `clap-instruments-and-handoff.md` | Plug-in instruments and handoff to a music program | No: a world run | **Not a scene:** `clap-instrument/handoff.cjs` (command script) |
| `contact-effects.md` | Measured contacts with surfaces | No: a world run | none |
| `contact-exciters.md` | Contact forces at audio rate | No: a world run | **Not a scene:** `simulation-contact-exciters/demo.cjs` (command script) |
| `controllers-inverse-targets.md` | Controllers and inverse fits to targets | No: a world run | **Not a scene:** `controller-tools/demo.cjs` (command script), `controller-tools/evaluators.cjs` (not a scene) |
| `crowds-and-bottlenecks.md` | Walkers avoiding each other | No: a world run | none |
| `dialogue-repair.md` | Speech recordings repaired | No: a world run | **Not a scene:** `music-production/dialogue-repair-workshop.cjs` (command script) |
| `discretization.md` | Solver cells and boundary faces | No: a world run | **Not a scene:** `simulation-discretization/demo.cjs` (command script) |
| `distributed-waves.md` | Pressure and flow waves in tubes | No: a world run | **Not a scene:** `simulation-wave-networks/demo.cjs` (command script) |
| `ecology.md` | Habitat channels, fire and recovery | No: a world run | **No:** `ecology.js` (colour changes). **Page:** `ecology.html` |
| `editable-simulation-inputs.md` | Pins, brushes and injections on a timeline | No: a world run | **No:** `editable-simulation-inputs.js` (live motion) |
| `event-actions.md` | Timeline cues to commands | No: a world run | **Not a scene:** `audio-world-events.cjs` (command script) |
| `event-visual-effects.md` | Timed effects from a recording's events | No: a world run | **Not a scene:** `event-visual-effects/demo.cjs` (command script) |
| `faction-perception.md` | What a faction has seen | No: a world run | none |
| `first-divergence.md` | Where two world runs first differ | Tool | **Not a scene:** `world-worker-estate.js` (world run) |
| `foley-perspective.md` | Foley spotted from world events | No: a world run | **Not a scene:** `music-production/foley-workshop.cjs` (command script) |
| `gameplay-state.md` | Timers, objectives and state graphs | No: a world run | none |
| `gesture-bank.md` | A searchable bank of recorded gestures | No: a world run | **Not a scene:** `music-production/gesture-bank-workshop.cjs` (command script) |
| `gesture-scores.md` | Scores that drive named controls on one clock | No: a world run | **Not a scene:** `gesture-scores/demo.cjs` (command script) |
| `graph-media.md` | Audio files, analysis and recorded input in graphs | No: a world run | **Not a scene:** `editable-musical-events.cjs` (command script), `graph-audio-automation.cjs` (command script), `live-modulation.cjs` (command script), `per-stem-controls.cjs` (command script) |
| `grid-operators.md` | Grid and mesh operators for solvers | No: a world run | **Not a scene:** `simulation-grid-operators/demo.cjs` (command script) |
| `group-formations.md` | Groups of agents sharing a destination | No: a world run | none |
| `headless-worlds.md` | Declarative simulated worlds, queries and replay | No: a world run | **Bakes:** `conservative-transfer.js` (44,413). **No:** `spatial-field-wind.js` (live motion). **Not a scene:** `canal-traversal.js` (not a scene), `interactable-locks.js` (needs a host page), `spatial-rebuild.js` (not a scene) |
| `input-compilers.md` | Text, MIDI and cues compiled into editable events | No: a world run | **Not a scene:** `input-compilers/demo.cjs` (command script) |
| `inspection-links.md` | Links to committed events in a run | No: a world run | **Not a scene:** `shared-inspection-links/demo.cjs` (command script) |
| `instrument-recording-sessions.md` | A recorded performance session as a playable instrument | No: a world run | **Not a scene:** `instrument-session/bench.cjs` (command script), `instrument-session/demo.cjs` (command script) |
| `interaction-components.md` | Reusable controls for interactables | No: a world run | none |
| `job-reservations.md` | Shared jobs and capacity | No: a world run | none |
| `lumped-networks.md` | Networks of storage, resistance and sources | No: a world run | **Not a scene:** `simulation-lumped-networks/demo.cjs` (command script) |
| `mass-properties.md` | Mass and inertia of assemblies | No: a world run | **Bakes:** `simulation-mass-properties/instrument.json` (10). **Not a scene:** `simulation-mass-properties/demo.cjs` (command script) |
| `material-conversion.md` | Material cells lifted into rigid bodies and back | No: physics | **Not a scene:** `material-conversion.cjs` (not a scene), `staged-fracture.cjs` (not a scene) |
| `mixing-essentials.md` | Mixer inserts | No: a world run | **Not a scene:** `music-production/mixing-essentials-workshop.cjs` (command script) |
| `model-reduction.md` | Detailed simulations baked into small models | No: a world run | **Not a scene:** `simulation-reduction/demo.cjs` (command script) |
| `motion-sound.md` | Sound automation from motion and render data | No: a world run | **Not a scene:** `motion-sound/demo.cjs` (command script) |
| `moving-boundaries.md` | Valves and seals with moving surfaces | No: a world run | **Not a scene:** `simulation-moving-boundaries/demo.cjs` (command script) |
| `music-adaptive-rehearsal.md` | An adaptive score rehearsed along paths | No: a world run | **Not a scene:** `music-production/listening-regression.cjs` (command script) |
| `music-composition-search.md` | Searching for passages to replace | No: a world run | none |
| `music-critique-audio.md` | Listening to a production and trying fixes | No: a world run | **Not a scene:** `music-production/audio-critique-diagnosis.cjs` (command script) |
| `music-critique.md` | Blind listening and votes on a passage | No: a world run | none |
| `music-cue-map.md` | How a whole cue unfolds | No: a world run | **Not a scene:** `music-production/cue-map-workshop.cjs` (command script) |
| `music-edit-session.md` | Takes and performances in one edit | No: a world run | **Not a scene:** `music-production/performance-accompaniment.cjs` (command script), `music-production/phrase-performance.cjs` (command script) |
| `music-foreground-mix.md` | A mix built around the foreground part | No: a world run | none |
| `music-gestures.md` | Phrases shaped by patch gestures | No: a world run | **Not a scene:** `music-production/phrase-gestures.cjs` (command script) |
| `music-instrument-graphs.md` | Modular instruments | No: a world run | none |
| `music-instrument-performance.md` | How notes start, join and end | No: a world run | none |
| `music-listening-preferences.md` | Listening choices carried to another cue | No: a world run | none |
| `music-locked-arrangement.md` | Arrangement search with locked passages | No: a world run | none |
| `music-persistent-performers.md` | Instruments that carry across score changes | No: a world run | **Not a scene:** `music-production/persistent-performers.cjs` (command script) |
| `music-playable-instruments.md` | Stock playable instruments | No: a world run | none |
| `music-producer.md` | Producer auditions | No: a world run | **Not a scene:** `music-production/night-signal.cjs` (command script) |
| `music-production.md` | A score with instruments, timing and mix | No: a world run | **Not a scene:** `music-production/split-reed.cjs` (not a scene) |
| `music-session-experiments.md` | Many musical choices auditioned together | No: a world run | **Not a scene:** `music-production/performance-ballot.cjs` (command script), `music-production/session-experiment.cjs` (command script) |
| `music-themes.md` | One theme across a production | No: a world run | **Not a scene:** `music-production/harbor-theme.cjs` (command script) |
| `music-voice-leading.md` | Inner voices searched around melody and bass | No: a world run | **Not a scene:** `music-production/voice-leading-workshop.cjs` (command script) |
| `music-whole-piece.md` | Whole pieces composed from a brief | No: a world run | none |
| `music-world-score.md` | Scene sound arranged with the score | No: a world run | **Not a scene:** `music-production/pressure-relay.cjs` (command script) |
| `navigation-flow.md` | Shared destination fields | No: a world run | none |
| `navigation-tiles.md` | Walking routes on tiles | No: a world run | none |
| `numerical-solvers.md` | Linear and nonlinear solvers | No: a world run | **Not a scene:** `simulation-numerical-solvers/demo.cjs` (command script) |
| `pad-patterns.md` | Beat patterns for a sample kit | No: a world run | **Not a scene:** `music-production/pad-pattern-workshop.cjs` (command script) |
| `parameter-fitting.md` | Simulation settings fitted to reference data | No: a world run | **Not a scene:** `parameter-fitting/demo.cjs` (command script) |
| `path-sections.md` | Section profiles along ducts and channels | No: a world run | **Not a scene:** `simulation-path-sections/demo.cjs` (command script), `simulation-path-sections/duct-field.cjs` (not a scene) |
| `performance-groove.md` | Groove taken from a performance | No: a world run | **Not a scene:** `music-production/performance-groove-workshop.cjs` (command script) |
| `phrase-composer.md` | Motifs developed into arranged phrases | No: a world run | none |
| `physical-audio.md` | Simulated physical signals into audio | No: a world run | **Not a scene:** `physical-audio/demo.cjs` (command script) |
| `physical-ports.md` | Physical units on graph ports | No: a world run | **Not a scene:** `physical-ports/demo.cjs` (command script) |
| `physical-work.md` | Stock, labour and construction | No: a world run | none |
| `playable-sound-workshop.md` | Playable instruments built from a sound | No: a world run | **Not a scene:** `music-production/playable-sound-workshop.cjs` (command script), `music-production/sound-discovery.cjs` (command script) |
| `population.md` | Households and residents | No: a world run | none |
| `portable-story-packs.md` | Story definitions and recorded runs packed | No: a world run | **Not a scene:** `portable-story-packs/demo.cjs` (command script) |
| `portals.md` | Travel between named places | No: a world run | **Not a scene:** `painted-portals.cjs` (needs a host page), `place-portals.js` (needs a host page), `portable-workshop.js` (not a scene) |
| `prefab-upgrades.md` | Moving placed assemblies to new revisions | No: a world run | **Not a scene:** `world-prefab-upgrade.js` (world run) |
| `procedural-score.md` | Audiovisual scores from motifs | No: a world run | **Not a scene:** `after-the-fifth.cjs` (command script) |
| `production-benchmark.md` | A full cue, a dialogue recut and an adaptive score compared on a listening page | No: a world run | **Not a scene:** `production-benchmark/cue.cjs` (command script), `production-benchmark/review.cjs` (command script), `production-benchmark/run.cjs` (command script), `production-benchmark/scene.cjs` (command script), `production-benchmark/support.cjs` (command script), `production-benchmark/world.cjs` (command script). **Page:** `production-benchmark/play.html`, `production-benchmark/play.js` |
| `public-influence.md` | Public priorities and rewards | No: a world run | none |
| `puzzles.md` | Inputs combined into doors and gates | No: a world run | none |
| `recording-instrument-fit.md` | Instruments fitted to a recording | No: a world run | none |
| `reference-experiments.md` | Physics experiments checked against known answers | No: a world run | **Not a scene:** `reference-experiments/demo.cjs` (command script) |
| `region-revisions.md` | Region-scoped state per tick | No: a world run | none |
| `resampling-jam.md` | Pad phrases resampled through racks | No: a world run | **Not a scene:** `music-production/resampling-jam-workshop.cjs` (command script) |
| `resonant-modes.md` | Resonators as baked mode assets | No: a world run | **Not a scene:** `simulation-resonant-modes/demo.cjs` (command script) |
| `sample-capture.md` | Audio captured and catalogued | No: a world run | **Not a scene:** `music-production/captured-strike.cjs` (command script) |
| `sample-edit.md` | Samples sliced and edited | No: a world run | **Not a scene:** `music-production/cut-metal.cjs` (command script) |
| `sample-instrument-builder.md` | Pitched instruments from recorded gestures | No: a world run | **Not a scene:** `music-production/sample-instrument-workshop.cjs` (command script) |
| `sample-kits.md` | Sample kits on pads | No: a world run | **Not a scene:** `music-production/kit-workshop.cjs` (command script) |
| `sample-motif.md` | One recording auditioned in four roles | No: a world run | none |
| `simulation-block-independence.md` | Results that do not depend on block size | Tool | **Not a scene:** `simulation-block-independence/demo.cjs` (command script), `simulation-block-independence/ink-studio.config.js` (not a scene). **Page:** `simulation-block-independence/playback.html` |
| `simulation-blocks.md` | Simulation blocks at audio rate | No: a world run | **Not a scene:** `simulation-blocks/demo.cjs` (command script), `simulation-blocks/ink-studio.config.js` (not a scene), `simulation-blocks/resonator.cjs` (not a scene) |
| `simulation-checkpoints.md` | Snapshots, forks and resets | No: a world run | **Not a scene:** `committed-events/demo.cjs` (command script), `simulation-fixtures/demo.cjs` (command script), `world-checkpoint-branch.js` (world run) |
| `simulation-chunks.md` | Systems owned by chunks | No: a world run | none |
| `simulation-diagnostics.md` | Stability and conservation checks | Tool | **Not a scene:** `simulation-diagnostics/demo.cjs` (command script) |
| `simulation-execution-plan.md` | How a simulation will run | Tool | **Not a scene:** `simulation-execution-plan/demo.cjs` (command script), `simulation-execution-plan/ink-studio.config.js` (not a scene) |
| `simulation-experiment-bundles.md` | Simulation experiments packed to reproduce | No: a world run | **Not a scene:** `simulation-experiment-bundles/demo.cjs` (command script) |
| `simulation-fast-checkpoints.md` | Checkpoints of fast simulation state | No: a world run | **Not a scene:** `simulation-fast-checkpoints/demo.cjs` (command script), `simulation-fast-checkpoints/ink-studio.config.js` (not a scene) |
| `simulation-forecasts.md` | Two copies of a run compared ahead | No: a world run | **Not a scene:** `simulation-forecast.cjs` (command script) |
| `simulation-kernels.md` | Simulation kernels of your own | No: a world run | **Not a scene:** `simulation-kernels/damped-spring.cjs` (not a scene), `simulation-kernels/demo.cjs` (command script), `simulation-kernels/ink-studio.config.js` (not a scene) |
| `simulation-measurements.md` | Named measurements and assertions | Tool | **Not a scene:** `simulation-measurements/demo.cjs` (command script) |
| `simulation-model-changes.md` | A model changed while it plays | No: a world run | **Not a scene:** `simulation-model-changes/demo.cjs` (command script), `simulation-model-changes/ink-studio.config.js` (not a scene) |
| `simulation-models.md` | Versioned simulation models | No: a world run | none |
| `simulation-modules.md` | Simulation models reused as modules | No: a world run | **Not a scene:** `simulation-modules/demo.cjs` (command script) |
| `simulation-output-adapters.md` | Solver results into rendering, analysis and audio | No: a world run | **Not a scene:** `live-snapshot-cursor/demo.cjs` (command script), `live-snapshot-cursor/dock.world.cjs` (not a scene), `live-snapshot-cursor/ink-studio.config.js` (not a scene), `output-adapters/demo.cjs` (command script), `world-graph-ports/demo.cjs` (command script) |
| `simulation-performance-budgets.md` | Measured simulation timing budgets | Tool | **Not a scene:** `simulation-performance-budgets/demo.cjs` (command script), `simulation-performance-budgets/ink-studio.config.js` (not a scene), `simulation-performance-budgets/stories.cjs` (command script) |
| `simulation-prepared-processing.md` | A kernel prepared once for playback | No: a world run | **Not a scene:** `simulation-prepared/demo.cjs` (command script), `simulation-prepared/ink-studio.config.js` (not a scene), `simulation-prepared/vent-network.js` (not a scene). **Page:** `simulation-prepared/playback.html` |
| `simulation-rate-crossings.md` | Signals between different rates | No: a world run | **Not a scene:** `simulation-rate-crossings/demo.cjs` (command script), `simulation-rate-crossings/ink-studio.config.js` (not a scene) |
| `simulation-scrubbing.md` | Scrubbing a world run | No: a world run | none |
| `simulation-signal-comparison.md` | Two estimates of one signal compared | Tool | **Not a scene:** `simulation-signal-comparison/demo.cjs` (command script) |
| `simulation-timed-events.md` | Events inside a time step | No: a world run | **Not a scene:** `simulation-timed-events/demo.cjs` (command script), `simulation-timed-events/ink-studio.config.js` (not a scene) |
| `simulation-transfer-coupling.md` | Two-way coupling of transfers | No: a world run | **Not a scene:** `simulation-transfer-coupling/demo.cjs` (command script), `simulation-transfer-coupling/ink-studio.config.js` (not a scene) |
| `simulation-workers.md` | World runs on worker threads | No: a world run | none |
| `slice-composition.md` | Phrases written with recorded slices | No: a world run | **Not a scene:** `music-production/slice-composition-workshop.cjs` (command script) |
| `sound-design-effects.md` | Sound design inserts | No: a world run | **Not a scene:** `music-production/sound-design-workshop.cjs` (command script) |
| `spatial-audio.md` | A spatial sound mix | No: a world run | none |
| `state-integrators.md` | Continuous state advanced in time | No: a world run | **Not a scene:** `simulation-integrators/bounce.cjs` (not a scene), `simulation-integrators/demo.cjs` (command script) |
| `state-remap.md` | State moved to a new grid or shape | No: a world run | **Not a scene:** `simulation-state-remap/demo.cjs` (command script) |
| `story-camera-suggestions.md` | Shot plans and cutaways from a recorded story | No: a world run | **Not a scene:** `story-camera-suggestions/demo.cjs` (command script) |
| `story-documents.md` | Incidents, questlets and arcs as documents | No: a world run | **Not a scene:** `presentation-cues/demo.cjs` (command script), `story-documents/bench-inspection.host.cjs` (not a scene) |
| `story-installation-inputs.md` | Tracking, MIDI and OSC mapped to a live world's choices | No: a world run | **Not a scene:** `story-installation/demo.cjs` (command script) |
| `story-integration-inputs.md` | Committed runs driving picture and sound | No: a world run | **Not a scene:** `read-only-story-integrations/demo.cjs` (command script) |
| `story-scene-timeline.md` | Scene markers from a committed run | No: a world run | **Not a scene:** `story-scene-timeline/demo.cjs` (command script) |
| `subtractive-synth.md` | Subtractive synth voices | No: a world run | **Not a scene:** `music-production/subtractive-workshop.cjs` (command script) |
| `take-clock.md` | One clock for picture and take audio | No: a world run | **Not a scene:** `clock-mapping/demo.cjs` (command script) |
| `targeted-interactions.md` | Verbs agents perform on targets | No: a world run | none |
| `timbre-composition.md` | Pitch and rhythm taken from a recording | No: a world run | none |
| `timbre-evolution.md` | One recording's attack, body and decay across players | No: a world run | none |
| `virtual-sensors.md` | Virtual instruments and sensors on a run | No: a world run | **Not a scene:** `virtual-sensors/demo.cjs` (command script) |
| `world-access.md` | Views of a run for different audiences | No: a world run | **Not a scene:** `world-access/demo.cjs` (command script) |
| `world-scaling.md` | Indexing large worlds | No: a world run | none |

### Tools and output

| Guide | What it gives a scene | Travels | Examples |
| --- | --- | --- | --- |
| `asset-interchange.md` | glTF, GLB and atlas round trips | No: export | none |
| `audio-delivery.md` | A soundtrack printed with stems and a cue sheet | No: export | **Not a scene:** `music-production/delivery-workshop.cjs` (command script) |
| `browser-renderer.md` | ink-studio's WebGL 2 renderer | No: browser | **Solids only:** `coverage-aware-glass.js` (27,925; loses look), `environment-test-scene.js` (13,338; loses sky and air). **Page:** `water-bodies.html` |
| `build-profiles.md` | Builds of the toolkit for authoring and playback | Tool | none |
| `graph-clips.md` | Graph outputs exported as clips | No: export | **Not a scene:** `visual-resampling.cjs` (command script) |
| `linked-views.md` | Charts, maps and scenes on one clock | No: browser | none |
| `patch-tooling.md` | Graph wiring edited from the terminal | Tool | **Not a scene:** `patch-tooling/demo.cjs` (command script), `patch-tooling/footage.cjs` (command script) |
| `project-bundles.md` | A JSON scene and its assets in one file | No: export | none |
| `scene-audio.md` | A scene soundtrack exported with stems | No: export | none |
| `scene-editor.md` | Editing JSON dioramas without a page | Tool | none |
| `scene-publishing.md` | Publishing a scene to a folder | No: export | none |
| `show-control.md` | Live audio, timecode, projection and lighting | No: browser | none |
| `stable-asset-references.md` | Asset ids with exact revisions | Tool | **Not a scene:** `stable-asset-references/demo.cjs` (command script) |
| `story-editorial-handoff.md` | A picture cut, stems and markers from a recorded story | No: export | **Not a scene:** `story-editorial/demo.cjs` (command script) |
| `story-presentation-pack.md` | Several views rendered from one recorded story | No: export | **Not a scene:** `story-presentation/demo.cjs` (command script) |
| `transitions.md` | Full-screen WebGL transitions | No: browser | **Not a scene:** `column-melt.mjs` (command script). **Page:** `transitions/index.html` |
| `typed-data-inputs.md` | Typed datasets for scenes and worlds | No: world field | none |
| `viewer-input.md` | Remappable browser input | No: browser | none |
| `webgpu-graphs.md` | GPU texture and geometry graphs | No: browser | **Not a scene:** `webgpu-graphs/kernels.mjs` (command script), `webgpu-graphs/sample.mjs` (command script). **Page:** `live-gaussian/demo.mjs`, `live-gaussian/index.html`, `live-gaussian/turntable.mjs`, `webgpu-graphs/demo.mjs`, `webgpu-graphs/index.html`, `webgpu-graphs/style.css` |

### Other examples

| Kind | Files |
| --- | --- |
| Inputs to commands and tools | `adaptive-story-audio/crossing-watch.audio.json`, `adaptive-story-audio/crossing-watch.story.json`, `atmosphere-depth-bands.json`, `audio-racks/clap-fixture.cpp`, `audio-racks/pocket-repeater.json`, `audio-racks/porcelain-room.json`, `audio-racks/signalsmith-gesture-probe.cpp`, `audio-racks/signalsmith-probe.cpp`, `audio-racks/steel-bus.json`, `block-video-corruption.html.template`, `blue-shadow.cube`, `caused-marks.recipe.json`, `clap-instrument/glass-reed.cpp`, `coastal-environment-pack.json`, `coastal-pack-beacon.json`, `coastal-pack-jetty.json`, `complementary-field.json`, `copperwind-color-clusters.json`, `copperwind-looks.json`, `courier-shot-lighting.json`, `curve-family.json`, `desaturation-field.json`, `driven-look-forge-actions.json`, `driven-look-forge.json`, `editable-passage.edits.json`, `environment-review-camera.js`, `event-visual-effects/spillway.effects-plan.json`, `event-visual-effects/spillway.wgsl`, `faceted-surfaces.json`, `frost-boundaries.html.template`, `grayscale-ramp.json`, `half-gain-legal.cube`, `harbor-compositing.json`, `headless-array-graph.json`, `headless-array-sweep.json`, `headless-graph-group.json`, `headless-graph.json`, `hue-brightness-field.json`, `lantern-dusk.json`, `learned-harbor-mark.json`, `lighting-ramp-palette.json`, `live-snapshot-cursor/dock.patch.json`, `live-snapshot-cursor/dock.queries.json`, `lock-signal-audition.json`, `look-assets.json`, `look-prefabs.json`, `market-color-clusters.json`, `material-conversion.html.template`, `millrace-aesthetics.json`, `music-production/gesture-palettes.json`, `music-production/relay-glass-timeline.json`, `music-production/relay-glass.json`, `music-production/samples/CREDITS.md`, `music-production/samples/hat-closed-alt.wav`, `music-production/samples/hat-closed.wav`, `music-production/samples/hat-open.wav`, `music-production/samples/metal-alt.wav`, `music-production/samples/metal-hit.wav`, `music-production/samples/metal-soft.wav`, `music-production/samples/snare-alt.wav`, `music-production/samples/snare-ghost.wav`, `music-production/samples/snare-main.wav`, `music-production/samples/snare-rim.wav`, `ornament-pattern.json`, `paint-mixture.json`, `painted-portals.html.template`, `palette-charts.json`, `palette-check-courier.json`, `palette-coverage-field.json`, `palette-dither-fit.json`, `palette-recipe.json`, `palette-space-plot.json`, `palette-weather-beacon.json`, `paper-relief.json`, `patch-tooling/ripple.wgsl`, `patch-tooling/show.cues.json`, `physical-materials.pack.json`, `physical-ports/pressure.graph.json`, `polar-colour-field.json`, `primary-ramp.json`, `procedural/authoring-example.js`, `procedural/gallery.js`, `production-benchmark/briefs.json`, `production-benchmark/recordings/README.md`, `production-benchmark/recordings/fan-line.wav`, `production-benchmark/recordings/water-line.wav`, `readability-courier.json`, `reference-experiments/recipes/closed-tube.wave.json`, `reference-experiments/recipes/damped-oscillator.network.json`, `reference-experiments/recipes/damped-oscillator.run.json`, `reference-experiments/recipes/heat-slab.domain.json`, `reference-experiments/recipes/heat-slab.transport.json`, `reference-experiments/recipes/membrane.bake.json`, `reference-experiments/recipes/membrane.obj`, `reference-experiments/recipes/open-tube.wave.json`, `reference-experiments/recipes/suite.json`, `reference-experiments/recipes/tube.network.json`, `relay-look-pack.json`, `rule-board.html.template`, `sector-raycaster.html.template`, `shared-sky-profiles.json`, `shot-correction.html.template`, `signal-courier-approval.json`, `simulation-block-independence/review.json`, `simulation-block-independence/vent.model.json`, `simulation-blocks/resonator.model.json`, `simulation-branched-domains/bench.domain.json`, `simulation-discretization/channel.plan.json`, `simulation-execution-plan/drive.csv`, `simulation-fast-checkpoints/bench.take.json`, `simulation-fast-checkpoints/voice.model.json`, `simulation-forecast.html.template`, `simulation-integrators/bounce.plan.json`, `simulation-kernels/spring.model.json`, `simulation-mass-properties/arm.obj`, `simulation-mass-properties/balance.pack.json`, `simulation-mass-properties/balance.plan.json`, `simulation-model-changes/chamber.model.json`, `simulation-model-changes/fork.model.json`, `simulation-model-changes/tube.changes.json`, `simulation-model-changes/tube.model.json`, `simulation-models/sluice.graph.json`, `simulation-models/sluice.json`, `simulation-models/sluice.take.json`, `simulation-modules/reservoir.json`, `simulation-modules/valve.json`, `simulation-path-sections/channel.plan.json`, `simulation-prepared/vent.model.json`, `simulation-timed-events/note.model.json`, `spatial-bed-edit.json`, `spatial-wind-transect.json`, `spatial-yard-queries.json`, `spectrum-ramp.json`, `spillway-phase.html.template`, `sprite-scanline-budget.html.template`, `staged-fracture.html.template`, `starter-recipes/README.md`, `starter-recipes/audio-driven-sign/beat.wav`, `starter-recipes/audio-driven-sign/graph.json`, `starter-recipes/audio-driven-sign/take.json`, `starter-recipes/layered-vista/graph.json`, `starter-recipes/layered-vista/take.json`, `starter-recipes/looping-spell/graph.json`, `starter-recipes/looping-spell/take.json`, `starter-recipes/relightable-sprite/graph.json`, `starter-recipes/relightable-sprite/right-light.json`, `starter-recipes/relightable-sprite/take.json`, `starter-recipes/weathered-tiles/graph.json`, `starter-recipes/weathered-tiles/stone.group.json`, `starter-recipes/weathered-tiles/take.json`, `story-documents/beacon-casting.query.json`, `story-documents/beacon-clearance.query.json`, `story-documents/beacon-dispatch.actions.json`, `story-documents/beacon-dispatch.json`, `story-documents/beacon-shift.actions.json`, `story-documents/bench-inspection.imported.events.json`, `story-documents/bench-inspection.json`, `story-documents/breakwater-draft.json`, `story-documents/breakwater-survey.json`, `story-documents/breakwater-watch.fork-compare.json`, `story-documents/breakwater-watch.intervene.actions.json`, `story-documents/breakwater-watch.json`, `story-documents/breakwater-watch.pause.actions.json`, `story-documents/bridge-credit.json`, `story-documents/bridge-credit.payment.actions.json`, `story-documents/burned-mill.json`, `story-documents/canal-camp-permanent.actions.json`, `story-documents/canal-camp-withdraw.actions.json`, `story-documents/canal-camp.json`, `story-documents/canal-caravan.json`, `story-documents/canal-inspection.json`, `story-documents/canal-kit.asset-pack.json`, `story-documents/canal-support.json`, `story-documents/channel-beliefs.evidence.actions.json`, `story-documents/channel-beliefs.json`, `story-documents/dispatch-rehearsal.json`, `story-documents/dispatch-rehearsal.stocked.condition.json`, `story-documents/dock-dispatch.actions.json`, `story-documents/dock-dispatch.template.json`, `story-documents/glass-coast.json`, `story-documents/harbor-catalog.welcome.actions.json`, `story-documents/harbor-encounters.json`, `story-documents/harbor-pressures.json`, `story-documents/harbor-recovery.json`, `story-documents/harbor-recovery.overlap.actions.json`, `story-documents/harbor-rotation.json`, `story-documents/harbor-watch-at-cutoff.actions.json`, `story-documents/harbor-watch-on-time.actions.json`, `story-documents/harbor-watch.json`, `story-documents/highwater-beacon-breach.actions.json`, `story-documents/highwater-beacon-ridge.actions.json`, `story-documents/highwater-beacon.json`, `story-documents/inspect.graph.json`, `story-documents/landing-selection.json`, `story-documents/lantern-ferry.json`, `story-documents/lantern-ferry.seed-matrix.json`, `story-documents/lantern-pass-ford.actions.json`, `story-documents/lantern-pass-ridge.actions.json`, `story-documents/lantern-pass.json`, `story-documents/live-passage.actions.json`, `story-documents/live-passage.json`, `story-documents/lock-knowledge.json`, `story-documents/lock-knowledge.relay.actions.json`, `story-documents/low-bank-sluice.commitment.actions.json`, `story-documents/low-bank-sluice.hint.actions.json`, `story-documents/low-bank-sluice.json`, `story-documents/low-bank.fork-compare.json`, `story-documents/low-bank.json`, `story-documents/low-bank.late-salvage.actions.json`, `story-documents/low-bank.salvaged.actions.json`, `story-documents/observatory.json`, `story-documents/pier-facts.full.actions.json`, `story-documents/pier-facts.json`, `story-documents/pier-facts.partial.actions.json`, `story-documents/pressure-shifts.json`, `story-documents/quay-candidates.actions.json`, `story-documents/quay-candidates.berth.actions.json`, `story-documents/quay-followups.json`, `story-documents/quay-opportunities.json`, `story-documents/quay-relay.actions.json`, `story-documents/quay-relay.fork-compare.json`, `story-documents/quay-relay.json`, `story-documents/relief-charter.actions.json`, `story-documents/relief-charter.json`, `story-documents/relief-crossing.json`, `story-documents/ridge-ford.json`, `story-documents/ridge-ford.mark.actions.json`, `story-documents/ridge-ford.reinforce.actions.json`, `story-documents/river-callbacks.broken.actions.json`, `story-documents/river-callbacks.casting.json`, `story-documents/river-callbacks.honored.actions.json`, `story-documents/river-callbacks.json`, `story-documents/river-memories.json`, `story-documents/river-memories.rescue.actions.json`, `story-documents/signal-contract.actions.json`, `story-documents/signal-contract.json`, `story-documents/signal-vault-lower.actions.json`, `story-documents/signal-vault-upper.actions.json`, `story-documents/signal-vault.json`, `story-documents/sluice-relief.actions.json`, `story-documents/sluice-relief.json`, `story-documents/sluice-relief.seed-matrix.json`, `story-documents/supply-dispatch.actions.json`, `story-documents/supply-dispatch.template.json`, `story-documents/survey-seal.json`, `story-documents/survey-seal.recovery.actions.json`, `story-documents/tide-calendar.early-signal.actions.json`, `story-documents/tide-calendar.json`, `story-documents/tide-calendar.late-signal.actions.json`, `story-documents/tide-calendar.missed-bell.actions.json`, `story-documents/winter-crossing.json`, `story-editorial/gate.handoff.json`, `story-editorial/gate.music.json`, `story-editorial/gate.performance.json`, `story-editorial/gate.soundtrack.json`, `story-presentation/beacon.wgsl`, `thread-studies.json`, `tideline-looks.json`, `tile-attributes.html.template`, `train-neural-cellular.py`, `transitions/column-melt.html.template`, `visual-consequences/cleaning.actions.json`, `visual-consequences/repair.actions.json`, `visual-sweep-attractor.plan.json`, `voxel-surface.json`, `world-access/harbor.access.json`, `world-access/harbor.queries.json`, `world-graph-ports/dock.graph.json` |
| Scenes and pages | **Bakes:** `cloth.js` (1,413), `sculpt.js` (4,027). **Solids only:** `breakable-parts.json` (24,342; loses breakable parts), `color-runoff.js` (10,759; loses look), `copperwind-crossing.json` (81,122; loses look), `palette-remap.json` (21,028; loses look), `signal-observatory.json` (35,566; loses look, timeline), `stipple.json` (12,390; loses look). **No:** `particles.js` (live motion), `puppet.js` (bones), `scene.json` (particles), `splat-effects.js` (live motion). **Not a scene:** `live-show/signals.mjs` (command script), `pixel-stamp-studies.js` (not a scene). **Page:** `live-show/demo.mjs`, `live-show/index.html`, `live-show/sample-capture-demo.mjs`, `live-show/sample-capture.html`, `live-show/style.css`, `painted-shadow-bands-workshop.mjs`, `procedural/gallery.html`, `transitions/gallery.css`, `transitions/gallery.mjs`, `transitions/scenes.mjs` |
| World runs (input to the world commands) | `adaptive-story-audio/crossing-watch.world.json`, `event-visual-effects/spillway.world.json`, `physical-ports/pump.world.json`, `reference-experiments/recipes/tank-drain.world.json`, `reference-experiments/recipes/two-body-impact.world.json`, `simulation-blocks/bench.world.json`, `simulation-branched-domains/bench.world.json`, `simulation-execution-plan/bench.world.json`, `simulation-fast-checkpoints/bench.world.json`, `simulation-models/sluice.world.json`, `simulation-modules/bench.world.json`, `simulation-moving-boundaries/bench.world.json`, `simulation-rate-crossings/bench.world.json`, `simulation-timed-events/bench.world.json`, `simulation-transfer-coupling/reed.world.json`, `story-documents/beacon-casting.world.json`, `story-documents/bench-inspection.world.json`, `story-documents/breakwater-survey.world.json`, `story-documents/breakwater-watch.world.json`, `story-documents/bridge-credit.world.json`, `story-documents/burned-mill.world.json`, `story-documents/canal-camp.world.json`, `story-documents/canal-caravan.world.json`, `story-documents/canal-inspection.world.json`, `story-documents/channel-beliefs.world.json`, `story-documents/dispatch-rehearsal.world.json`, `story-documents/dock-dispatch.world.json`, `story-documents/glass-coast.world.json`, `story-documents/harbor-catalog.world.json`, `story-documents/harbor-recovery.world.json`, `story-documents/harbor-rotation.world.json`, `story-documents/harbor-watch.world.json`, `story-documents/highwater-beacon.world.json`, `story-documents/landing-selection.world.json`, `story-documents/lantern-ferry.world.json`, `story-documents/lantern-pass.world.json`, `story-documents/live-passage.world.json`, `story-documents/lock-knowledge.world.json`, `story-documents/low-bank-sluice.world.json`, `story-documents/low-bank.world.json`, `story-documents/observatory.world.json`, `story-documents/pier-facts.world.json`, `story-documents/pressure-shifts.world.json`, `story-documents/quay-candidates.world.json`, `story-documents/quay-relay.world.json`, `story-documents/relief-charter-quay.world.json`, `story-documents/relief-charter-ridge.world.json`, `story-documents/relief-crossing.world.json`, `story-documents/ridge-ford.world.json`, `story-documents/river-callbacks.world.json`, `story-documents/river-memories.world.json`, `story-documents/signal-contract.world.json`, `story-documents/signal-vault.world.json`, `story-documents/sluice-relief.world.json`, `story-documents/supply-dispatch.world.json`, `story-documents/survey-seal.world.json`, `story-documents/tide-calendar.world.json`, `story-documents/winter-crossing.world.json`, `story-editorial/gate.world.json`, `visual-consequences/clay-crossing.world.json`, `world-access/harbor.world.json`, `world-acoustic-hatch.json`, `world-adaptive-music.json`, `world-agent-orders.json`, `world-agent-roster.json`, `world-aggregate-estuary.json`, `world-causal-mill.json`, `world-cellar-flood.json`, `world-conditional-weather.json`, `world-construction-bridge.json`, `world-contact-effects.json`, `world-continuous-colliders.json`, `world-crossing.json`, `world-crowd-bridge.json`, `world-deformable-yard.commands.json`, `world-deformable-yard.json`, `world-estuary-households.json`, `world-expedition-formation.json`, `world-flow-ford.json`, `world-ford-shift.json`, `world-graph-ports/dock.world.json`, `world-harvest-logistics.json`, `world-hydraulic-yard.commands.json`, `world-hydraulic-yard.json`, `world-influence-yard.json`, `world-interaction-yard.json`, `world-lightwell-workshop.json`, `world-live-volumes.json`, `world-lookout-memory.json`, `world-material-fatigue.commands.json`, `world-material-fatigue.json`, `world-multi-rate.json`, `world-persistent-valley.json`, `world-physical-materials.json`, `world-physical-work.json`, `world-pocket-moon.json`, `world-prefab-upgrade.migration.json`, `world-puzzle-gate.actions.json`, `world-puzzle-gate.json`, `world-region-revisions.json`, `world-resident-shelter.json`, `world-rotating-dock.json`, `world-route-queue.json`, `world-routed-workshop.commands.json`, `world-routed-workshop.json`, `world-sediment-ford.json`, `world-sediment-gate.json`, `world-shelter-reservations.json`, `world-spatial-fields.json`, `world-spatial-yard.json`, `world-storm-canopy.json`, `world-surface-state.json`, `world-thawing-ford.json`, `world-tiled-ford.json`, `world-transfers.json`, `world-ventilated-shelter.json`, `world-watershed.json`, `world-windmill-workshop.json` |

Each example's first lines say what it shows; `ink-studio catalog <words>` searches every feature the toolkit has and points at its
source.
