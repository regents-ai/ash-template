# The baked scene file

One scene is one file (`.bin`). It holds every splat of the scene at rest, the tables its splats point into, how the scene moves over
one loop, and the camera and look it is drawn with. This note says what every number is and how to draw a picture from them.

- `kit/format.cjs` holds the layout and the small codecs (the baker and the decoder share it).
- `kit/decode.cjs` is a working reader in plain JavaScript: it turns a file back into the toolkit's own rows at any frame.
- `kit/verify.cjs` shows a file draws what the toolkit drew (section 8).
- `player/scene.js` reads the same file in the browser; `player/painter.js` draws it (references/painter.md).

A splat is a small, soft, coloured blob: a centre, a 3 x 3 covariance that gives its size and shape (a sphere, a disc, a needle), a
colour from the scene's palette, and a density. The picture is a coarse grid of "art pixels", each the palette colour nearest to what
the blobs blend to there.

## 1. Layout

Little-endian throughout. The file is the four bytes `RSPL`, a 280-byte header, then, from byte 284, the blocks of section 1.2, one
after another, in the order listed. Each block starts on a multiple of four bytes (any gap before it is zero bytes), so every block
can be handed to the graphics card, or viewed as a typed array, as it is. Where each block starts follows from the header's counts
alone.

### 1.1 Header

Counts and palette places are unsigned 32-bit integers (`u32`); every other number is a 64-bit float (`f64`), so nothing in the header
is rounded. In order:

| Field | Type | Meaning |
| --- | --- | --- |
| `version` | u32 | 1 |
| `splats` | u32 | Number of splats, N |
| `moving` | u32 | The first `moving` splats move by their kind (section 4) and carry motion numbers; the rest do not |
| `styles` | u32 | Entries in the style table (at most 256) |
| `motions` | u32 | Entries in the motion table (at most 256) |
| `parts` | u32 | Rigid parts, part 0 included (at most 256) |
| `frames` | u32 | Frames in one loop (loop x 30) |
| `cloth` | u32 | Cloth dabs (0 when the scene has no cloth) |
| `clothFirst` | u32 | The first cloth dab's splat number; the dabs are splats `clothFirst` to `clothFirst + cloth - 1` |
| `colours` | u32 | Palette entries (at most 256) |
| `chunkSize` | u32 | Splats per position box (256) |
| `fogIndex` | u32 | Palette place of the fog colour |
| `outlineIndex` | u32 | Palette place of the outline colour |
| `backdropIndex` | u32 | Palette place of the empty background (0: the toolkit's backdrop is the palette's first colour) |
| `loop` | f64 | Loop length in seconds, as given to the baker |
| `clockStart` | f64 | The motion clock at the start of the loop (15 loops); section 3 |
| `logScaleMin`, `logScaleMax` | f64 | Range of the stored sizes' natural logarithms |
| `clothMin`, `clothMax` | 3 x f64 | Box holding every cloth dab's centre over the whole loop (zeros without cloth) |
| `clothRadius`, `clothThickness` | f64 | Every cloth dab's disc: radius (standard deviation across it) and thickness |
| `camTarget` | 3 x f64 | The point the camera looks at |
| `camDist` | f64 | Camera distance from the target |
| `camPitch`, `camYaw` | f64 | The camera's starting angles, radians |
| `fov` | f64 | Vertical field of view, radians (the toolkit's 38 degrees) |
| `detail` | f64 | Art pixels per world unit at the camera's own distance |
| `radius` | f64 | The scene's radius R, the yardstick for fog, depth, shade and outline |
| `fogStart`, `fogMax` | f64 | Where fog starts (0 to 1 of the depth range) and its full strength |
| `outlineEdge` | f64 | Depth step that draws an outline, in world units (0: no outline) |
| `shadeStrength`, `shadeRange` | f64 | Contact shade: how dark (0: none), and the depth gap (world units) it reaches across |
| `dither` | f64 | Dither strength |
| `glassBend` | f64 | How far glass bends what is behind it, in art pixels per unit of glass slope |

The baker fills the look from the finished world as the toolkit's renderer reads it: `shadeStrength` is `ao.k` (0.5 when `ao` is set
without `k`, 0 without `ao`), `shadeRange` is `ao.range` or 0.6, `glassBend` is `refract` or 6.

### 1.2 Blocks

| Block | Element | Per entry | Entries | Meaning |
| --- | --- | --- | --- | --- |
| `palette` | u32 | 1 | colours | 0xRRGGBB |
| `styleDensity` | f32 | 1 | styles | Density (section 2.4) |
| `styleCode` | u8 | 1 | styles | Kind and flags (section 2.4) |
| `stylePart` | u8 | 1 | styles | The rigid part that carries the splat |
| `motionRange` | f32 | 1 | motions | A motion's range, r |
| `motionExtra` | f32 | 1 | motions | A motion's extra number, e |
| `chunkBounds` | f32 | 6 | ceil(N / chunkSize) | A box for each run of `chunkSize` splats: min x, y, z, then max x, y, z |
| `position` | u16 | 3 | N | Centre within its run's box |
| `rotation` | u32 | 1 | N | The turn of its axes (section 2.2) |
| `scale` | u16 | 3 | N | Size along each axis, as a logarithm |
| `colour` | u8 | 1 | N | Palette place |
| `style` | u8 | 1 | N | Style table entry |
| `cycles` | i8 | 1 | moving | Whole cycles of its motion in one loop (negative: the other way) |
| `phase` | u16 | 1 | moving | Where in its cycle it starts |
| `motion` | u8 | 1 | moving | Motion table entry |
| `track` | f32 | 12 | frames x parts | Each part's matrix at each frame (section 3.1) |
| `clothPosition` | u16 | 3 | frames x cloth | Each cloth dab's centre at each frame, within the cloth box |
| `clothNormal` | u8 | 2 | frames x cloth | Each cloth dab's facing at each frame (section 3.2) |
| `clothColour` | u8 | 1 | frames x cloth | Each cloth dab's palette place at each frame |

Entry k of a per-frame block for frame f and part or dab j is entry `f * (parts or cloth) + j`.

The splats are in the toolkit's order with the moving ones first (`kit/format.cjs`, `fileOrder`), so splat n of the file is not row n
of the toolkit's world; `decode.cjs` and `verify.cjs` keep the two orders side by side.

## 2. A splat at rest

For splat n (counting from 0):

### 2.1 Centre

The splat's run is c = floor(n / chunkSize), its box lo = `chunkBounds[6c .. 6c+2]`, hi = `chunkBounds[6c+3 .. 6c+5]`. For each axis k:

    p_k = lo_k + (hi_k - lo_k) * position[3n + k] / 65535

A run's box is only as big as its 256 splats need, so a step is usually a few hundred-thousandths of a world unit; where a run is
spread wide (a sky of scattered splats) it reaches about a thousandth.

### 2.2 Shape

The covariance is Σ = R S² Rᵀ: R turns the splat's own axes into the world's, S = diag(σ₀, σ₁, σ₂) holds its standard deviation along
each of them.

The turn is a unit quaternion (x, y, z, w), stored by its three smallest parts. In `rotation[n]`, bits 30 and 31 give m, the place (0
to 3, in the order x, y, z, w) of the part that was left out; the other three follow in order in ten bits each, bits 20 to 29, 10 to 19
and 0 to 9. A stored ten-bit value v stands for (2v / 1023 − 1) / √2. The part left out is the largest, made positive when stored (a
quaternion and its negative are the same turn), so it is √(1 − the sum of the other three squared).

    R = | 1 − 2(y² + z²)   2(xy − zw)       2(xz + yw)     |
        | 2(xy + zw)       1 − 2(x² + z²)   2(yz − xw)     |
        | 2(xz − yw)       2(yz + xw)       1 − 2(x² + y²) |

    σ_k = exp(logScaleMin + (logScaleMax − logScaleMin) * scale[3n + k] / 65535)

### 2.3 Colour

`palette[colour[n]]`, as 0xRRGGBB; each channel / 255 gives 0 to 1.

### 2.4 Style: density, kind, flags, part

s = `style[n]`. The density α = `styleDensity[s]`: 1 or more is a solid splat, with a crisp edge, which hides what is behind it and
writes depth; under 1 is a soft one, a haze that only tints. The part is `stylePart[s]`. The code `styleCode[s]` holds:

| Part of the code | Meaning | The toolkit's kind bit |
| --- | --- | --- |
| code & 15 | The kind of motion (section 4) | the same |
| code & 16 | No depth: the splat never writes depth, even when solid (so it draws no outline and casts no contact shade) | 16 |
| code & 32 | No fog (an emissive splat) | 32 |
| code & 64 | Glass (sections 5.3 and 5.4) | 256 |

The toolkit's bit 64 (a splat drawn only from behind, `world.back`) is not carried; the baker refuses it.

### 2.5 Motion numbers (the first `moving` splats only)

m = `motion[n]`; range r = `motionRange[m]`, extra e = `motionExtra[m]`. The speed comes from the whole number of cycles c =
`cycles[n]` it makes in one loop L:

- kinds 2 and 3 (fall and rise): ω = r c / L, in world units a second; the phase φ = `phase[n]` / 65536 is a part of a cycle, 0 to 1;
- every other kind: ω = 2π c / L, in radians a second; φ = 2π `phase[n]` / 65536 is an angle.

Every motion therefore comes round exactly once a loop (but see the sway in section 4). The baker refuses a speed that is not a whole
number of cycles a loop; `kit/loop.cjs` snaps a world's speeds before it is returned (SKILL.md, The loop).

## 3. The loop

The motion clock is t = clockStart + τ, with τ the time into the loop, 0 ≤ τ < L. The bake starts the loop fifteen loops in, so
anything simulated step by step (a cloth) has settled into a steady swing, and because the sway's second term (section 4) need not make
a whole number of cycles a loop its starting point is part of the scene: use t, not τ, in the motion maths. A 32-bit float holds t to
about one hundred-thousandth of a second at these clocks, which is plenty; a painter that works in turns, frac(c · clockStart / L) +
c · τ / L, keeps the clock small (as `player/painter.js` does).

Frame f of the loop is the moment τ = f / 30: the part matrices and the cloth are stored for those moments. Between them a painter may
hold the frame before or blend the two frames either side; the motions of section 4 are worked from t directly at any moment. The
player holds the frame before, f = floor(30 τ), so at every stored moment it draws exactly what the file holds.

What changes from frame to frame, and nothing else does: the rigid parts (3.1), the cloth dabs (3.2), and the kind motions (4).
Densities, kinds, flags and colours never change, except a cloth dab's colour.

### 3.1 Rigid parts

At frame f, part p's twelve numbers are `track[(f * parts + p) * 12 ..]`: a 3 x 3 matrix A by rows, then a shift b. A splat on part p
is carried to

    p' = A p + b,      Σ' = A Σ Aᵀ

Part 0 is always the identity. A scene's parts are the tags of `K.rig` (references/ink-studio.md, Moving parts), in their order.

### 3.2 Cloth

One `K.cloth` per scene. The cloth dabs are part 0, kind 0, and their rest numbers in the per-splat blocks are their first frame. At
frame f, dab j (splat n = clothFirst + j, entry k = f * cloth + j) takes:

- its centre: `clothMin_i + (clothMax_i − clothMin_i) * clothPosition[3k + i] / 65535` for each axis i;
- its facing ν: opened out from two bytes a = `clothNormal[2k]`, b = `clothNormal[2k + 1]`. Let u = 2a / 255 − 1, v = 2b / 255 − 1, z =
  1 − |u| − |v|. Where z < 0, replace (u, v) by ((1 − |v|) sign u, (1 − |u|) sign v), signs taken before the change. ν is (u, v, z)
  made unit length;
- its shape: a disc facing ν, Σ = ρ² I + (h² − ρ²) ν νᵀ, with ρ = clothRadius and h = clothThickness;
- its colour: `palette[clothColour[k]]`.

A cloth blown by gusts does not come back to where it began in one loop; the baker prints how far it is from its first frame a loop
on, and the GIF's seam check shows what that costs (references/gif.md).

## 4. Kinds of motion

Each kind changes the splat after its part has carried it, from its carried centre (x, y, z), density α and the clock t; a size factor
g, 1 unless a kind sets it, scales the covariance to g² Σ'. sstep(a, b, x) is the smooth step: with u = clamp((x − a)/(b − a), 0, 1),
it is u²(3 − 2u). frac(x) = x − floor(x).

| Kind | Name | Change |
| --- | --- | --- |
| 0 | still | none |
| 1 | flicker | α ← α (0.62 + 0.38 sin(ωt + φ)); its screen centre snaps to the middle of the art pixel it falls in |
| 2 | fall | u = frac(ωt / r + φ); y ← y − u r; α ← α (1 − u²); g = 1 + u e |
| 3 | rise | u = frac(ωt / r + φ); y ← y + u r; x ← x + 0.25 u sin(7u + 50φ); α ← α (1 − u) sstep(0, 0.1, u); g = 0.6 + u e |
| 4 | blink | adds 0.3 sstep(0.75, 1, sin(ωt + φ)) to each colour channel (before fog; section 5.3) |
| 5 | orbit | turns its centre about the world's upright axis by ωt: x ← x cos ωt + z sin ωt, z ← z cos ωt − x sin ωt (from the old x and z). Its shape is not turned |
| 6 | bob | y ← y + r sin(ωt + φ) |
| 7 | pulse | α ← α (0.82 + 0.18 sin(ωt + φ)) |
| 11 | sway | x ← x + r sin(ωt + 1.3y + 0.9z + φ); y ← y + 0.6 r sin(1.3ωt + 1.1x + φ), with x, y, z the values before the sway |

Kinds 8 to 10 and 12 to 15 are not carried; the baker refuses a splat of one. The sway's second term turns 1.3 times as fast as its
first, so over one loop it makes 1.3 c cycles where the first makes c. `kit/loop.cjs` picks, of the counts either side of a sway's own,
the one that brings 1.3 c nearest a whole number: c = 10 makes 13 and closes exactly; c = 3 makes 3.9, and where the loop wraps a
swaying leaf's height jumps by at most 0.6 r × 2 sin(0.1π) ≈ 0.37 r. For the small ranges sways use (a few hundredths of a world unit)
that is well under an art pixel. The toolkit's own loops have the same seam.

Whether a splat is solid is decided after its kind has changed α: a falling drop of density 3 at 60% stays solid.

## 5. Drawing a picture

This is the toolkit's own drawing (its CPU renderer, with none of its optional looks), which `verify.cjs` uses for both sides.

### 5.1 Camera

Yaw y and pitch p (the starting ones are camYaw and camPitch; dragging changes them), and a zoom z (1 is the scene's own distance). The
eye is at distance d = camDist / z from the target T:

    E = T + d (cos p sin y, sin p, cos p cos y)

The camera's back axis is k = (E − T) / |E − T|; its right axis i = (k_z, 0, −k_x) made unit length, so the horizon stays level; its up
axis j = k × i. A point P is at view coordinates (c_x, c_y, c_z) = (i · (P − E), j · (P − E), k · (P − E)); in front of the camera c_z
< 0. Splats with c_z > −near are not drawn, near = max(0.4, 0.15 d). (Straight up or down, p = ±π/2, has no right axis; keep |p| a
little under π/2. The player stops at 86 degrees.)

### 5.2 The art-pixel grid

On a stage w by h screen pixels, an art pixel is q screen pixels wide:

    s = z (the zoom), ρ = detail * s^(1/2 if s > 1, else 1/4)
    q = clamp(round(h / (2 tan(fov/2) ρ d)), 1, 18)

Here, and in section 5.4, round takes halves up, round(x) = floor(x + 0.5), as JavaScript's Math.round does. The grid is W = ceil(w /
q) by H = ceil(h / q) art pixels, shown as q by q blocks from the top left. The focal length in art pixels is
F = H / (2 tan(fov / 2)). Below, art-pixel rows count up from the bottom (row 0 is the bottom row on screen); flip them for the screen.

A splat's centre lands at sx = W/2 + F c_x / (−c_z), sy = H/2 + F c_y / (−c_z) (a flickering splat then snaps, section 4).

Its footprint is its covariance carried to the screen. With ι = −1 / c_z, and its view position nudged inside 1.3 times the frame
before taking the slope (x̃ = clamp(c_x ι, −1.3 W / 2F, 1.3 W / 2F) / ι, ỹ likewise with H),

    J = | F ι   0     F x̃ ι² |      M = J V,   V the 3 x 3 whose rows are i, j, k
        | 0     F ι   F ỹ ι² |

    | a  b |  =  M (g² Σ') Mᵀ  +  0.15 I
    | b  c |

The 0.15 gives every footprint a least size, about 0.4 of an art pixel in standard deviation. With δ = ac − b², skip the splat if
δ ≤ 0; otherwise it reaches ±min(3√a, 2048) art pixels across and ±min(3√c, 2048) up and down from its centre (skip it if that box
misses the grid). Its weight at an art pixel whose middle is (dx, dy) from the centre is

    w = α exp(P),   P = −(c dx² − 2b dx dy + a dy²) / (2δ)

skipping pixels where P > 0 or P < −4.5. Its cover there is

- solid (α ≥ 1): A = 0.99 sstep(0.38, 0.62, w), the crisp edge;
- soft: A = min(0.99, w);

and pixels with A < 0.004 are skipped.

### 5.3 Order, colour, fog and blending

Every art pixel starts as `palette[backdropIndex]`, depth D = 1 and glass G = 0. Splats are drawn from far to near: sorted by c_z,
smallest (farthest) first, splats at the same depth in file order. Splats with α ≤ 0 after their kind are not drawn.

A splat's colour is its palette colour plus any blink. Its depth is dn = clamp((−c_z − (d − R)) / (2R), 0, 1), 0 at the front of the
scene and 1 at the back. Fog is drawn only when fogMax > 0 and fogStart < 1; then, unless the splat has the no-fog flag, its colour
moves toward the fog colour `palette[fogIndex]` by sstep(fogStart, 1, dn) fogMax. Then each channel is capped at 1.

At each pixel it covers, with cover A:

- colour ← A splat colour + (1 − A) colour;
- if it is solid and lacks the no-depth flag: D ← A dn + (1 − A) D, and G ← (1 − A) G;
- otherwise, if it is glass: G ← min(1, G + A/2).

### 5.4 Finishing each art pixel

Reads outside the grid take the nearest pixel inside it. For the art pixel (x, y), with C its blended colour:

1. Glass bends: gx = G(x+1, y) − G(x−1, y), gy = G(x, y+1) − G(x, y−1). If G(x, y) + |gx| + |gy| > 0, C becomes the blended colour at
   (x + round(glassBend gx), y + round(glassBend gy)).
2. Contact shade, when shadeStrength > 0: for the eight neighbours at (±2, 0), (0, ±2) and (±1, ±1), let δ = (D(x, y) −
   D(neighbour)) / (shadeRange / 2R); each with 0.08 < δ < 3 adds min(1, δ) to an occlusion o. C ← C (1 − shadeStrength min(1, o / 4)).
3. Outline, when outlineEdge > 0: if max(2D(x,y) − D(x−1,y) − D(x+1,y), 2D(x,y) − D(x,y−1) − D(x,y+1)) > outlineEdge / 2R, the pixel
   is `palette[outlineIndex]`, and step 4 is skipped.
4. Dither: with the 4 x 4 table B = 0 8 2 10 / 12 4 14 6 / 3 11 1 9 / 15 7 13 5 (rows by y mod 4, columns by x mod 4, y counted from
   the bottom), add (B + 0.5)/16 − 0.5 times 0.105 dither to each channel, then clamp each to 0 to 1. (0.105 = 0.35 x 0.3, the
   toolkit's own scale.)
5. Palette: the pixel takes the palette colour nearest C by 0.3 Δred² + 0.55 Δgreen² + 0.15 Δblue², the first of any tie.

## 6. What a file costs

A splat costs 18 bytes at rest (6 centre, 4 turn, 6 size, 1 colour, 1 style) and a moving one 4 more (cycles, phase, motion). Each
rigid part costs 48 bytes a frame (11.5 KB a part for an 8-second loop), and each cloth dab 6 + 2 + 1 = 9 bytes a frame (2.2 KB a dab
for 8 seconds). The baker prints the raw and gzipped size and every block over 20 KB.

| Scene (8-second loop) | Splats | Raw | Gzipped |
| --- | --- | --- | --- |
| ink-studio's `examples/sculpt.js` | 4,027 | 0.08 MB | 0.02 MB |
| ink-studio's `examples/cloth.js` (396 dabs) | 1,413 | 0.89 MB | 0.66 MB |
| 300,000 splats, a tenth of them moving by their kind, two parts (by the costs above) | 300,000 | about 5.5 MB | about half of that |

A served `.bin` should go gzipped (references/hosting.md). Keep a file under about 9 MB raw: a cloth is the expensive part, so a big
cloth wants a shorter loop or fewer dabs.

## 7. How near the stored numbers are

The baker measures every splat and prints these on each bake. What it printed for ink-studio's examples and a moving scene (an art pixel
is 1 / detail world units at the scene's own distance, 0.071 at detail 14):

| Field | Stored as | Largest error |
| --- | --- | --- |
| Centre | 16 bits within its run's box | about 5e-5 world units (0.0007 of an art pixel); a wide-spread run reaches about 1e-3 |
| Size | 16-bit logarithm | under 0.003% |
| Turn of the axes | three 10-bit parts | about 0.14 degrees |
| Whole covariance | (both of the above) | about 0.1% for round splats; 0.31% for one 4.5 times longer than thick, which takes the turn's error harder (the bake's `whole shape`) |
| Density, kind, flags, part | style table, 32-bit float | exact |
| Colour | palette place | exact |
| Speed, range, extra | whole cycles, 32-bit floats | exact |
| Phase | 16 bits of a turn | under 5e-5 radians; under 1e-5 of a cycle |
| Part matrices | 32-bit floats, every frame | exact |
| Cloth centre | 16 bits within the cloth box | about 1.5e-5 world units |
| Cloth facing | two bytes | under 1 degree (about 0.94); a flat dab tilted that much moves its covariance by 0.96% to 1.38% (the proof's shape figure on a scene with a cloth) |
| Cloth colour, disc size | palette place; header | exact |

The two shape figures measure the same thing at different times: how far a splat's covariance is from the toolkit's, as a share of
its size. The bake's `whole shape` compares every splat at rest with its stored sizes and turn, and a cloth's dabs at their first
frame: `sculpt.js` 0.12%, `cloth.js` 0.19% (its dabs; its other splats 0.11%), a trial scene of 213,405 splats 0.31%. The proof's
`of shape` compares the live scene with the decoded file at each of its three moments, so a cloth's dabs count with the facing
stored for that frame: the same as the bake's for every other splat, and for the dabs 0.96% to 1.38% (0.96% to 1.23% on
`cloth.js`, 1.18% to 1.35% on that trial scene, 1.22% to 1.31% on a throne-hall scene of 371,821 splats, 1.33% to 1.38% on a
trial scene of 344,697 splats).

The turn of the axes is most of what is left. Fifteen bits a part would take a turn 6 bytes instead of 4 and roughly halve the pixels
that differ (section 8); 32-bit floats for every centre and covariance (38 bytes a splat) would remove the difference entirely. Neither
is in this format.

## 8. The proof

`verify.cjs` builds the scene with the toolkit, reads the file back with `decode.cjs`, and has the toolkit's own renderer draw both on a
1440 x 960 stage, from four quarter turns at the starting pitch and from nearly straight above and below (pitch ±1.45), at three
moments of the loop (5/16 and 11/16 of it besides the start). Its row check reports any density, colour, kind, flag, speed, range or
extra that differs (there should be none), and its last line gives the most art pixels that differ in any view.

What it measured: ink-studio's `examples/sculpt.js` 0 or 1 art pixels of 21,600 a view; `examples/cloth.js` at most 0.023% and a scene
with a turning part, a flame and motes at most 0.019%. On scenes of a few hundred thousand splats the same format measures 0.115% to
0.768% (references/proof.md, 1): a blob a hair bigger or turned a fraction of a degree tips a pixel whose blend sat right on the line
between two palette colours. Most differing
pixels have no differing neighbour, and most swap one shade for a near one.

The live scene is walked to each moment one frame at a time, as the bake walked it: a cloth remembers every step it took, so a
different walk leaves it a hair elsewhere and the comparison would no longer be like with like.

The toolkit's pictures are kept in the reference folder with `reference.json` listing each one's camera, art-pixel size, grid, loop
time and clock: the reference for checking any painter (references/proof.md).

## 9. What the baker refuses

The format carries sculpted solids, their palette colours and densities, the kinds of section 4, `K.rig` parts and one `K.cloth`. The
baker stops, naming the cause, on anything else:

- A world field the file does not carry: a look (`look`, per-pixel materials `pix`, `ramps`, `surfaces`, `fine`), a sky, aerial
  perspective, lights, water, atmosphere, reflections, back-facing splats, growth. These draw in the toolkit in ways the player cannot.
  Among those ink-studio `e80d985` sets (each met in its examples): drawn splat outlines (`splatFootprints`, from a material's
  `brush`, `footprint`, `engraving` or `screenPrint`, or the sculptor's `S.stipple`) and print passes (`engraving`); sprites and
  pixel stamps (`spriteSurfaces`, `spriteAtlases`, `pixelStamps`); surface data and light (`surfaceData`, `surfaceLight`,
  `materialAlbedo`, `materialPixelStyles`); shapes and shadows worked out as it draws (`renderSdfs`, `shadowReadability`,
  `highlightCels`); curve splats (`curveSplats` and the other `curve...` fields); clouds (`cloudField`, `cloudRepresentation`);
  weather (`weatherBinding`, `precipitation`, `rainImpacts`); `reflectionProbes`; a camera rig (`cameraRig`).
- A stage that zooms, kicks or grades the camera.
- A world moved by bones (`K.puppet`, `K.bones`; ink-studio's `examples/puppet.js` is refused): bones bend splats, which a rigid part
  cannot carry.
- A splat that moves any other way: particles, frame-local effects, physics, breaking, a second cloth, or one whose density or colour
  changes as the scene plays.
- A kind or flag outside section 2.4 and 4, a speed that is not whole cycles a loop, a hidden pool splat, a flat splat.
- More than 256 colours, styles, motions or parts.

## 10. Notes for a painter

- WebGPU has no three-part 8- or 16-bit vertex formats, so read the per-splat blocks from storage buffers and unpack in the shader: the
  k-th 16-bit value is half of 32-bit word k >> 1 (the low half when k is even). The player puts the whole file in one storage buffer
  and writes each block's start (in words) into the shader as a constant.
- All three per-pixel targets of section 5.3 can share one blend, "over" with the source already multiplied by its cover A (factors
  one, and one minus source alpha), if each splat writes:
  - colour: (A c, A);
  - depth: (A dn, A) when it is solid without the no-depth flag, else (0, 0);
  - glass: (0, A) when it is solid without the no-depth flag, (A/2, 0) when it is glass otherwise, else (0, 0); a target clamped to 1
    caps the glass.
- The depth target needs real precision: shade reacts to depth gaps of 0.002 and the outline to 0.035. A 16-bit float target resolves
  about 0.0005 near 1 and blends everywhere; 32-bit float blending needs WebGPU's float32-blendable feature. Keep the colour target in
  16-bit floats too: rounding to 8 bits before the palette snap moves pixels across shade lines.
- Draw into the W x H art-pixel grid, not the screen; finish there (section 5.4) and show each art pixel as a q x q block.
- Splats are drawn far to near and the order changes as the camera turns. A sort that does not keep file order for equal depths may
  change a few pixels.
- A flickering splat snaps its centre to the middle of its art pixel.
- The part matrices and the cloth's frames go to the graphics card once and are picked by frame number.
- The art-pixel size follows the stage's height in screen pixels (section 5.2): decide whether that means CSS pixels or device pixels.
  The reference pictures use a 1440 x 960 stage. The player uses device pixels (up to three a CSS pixel), so a scene has about the same
  number of art pixels on any screen.
- A stage narrower than three by two steps the camera back so the scene still fits across it: z = min(1, (w / h) / 1.5).
- WGSL rejects a smooth step whose two edges are the same constant, so a painter that writes the header's numbers into the shader as
  constants must leave fog out (fogStart 0, fogMax 0) when the file has none, rather than write sstep(1, 1, dn).
