# Serving, the security policy and a scene's own page

How ash-template serves scene files and pictures, which security policy each scene page has, and how a scene's own page can be framed
by any site. Paths are from ash-template's root; the endpoint is `platform/lib/ash_template_web/endpoint.ex`.

## 1. Scene files

- **Where.** `platform/priv/static/splats/<name>.bin`, served by its own `Plug.Static` at `/splats`, ahead of the site's main one.
  `static_paths/0` (`platform/lib/ash_template_web.ex`) lists `splats` too, so the files are part of the site's static files.
- **Gzipped.** `config :phoenix, :gzippable_exts` in `platform/config/config.exs` adds `.bin` to Phoenix's list, so `phx.digest`
  (the last step of `assets.deploy` in `platform/mix.exs`) writes a `.gz` beside each scene file, and the plug, with
  `gzip: not code_reloading?`, answers a browser that accepts gzip with it. In development the files are served as they are.
- **Digested and cached.** In production the endpoint reads `cache_static_manifest` (`platform/config/prod.exs`), so
  `Endpoint.static_path/1` names each file's digested copy: `Scenes.file/1` gives `/splats/<name>-<digest>.bin?vsn=d`, which the
  plug sends with a cache of a year. A scene baked again gets a new name, and browsers fetch it once. The stills on the site go the
  same way through `Scenes.still/2`.
- **Kept addresses.** `Scenes.still_url/2` and `Scenes.page_url/1` are full public addresses of the file itself, not of this
  release's digested copy, for addresses kept elsewhere: the link preview and the trait file. They still work after the next
  release.
- **Headers.** Every static file, scene files included, carries the endpoint's `@static_headers`:
  `content-security-policy: default-src 'none'; frame-ancestors 'none'`, `x-content-type-options: nosniff`,
  `x-frame-options: DENY` and `referrer-policy: no-referrer`. A file opened on its own can do nothing as a page.
- **Open to every origin.** The `/splats` plug adds `access-control-allow-origin: *`, and only it does: a scene's own page shown in
  a sandboxed frame has an origin that is no site's, so its fetch of the file is a cross-origin read (section 3). The other place
  open to every origin is the trait file.

## 2. The scene pages' policy

- The Splats and Scenes pages are live routes, `live "/animations/splats", SplatsLabLive` and `live "/animations/scenes",
  ScenesLabLive`, in `live_session :motion_lab`, in a scope that pipes through `[:motion_lab, :browser]`
  (`platform/lib/ash_template_web/router.ex`). `:motion_lab` is the motion lab's switch (`Showcase, :motion_lab`: public once the
  site opens, unless the showcase is off); `:browser` is the site's usual pipeline and policy, `ContentSecurityPolicy.sign_in()`.
- Nothing is added to the policy for scenes. The renderer's chunk is a script from the site (`script-src 'self'`), the scene file a
  fetch from the site (`connect-src 'self'`), the stills images from the site (`img-src 'self'`). WebGPU needs no directive.
- A site whose scene pages are not lab pages keeps them under its own usual pipeline the same way; the policy does not change.

## 3. A scene's own page, framed anywhere

- **Route.** `scope "/scenes"` piping through `[:motion_lab, :scene_page]`: `get "/:number", SceneController, :show`. The
  `:scene_page` pipeline is `accepts html`, the launch gate, and `put_secure_browser_headers` with `ContentSecurityPolicy.scene/0`:
  the strict baseline (`reading/0`, everything from the site) with `frame-ancestors *`, the one policy that lets any site frame a
  page. No session, no forms token, no live connection and nothing about the visitor.
- **Page.** `AshTemplateWeb.SceneHTML.show/1` is plain HTML with no root layout: the stage alone, filling the page on the scene's
  sky (`--scene-sky`, read from the file's backdrop as `AshTemplateWeb.Scenes` compiles), its zoom buttons small in the corner once
  it has drawn, no Download GIF. The head is `Regent.AgentMetadata.head` with the title, the description and the card picture
  (1440 by 960) for the link preview.
- **Script.** `platform/assets/js/scene_page.ts` mounts `createSplatIsland` on its one box, no LiveView. It is built on its own as
  one classic script (`--format=iife`) with its stylesheet `platform/assets/css/scene_page.css`, by the esbuild profile
  `scene_page` in `platform/config/config.exs`, which `assets.build` and `assets.deploy` run beside the site's own bundle. A frame
  sandboxed with scripts allowed, whose origin is no site's, loads a classic script and a stylesheet without asking the site's
  leave; the scene file it fetches is open to every origin (section 1).
- **Full addresses.** The stylesheet and script are named with `url(~p"...")`, the scene file and the still with
  `Endpoint.static_url()` before their paths, so they resolve to the site whatever page frames them.
- **Trait file.** `get "/:number/metadata.json", SceneController, :metadata` in a second `/scenes` scope through
  `[:motion_lab, :scene_traits]`: `accepts json`, the launch gate, `access-control-allow-origin: *`. It answers
  `Scenes.metadata/1`: name, description, image (the item picture, 1080 by 1080), `animation_url` (the scene's own page),
  `external_url` (the Scenes page) and `attributes` (each trait as `trait_type` and `value`).
- An address that numbers no scene answers the site's 404 (`Scenes.fetch!/1`).
