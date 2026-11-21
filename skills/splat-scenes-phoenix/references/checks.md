# Checks

What to check before a scene, or a change to the island, is released. regent-workflow says how a change proves itself, how to start
a local site with its settings and stop it after, and that browsers are headless Playwright only. The sibling skill's
`kit/verify.cjs` has already proved the file draws what the scene draws.

## 1. Before the browser

- `make check` from ash-template's root: warnings as errors, the design system's style check, format, Credo and the TypeScript
  typecheck against the installed vgpu (check `platform/node_modules/vgpu/package.json` matches the pin first, as vgpu-island says).
- The scene file is in `platform/priv/static/splats/<name>.bin`, unchanged from the bake.
- The four pictures are in `platform/priv/static/images/animations/` at the sizes references/add-a-scene.md predicts from the
  scene's detail × dist: the wide still 480 by 320 or 360 by 240, the square one 540, 360 or 270 square, the card 1440 by 960 and the
  item 1080 by 1080. A size other than predicted means the stills step drew an older file or the scene's grid changed.
- `git status` after the stills step: it draws every listed scene again, so any other scene's pictures that changed are a finding,
  not part of this change.

## 2. In a headless browser

Chromium launched by Playwright with `--enable-unsafe-webgpu` (and `--use-angle=metal` on a Mac), at a 1440 by 960 window unless a
step says otherwise, on the local site. The box follows the page's layout, so its stage is smaller than the window (1086 by 723 on
the Splats page at that width) and no step here depends on its size. The flags are for the browser's own WebGPU; the stills step
needs none, because vgpu draws its pictures in Node.

1. **It draws.** Open `/animations/splats?scene=<name>`. The box `#splats-<name>` reaches `data-splats-ready="true"` (wait for it:
   the first live frame can take some seconds), the zoom buttons show, Download GIF shows, and the console has no `VGPU-` errors and
   no others. Before the flag, the still is there from the first paint and nothing on the page moves when the scene fades in.
2. **It moves.** Two screenshots of the box a second apart differ (the cruise and the loop). A drag across turns it; a mouse drag
   up tilts it; an arrow key on the focused box turns or tilts it; `+` four times reaches the nearest zoom, where Zoom in is
   `aria-disabled="true"`; Reset view or `0` goes back, where Zoom out and Reset view are disabled again.
3. **Tabs.** Choose another tab, then come back: each time the old box's id is gone, the new box reaches `"true"`, and the console
   stays clean.
4. **Reconnect.** `window.liveSocket.disconnect()`, wait, `window.liveSocket.connect()`: the flag is still `"true"` after the
   reconnect and the scene draws again. A patch (a tab change and back) keeps the flag and the canvas.
5. **No WebGPU.** A context whose init script removes `navigator.gpu` (`delete Navigator.prototype.gpu`): the flag is `"false"`,
   the still stays, and neither the zoom buttons nor Download GIF show.
6. **Less motion.** A context with `reducedMotion: "reduce"`, and separately the page's Less motion switch: the scene holds at the
   still's view (two screenshots a second apart are the same); a drag moves it at once and it stays where it is left.
7. **Download GIF.** Press it and wait for the download: Making counts up in place, the file is named after the scene, it is a GIF
   of 160 frames, and the button reads Download GIF again. A second press while it works does nothing.
8. **Widths.** At 390 and 320 pixels wide: no sideways scroll on the page, the box is square with the square still, and the tabs keep
   to one row that scrolls on its own.
9. **Scenes page**, for a numbered scene: `/animations/scenes`; its card's box `#scene-<number>` reaches `"true"` once scrolled into
   view, and its Download GIF shows only then.
10. **Its own page**, for a numbered scene: `/scenes/<number>` draws on the scene's sky. Then frame it from another origin: route a
    made-up address (Playwright's `page.route`) to a page holding `<iframe sandbox="allow-scripts" src="<site>/scenes/<number>">`,
    open it, and check the box inside reaches `"true"` with a clean console. `/scenes/<number>/metadata.json` answers the trait
    file with `access-control-allow-origin: *`.

## 3. Serving, on a production build or the live site

Development serves the scene files as they are, so gzip and digests show only on a production build or the live site (plain
signed-out requests, as regent-workflow's live checks say).

- The page's `data-splats-file` names `/splats/<name>-<digest>.bin?vsn=d`.
- That address, asked with `accept-encoding: gzip`, answers `content-encoding: gzip`, a `cache-control` of a year,
  `access-control-allow-origin: *`, and the static headers (`content-security-policy: default-src 'none'; frame-ancestors 'none'`,
  `x-content-type-options: nosniff`).
- `/scenes/<number>` answers a `content-security-policy` ending in `frame-ancestors *`; the Splats and Scenes pages answer the
  site's usual policy, unchanged.
- The site's main bundle holds no `RSPL` and no shader: those are in the renderer's chunk, fetched only for a box on screen.
