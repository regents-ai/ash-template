---
name: splat-scenes-phoenix
description: Put a baked Gaussian splat scene on an Elixir, Phoenix, LiveView and Ash site the way ash-template shows its scenes - the SplatStage component, the SplatIsland and SplatGif hooks on the shared vgpu canvas island, the WebGPU painter in assets/js/splats, the stills step, gzipped and digested scene files, the security policy and a scene's own page that other sites may frame. Use after a scene is written, baked and proved with the sibling splat-scenes skill, to add it to a Phoenix site, to take the splat island into another Phoenix site, or when a scene's box stays on its still, loses its picture after a LiveView patch, or its stills, GIF or file serving go wrong.
---

# Splat scenes on a Phoenix site

A scene is made with the sibling skill **splat-scenes**; this skill puts it on a Phoenix site. It carries no kit and no player of its
own. ash-template shows its scenes through a **splat island**: a HEEx component that sends the still picture and the canvas, a
LiveView hook on the shared canvas island, and a vgpu renderer that draws the baked file. A file baked by the sibling skill goes onto
the site unchanged.

**Load first:** regent-workflow, ash-stack and elixir-stack (who decides, the house rules, wording, checks and release, and the design
check); for any change to the renderer or to another GPU picture, vgpu-island and the two it asks for, ash-frontend and animejs; and
the sibling splat-scenes. All are in ash-template's `skills/` (read them from main: `git show origin/main:skills/<name>/SKILL.md`);
in the Regent workspace each is `.agents/skills/<name>/` at the workspace's root, a link into its ash-template checkout's `skills/`.
This skill points to them and does not repeat them.

**Tools run through mise.** The plain shell's `mix`, `elixir` and `node` may not be the versions ash-template pins
(`platform/.tool-versions`): run them as `mise exec -- mix ...` and `mise exec -- npm run ...` from `platform/`.

**One source of truth.** The island's files live in ash-template. Read them from its main, never from a checkout that may be behind:
`git fetch origin main`, then `git show origin/main:<path>`. Take them from there into another site; never paste them into a skill.
Every path here is from ash-template's root.

**Design check** (elixir-stack): nothing here is stored, queued or retried. A scene is a static file (`Plug.Static`, digested and
gzipped by `phx.digest`), the list of scenes is module data compiled into the site, a page is a LiveView that picks the scene from its
address, and the drawing is the browser's (the canvas island). No database, no Oban, no process of its own.

## From a scene file to a scene on the site

1. **Make it with splat-scenes**, in its order: write the scene file, look at it at stage size, make it loop, bake it with an
   8-second loop (`env INK_STUDIO=... node kit/bake.cjs <scene file> 8 <out .bin>`), prove it (`kit/verify.cjs`) and look at its
   stills (`kit/stills.cjs`). Every scene on the template is an 8-second loop, and Download GIF plays 160 frames of 5 hundredths:
   8 seconds. The sibling's player and GIF are optional here; the site has its own.
2. **Add it to the site**: references/add-a-scene.md (where the file goes, its name, the stills step and its four pictures, the list
   entry, every other place that lists scenes, the page text, where the source lives, a local side branch).
3. **Check it** with `make check`, the site's still against the kit's, and a headless browser on the local site:
   references/checks.md. Release as regent-workflow says, or hand a side branch to the site's chief.

## The kit and the site share one file

- **Same layout.** The kit's `skills/splat-scenes/kit/format.cjs` and the site's `platform/assets/js/splats/studio/format.cjs`
  differ only in their opening comment: magic `RSPL`, `VERSION = 1`, the same header and blocks in the same order. The site's reader,
  `platform/assets/js/splats/scene.ts`, reads that layout, so a baked file is read unchanged by the site's renderer, GIF and stills
  step. All 24 scene files on the template are `RSPL` version 1, two of them baked by the sibling skill's kit.
- **No fog.** The kit stores the toolkit's fog as it is, and a scene without fog comes out with fog start 1 and strength 0 (both
  kit-baked files on the template). WGSL refuses a `smoothstep` whose two edges are the same constant, so the site's painter writes
  both as 0 unless `h.fogMax > 0 && h.fogStart < 1` (`platform/assets/js/splats/painter.ts`), the same rule as the kit's player;
  it came in with the first kit-baked scene. Any other painter that draws these files needs it too.
- **An outline only where the scene asks.** Since 22 Nov 2026 the site's painter, like the kit's player, draws the outline only when
  the file's outline edge is above 0 (`OUTLINE_EDGE > 0.0` in `painter.ts`; the studio's `FORMAT.md`, 5.4, step 3). When the site's
  still and the kit's disagree (references/checks.md, 1), look at the outline first: the measured figures are there.

## References

| Note | Read it for |
| --- | --- |
| references/files.md | Every file of the island and what it owns: components, pages, hooks, renderer, painter, stills, styles, serving, settings |
| references/add-a-scene.md | Adding one scene: the file and its name, the stills step and its four pictures with their sizes, the list entry, page text |
| references/island.md | How the hook starts and stops the GPU with the LiveView lifecycle, the still until the first frame and without WebGPU, less motion, device loss, the renderer rules from vgpu-island |
| references/controls.md | Turn, tilt, zoom, keys, touch and less motion, and the Download GIF button |
| references/serving.md | Scene files gzipped, digested and cached; the security policy; a scene's own page that any site may frame |
| references/checks.md | What to check before release: `make check`, the pictures, and the headless browser checks on a Phoenix site |
| references/adopting.md | Taking the island into another Phoenix site: which files to take from ash-template, and the wiring |
