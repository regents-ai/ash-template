# Checks

What to check before a scene, or a change to the island, is released. regent-workflow says how a change proves itself, how to start
a local site with its settings and stop it after, and that browsers are headless Playwright only. The sibling skill's
`kit/verify.cjs` has already proved the file draws what the scene draws.

## 1. Before the browser

- `make check`, through mise so its tools are the pinned ones: from `platform/`, `mise exec -- make -C .. check`. It runs warnings as errors, the design system's style check, format,
  Credo and the TypeScript typecheck against the installed vgpu (check `platform/node_modules/vgpu/package.json` matches the pin
  first, as vgpu-island says).
- The scene file is in `platform/priv/static/splats/<name>.bin`, unchanged from the bake.
- The four pictures are in `platform/priv/static/images/animations/` at the sizes references/add-a-scene.md predicts from the
  scene's detail × dist: the wide still 480 by 320 or 360 by 240, the square one 540, 360 or 270 square, the card 1440 by 960 and the
  item 1080 by 1080. A size other than predicted means the stills step drew an older file or the scene's grid changed.
- `git status` after the stills step: it draws every listed scene again, so any other scene's pictures that changed are a finding,
  not part of this change.
- **The site's still against the kit's.** `splats-<name>-wide.png` and the sibling's `still.png` show the same view, moment and art
  grid, drawn by two painters; count the pixels that differ, and the outline pixels in each (the outline's palette colour). Two
  scenes measured: 98.2% the same with 5,462 outline pixels against 5,497 (a mansion-grounds scene), and 0.43% differing (a
  lighthouse scene). Far more than that, or outline counts far apart, means the painters disagree: look first at the outline rule
  (SKILL.md, The kit and the site share one file), then at fog.

## 2. In a headless browser

**The local site.** From the working copy's `platform/`, start it with its settings loaded the repository's way (regent-workflow,
Local sites): `direnv exec <main checkout>/platform env PORT=<port> mise exec -- mix phx.server`. Never read a settings file. The
site then uses this machine's own development database, `ash_template_dev` (`AshTemplate.DatabaseConfig`). If the settings name the
remote cluster (`AshTemplate.DatabaseConfig.remote?/0`), that is the live database: do not run a working copy on it for these
checks; stop and tell the site's chief. Where this machine has no development database, give the site one of its own: add
`ASH_TEMPLATE_DEV_PARTITION=<letters>` to the start line (the database `ash_template<letters>_dev`), set it up first as
`platform/README.md` does, and drop that one database after. Create, drop, reset and migrate no other. After the start, check that the home page's `privy-app-id` meta is non-empty by its length, never its
value; stop the server after, as regent-workflow says. The Splats page is public: every step here runs signed out.

Chromium launched by Playwright with `--enable-unsafe-webgpu` (and `--use-angle=metal` on a Mac), at a 1440 by 960 window unless a
step says otherwise. The box follows the page's layout, so its stage is smaller than the window (1086 by 723 on the Splats page at
that width) and no step here depends on its size. The flags are for the browser's own WebGPU; the stills step needs none, because
vgpu draws its pictures in Node.

1. **It draws.** Open `/animations/splats?scene=<name>`. The box `#splats-<name>` reaches `data-splats-ready="true"` (wait for it:
   the first live frame can take some seconds), the zoom buttons show, Download GIF shows, and the console has no `VGPU-` errors and
   no others except the one every page logs: Chrome's warning about the `tools=(self)` feature in the site's `permissions-policy`
   header. Before the flag, the still is there from the first paint. To prove nothing moves when the scene fades in, read the
   positions of the box and of the content below it (`getBoundingClientRect()`) after `document.fonts.ready` and again after the
   flag: they match. A font swap shifts every page a little about 50 ms after load, so measure after it.
2. **It plays.** Two screenshots of the box a second apart differ (the cruise and the loop).
3. **It moves**, proved on the held scene (step 7's context), where the picture changes only when moved: a drag across turns it; a
   mouse drag up tilts it; an arrow key on the focused box turns or tilts it; each change stays. `+` four times reaches the nearest
   zoom, where Zoom in is `aria-disabled="true"`; Reset view or `0` goes back, where Zoom out and Reset view are disabled again.
4. **Tabs.** Choose another tab, then come back: each time the old box's id is gone, the new box reaches `"true"`, and the console
   stays clean.
5. **Reconnect.** `window.liveSocket.disconnect()`, wait, `window.liveSocket.connect()`: the flag is still `"true"` after the
   reconnect and the scene draws again. A patch that keeps the scene (its own tab pressed again) keeps the flag and the canvas; a
   tab change makes a new box (step 4).
6. **No WebGPU.** A context whose init script removes `navigator.gpu` (`delete Navigator.prototype.gpu`): the flag is `"false"`,
   the still stays, and neither the zoom buttons nor Download GIF show.
7. **Held still.** A context with `reducedMotion: "reduce"`: the scene holds at the still's view (two screenshots a second apart are
   the same); a drag moves it at once and it stays where it is left. The Splats page has no Less motion switch of its own; the
   island also holds when anything round it carries `data-motion="reduced"`, which a script can set on `<html>` to check that path.
8. **Download GIF.** Press it and wait for the download: Making counts up in place, the file is named after the scene, it is a GIF
   of 160 frames, and the button reads Download GIF again. A second press while it works does nothing; send that press with
   `click({ force: true })`, since Playwright's ordinary click waits until the button can take it.
9. **Widths.** At 390 and 320 pixels wide: no sideways scroll on the page, the box is square with the square still, and the tabs keep
   to one row that scrolls on its own.
10. **Scenes page**, for a numbered scene: `/animations/scenes`; its card's box `#scene-<number>` reaches `"true"` once scrolled
    into view, and its Download GIF shows only then.
11. **Its own page**, for a numbered scene: `/scenes/<number>` draws on the scene's sky. Then frame it from another origin: route a
    made-up address (Playwright's `page.route`) to a page holding `<iframe sandbox="allow-scripts" src="<site>/scenes/<number>">`,
    open it, and check the box inside reaches `"true"` with a clean console. `/scenes/<number>/metadata.json` answers the trait
    file with `access-control-allow-origin: *`.

## 3. Serving, on the live site

Development serves the scene files as they are, so gzip and digests show only on a production build. ash-template has no recipe that
leaves one running on this machine (`make release` builds the committed tree into an image, smoke-checks it and removes it), so
check these on the live site after the release, with plain signed-out requests as regent-workflow's live checks say.

- The page's `data-splats-file` names `/splats/<name>-<digest>.bin?vsn=d`.
- That address, asked with `accept-encoding: gzip`, answers `content-encoding: gzip`, a `cache-control` of a year,
  `access-control-allow-origin: *`, and the static headers (`content-security-policy: default-src 'none'; frame-ancestors 'none'`,
  `x-content-type-options: nosniff`).
- `/scenes/<number>` answers a `content-security-policy` ending in `frame-ancestors *`; the Splats and Scenes pages answer the
  site's usual policy, unchanged.
- The site's main bundle holds no `RSPL` and no shader: those are in the renderer's chunk, fetched only for a box on screen.
