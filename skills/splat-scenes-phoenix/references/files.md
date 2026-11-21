# The island's files

What each file of ash-template's splat island owns, by path from the repository's root. Read each on `origin/main`; its opening
comment or `@moduledoc` says the same at more length.

## Server

| Path | Owns |
| --- | --- |
| `platform/lib/ash_template_web/components/splat_stage.ex` | `AshTemplateWeb.Components.SplatStage`. `stage/1`: the box, wherever a scene shows (the still in a `<picture>`, the canvas, Zoom out, Zoom in and Reset view), with the `SplatIsland` hook. `gif/1`: Download GIF for one box, with the `SplatGif` hook. `meta/1`, `rarity/1`, `traits/1`: a numbered scene's number and kind, rarity score and trait table |
| `platform/lib/ash_template_web/scenes.ex` | `AshTemplateWeb.Scenes`: the numbered scenes as data (`number`, `name`, `title`, `kind`, `description`, `rarity`, `traits`), each one's sky read from its file as the module compiles, and the addresses: `file/1`, `still/2`, `still_url/2`, `page_url/1`, `metadata/1` |
| `platform/lib/ash_template_web/live/splats_lab_live.ex` | `AshTemplateWeb.SplatsLabLive` at `/animations/splats`: one scene at a time under tabs, picked by `?scene=<name>`; the scenes without a number in `@unnumbered`, then every numbered one; Formats (Picture, Card, and for a numbered scene Full view and Metadata) and Download GIF; a numbered scene's traits |
| `platform/lib/ash_template_web/live/scenes_lab_live.ex` | `AshTemplateWeb.ScenesLabLive` at `/animations/scenes`: every numbered scene on a card with its own stage, Download GIF, tags, traits folded away, and links to its own page and trait file |
| `platform/lib/ash_template_web/controllers/scene_controller.ex` | `AshTemplateWeb.SceneController`: `SceneController.show/2`, a numbered scene's own page at `/scenes/<n>`; `SceneController.metadata/2`, its trait file at `/scenes/<n>/metadata.json` |
| `platform/lib/ash_template_web/controllers/scene_html.ex` | `AshTemplateWeb.SceneHTML`: that page, plain HTML with no live connection: the stage alone on the scene's sky, and the link preview with the card picture |
| `platform/lib/ash_template_web/router.ex` | The two live routes in the `:motion_lab` live session; the `:scene_page` and `:scene_traits` pipelines and the two `/scenes` scopes |
| `platform/lib/ash_template_web/endpoint.ex` | The `Plug.Static` at `/splats`: scene files gzipped, with `access-control-allow-origin` `*` |
| `platform/lib/ash_template_web/content_security_policy.ex` | `AshTemplateWeb.ContentSecurityPolicy.scene/0`, the policy of a scene's own page |
| `platform/lib/ash_template_web.ex` | `static_paths/0`, which lists `splats` |
| `platform/config/config.exs` | `config :phoenix, :gzippable_exts` with `.bin`; the esbuild profile `scene_page` |
| `platform/mix.exs` | `assets.build` and `assets.deploy` run `esbuild scene_page` beside the site's own bundle |

## Browser

| Path | Owns |
| --- | --- |
| `platform/assets/js/canvas_island.ts` | `createCanvasIsland`: the controller every GPU picture on the site shares (on screen, visible tab, motion setting, the two-frame wait, the lazy import, size caps, device loss, the ready flag) |
| `platform/assets/js/hooks/splat_island.ts` | The `SplatIsland` hook and `createSplatIsland`: one canvas island per box, its pointer, wheel, key and button wiring, less motion; `rendererOf` hands a box's renderer to Download GIF |
| `platform/assets/js/hooks/splat_gif.ts` | The `SplatGif` hook and `createSplatGif`: Download GIF for one box |
| `platform/assets/js/splats/renderer.ts` | `createSplatRenderer`: the box's picture; starts the GPU and fetches the file together, cruise, drag, flick, keys, zoom, hold |
| `platform/assets/js/splats/painter.ts` | `createPainter`: draws a scene in three passes (layers on the art grid, finish, onto the canvas); shared by the page, the GIF and the stills |
| `platform/assets/js/splats/scene.ts` | `decodeScene` and `loadScene`: reads a file (magic `RSPL`) into its header and blocks |
| `platform/assets/js/splats/camera.ts` | `gridFor` (the art grid, and the camera stepping back on a stage narrower than three by two), `viewFrom`, `TILT_LIMIT`, `ZOOM_LIMIT` |
| `platform/assets/js/splats/motion.ts` | Motion worked on the processor (`centreAt`), for ordering |
| `platform/assets/js/splats/order.ts` | `createOrder`: which splats are drawn far to near, and in what order, each frame |
| `platform/assets/js/splats/gif.ts` | `makeGif` and `createGif`: one loop as a GIF in the palette, loaded on the first press |
| `platform/assets/js/splats/stills.mjs` | The stills step (`npm run stills:splats`): four pictures for every scene in its `SCENES` list |
| `platform/assets/js/splats/studio/` | `FORMAT.md` (the file, field by field) and the site's own baker for the scenes whose sources are in that folder; new scenes are baked by the sibling skill's kit instead |
| `platform/assets/js/lab_pages.ts` | Registers `SplatIsland` and `SplatGif`, with the other lab hooks, on the `/animations` pages only (`platform/assets/js/app.ts` loads it there) |
| `platform/assets/js/scene_page.ts` | A scene's own page: `createSplatIsland(...).mount()` on its one box, no LiveView |
| `platform/assets/js/hooks/motion/shared.ts` | `still`: less motion asked for, by the device or by a `[data-motion='reduced']` switch round the box |
| `platform/assets/js/types.d.ts` | The `gifenc` 1.0.3 surface `gif.ts` uses |

## Styles

| Path | Owns |
| --- | --- |
| `platform/assets/css/components/splat_stage.css` | The box (three by two, `touch-action: pan-y`, grab cursor, focus ring), the still and canvas (`image-rendering: pixelated`, `object-fit: cover`), the fade-in under `[data-splats-ready="true"]`, the zoom buttons, Download GIF's words and failed line, the traits table |
| `platform/assets/css/pages/splats_lab.css` | The Splats page: tabs, the box turning square under 36rem, Formats, Download GIF shown once the box has drawn |
| `platform/assets/css/pages/scenes_lab.css` | The Scenes page: the cards, one column or two, Download GIF shown once its box has drawn |
| `platform/assets/css/scene_page.css` | A scene's own page: the box filling the frame on `--scene-sky`, the still laid out with `object-fit: contain` |
| `platform/assets/css/app.css` | Imports `splat_stage.css`, `splats_lab.css` and `scenes_lab.css` |

## Files and packages

| Path | Holds |
| --- | --- |
| `platform/priv/static/splats/<name>.bin` | One baked scene a file |
| `platform/priv/static/images/animations/splats-<name>-wide.png`, `-square.png`, `-card.png`, `-item.png` | Its four pictures (references/add-a-scene.md) |
| `platform/package.json` | `vgpu` 0.6.0 and `@vgpu/wgsl` 0.6.0, `gifenc` 1.0.3, `playwright` 1.65.1 for the stills step, and the script `stills:splats` |
| `CHANGELOG.md`, `platform/priv/public/changelog.md` | Where a new scene is noted |
