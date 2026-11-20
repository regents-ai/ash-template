# The painter

`player/painter.js` draws a baked file with WebGPU (vgpu 0.6) as pixel art: the same picture references/format.md, section 5,
describes, with one shortcut for speed. The page, an in-page GIF and a proof all use the same painter. Each player file's opening
comment says what it owns.

| File | What it does |
| --- | --- |
| `scene.js` | Reads a file: the header, a typed view on each block (no copies), the whole file as 32-bit words for the GPU |
| `camera.js` | The art-pixel grid for a stage (`gridFor`), the camera at a yaw and pitch (`viewFrom`), `TILT_LIMIT` (86 degrees) |
| `motion.js` | Where a splat is at a moment, on the processor, for the far-to-near order |
| `order.js` | Which splats are sorted, and their order each frame |
| `painter.js` | The three passes below; `resize`, `encode`, `compile`, `picture` |
| `main.js` | The page: cruise, drag, flick, keys, less motion, the ready flag (references/hosting.md) |

## Three passes a frame

1. **Layers**, on the art-pixel grid, three colour targets and a depth buffer: colour `rgba16float`, depth `rg16float`, glass
   `r8unorm`, `depth32float`. All splats come from one storage buffer holding the whole file; the block offsets and header numbers are
   WGSL constants written from the header, and the vertex shader unpacks and poses each splat: at rest or where the cloth is at the
   held frame f = floor(30τ), carried by its part's matrix at that frame, then moved by its kind from the loop's clock (format.md,
   sections 3 and 4). Each splat is a four-corner strip reaching 3 standard deviations.
   - Solid splats whose density never changes are drawn **unsorted**: first their middles (weight ≥ 0.62) fully opaque, `depth:
     {write: true, compare: "less-equal"}`; then their crisp edges (0.38 < weight < 0.62) blended premultiplied over them, `compare:
     "less"`, no depth write, so an edge behind a nearer middle is hidden.
   - The rest (soft splats, splats without depth, and kinds that change density: flicker, fall, rise, pulse) are **sorted far to
     near** on the processor every frame (`order.js`, ties in file order) and blended over everything, `compare: "less"`.
   - A scene with no solid splats, or none to sort, skips that draw: WebGPU warns of a draw of nothing.
2. **Finish** (format.md 5.4) into an `rgba8unorm` picture: glass bends what is behind it, contact shade, outline, a 4 x 4 ordered
   dither, the nearest palette colour. Every pixel is exactly one palette colour.
3. **Present**: each art pixel as a square of screen pixels on the canvas. `encode(f, moment)` without a stage stops after the finish,
   for reading the picture back (`painter.picture.color.read(...)`).

Format 5.3 sorts every splat and lets 1% of what is behind a solid middle show through it. The unsorted solids give both up for
speed. On ink-studio's examples that costs nothing visible: 1 to 21 art pixels of 21,600 differ from the toolkit's pictures, nearly all
single pixels (references/proof.md). On scenes of a few hundred thousand splats, about one art pixel in a hundred differs, nearly all
single pixels where two crisp edges cross or meet the sky; sorting every splat brings that to about a third, but costs a sort of every
splat each frame. A GPU sort is the way there if a closer match is wanted.

## The toolkit's rules the painter must follow

These are in ink-studio's CPU renderer (`cli/render.js`) and are easy to miss:

- Contact shade only when the world has `ao`; strength `ao.k` (0.5 if missing), reach `ao.range` (0.6 if missing), against 2R.
- Outline only when `outline.edge > 0`: with edge 0 the test "step > 0" would outline every depth change.
- Fog only when `fog.max > 0` and `fog.start < 1`. WGSL rejects `smoothstep(1.0, 1.0, x)` when both edges are constants, so the
  painter writes fog start and strength as 0 when the file has no fog, and the pipeline would otherwise fail to compile.
- The empty background is `palette[backdropIndex]` (the palette's first colour).
- Dither strength is 0.35 x 0.3 x the world's dither = 0.105 dither.
- Glass bend defaults to 6 art pixels per unit of slope.
- The field of view is 38 degrees; the art pixel q = round(h / (2 tan 19° x detail x dist)), clamped to 1 to 18.
- A motion's clock includes the bake's start (15 loops in): the painter works in turns, frac(c x clockStart / L) + c x τ / L, so the
  numbers stay small in 32-bit floats.

## Mistakes made or caught building this

- **Half floats drift.** Many thin edge layers blended in 16-bit floats came out a shade dark, and the contact shade's small depth
  steps blurred. Store colour and depth less a half (round 0, where a 16-bit float is two to four times finer) and add the half back
  when reading. 32-bit float targets would be better still but need the optional `float32-blendable` feature, which many phones lack;
  do not branch on it.
- **Rounding.** The format's round is floor(x + 0.5); WGSL's `round` takes halves to even.
- **Sort ties.** A sort that does not keep file order for equal depths changes pixels.
- **The sway does not quite come round.** Its second term makes 1.3 times its cycles a loop; `kit/loop.cjs` picks counts that close or
  nearly close it, and what is left is the toolkit's own seam, well under an art pixel for the small ranges sways use.
- **Vertex formats.** WebGPU has no three-part 8- or 16-bit vertex formats: read the blocks from storage and unpack in the shader.
- **Device pixels.** The grid follows the stage in device pixels (up to three a CSS pixel), so a scene has about the same art pixels on
  any screen: 180 x 120 for a 1440 x 960 stage at detail 14 and distance 12, the camera stepping back by z = min(1, (w / h) / 1.5) on a
  stage narrower than three by two.
- **Constant smooth steps.** See fog, above: a shader that compiles for one scene can fail for the next when header numbers are
  constants. Check a new painter change against a scene with fog, outline and shade and one with none (ink-studio's `sculpt.js` has
  none).
- **Empty draws.** A scene of only solid splats has nothing to sort; skip the draw rather than draw zero instances.

## Performance

Measured on a Mac (Metal), headless Chromium with `--enable-unsafe-webgpu --use-angle=metal`, on scenes of 300,000 to 400,000 splats
with this painter's design: a frame takes 7 to 11 ms end to end, of which the processor's part, mostly the far-to-near sort, is about
2 ms; about 60 frames a second while dragging at 1440 wide. ink-studio's examples (1,400 to 4,000 splats) reach their first frame
about 0.1 s after the page is asked for, on the same machine and from a local server. Not measured on a phone, in Safari or in
Firefox.

The sort grows with the splats that need it, not with the scene: keep soft haze, no-depth splats and fading kinds to what the scene
needs.

## Sources

- Kerbl, Kopanas, Leimkühler, Drettakis, "3D Gaussian Splatting for Real-Time Radiance Field Rendering", SIGGRAPH 2023 (the footprint
  through the Jacobian, the 1.3 clamp, 3σ). Code: github.com/graphdeco-inria/diff-gaussian-rasterization.
- Shi Yan, "WebGPU Unleashed", 5.8 Gaussian Splatting: https://shi-yan.github.io/webgpuunleashed/Advanced/gaussian_splatting.html
- A WebGPU splat renderer: https://github.com/Scthe/gaussian-splatting-webgpu
- vgpu 0.6.0 has no splat or sort example: draw splats as `draw` with `vertices: 4`, `instances: count`, `storage` buffers for the file
  and the order, and a `target` with several colours and a depth buffer for the layers, as `painter.js` does. vgpu's own docs: see
  references/hosting.md, section 1.
