---
name: vgpu-island
description: GPU pictures on Regent sites with vgpu 0.6 inside the shared canvas island (canvas_island.ts). Use for any WebGPU or shader work on a Regent site (heroes, crowns, cubes, foil cards, gradient materials, charts drawn on the GPU), whenever code imports vgpu or @vgpu/*, writes WGSL, or calls createCanvasIsland, and when a canvas stays blank, disappears after a LiveView patch, or a vgpu upgrade breaks a renderer.
---

# vgpu island

**Load `ash-stack`, `ash-frontend` and `animejs` first.** The island is presentation only;
the LiveView owns state, markup and outcomes.

Every GPU picture on every Regent site is a **vgpu island**: the shared controller
`platform/assets/js/canvas_island.ts` (`createCanvasIsland`) wrapped around a renderer
module that draws with **vgpu**. ash-template holds the reference copy; sites copy it.
Never hand-build what the island already owns: no own `requestAnimationFrame` loop,
`IntersectionObserver`, visibility or reduced-motion listener, device-loss retry, DPR
clamp or `frameLoop` inside an island renderer.

## Version and documentation

- Pinned: `vgpu` **0.6.0** and `@vgpu/wgsl` **0.6.0**, exact versions, in `platform/package.json`.
  Upgrade both together. Before trusting types or a build, check that the installed copy
  matches the pin (`platform/node_modules/vgpu/package.json`); a stale install after a
  catch-up builds against the wrong API.
- The docs ship inside the installed package and work offline. Read them before writing or
  reviewing a renderer, and read the migration guide before any upgrade:

  ```bash
  npx vgpu docs ls                              # /guides, /vgpu, /migrations, ...
  npx vgpu docs cat getting-started.md
  npx vgpu docs cat /migrations/0.6.0.docs.md
  npx vgpu docs cat /vgpu/surface.docs.md       # likewise effect, frame, gpu, init
  npx vgpu docs cat /guides/shipping-to-production.docs.md
  npx vgpu docs find effect
  npx vgpu examples search "gradient"
  ```

  Online: https://vgpu.sh/docs, https://vgpu.sh/agents.md, https://vgpu.sh/llms.txt.
  The installed docs win over memory and over older code in other sites.

## The three parts of an island

1. **Markup (HEEx component).** A root element with the hook, a still fallback the server
   renders, and the canvas. Put `phx-update="ignore"` on the canvas (or its stage) and
   `phx-mounted={JS.ignore_attributes(["data-<name>-ready"])}` on the root, so a LiveView
   patch never removes the ready flag the browser set. Losing it hides a working canvas
   after the next state change. The flag is `"true"` once a first frame is drawn and
   `"false"` once the island knows it will not draw, and absent while that is open.
   CSS shows the canvas only under `[data-<name>-ready="true"]` and the still face
   otherwise. Text never sits under the shader.
2. **Hook.** Calls `createCanvasIsland(root, {}, kind)` and maps the LiveView lifecycle:
   `mounted` → `mount()`, `disconnected` → `pause()`, `reconnected` → `resume()`,
   `destroyed` → `destroy()`, `updated` → hand new `data-*` state to the renderer and
   `nudge()`. The `kind` fields:
   - `canvasSelector`, `readyFlag` (camelCase dataset key, such as `gradientReady`).
   - `browserLoad`: a dynamic `import()` of the renderer module, so vgpu never enters the
     initial chunk and is fetched only for an island that is visible.
   - `motionSensitive`: true for anything that moves; reduced motion keeps the still face.
   - `continuous`: true only for a picture that moves by itself (a turning cube). A picture
     that changes only with state is `false` and draws on demand: no idle loop.
   - `interact`: pointer or state wiring; register composition with `onReady`.
3. **Renderer (`IslandRenderer`).** `resize`, `step(snap)`, `present`, `settled`, `dispose`,
   built from the vgpu 0.6 API:

   ```ts
   import {prepareShader} from "@vgpu/wgsl/prepare"
   import {effect, frame, init, surface} from "vgpu"

   const gpu = await init()
   let disposed = false
   void gpu.lost.then(() => { if (!disposed) onDeviceLost() }) // dispose also resolves it
   const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "opaque", label: "name"})
   stage.resize([size[0], size[1]])          // the island measured and capped the size
   const shader = effect(gpu, prepareShader(wgsl, "name.wgsl"), {label: "name.pass"})
   await shader.compile(stage)               // pre-warm against the surface, before the first frame
   // present(): shader.set({...complete uniform struct...}); frame(gpu, f => f.pass(stage, shader))
   // settled(): return gpu.settled()        // waits for submitted queue work too
   // dispose(): if (disposed) return; disposed = true; stage.dispose(); gpu.dispose()
   ```

   - Prefer `compile(stage)` once the surface exists: it reads the surface's real format,
     depth and sample count. `compile({colors: [stage.format]})` warms the same pipeline for
     a plain surface, and `gpu.settled()` already captures the `queue.onSubmittedWorkDone()`
     fence, so an explicit `await gpu.gpu.queue.onSubmittedWorkDone()` before it is
     redundant. Both forms are valid in 0.6; the crown and both cubes still use the older one.

   - 0.6 rejects raw WGSL strings (`VGPU-SHADER-SOURCE-UNPREPARED`): pass a static `.wgsl`
     import from the build loader, or `prepareShader(source, name)` once, outside frames.
   - Use `gpu.lost`, not the old `gpu.gpu.lost`. Loss does not dispose anything; the island
     asks for a new device (up to three times) and retires to the still face after that.
   - Frame callbacks are synchronous: no `await` inside `frame()`.
   - The first `set()` of a uniform struct supplies every member with exact component counts.
   - A `Surface` is only ever a render destination, never a binding.
   - If construction throws after `init()`, call `gpu.dispose()` and rethrow.

## What the island already guarantees

Work runs only while mounted, on screen, in a visible tab, allowed by the motion setting
and not retired. The renderer chunk is requested two frames after the server's paint. The
backing store is capped at 1.5 DPR and 1.5 million pixels. The still face stays until a
first frame really finished on the GPU (`settled()`), not when a canvas or adapter merely
exists. Without WebGPU the island never mounts and the server's picture remains.

## Verify

- Typecheck against the installed 0.6 packages (`npm run typecheck` in `platform/`) and
  build the assets. Prepare each shader once in Node to confirm a v2 artifact
  (`version: 2`, producer `@vgpu/wgsl/prepare-v2`).
- Validate `.wgsl` files with `npx vgpu check <file>`.
- In a browser with WebGPU: the ready flag appears (a real finished frame), the picture
  survives a LiveView patch and a state change, Less motion and reduced motion show the
  still face, hiding and showing the tab resumes drawing, and there are no `VGPU-*` console
  errors. Check 390px and 320px widths for overflow.
- Read `/guides/shipping-to-production.docs.md` before calling a render done.

## Reference islands in ash-template

`hooks/crown.ts` + `crown/`, `hooks/world_cube.ts` + `world_cube/renderer.ts`,
`hooks/code_cube.ts` + `code_cube/renderer.ts`, `hooks/holographic_card.ts` (its renderer is vendored from `regent_ui`), and the lab's
state-driven material `feedback_lab.ts` (`LabGradient`) + `feedback_gradient.ts`.
