# Taking the island into another Phoenix site

The splat island lives in ash-template, the baseline every site matches (regent-workflow, The baseline is ash-template). A site takes
it as it is on ash-template's `origin/main`, file by file with `git show origin/main:<path>`, and never keeps a second version of
its own: a change the site needs is made in ash-template first and taken again (regent-workflow, Shared changes). Never paste the
files into a skill or a handoff. references/files.md says what each one owns.

## 1. The files

| Part | Take from ash-template | Notes |
| --- | --- | --- |
| Controller | `platform/assets/js/canvas_island.ts` | Every site has one for its GPU pictures (vgpu-island); bring it level with the template's first |
| Hooks | `platform/assets/js/hooks/splat_island.ts`, `platform/assets/js/hooks/splat_gif.ts` | `still` comes from `platform/assets/js/hooks/motion/shared.ts` |
| Drawing | Every file in `platform/assets/js/splats/` (the renderer, painter, reader, camera, motion, order, GIF and stills step), and `platform/assets/js/splats/studio/FORMAT.md` | The rest of `studio/` is the template's own baker and scene sources; a site's scenes are baked with the sibling skill's kit |
| Types | The `gifenc` declaration in `platform/assets/js/types.d.ts` | |
| Component | `platform/lib/ash_template_web/components/splat_stage.ex` | |
| Scene list | `platform/lib/ash_template_web/scenes.ex` | For numbered scenes, their own pages and trait files; `file/1` and `still/2` serve any scene by name |
| Pages | `platform/lib/ash_template_web/live/splats_lab_live.ex`, `platform/lib/ash_template_web/live/scenes_lab_live.ex` | Or the site's own pages placing `SplatStage.stage/1` and `SplatStage.gif/1` the same way, one box with its own id a scene |
| Own page | `platform/lib/ash_template_web/controllers/scene_controller.ex`, `platform/lib/ash_template_web/controllers/scene_html.ex`, `platform/assets/js/scene_page.ts`, `ContentSecurityPolicy.scene/0` | Only for scenes other sites may frame |
| Styles | `platform/assets/css/components/splat_stage.css`, the page styles, `platform/assets/css/scene_page.css` | |
| Scenes | `platform/priv/static/splats/<name>.bin` and the four pictures of each scene the site shows | Or the site's own scenes, added as references/add-a-scene.md says |

## 2. The wiring

1. **Names.** `AshTemplateWeb` becomes the site's web module, `:ash_template` its application (the `/splats` plug's `from:` and the
   sky read's `Application.app_dir/2` in `scenes.ex`). The own page's site name and preview account in `scene_html.ex`, and the
   saved GIF's prefix in `splat_gif.ts`, become the site's.
2. **Packages** in `platform/package.json`: `vgpu` 0.6.0 and `@vgpu/wgsl` 0.6.0 (likely there already), `gifenc` 1.0.3, `playwright`
   1.65.1 for the stills step, and the script `"stills:splats": "node assets/js/splats/stills.mjs"`, all exact versions.
3. **Shared parts.** The component uses the design system's `Regent.Primitives.button`, `Regent.Primitives.figure` (its
   `data-count` is what Download GIF counts in) and `Regent.Icons.icon` (`minus`, `plus`, `scan`); the own page uses
   `Regent.AgentMetadata.head`. The pages and `scenes.ex` use the template's `PublicDocuments` for full public addresses, and the
   router the template's launch gate and showcase switch; a site uses its own copies of those baseline modules.
4. **Hooks.** The template registers `SplatIsland` and `SplatGif` in `platform/assets/js/lab_pages.ts`, which
   `platform/assets/js/app.ts` loads only on paths under `/animations`. A site that shows scenes on other pages registers both in the
   hook map those pages load.
5. **Styles.** Import `splat_stage.css` and the page styles from `platform/assets/css/app.css`, as the template does. The own page's
   stylesheet is imported by `scene_page.ts` and built with it, not from `app.css`.
6. **Serving** (references/serving.md): `.bin` in `config :phoenix, :gzippable_exts` in `platform/config/config.exs`; `splats` in
   `static_paths/0`; the `Plug.Static` at `/splats` in the endpoint, ahead of the main one, with the static headers (and
   `access-control-allow-origin: *` when the site has scenes' own pages).
7. **Own page** (only with it): the esbuild profile `scene_page` in `platform/config/config.exs`, `esbuild scene_page` in
   `assets.build` and `esbuild scene_page --minify` in `assets.deploy` in `platform/mix.exs`, the `:scene_page` and `:scene_traits`
   pipelines and the two `/scenes` scopes in the router, and `ContentSecurityPolicy.scene/0`.
8. **Words.** The site keeps the template's words for the controls (Zoom out, Zoom in, Reset view, Download GIF, Making, the failed
   line) and the box's `@moving` sentence; titles and labels follow regent-workflow's Words on screen.

## 3. Proof

Run every check in references/checks.md on the site, and note the change in its changelog as regent-workflow says.
