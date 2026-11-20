# What these splats are, what stays offline, and baking again

## 1. What "true" means

The scenes are real Gaussian splats: each a centre, a covariance from a turn and three sizes, a colour and a density, carried to the
screen through the perspective Jacobian and blended. They are **not trained**: no photographs, no optimisation; code places every splat
and bakes its light into a palette colour. Nor is the drawing the original 3D Gaussian Splatting renderer's: there are no spherical
harmonics (a colour is a place in the palette), the least footprint is 0.15 art pixels squared, solid splats have a crisp smooth-step
edge, and every picture pixel is snapped to the palette. Say "baked from code, drawn as pixel art" whenever you describe them.

## 2. What stays offline

- **ink-studio.** The kit's `.cjs` files call it from the folder `INK_STUDIO` names (`kit/toolkit.cjs`). It is MIT licensed, but keep
  it out of the kit and out of any page: a page needs only the baked file and the player, and a copy would go stale. Never let a kit
  `.cjs` file into a page's bundle.
- **Everything worked out once:** the shapes, the light (baked into palette colours), every rigid part's matrix for each of the loop's
  frames, and a cloth, simulated step by step and stored for every frame. The player does only the arithmetic of section 4 of
  references/format.md each frame.
- **The toolkit's pictures of a scene** (`kit/verify.cjs`'s reference folder, with `reference.json` giving each view's camera, grid and
  moment): the reference for any painter. Keep them beside the scene's source, not in a page.

## 3. Baking again

1. Change the scene file, then bake and prove it (SKILL.md, Commands):
   `env INK_STUDIO=/path/to/ink-studio node kit/bake.cjs scenes/my-scene.js 8 out/my-scene/scene.bin` and
   `env INK_STUDIO=/path/to/ink-studio node kit/verify.cjs scenes/my-scene.js out/my-scene/scene.bin out/my-scene/reference`.
   The same scene file and ink-studio give the same bytes.
2. Draw the stills again: `env INK_STUDIO=/path/to/ink-studio node kit/stills.cjs out/my-scene/scene.bin out/my-scene`.
3. Bring every number that changed up to date wherever it is written down: splat counts, sorted counts, sizes, the scene's
   screen-reader label if what it shows changed.
4. Prove the page against the new reference (references/proof.md, sections 2 and 3).

A baked file is a large binary. Committed to a repository it stays in its history for ever: commit a bake once, final, and test with
working copies. Keep a file under about 9 MB raw (3 to 5 MB on the wire); references/format.md, section 6, says what costs what.

## 4. Sources

- ink-studio: https://github.com/siliconjungle/shapeshift-labs-ink-studio (MIT). This kit was checked against commit `cf35ff8`.
- Kerbl, Kopanas, Leimkühler, Drettakis, "3D Gaussian Splatting for Real-Time Radiance Field Rendering", SIGGRAPH 2023 (the footprint
  through the Jacobian, the 1.3 clamp, 3σ). Code: https://github.com/graphdeco-inria/diff-gaussian-rasterization
- Shi Yan, "WebGPU Unleashed", 5.8 Gaussian Splatting: https://shi-yan.github.io/webgpuunleashed/Advanced/gaussian_splatting.html
- A WebGPU splat renderer: https://github.com/Scthe/gaussian-splatting-webgpu
- vgpu: https://vgpu.sh/docs and the docs inside the installed package (references/hosting.md, section 1).
