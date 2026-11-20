# Baked scene file

One little-endian binary file per scene, written by `kit/bake.cjs` and read by `player/scene.js`. `kit/format.cjs` holds the same
layout as code.

## Layout

The four bytes `SPLT`, then the header, then the blocks in the order below. Every block starts on a multiple of four bytes (pad with
zeros), so the whole file can go to the graphics card as one buffer of 32-bit words. The file ends at the end of the last block.

### Header

Nine `u32`, then `f64` fields:

| Field | Type | Meaning |
| --- | --- | --- |
| splats | u32 | splats in the file |
| moving | u32 | the first `moving` splats have a kind of motion; the rest are still |
| styles, motions, parts | u32 | entries in the style, motion and part tables (each at most 256) |
| frames | u32 | part frames: loop times 30 |
| colours | u32 | palette entries (48) |
| fogIndex, outlineIndex | u32 | palette colours of the haze and the outline |
| loop | f64 | seconds in the loop (8) |
| logScaleMin, logScaleMax | f64 | range of the log sizes |
| camTarget | f64 x 3 | the point the camera looks at |
| camDist, camPitch, camYaw | f64 | the opening camera |
| fov | f64 | vertical field of view, radians |
| detail | f64 | art pixels per world unit at the target, on a 3:2 stage |
| radius | f64 | the scene's depth range is `camDist - radius` to `camDist + radius` |
| fogStart, fogMax | f64 | haze begins at this depth (0 to 1) and reaches this mix |
| outlineEdge | f64 | a depth step, in world units, that draws an outline |
| shadeStrength, shadeRange | f64 | contact shade |
| dither | f64 | ordered dither strength (0 to 1) |
| glassBend | f64 | how far glass bends what is behind it, in art pixels |

### Blocks

| Block | Type | Entries | Meaning |
| --- | --- | --- | --- |
| palette | u32 | colours | `0xRRGGBB`; colour 0 is the backdrop |
| styleDensity | f32 | styles | solidity: 1 or more is solid |
| styleCode | u8 | styles | motion kind in the low 4 bits; 16 no depth or outline, 32 glows and skips the haze, 64 glass |
| stylePart | u8 | styles | the part that carries the style's splats (0 is still) |
| motionRange | f32 | motions | distance or height of the motion |
| motionExtra | f32 | motions | growth over a fall or rise |
| chunkBounds | f32 x 6 | splats / 256, rounded up | min x, y, z, max x, y, z of each run of 256 splats |
| position | u16 x 3 | splats | place within the run's box: `min + (max - min) * v / 65535` |
| rotation | u32 | splats | quaternion: top 2 bits say which of x, y, z, w was left out; then the other three in order, 10 bits each, `(2 v / 1023 - 1) / sqrt 2`; the left-out one is `sqrt(1 - others squared)` |
| scale | u16 x 3 | splats | size along each axis: `exp(logScaleMin + (logScaleMax - logScaleMin) * v / 65535)` |
| colour | u8 | splats | palette index |
| style | u8 | splats | style index |
| cycles | i8 | moving | whole cycles per loop |
| phase | u16 | moving | `v / 65536` of a cycle |
| motion | u8 | moving | motion index |
| track | f32 x 12 | frames x parts | per frame, per part: a 3x3 matrix by rows, then a shift |

## Drawing a moment

At `seconds` into the loop:

1. Frame `f = min(frames - 1, floor(seconds * 30))`. A splat's part matrix `A` and shift `s` come from `track[(f * parts + part) * 12]`.
   Its centre is `A * rest + s`, and its covariance `A * Sigma * A^T`, where `Sigma = R diag(scale^2) R^T`.
2. For a moving splat, `u = fract(cycles * seconds / loop)` and `angle = TAU * (u + phase)`:
   - 1 flicker: solidity times `0.62 + 0.38 sin(angle)`.
   - 2 fall: `v = fract(u + phase)`; down by `v * range`; solidity times `1 - v^2`; grows by `1 + v * extra`.
   - 3 rise: up by `v * range`, across by `0.25 v sin(7 v + 50 phase)`; solidity times `(1 - v) * smoothstep(0, 0.1, v)`; grows by `0.6 + v * extra`.
   - 4 blink: colour plus `0.3 * smoothstep(0.75, 1, sin(angle))`.
   - 5 orbit: turned `TAU * u` about the world's y axis.
   - 6 bob: up by `range * sin(angle)`.
   - 7 pulse: solidity times `0.82 + 0.18 sin(angle)`.
   - 11 sway: x plus `range * sin(angle + 1.3 y + 0.9 z)`; y plus `0.6 range * sin(TAU * (fract(1.3 * cycles * seconds / loop) + phase) + 1.1 x)`, using the carried position.
3. Project onto a grid of art pixels sized by `detail` and the stage, and draw each splat as a 2D Gaussian with 0.15 added to its
   footprint's diagonal. A solid splat covers an art pixel where its weight is at least 0.62 (a crisp edge from 0.38 to 0.62); the
   rest blend far to near.
4. Haze towards `fogIndex` by `smoothstep(fogStart, 1, depth) * fogMax`, unless the style glows. Then glass bend, contact shade, an
   outline in `outlineIndex` where depth steps by more than `outlineEdge`, a 4x4 Bayer dither, and the nearest palette colour by
   0.3 red, 0.55 green, 0.15 blue.

`player/painter.js` is the reference for every number in steps 3 and 4.
