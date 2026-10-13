# Third-party notices

Third-party material redistributed inside this repository, and the terms it arrives under.

## vgpu — account holographic card

The foil on the account page's identity card and the homepage's feature cards is the shared `Regent.HolographicCard`
from the Regent design system, whose `holographic_card.mjs` adapts the "Holographic
Card" example published with Vercel's `vgpu` project. This repository ships no copy of
that material: `mix regent_ui.assets` stages the module from the pinned design-system
revision at build time, and the attribution and licence text live in the design system's
`THIRD_PARTY_NOTICES.md`. The renderer runs on the `vgpu` 0.6.0 this repository pins, with `@vgpu/wgsl` 0.6.0 preparing its shader.

## vgpu — crown renderer

The glass crown under `assets/js/crown/` began as the prism scene from Vercel's `vgpu`
project. Its camera, pass structure, post-processing, crown mesh and WGSL are adapted
from that work. One crown serves every Regent site; a site supplies only its look.

- Project: `vercel-labs/vgpu` — https://github.com/vercel-labs/vgpu
- Commit: `bd3b05101fdd1193a1593558d3c52a0b2b18f31d` ("feat(docs): move prism shader to homepage")
- Source directory: `apps/docs/app/[lang]/(home)/components/prism-background`
- License: MIT

Pinned npm packages, exact versions, no ranges:

| Package         | Version |
| --------------- | ------- |
| `vgpu`          | 0.6.0   |
| `@vgpu/wgsl`    | 0.6.0   |
| `@webgpu/types` | 0.1.69  |

### What was taken

The camera and pass structure, and the production shaders `copy-linear`, `bloom`,
`bloom-upsample` and `present`, together with the colour functions of
`@vgpu/wgsl-std/color` and the upstream `environment.wgsl` studio that the glass
reflects.

The visible solid is the Regents 3/5/5 crown: thirteen disconnected glass cubes in
place of the upstream triangle prism. Its mesh (`assets/js/crown/mesh.ts`) and its
front and back glass shaders are structural adaptations of the upstream prism mesh
and its `glass` and `glass-back` shaders. The beam tracer (`assets/js/crown/light.ts`)
and its additive sheet shader are adapted from the upstream spectral light sheet.

### What was left behind

The React component and its control panel, the debug renderers and view modes, the
wireframe paths, the triangle prism mesh, the `wall` shader, the thumbnail renderer
and the upstream test suites.

### How the shaders got here

Each shader under `assets/js/crown/shaders/` is a plain WGSL string. Those that came
from more than one upstream module were joined once, offline, with identifiers kept,
and carry a `vgsl-module:` comment naming each module they hold. Nothing is downloaded
at runtime: `@vgpu/wgsl` prepares each string in the browser when the crown first draws.

### License

```
MIT License

Copyright (c) 2025 Vercel, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
