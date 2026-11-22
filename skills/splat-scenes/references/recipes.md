# Recipes: sizes, budgets, backdrops, lettering, light, and what to build instead

Short recipes for a rich, finished scene. Sections 1 to 8 were each checked by baking a test scene with this kit against ink-studio
`cf35ff8`, proving it (at most 0.026% of a view's art pixels differ) and looking at its still and GIF; the numbers there are what
that run measured. Sections 9 to 12 come from three trial scenes (a lighthouse scene, a throne-hall scene and a mansion-grounds
scene) baked and proved against `983d91f`. Section 13, and the parts of 3 and 8 that say so, were checked against `22c23d8` by
baking a test scene, proving it and looking at its stills. The material fields they use are in references/ink-studio.md, 2.3.

Contents: 1. The art grid and readable sizes. 2. Budgets: styles, motions, parts, and counting splats. 3. A far backdrop.
4. Lettering. 5. Neon. 6. A glass case. 7. An interior lit by one sun and a fill. 8. What the file cannot carry, and what to build
instead. 9. Water. 10. Small figures. 11. Dusk light. 12. A cape. 13. Steep ground.

## 1. The art grid and readable sizes

The player's art pixel is q screen pixels square, from the stage height h, the finish's `detail` and the camera's `dist`
(references/format.md, 5.2, at the opening view and the toolkit's 38-degree field of view):

    q = clamp(round(h / (0.6887 × detail × dist)), 1, 18)        on a 960-high stage: q = round(1394 / (detail × dist))

| detail × dist | q | Art pixels on a 1440 by 960 stage |
| --- | --- | --- |
| 558 to 929 | 2 | 720 by 480 |
| 399 to 557 | 3 | 480 by 320 |
| 310 to 398 | 4 | 360 by 240 |
| 254 to 309 | 5 | 288 by 192 |
| 215 to 253 | 6 | 240 by 160 |

So detail × dist ≈ 465 (for example `detail: 31` at `dist: 15`) gives 480 by 320 art pixels of 3 screen pixels on a 1440 by 960
stage; the kit's `still.png` of such a scene is 480 by 320 (checked).

**Sizing something.** With H the grid's height in art pixels (320 above), a thing s world units across at distance D from the eye
spans

    s × H / (0.6887 × D) art pixels,    plus a pixel or two of splat edge

At the target (D = dist) and q = 3 this is close to s × detail. Checked: a bar one world unit long at the target of a `detail: 31`,
`dist: 15` scene measures 34 art pixels (31, plus its edges). To make something readable, choose its size in art pixels first and
divide back:

- **Capitals**: at least 6 art pixels tall, strokes at least one art pixel wide. Checked: single-stroke capitals 0.32 tall (about 10
  art pixels) read cleanly; 0.18 tall (about 6) still read.
- **A face**: about 20 art pixels across for two eyes and a mouth to read. Checked on three heads 0.5, 0.32 and 0.2 across (20, 14
  and 10 art pixels): the first reads as a face, the second only just (one-pixel eyes), the third is two dots.
- **Hand-placed splats** (`B.iso`, `B.disc`, `B.stick`) take standard deviations, not radii: a solid one (density 3) shows its crisp
  edge about 1.9 sizes out, so a splat of size s is about 3.8 s across. An eye 2 to 3 art pixels wide on the 0.5 head is a disc of
  size 0.02.

Things nearer the camera than the target are larger in proportion. The player keeps the camera's distance as it turns, so a thing at
the target keeps its size all the way round, while things off to one side come nearer and go farther.

## 2. Budgets: styles, motions, parts, and counting splats

A file holds at most **256 styles, 256 motions, 256 parts and 256 colours** (references/format.md, 1.1). The baker stops past any of
them ("more than 256 styles or motions").

- A **style** is one combination of density, kind and flags, and part. Every part multiplies the styles: the same ten densities in 30
  rig parts are 300 styles, and the bake stops (checked). A density drawn at random for each splat (`B.rr(0.2, 0.9)`) is a style
  each: 300 haze splats stopped the bake; rounded to quarters they made 6 styles in all (checked).
- A **motion** is one combination of range and extra among moving splats. A random range for each of 300 swaying splats stopped the
  bake; rounded to hundredths they made 5 motions (checked).
- Each glyph of `K.typography`'s `T.extrude` is its own part (section 4), so a long extruded line eats parts and multiplies styles.

So pick densities and ranges from a few values, and keep the parts to what really moves.

**Counting splats per part.** Label solids with `objectId` in their options and hand-placed splats with `B.describeSplats(from, to,
{ object })`, then count after the finish. Labels change no splat (checked: the same file with and without them). `objectId`, unlike
`tag`, does not make a rig part.

```js
S.box([0, -0.2, 0], [3.2, 0.2, 2.2], ground, { objectId: 'island' });
let n0 = B.count();
// ... hand-placed splats ...
B.describeSplats(n0, B.count(), { object: 'pool' });
// after B.finish:
const m = W.renderMetadata, n = {};
for (let i = 0; i < W.count; i++) {
  const name = m.objects[m.objectIds[i]] ?? 'unlabelled';
  n[name] = (n[name] || 0) + 1;
}
console.error(JSON.stringify(n), W.count);
```

In the test scene this printed, for example, `"island": 7918, "sign": 7829, "backdrop": 21236, "unlabelled": 9` of 41,997: the far
backdrop was half the scene, and eleven small capitals at a fine `res` cost as much as the ground.

Solids become splats only at `S.bake()`, so `B.count()` taken before and after a solid's line reads no change: label solids with
`objectId`, and use `B.count()` marks for hand-placed splats only (checked against `983d91f`, and again at `e80d985`).

What the baker's and `stats`' counts mean: the bake's "N splats (M moving by their kind)" counts the splats that carry a kind of
motion, the number `stats` calls "shader-animated"; `stats`' "animation N splats in the moving span" counts every splat from the
first that moves to the last, which was all of them in three scenes with rig parts (checked with both toolkit versions).

## 3. A far backdrop

The file carries no sky, but a sky made of splats bakes like anything else. Depth is measured against the finish's `radius` R: a
splat farther from the eye than dist + R has depth 1, so no outline and no contact shade is drawn between such splats. They are still
drawn far to near, and fog reaches them fully unless they are fixed light (`em`). So plain splats well beyond the radius make a clean
painted backdrop: sky bands, peaks, a sun, far water.

```js
// FOOT: below the lowest eye (the limits below). Here the camera's target is at y 1 and dist is 15, so the lowest eye is
// 1 - 15 × sin 86° = -13.96, and the foot goes at -16.
const FOOT = -16;
for (let a = 0; a < 2 * Math.PI; a += 0.02) {
  for (let e = 0; e < 0.7; e += 0.04) {                       // sky: bands by elevation, each 3 units farther out than the one below
    const band = Math.min(3, Math.floor(e / 0.18)), R = 60 + 3 * band, y = FOOT + 60 * Math.tan(e);
    B.stick(R * Math.sin(a), y, R * Math.cos(a), [Math.cos(a), 0, -Math.sin(a)], 1.4, 1.4, B.P[SKY_LOW + band], 3, { em: 1 });
  }
  const h = 6 + 5 * B.n3(Math.cos(a) * 3, Math.sin(a) * 3, 1);  // peaks: a ring of discs at radius 45
  for (let y = FOOT; y < h; y += 0.9)
    B.disc(45 * Math.sin(a), y, 45 * Math.cos(a), [-Math.sin(a), 0, -Math.cos(a)], 0.9, 0.2, B.P[y > h - 1.5 ? SNOW : ROCK], 3, { em: 1 });
  for (let r = 0.6; r < 44; r += 1.2)                         // far water, reaching right under the scene
    B.disc(r * Math.sin(a), FOOT, r * Math.cos(a), B.UP, 0.7, 0.1, B.P[WATER], 3, { em: 1, nd: 1 });
}
B.disc(0, 14, -58, [0, 0, 1], 3, 0.3, B.P[SUN], 3, { em: 1 });
```

Checked, round a scene of radius 4 (a ground disc, a box and a ball) with its camera's target at y 1 and `dist: 15`: the bands,
peaks, sun and water draw with no lines between them; at the opening view the backdrop fills every pixel round the scene. From
straight below (the player's 86° tilt), nothing of the backdrop is in the way: the scene's own ground shows from underneath, against
the page's background. The same backdrop with its foot at y −2 instead, above that eye, covered the whole picture with water from
below. Two more things learned:

- Far ground that stops short of the scene leaves the background showing under it; bring it right in.
- Where far ground passes inside the radius (under and in front of the scene), its rings drew dark lines between them; `nd: 1` (no
  depth: it hides nothing and draws no outline) removed them.

A full ring of sky costs splats: this one was 26,101 (21,172 with its foot at −2; the difference is the peaks' discs below that).
Coarser steps, or only the half the camera sees most, cost less.

Limits, from the kit and the camera (checked against `983d91f` on a throne-hall scene and a mansion-grounds scene; the first again
at `e80d985`; the lowest eye again at `e8cef0c` with the example above):

- **Nothing below y = −30.** The bake stops on any splat lower ("a hidden splat": the toolkit parks unused splats there; one disc
  at y −31 stopped it). A sky dome of radius 74 reaching 0.4 rad below level (y −28.8) baked.
- **Only a low strip of sky is in frame.** The field of view is 38° high, so at the opening view the top of the picture is
  (19° − pitch) above level from the eye: about 10° at `pitch: 0.16`. Moons, a sun and stars meant for the opening picture sit
  lower than that; the sky above still shows when a visitor tilts the view up from below.
- **Far ground must lie below the lowest eye.** The player tilts to 86° either way, so the eye comes as low as about
  target_y − dist × sin 86° (−13.8 for target y 2.2 at `dist: 16`). Flat far ground above that covers the scene from below: a cloud
  sea at y −9 under a scene whose lowest eye is −13.5 hid it at full tilt; mist at −16 under the −13.8 eye did not. With
  everything below the lowest eye, a view from straight below sees the scene's underside against the page's background.
- **A band's edge scallops where two bands' splats take turns.** Splats draw far to near, and round a ring the splats of a band
  and of the band above it lie at nearly the same distance from the eye, so they take turns: where one of the band below draws
  after its neighbour above, its rounded end pokes up past the edge, a tooth for every stick. Checked at `22c23d8` round the
  scene above with the peaks left out: the recipe's sticks all at radius 60 drew teeth about 4 art pixels high and 9 apart along
  the outer part of each edge, thin sticks (half-length 3, width 0.5, every 1.8 units, as a trial scene used) waved by an art pixel, and
  both were the same with the finish's `dither` at 0, so it is not the dither. With each band 3 units farther out than the band
  below (`R` above), the whole band below draws after the band above and its straight top row makes the edge: every edge came
  out straight, for both stick shapes.
- **Within a band, rows of hand-placed splats scallop unless each splat is long.** Lay sticks along the row with a half-length
  longer than the spacing between them (the sky above: half-length 1.4 every 1.2 units round); round discs in a row show a wavy
  edge.

## 4. Lettering

Three ways in ink-studio, all of which bake as solids:

| Way | Letters | Use |
| --- | --- | --- |
| `K.poly2.text(str, size)` with `S.strokes(shape, centre, depth, material, options)` or `S.engrave(shape, { on, at, n, up, depth, mat, raise })` | Single-stroke capitals A to Z, 0 to 9 and `. , - ' ! ?` on a 4 by 6 grid; strokes size × 0.16 wide | Signs, plaques, carved names |
| `K.typography`: `T.layout(text, { font: T.fonts.bitmap(), size, align })` then `T.extrude(B, S, run, { id, rig, material, position, depth, res })` | A 6 by 8 pixel font with real lowercase, digits and symbols | Mixed-case words, shop signs |
| `S.stroke({ points, width, depth, pressure, taper }, mat)` and `S.fill({ rings, frame }, mat)` (README, Editable 3D drawing) | Anything drawn as a path or filled outline | Script, logos, hand-drawn letters |

`K.typography`'s default font, Ink Sans, has capitals only: its lowercase are the capitals. The pixel font
(`T.fonts.bitmap()`) has a true lowercase (checked: its "e" and "a" differ from "E" and "A"). `T.extrude` needs a rig and makes one
rig part a glyph (section 2).

- **Sampling.** Give letter solids a `res` at most half their stroke width (0.02 for 0.04 strokes, 0.015 for smaller): at the
  default 0.09 the letters were blobs. That is what makes them costly (section 2).
- **Size.** At least 6 art pixels tall (section 1).
- **Which way it reads.** Lettering laid in the X–Y plane faces +Z and reads left to right from the opening view at yaw 0 (the
  camera sits on +Z looking toward −Z). From behind it reads mirrored, and strokes standing on a board do not show at all (checked).
  A sign that must read from both sides needs a second copy on its back, turned half a turn about the upright axis.

## 5. Neon

- **The tube**: a `S.tube` along the letter paths with a fixed-light material at its brightest place, `{ r: [dark, mid, bright], em:
  true, v: 1 }`, `res` near half the tube's width. It reads well (checked).
- **The glow**: soft haze round it (`B.iso` at density 0.25 with `em` and `nd`) snapped to grey speckle over a busy background, even
  with in-between tones in the palette; a fatter tube behind in a dim tone fused into the stroke (both checked). So paint the glow
  into the surroundings instead: a lamp at the sign (`S.lights.push({ p, r, s })`) before the solids around it are baked, and a `g`
  ramp in their materials in the light's colours. The lamp's ramp only shows where the lamp outweighs the other light: it tinted
  nothing in daylight and showed clearly round the lamp at night (checked on a test block, references/ink-studio.md, 2.3; a whole
  neon sign at night was not drawn). Dark surfaces behind the tube make it read best.

## 6. A glass case

```js
S.box([x, y, z], [0.25, 0.26, 0.25], K.look.glass([PALE], { a: 0.13 }), { ghost: true, res: 0.06 });
```

`K.look.glass(ramp, { a })` is `{ r, a, glass: true }`: a soft solid of density `a` that bends what is behind it (the finish's
`refract`). `ghost: true` draws it on its own: it takes no part in the joins or the shadows (`src/sculpt.js`), so the case neither
melts into what stands inside it nor shades it. How solid: 0.06 was almost invisible, 0.13 faint and read as glass, 0.3 clouded what
was inside (checked side by side). Use 0.1 to 0.15, a pale palette colour, and a coarse `res`: the glass is a haze, not a surface.

## 7. An interior lit by one sun and a fill

Light is baked (references/ink-studio.md, 2.2), so a room's inside gets only what reaches it through its openings at bake time. A
test room with an open front, mean ramp places (1 darkest to 7 lightest):

| Light | Back wall | Floor | Roof, outside |
| --- | --- | --- | --- |
| Default sun | 2.00 | 3.27 | 5.95 |
| Sun turned low into the opening | 3.38 | 4.03 | 4.73 |
| `S.amb = 0.3` | 3.29 | 4.08 | 6.95 |
| `S.sky = 0.5` | 2.81 | 4.49 | 6.95 |
| One lamp inside, `{ p: [0, 1.4, 0], r: 2.6, s: 0.5 }` | 2.80 | 3.68 | 5.95 |

So: keep the sun for the outside, and put one fill lamp inside, near the ceiling in the middle of the room, reaching about the room's
size at half strength. It lifts only the inside. Raising `amb` or `sky` lifts the inside as much but washes out everything outside;
turning the sun into the opening changes the whole scene. The lamp's `sh` and stronger contact shade (`S.aoK`) barely changed the
inside (2.06 for `aoK` 0.8).

## 8. What the file cannot carry, and what to build instead

| Wanted | Why it does not travel | Build instead |
| --- | --- | --- |
| A real sky and sun (`skyEnvironment`, `celestialTracks`, `liveSun`) | Drawn by ink-studio's renderers, not stored as splats | Far splats and a fixed-light sun disc (section 3, checked); point `S.sun` toward the disc so the baked light agrees with it |
| Lamp or flame light | Light is baked once; nothing lights the scene as it plays | A lamp in `S.lights` with `g` ramps for the light it casts, fixed light (`em`) on the source, `flame()` for the flame itself, and flicker or pulse on its splats (checked) |
| Light that stays put while a part turns | A part's colours are baked onto its splats and turn with it (checked: a wheel's lit top comes round to its side) | Rock the part through a small swing so its dark side never comes round, or accept the dark side; or bake the lit side's colours into a material that does not depend on the sun (`em`, `tex`) |
| Water reflections (`reflections`, `water`) | Live reflections are drawn per view | Paint them: short level sticks under the reflected thing, in its colours, swaying a little (kind 11) on a flat disc of water (checked); a sea: section 9 |
| More than one cloth | The file stores one simulated cloth | Swaying shapes: sticks or discs with sway (kind 11), or a rigid part that swings with sin(2π k t / L) (checked) |
| Limbs that bend (bones, puppets) | Bones bend splats; the file moves rigid parts only | Rigid parts on `K.rig`, each limb its own `tag`, hung on its parent with `rig.child` (checked, next row), with the joints overlapping so no gap opens as they turn |
| Drifting clouds | A cloud that drifts away does not come back in the loop | A ring of identical clouds as one rig part that turns one cloud-spacing a loop: twelve clouds round the upright axis turning a twelfth of a turn in L seconds came round with no visible jump (checked). The bake then prints that part as 0.5 from where it began, since the ring itself is a twelfth of a turn on; the GIF's seam check is the test here (32,032 pixels changed at the seam, against 29,608 to 42,912 between neighbouring frames). Sway tied to position (kind 11) gives a wobble in place |
| Orbit about anything but the world's upright axis | Kind 5 orbits the upright axis only | A rig part turned by `K.M.rot(axis, 2π k t / L)` about any axis and point (checked: a wheel on a level axis, with an arm hung on it by `rig.child`, came round to within 1e-11 and proved at 0.005%) |
| Sways bound to a wind field (`windField`, flag 8192) | The format refuses the wind flag | Plain sway (kind 11); vegetation helpers already sway |
| Particles: sparks, rain, snow, smoke | Pools are live | Hand-placed splats with fall, rise, blink, bob or flicker; `motes()` for drifting specks (references/format.md, 4); snow and smoke worked below the table |
| Per-pixel looks: tone, stipple, colour stacks, outlines by material | Drawn per pixel by ink-studio | Bake the colour choice into materials (`tex`, `rf`, `mod`, `by`), the finish's `dither`, `outline` and `ao` |
| A camera of its own field of view (`cam.fov`) | The baker writes the toolkit's 38 degrees | Leave `fov` out; the proof fails if it is set (79% of a view's art pixels differed) |

**Snow and smoke**, checked at `22c23d8` on a hut with a chimney under falling snow (8,673 splats, 316 of them moving; `dist: 15`,
`detail: 31`, an 8-second loop `L`; proved at 0.006% to 0.010%):

```js
// smoke: 16 puffs, two rises a loop, each rising 1.5 units and growing from 0.6 to 1.9 times its size
for (let i = 0; i < 16; i++)
  B.iso(0.35 + B.rr(-0.03, 0.03), 1.66, B.rr(-0.03, 0.03), 0.05, B.P[SMOKE], 2.2,
    { k: 3, ph: i / 16, sp: (1.5 * 2) / L, rg: 1.5, ex: 1.3, em: 1 });
// snow in the air: 300 flakes over 6 by 6 units, each falling once a loop through 3, 4 or 5 units
for (let i = 0; i < 300; i++) {
  const rg = B.pick([3, 4, 5]);
  B.iso(B.rr(-3, 3), B.rr(0.5, 5), B.rr(-3, 3), 0.01, B.P[FLAKE], 3, { k: 2, ph: B.R(), sp: rg / L, rg, ex: 0, em: 1 });
}
```

- **Speeds.** For fall and rise `sp` is world units a second and `ph` a fraction of a cycle (references/ink-studio.md, 2.4), so
  `rg / L` passes once a loop and `2 rg / L` twice. With the phases spread evenly (`i / 16`) a puff leaves the chimney every
  quarter of a second and the column is never empty. The flakes fall 0.375 to 0.625 units a second, about 12 to 20 art pixels.
- **Sizes.** A flake of size 0.01 draws as one art pixel. A puff of 0.05 starts at 0.6 times that and ends at 1.9 (`ex: 1.3`).
- **Density.** A rising splat's density is multiplied by (1 − u), u the part of the rise done (references/format.md, 4), and it is
  solid while that stays at 1 or more. At 2.2 a puff is solid to u = 0.55 and thins over the upper half: a solid column with a soft
  head. At 6 it is solid to 0.83 and only the topmost puff thins.
- **A hollow diamond.** A thinning puff is a soft splat, and its blend with the sky is snapped to the nearest palette colour. With a
  lavender in the palette (used on the hut's door) lying between the smoke and the sky, each thinning puff drew a lavender ring round a
  paler centre, a small diamond at stage size; at density 6 the top puff showed it clearly, and thinning flakes left lavender
  specks. It is the palette, not the kind: with two shades from the sky to the smoke in its place (`0x6f84b6` and `0xa7b6d8`,
  between the sky's `0x3a4f86` and the smoke's `0xdfe6f2`), the same puffs thinned through those shades into a soft head. For a
  soft puff, give the palette a ramp from the sky's colour to the smoke's and keep other colours from lying between them.

## 9. Water

The file has no water surface (section 8), but a sea of flat discs at the waterline bakes. From the lighthouse scene:

- **Cut away everything under the waterline.** The sea's discs take `nd` (without it their edges draw dark lines between them,
  section 3), so they hide nothing from the outline, and rock under the water is traced through the sea. One `neg` box under the
  waterline, before `S.bake()`, removes it: `S.box([0, -10.06, 0], [60, 10, 60], wet, { neg: true });` for a waterline at y −0.06.
- **The near sea**: discs of size 0.075 on a hexagonal grid 0.13 apart at y 0, skipping points inside the rock
  (`S.sdf(x, 0.02, z) < 0.01`), in three tones from `B.fbm`. Each is `nd` and either blinks (kind 4, four times a loop) or sways
  (kind 11, twice a loop, range 0.03), its phase taken from its place along the wave, so swells roll through.
- **Foam** where `S.sdf` is under about 0.2: pale discs bobbing fast (kind 6, range 0.03).
- **The far sea**, out to the horizon: rings of discs, `em` and `nd`, spaced 0.25 + 0.03 r apart and paler in bands with distance;
  glints are short level sticks across the line of sight, blinking, where the low sun's path lies on the water.

## 10. Small figures

A figure about 1.3 units tall (about 40 art pixels at `detail: 31`) reads when it is stylised: a big head and short limbs. From the
mansion-grounds scene, which has five:

- **A frame per figure**: an origin, a turn (`K.M.rot([0, 1, 0], a)`) and a scale, so every point is written in the figure's own
  units and a pose is the three points of each limb.
- **One melted group** (`S.grp(0.03)`, `res` 0.026) for the body: legs as `S.tube` through three points (radius 0.09 to 0.08),
  flattened balls for boots, pelvis and torso, arms as tubes (0.066 to 0.058) ending in ball hands, and a head ball of radius 0.235,
  about a third of the height across.
- **The face**: a smaller ball in skin set into the front of the head (radius 0.19), eyes as two discs of size 0.026. A head about
  14 art pixels across has room for eyes of a pixel or two and little more (section 1).
- **Costume by material**: a ramp for each garment; stripes with `rf` returning another ramp by the point's place in the frame.
- **A moving limb** is a rig part (`tag`) turned about its shoulder by sin(2π k t / L).
- **Pose for the opening view**: the arm nearest the camera hangs low, so it hides neither the face nor what the figure holds.

## 11. Dusk light

The lighthouse scene and the mansion-grounds scene lit dusk the same way:

- **A low sun**, its upward part 0.24 to 0.55 (`B.norm([-0.73, 0.24, -0.69])`, `B.norm([-0.5, 0.55, 0.66])`), `S.sunK` 0.78 to
  0.85, `S.amb` 0.2 to 0.22, `S.sky` 0.22 to 0.24.
- **Warm lights** at fires, lamps and windows (`S.lights`, reach 2.2 to 2.7 for a fire or lamp, 0.7 for a window; strength 0.6
  to 0.95) and `g` ramps in warm colours on what they light (references/ink-studio.md, 2.2).
- **Ramps that run cool to warm**: the sky from deep violet overhead through magenta and coral to pale gold at the horizon, nine or
  ten steps; stone, grass and paint ramps whose dark ends lean violet or blue and whose light ends lean gold; a sunlit ramp (`s`)
  for faces turned to the sun.
- **A sky that agrees with the light**: warm round the sun's bearing (from `S.sun`), the sun's disc at the horizon in fixed light
  (`em`), and the first stars overhead, flickering or blinking (kind 1 or 4).

## 12. A cape

One cloth (references/ink-studio.md, 2.5, says how its shape, shading and loop work). From the mansion-grounds scene, on a figure
1.3 units tall:

```js
const cape = K.cloth(B, {
  at: shoulderLeft,                            // the top-left corner
  u: [w, 0, 0], v: [0, -1.02, 0.25],          // the top edge across the shoulders; the side hanging down and back
  nu: 8, nv: 11, pins: (i, j) => j === 0,     // the top row held
  wind: (x, y, z, t) => {                     // repeats every loop: whole cycles of LOOP only
    const g = 1 + 0.4 * Math.sin((TAU * 2 * t) / LOOP + 0.8 * x) + 0.25 * Math.sin((TAU * 5 * t) / LOOP + 3 * y);
    return [-2.3 * g, 0.5 * g, 1.5 * g];
  },
  pattern: (u, v) => (v > 0.93 ? HEM : BODY), // ramps; null leaves a piece out
  sdf: S.sdf, sun: S.sun
});
// after the finish: K.stage(W).add(cape)
```

Its seam was 0.004 units with the defaults. Its ramps repeat their middle reds (`[RED[0], RED[1], RED[2], RED[2], RED[3], RED[3]]`)
so full sun stops short of the palest. The throne-hall scene's cloak (20 by 12 points, pinned on part of one edge) cut its outline
with `null`, gave its hem a gold ramp, set `amb: 0.12, sunK: 1` for a wider spread of shade, and closed to 0.003.

## 13. Steep ground

`S.ground` is for nearly level ground: it lays its points on a level grid at the height `h(x, z)`, so along a slope they lie
`res` / cos(slope) apart and the background shows through in stripes. On the peak below, `S.ground` at `res` 0.06 (9,016 splats)
and even at 0.03 (36,077) striped its steep face. For hills, cliffs and peaks, write the height as one field solid
(`S.implicitForm`, references/ink-studio.md, 2.3), as the toolkit's own `examples/shaped-mist-ravine.js` does for its riverbed
(`docs/geometry-shaped-atmosphere.md`). The toolkit's terrain proper, `P.biomeWorld` in `docs/procedural.md` (a height `h(x, z)`
with caves cut from it, realised in chunks), is for a page that streams a world; its example needs a host page. The other
terrain tools there (`routes.terrain`, `hydrology`, `supportSkirt`, `clipHeightMesh`) place, route and cut against a height field
and lay no ground of their own.

Checked at `22c23d8`: a peak 3 units high with a cliff on one side, over a region 6 by 5 by 6 units (`dist: 15`, `detail: 31`, an
art pixel 0.032 units):

```js
const H = (x, z) => 3 * Math.exp(-(x * x + z * z) / 3.2)                      // the peak
  - 1.4 / (1 + Math.exp(-(x - 0.6) / 0.06)) * Math.exp(-(z * z) / 2)          // a cliff: 1.4 units down across about 0.3
  + 0.25 * (B.fbm(x * 1.5, 0, z * 1.5, 3) - 0.5);                             // roughness
const lo = [-3, -1.6, -3], hi = [3, 3.4, 3], RES = 0.05;
const sd = (x, y, z) => Math.max((y - H(x, z)) * 0.65,                        // inside below the height,
  lo[1] - y, lo[0] - x, x - hi[0], lo[2] - z, z - hi[2]);                     // closed by the region's box: sides and a floor
const rock = { r: [1, 2, 3, 4, 5], top: { min: 0.6, r: [4, 5, 7] } };         // snow on what faces up
S.merge = 0.5;                                                                // the tiles overlap: drop points laid twice
const CELL = RES * 0.76, on = v => Math.round(v / CELL) * CELL;               // corners on whole spacings: one lattice
const xs = [on(lo[0]), on(0), on(hi[0])], zs = [on(lo[2]), on(0), on(hi[2])];
for (let i = 0; i < 2; i++)
  for (let j = 0; j < 2; j++)
    S.implicitForm({ sd, bounds: { min: [xs[i], on(lo[1]), zs[j]], max: [xs[i + 1], on(hi[1]), zs[j + 1]] } }, rock, { res: RES });
S.bake();
```

- **What it gave.** 78,209 splats, 1.43 MB (0.35 MB gzipped), proved at 0.003%; from above and from every side the tiles meet with
  no seam, and the sides and floor are solid. Without the box (`sd` the height part alone) the same tiles laid 29,147: an open
  sheet, whose underside shows when a visitor tilts the view to look up at it. Without merge, 105,112.
- **Tiles, because of the budget.** The whole region as one solid at `res` 0.05 is about 3.4 million samples, over the 3,000,000
  any one field solid may take, and the bake stops at `S.bake()` with `Error: Implicit form exceeds its sample budget`. Each of the
  four tiles is about 880,000. Count a tile as about (W / s + 3) × (H / s + 3) × (D / s + 3) for spacing s = `res` × 0.76.
- **The 0.65.** A height difference is not a distance on a slope: the distance is the difference over √(1 + g²) for a slope of
  gradient g. The factor does not move the ground, since the points go where the field changes sign: one solid at `res` 0.06
  laid the same 36,448 splats at 0.3, 0.65 and 1. It changes the light, which reads the field for shadow and occlusion: at 0.3
  the whole peak came out a shade darker, at 1 a shade paler. 0.65 is the ravine example's own; the toolkit's terrain takes a
  bound on the slope (`terrainSlope`) for the same reason.
- **Snow by facing.** `top: { min: 0.6, ... }` takes over where the surface faces up by more than about 0.6, with noise on the
  boundary (references/ink-studio.md, 2.3): slopes under about 53° take snow, and the cliff, near 80°, stays rock.
