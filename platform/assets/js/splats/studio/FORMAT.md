# Baked splat scenes

Each scene the page shows is one file in `platform/priv/static/splats/`, named for the scene: `island.bin` and `factory.bin`. A file
holds every splat of the scene at rest, the tables its splats point into, how the scene moves over one loop, and the camera and look it
is drawn with. This note says what every number is and how to draw a picture from them. `decode.cjs` is a working reader in plain
JavaScript; `verify.cjs` shows it draws what the toolkit drew (see the end of this note).

A splat is a small, soft, coloured blob: a centre, a 3 x 3 covariance that gives its size and shape (a sphere, a disc, a needle), a
colour from the scene's palette, and a density. The picture is a coarse grid of "art pixels", each the colour of the palette nearest to
what the blobs blend to there.

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
| `styles` | u32 | Entries in the style table |
| `motions` | u32 | Entries in the motion table |
| `parts` | u32 | Rigid parts, part 0 included |
| `frames` | u32 | Frames in one loop (loop x 30) |
| `cloth` | u32 | Cloth dabs (0 when the scene has no cloth) |
| `clothFirst` | u32 | The first cloth dab's splat number; the dabs are splats `clothFirst` to `clothFirst + cloth - 1` |
| `colours` | u32 | Palette entries |
| `chunkSize` | u32 | Splats per position box (256) |
| `fogIndex` | u32 | Palette place of the fog colour |
| `outlineIndex` | u32 | Palette place of the outline colour |
| `backdropIndex` | u32 | Palette place of the empty sky (0) |
| `loop` | f64 | Loop length in seconds (8) |
| `clockStart` | f64 | The motion clock at the start of the loop (120); section 3 |
| `logScaleMin`, `logScaleMax` | f64 | Range of the stored sizes' natural logarithms |
| `clothMin`, `clothMax` | 3 x f64 | Box holding every cloth dab's centre over the whole loop |
| `clothRadius`, `clothThickness` | f64 | Every cloth dab's disc: radius (standard deviation across it) and thickness |
| `camTarget` | 3 x f64 | The point the camera looks at |
| `camDist` | f64 | Camera distance from the target |
| `camPitch`, `camYaw` | f64 | The camera's starting angles, radians |
| `fov` | f64 | Vertical field of view, radians (38 degrees) |
| `detail` | f64 | Art pixels per world unit at the camera's own distance |
| `radius` | f64 | The scene's radius R, the yardstick for fog, depth, shade and outline |
| `fogStart`, `fogMax` | f64 | Where fog starts (0 to 1 of the depth range) and its full strength |
| `outlineEdge` | f64 | Depth step that draws an outline, in world units |
| `shadeStrength`, `shadeRange` | f64 | Contact shade: how dark, and the depth gap (world units) it reaches across |
| `dither` | f64 | Dither strength |
| `glassBend` | f64 | How far glass bends what is behind it, in art pixels per unit of glass slope |

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

## 2. A splat at rest

For splat n (counting from 0):

### 2.1 Centre

The splat's run is c = floor(n / chunkSize), its box lo = `chunkBounds[6c .. 6c+2]`, hi = `chunkBounds[6c+3 .. 6c+5]`. For each axis k:

    p_k = lo_k + (hi_k - lo_k) * position[3n + k] / 65535

A run's box is only as big as its 256 splats need, so a step is usually a few hundred-thousandths of a world unit; in the sparse sky,
where a run spans tens of units, it reaches about a thousandth.

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

| Part of the code | Meaning |
| --- | --- |
| code & 15 | The kind of motion (section 4) |
| code & 16 | No depth: the splat never writes depth, even when solid |
| code & 32 | No fog |
| code & 64 | Glass (sections 5.3 and 5.4) |

### 2.5 Motion numbers (the first `moving` splats only)

m = `motion[n]`; range r = `motionRange[m]`, extra e = `motionExtra[m]`. The speed comes from the whole number of cycles c =
`cycles[n]` it makes in one loop L:

- kinds 2 and 3 (fall and rise): ω = r c / L, in world units a second; the phase φ = `phase[n]` / 65536 is a part of a cycle, 0 to 1;
- every other kind: ω = 2π c / L, in radians a second; φ = 2π `phase[n]` / 65536 is an angle.

Every motion therefore comes round exactly once a loop (but see the sway in section 4).

## 3. The loop

The motion clock is t = clockStart + τ, with τ the time into the loop, 0 ≤ τ < L. The clock starts at 120 rather than 0 because the
sway's second term (section 4) makes 3.9 cycles a loop, not a whole number, so its starting point is part of the scene: use t, not τ, in
the motion maths. A 32-bit float holds t to about one hundred-thousandth of a second, which is plenty.

Frame f of the loop is the moment τ = f / 30: the part matrices and the cloth are stored for those moments (section 8 shows how near
the toolkit they come). Between them a painter may hold the frame before or blend the two frames either side; the motions of section 4
are worked from t directly at any moment. The page's painter holds the frame before, f = floor(30 τ), so at every stored moment it
draws exactly what the file holds.

What changes from frame to frame, and nothing else does:

| | Island | Factory |
| --- | --- | --- |
| Rigid parts (section 3.1) | 1 of 2: the island (294,039 splats) rises and falls; part 0 (668 splats, the sky) stays | 27 of 28: the island (362,979 splats) rising and falling, two rotors, the water wheel, a propeller, the fans, the press, the things on the belt, two robot arms (three parts each), the walker and its four limbs, the gardener's arm, the drone; part 0 (1,068 splats) stays |
| Cloth dabs (section 3.2) | none | 540: the flag |
| Kind motions (section 4) | 107,407 splats, worked from the clock | 45,950 splats, worked from the clock |

Densities, kinds, flags and colours never change, except a cloth dab's colour.

### 3.1 Rigid parts

At frame f, part p's twelve numbers are `track[(f * parts + p) * 12 ..]`: a 3 x 3 matrix A by rows, then a shift b. A splat on part p
is carried to

    p' = A p + b,      Σ' = A Σ Aᵀ

Part 0 is always the identity. The matrices are turns (and shifts), never stretches.

### 3.2 Cloth

The cloth dabs are part 0, kind 0, and their rest numbers in the per-splat blocks are their first frame. At frame f, dab j (splat n =
clothFirst + j, entry k = f * cloth + j) takes:

- its centre: `clothMin_i + (clothMax_i − clothMin_i) * clothPosition[3k + i] / 65535` for each axis i;
- its facing ν: opened out from two bytes a = `clothNormal[2k]`, b = `clothNormal[2k + 1]`. Let u = 2a / 255 − 1, v = 2b / 255 − 1, z =
  1 − |u| − |v|. Where z < 0, replace (u, v) by ((1 − |v|) sign u, (1 − |u|) sign v), signs taken before the change. ν is (u, v, z)
  made unit length;
- its shape: a disc facing ν, Σ = ρ² I + (h² − ρ²) ν νᵀ, with ρ = clothRadius and h = clothThickness;
- its colour: `palette[clothColour[k]]`.

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

Kinds 8 to 10 and 12 to 15 are not used. The sway's second term turns 1.3 times as fast as its first, so over one loop it makes 3.9
cycles where the first makes 3: where the loop wraps, a swaying leaf's height jumps by at most 0.6 r × 2 sin(0.1π) ≈ 0.37 r. Every
sway in these scenes has c = 3 and r from 0.012 to 0.045, so the jump is at most 0.017 world units, about a third of an art pixel at
the scene's own distance (0.0074 for the r = 0.02 sways). The toolkit's own loops have the same small seam.

Whether a splat is solid is decided after its kind has changed α: a falling drop of density 3 at 60% stays solid.

## 5. Drawing a picture

### 5.1 Camera

Yaw y and pitch p (the starting ones are camYaw and camPitch; dragging changes them), and a zoom z (1 is the scene's own distance). The
eye is at distance d = camDist / z from the target T:

    E = T + d (cos p sin y, sin p, cos p cos y)

The camera's back axis is k = (E − T) / |E − T|; its right axis i = (k_z, 0, −k_x) made unit length, so the horizon stays level; its up
axis j = k × i. A point P is at view coordinates (c_x, c_y, c_z) = (i · (P − E), j · (P − E), k · (P − E)); in front of the camera c_z
< 0. Splats with c_z > −near are not drawn, near = max(0.4, 0.15 d). (Straight up or down, p = ±π/2, has no right axis; keep |p| a
little under π/2.)

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
scene and 1 at the back. Unless it has the no-fog flag, the colour moves toward the fog colour `palette[fogIndex]` by
sstep(fogStart, 1, dn) fogMax. Then each channel is capped at 1.

At each pixel it covers, with cover A:

- colour ← A splat colour + (1 − A) colour;
- if it is solid and lacks the no-depth flag: D ← A dn + (1 − A) D, and G ← (1 − A) G;
- otherwise, if it is glass: G ← min(1, G + A/2).

### 5.4 Finishing each art pixel

Reads outside the grid take the nearest pixel inside it. For the art pixel (x, y), with C its blended colour:

1. Glass bends: gx = G(x+1, y) − G(x−1, y), gy = G(x, y+1) − G(x, y−1). If G(x, y) + |gx| + |gy| > 0, C becomes the blended colour at
   (x + round(glassBend gx), y + round(glassBend gy)).
2. Contact shade: for the eight neighbours at (±2, 0), (0, ±2) and (±1, ±1), let δ = (D(x, y) − D(neighbour)) / (shadeRange / 2R); each
   with 0.08 < δ < 3 adds min(1, δ) to an occlusion o. C ← C (1 − shadeStrength min(1, o / 4)).
3. Outline: if max(2D(x,y) − D(x−1,y) − D(x+1,y), 2D(x,y) − D(x,y−1) − D(x,y+1)) > outlineEdge / 2R, the pixel is
   `palette[outlineIndex]`, and step 4 is skipped.
4. Dither: with the 4 x 4 table B = 0 8 2 10 / 12 4 14 6 / 3 11 1 9 / 15 7 13 5 (rows by y mod 4, columns by x mod 4, y counted from
   the bottom), add (B + 0.5)/16 − 0.5 times 0.105 dither to each channel, then clamp each to 0 to 1. (0.105 = 0.35 x 0.3, the
   toolkit's own scale.)
5. Palette: the pixel takes the palette colour nearest C by 0.3 Δred² + 0.55 Δgreen² + 0.15 Δblue², the first of any tie.

## 6. What a file costs

| | Island | Factory |
| --- | --- | --- |
| Splats | 294,707 | 399,656 |
| Moving by kind | 107,407 | 45,950 |
| Styles, motions, parts | 73, 187, 2 | 117, 164, 28 |
| Cloth dabs | 0 | 540 |
| Raw | 5.79 MB (5.52 MiB) | 8.91 MB (8.49 MiB) |
| Gzipped (level 9) | 3.19 MB | 4.19 MB |
| On the wire from the page, gzipped by `mix phx.digest` | 3.19 MB | 4.17 MB |

A splat costs 18 bytes at rest (6 centre, 4 turn, 6 size, 1 colour, 1 style) and a moving one 4 more. The factory's moving parts cost
0.32 MB and its flag 1.17 MB (9 bytes a dab a frame, 240 frames).

## 7. How near the stored numbers are

Measured by `bake.cjs` over every splat (an art pixel is 1 / detail = 0.052 world units at the scene's own distance):

| Field | Stored as | Largest error |
| --- | --- | --- |
| Centre | 16 bits within its run's box | 7.0e-4 world units on any one axis (0.014 art pixel), in the sparse sky; 6e-6 to 9e-6 on average. A turned part turns the same error, so on the world's axes it can read a little more (7.7e-4 at most in the proof) |
| Size | 16-bit logarithm | 0.005% |
| Turn of the axes | three 10-bit parts | 0.16 degrees |
| Whole covariance | (both of the above) | 0.28% (0.08% on average) |
| Density, kind, flags, part | style table, 32-bit float | exact |
| Colour | palette place | exact |
| Speed, range, extra | whole cycles, 32-bit floats | exact |
| Phase | 16 bits of a turn | 4.8e-5 radians; 7.6e-6 of a cycle |
| Part matrices | 32-bit floats, every frame | exact |
| Cloth centre | 16 bits within the cloth box | 7.9e-6 world units |
| Cloth facing | two bytes | 0.94 degrees (a dab's covariance within 1.5%) |
| Cloth colour, disc size | palette place; header | exact |

## 8. The proof

`verify.cjs` builds each scene with the toolkit, reads its file back with `decode.cjs`, and has the toolkit's own renderer draw both on a
1440 x 960 stage (480 x 320 art pixels of 3), from four quarter turns at the starting pitch and from straight above and below (pitch
±1.45), at τ = 0, 2.5 and 5.5 seconds. Its row check finds no density, colour, kind, flag, speed, range or extra that differs.

Art pixels that differ, of 153,600 a view (yaw in degrees; above and below at the starting yaw):

| Scene | τ | 25.8 | 115.8 | 205.8 | 295.8 | Above | Below |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Island | 0 | 243 | 153 | 195 | 173 | 108 | 119 |
| Island | 2.5 | 253 | 170 | 194 | 202 | 108 | 123 |
| Island | 5.5 | 210 | 196 | 183 | 200 | 98 | 120 |
| Factory | 0 | 165 | 115 | 139 | 126 | 92 | 86 |
| Factory | 2.5 | 129 | 103 | 118 | 101 | 104 | 97 |
| Factory | 5.5 | 144 | 131 | 132 | 137 | 85 | 93 |

That is 0.06% to 0.16% of a picture: a blob a hair bigger or turned a fraction of a degree tips a pixel whose blend sat right on the
line between two palette colours. On the front views at τ = 0, most differing pixels have no differing neighbour (208 of 243 on the
island, 125 of 165 on the factory), and most swap one shade for a near one; a bigger jump, such as a single outline dot that comes or
goes, is 6 of the island's 243 and 17 of the factory's 165.

What each stored field adds, measured one at a time on the island's front and back views together (307,200 art pixels):

| Stored as | Differing |
| --- | --- |
| Centres in 16 bits within one box for the whole scene | 1,516 |
| Centres in 16 bits within a box for each run of 256 (this format) | 85 |
| Sizes in 8 bits | 2,543 |
| Sizes in 16 bits (this format) | 10 |
| Turns in 10 bits a part (this format) | 389 |
| Turns in 16 bits a part | 6 |
| This format, all together | 450 |
| With turns in 15 bits a part | 93 |

So the turn of the axes is most of what is left. Fifteen bits a part would take a turn 6 bytes instead of 4 and bring the differing
pixels to about 45 a view, but the factory would be 9.71 MB, over the 9 MB ceiling, unless its flag were stored more cheaply (section
9). None at all would need the toolkit's own numbers: each centre and covariance as 32-bit floats, 38 bytes a splat and about 17 MB for
the factory (not tried).

The live flag is walked to each moment one frame at a time, as the bake walked it: the cloth remembers every step it took, so a
different walk leaves it a hair elsewhere and the comparison would no longer be like with like.

The pictures the toolkit drew are kept in `/Users/sean/Documents/regent/handoffs/ink-studio-2026-11-16/reference/`, with
`reference.json` listing each one's camera, art-pixel size, grid, loop time, clock and count, for checking the page's own painter.

## 9. Proposed, not done

Each of these changes what the page shows or what the painter must do, so none was made without a decision:

1. **Turns in fifteen bits a part.** 2 more bytes a splat; about 45 differing pixels a view instead of 85 to 253. Island 6.38 MB,
   factory 9.71 MB, so the factory needs the next item as well.
2. **The flag as its 160 cloth points.** Store each frame's 16 x 10 grid points (about 0.23 MB for the loop) and, once, each dab's cell,
   its place in the cell and its four shades; the painter then rebuilds each dab's centre, facing and shade every frame, as the toolkit
   does. Saves about 0.9 MB, but moves the toolkit's cloth lighting into the painter.
3. **The flag at 15 frames a second**, blended between: halves its 1.17 MB; it would move a little differently between stored frames.
4. **Leaving out splats no view can see** (those buried inside solid shapes): not measured.

The page sends the files gzipped: `.bin` is among the file types `mix phx.digest` compresses (`config/config.exs`), and the scenes
keep a year-long cache under their digested names like every other static file.

## 10. Notes for a painter

- WebGPU has no three-part 8- or 16-bit vertex formats, so read the per-splat blocks from storage buffers and unpack in the shader: the
  k-th 16-bit value is half of 32-bit word k >> 1 (the low half when k is even). Binding a block as a range of one big buffer needs its
  start on a multiple of 256 bytes; copying each block into its own buffer avoids that.
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
- Splats are drawn far to near and the order changes as the camera turns, so the 300,000 to 400,000 splats are sorted again whenever
  the view changes. A sort that does not keep file order for equal depths may change a few pixels.
- A flickering splat (kind 1, 9 on the island and 45 on the factory) snaps its centre to the middle of its art pixel.
- The part matrices (0.32 MB) and the flag's frames (1.17 MB) can go to the graphics card once and be picked by frame number.
- The art-pixel size follows the stage's height in screen pixels (section 5.2): decide whether that means CSS pixels or device pixels.
  The reference pictures use a 1440 x 960 stage, so 3 screen pixels an art pixel. The page uses device pixels (up to three a CSS
  pixel), so a scene has about the same number of art pixels on any screen.
- The page steps the camera back on a stage narrower than three by two, so the scene still fits across it: z = min(1, (w / h) / 1.5).
  A phone's square stage is drawn at z = 2/3.
- The page's painter (`../painter.ts`) does not sort every splat. Solid splats whose density never changes are drawn unsorted, their
  middles (w ≥ 0.62) fully opaque with a depth test and their crisp edges (0.38 < w < 0.62) blended over them; only the rest (soft
  splats, those without depth and those whose kind changes α: 3,063 on the island and 5,889 on the factory) are sorted far to near on
  the processor. Against the reference pictures that differs in 0.5% to 1.1% of the art pixels of a view (792 to 1,711 of 153,600),
  mostly single pixels along edges; drawing every splat sorted brings the island to 335 to 548. `../painter.ts` says where.
- Colour and depth blended in 16-bit floats drift a shade dark over many thin layers on some graphics cards. Keeping each less a half,
  round 0, where a 16-bit float is finer, and adding the half back when reading, took about 5% off the differing pixels above;
  32-bit float targets would take about 15%, but blending them needs WebGPU's optional float32-blendable feature, which many phones
  lack.
