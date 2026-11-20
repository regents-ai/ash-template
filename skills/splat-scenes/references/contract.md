# Piece contract

A scene is a JSON file listing piece files. A piece is one CommonJS file that exports `kind` and what this page asks of that kind,
with exactly those keys. `kit/compose.cjs` holds the same rules as code; when they disagree, the code wins.

## Scene file

```json
{ "seed": 7, "pieces": ["pieces/palette/meadow.cjs", "pieces/thing/tree.cjs"] }
```

- Paths are relative to the scene file. No piece twice.
- Exactly one each of `palette`, `light`, `camera`, `finish`, `ground`.
- At most one `sky` and one `character`. Any number of `weather`.
- Any number of `thing` pieces, up to the ground's places of each size, taken in list order.
- `seed` seeds the scene. Each piece's random draws come from the seed and the piece's path, so adding or removing a piece leaves
  the others' draws as they were.

## Kinds

| Kind | Exports |
| --- | --- |
| palette | `name`, `ramps`: one list of `0xRRGGBB` colours per role (below) |
| light | `sun` [x, y, z] towards the sun, `amb` ambient, `sky` sky fill, `sunK` sun strength |
| camera | `yaw`, `pitch` (radians; yaw 0 looks from +z), `dist` (times the fitted distance), `rise` (share of the stage's height to look above the best fit), `pixel` (screen pixels per art pixel on a 960-high stage) |
| finish | `outline` (depth step, world units, that draws an outline), `dither` (0 to 1), `shade: {k, range}` (contact shade strength and reach), `grain` (surface wobble) |
| ground | `places`, `build(ctx)` returning `{ top, radius, air }` |
| thing | `size` (`'large'`, `'medium'` or `'small'`), `build(ctx, place)` |
| character | `build(ctx, place)`; its place is the stage |
| weather | `build(ctx, air)`; built after the camera is fitted, so `ctx.hero` is there |
| sky | `build(ctx, sky)`; `sky` is `{ r0: 30, r1: 46, sun, sunK }`, the shell to lay it on; `ctx.fog(k, start, max)` sets the haze to sky colour `k` from depth `start` (0 to 1) up to `max` |

### Palette

48 colours in 13 roles, in this order: sky 5, ink 1, ground 4, stone 4, wood 4, leaf 5, water 4, metal 4, flesh 4, warm 4, gold 3,
cool 4, light 2. Each ramp runs dark to light by luma (0.3 red + 0.55 green + 0.15 blue), and no colour appears twice. The first sky
colour is the backdrop and ink is the outline. Every splat must use one of the 48, so pick colours through `ctx.pal`.

### Ground

`places` is `{ stage: [x, z], large: [{ at: [x, z], turn }], medium: [...], small: [...] }`. `turn` (radians) is the way a place
faces: 0 faces +z. `build` gets `ctx.taken(x, z)`, true within a thing's place, so tufts and stones keep off. The stage stays open ground. It returns:

- `top(x, z)`: the ground's height there, or `-Infinity` off the ground.
- `radius`: about how far the ground reaches. It sizes depth and haze.
- `air: { r, y0, y1 }`: the cylinder weather may fill.

Every place must sit wholly on the ground and be level: its height at twelve points round its edge is within 0.08 of its middle.
No two places overlap by more than 0.05.

### Places and sizes

| Size | Reach `r` | Height `h` |
| --- | --- | --- |
| large | 1.3 | 3.2 |
| medium | 0.8 | 2.2 |
| small | 0.42 | 1.4 |
| stage | 1.6 | 4.0 |

`place` has `at` [x, y, z] on the ground, `r`, `h`, `turn`, the axes `left`, `up` and `forward` (also as `ax`), `to([l, u, f])`
from place space to the world, and `dir([l, u, f])` for a direction. The stage faces the camera. A piece is a fault when it reaches
past 1.15 r from its middle or stands taller than 1.1 h.

## Context

Every `build` gets `ctx`:

- `B`, `S`: ink-studio's builder and sculpt for this scene. `K` is the toolkit, `M` its 3x3 matrices (`M.rot(axis, angle)`, `M.id()`).
- `TAU`, `L` (the loop, 8 seconds).
- `pal.ramp(role, from, to)` colour indices, `pal.c(role, k)` one index (negative k counts from the light end), `pal.rgb(role, k)`
  the colour for builder calls, `pal.mat(role, extra)` a sculpt material whose sunlit side is one step lighter.
- `share`: this piece's `{ splats, styles, motions, parts }`.
- `view`: the direction from the scene towards the camera.
- `along(d)`: three axes with the second along `d`.
- `part(name, build, { pivot, parent })` and `loop(fn)`: moving parts (below).
- `hero` (weather and sky only): `see(p)` gives `[across, up, distance]` in the opening picture, across and up running -1 to 1 from
  edge to edge; `at([across, up], d)` is the point shown there at distance d. Also `view`, `up`, `right`, `target`, `dist`.

## Drawing with the toolkit

Colours for `B` calls are `pal.rgb(...)` or `B.P[index]`. Sculpt materials take index lists.

- `B.iso(x, y, z, size, colour, a, an)`: a round splat. `a` is how solid it is: 1 or more is solid, under 1 lets things show through.
- `B.stick(x, y, z, axis, halfLength, halfWidth, colour, a, an)`: a long splat.
- `B.dab(x, y, z, normal, along, sa, sb, sn, colour, a, an)`: a flat splat.
- `S.ball`, `S.box`, `S.tube`, `S.lathe`, `S.torus`, `S.rock`, `S.tree`, `S.solid`: shapes filled with splats at spacing `res`, lit
  and shaded when baked. A material is `{ r, s, mod, top, em, fl }`: `r` the colours in shade, `s` in sun (never empty), `top` a
  different ramp on upward faces, `em` glowing, `fl` the motion of every splat it makes. A material's `fl` replaces its glow, so put
  `em: true` inside `fl`. `S.grp(k)` starts a new group of shapes.
- `B.rr(lo, hi)`, `B.R()`, `B.pick(list)`, `B.gauss()`, `B.randDir()`, `B.norm(v)`, `B.n3(x, y, z)`, `B.fbm(...)`: seeded randomness and noise.
- `an` is `{ k, ph, sp, rg, ex, nd, em, gl }`: a kind of motion and its numbers, and the flags no outline (`nd`), glowing and out of
  the haze (`em`) and glass (`gl`). Other flags stop the build.

Read ink-studio's `README.md`, `src/builder.js` and `src/sculpt.js` for every option.

## Motion

Every motion comes round in the 8-second loop. The kit snaps each speed to a whole number of cycles, and stops the build, naming the
piece, when one still does not close.

| `k` | Kind | `rg` | Notes |
| --- | --- | --- | --- |
| 1 | flicker | | brightness wavers |
| 2 | fall | distance | `ph` 0 to 1; `sp = rg * cycles / L`; fades and grows by `ex` as it goes |
| 3 | rise | distance | as fall, upwards and drifting |
| 4 | blink | | brightens at the top of each cycle |
| 5 | orbit | | turns about the world's y axis |
| 6 | bob | height | up and down |
| 7 | pulse | | solidity wavers |
| 11 | sway | distance | needs a multiple of 10 cycles a loop, as its second wave runs 1.3 times as fast |

For kinds other than fall and rise, `sp = cycles * TAU / L` and `ph` is an angle.

A moving part is a rigid group of splats turned about a pivot: `const arm = part('arm', () => { ...shapes... }, { pivot, parent })`.
`parent` is another part's handle, which carries this one. Inside `loop((t, w) => { ... })`, where `w = TAU * t / L`, call
`handle.set(rotation, shift)` for each part. A part that is not back where it began after 8 seconds stops the build.

## Shares

A share is a ceiling. A piece that makes anything should also use at least 70% of its splats. Both are reported as faults that name
the piece.

| Piece | Splats | Styles | Motions | Parts |
| --- | --- | --- | --- | --- |
| ground | 60,000 | 16 | 12 | 2 |
| sky | 12,000 | 8 | 10 | 0 |
| character | 40,000 | 16 | 10 | 8 |
| weather | 10,000 | 6 | 10 | 2 |
| large thing | 40,000 | 14 | 12 | 4 |
| medium thing | 25,000 | 12 | 10 | 3 |
| small thing | 10,000 | 8 | 6 | 2 |

A style is one mix of solidity, motion kind, flags and part. A motion is one `rg` and `ex` pair. A scene file holds at most 340,000
splats, 256 styles and 256 motions. Spend a share by tuning a piece's spacing (`res`) or counts, then run `stand` to read the result.

## Look checks

`build` and `check` draw the opening view and fault the scene when:

- the character stands less than 30% of the picture's height, or less than 70% of it shows;
- the ground's top and what stands on it span less than 50% of the picture's height;
- a bare square of ground in the front third of its top, outside the things' places, is wider than 7% of the picture's height;
- a piece adds fewer than 200 art pixels in every one of the seven views.

Every fault starts with the piece it names.
