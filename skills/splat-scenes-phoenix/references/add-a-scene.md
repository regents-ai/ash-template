# Adding one scene

On ash-template, by path from the repository's root. A site that has taken the island (references/adopting.md) has the same files
under its own names.

## 1. Bake it with the sibling skill

Write, loop, bake and prove the scene with **splat-scenes** (its SKILL.md, steps 1 to 7), proved with `kit/verify.cjs`. Bake an
8-second loop, as every scene on the template has: the box plays the file's own loop, but Download GIF always lasts 8 seconds (160
frames of 5 hundredths), so another loop would play faster or slower there. Keep to at most 255 colours: Download GIF's one colour
table is the palette plus one entry. The site works out the art grid as the
sibling's player does (`gridFor` in `platform/assets/js/splats/camera.ts`), so its table of detail × dist (the finish's `detail`, the
camera's `dist`; splat-scenes references/recipes.md, section 1) holds here: on the 1440 by 960 stage 399 to 557 gives art pixels of
3 screen pixels (480 by 320), as most scenes on the template have, and 310 to 398 gives 4 (360 by 240).

## 2. The file and its name

Copy the baked file in unchanged as `platform/priv/static/splats/<name>.bin`. The name is lowercase words joined by hyphens, like
every scene file on the site. It names everything else: the four pictures, the Splats page's `?scene=<name>` and its box
`splats-<name>`, and the saved GIF.

## 3. The stills step

Add `<name>` to `SCENES` in `platform/assets/js/splats/stills.mjs`, then from `platform/` run:

```sh
mise exec -- npm run stills:splats
```

It needs Node 22.18 or newer (the Node that `platform/.tool-versions` pins is, hence `mise exec`) and the site's packages
installed: vgpu draws each picture on this machine's GPU (`vgpu/node`) with the site's own painter, and Playwright's headless
Chromium only packs the pixels as PNG. It draws every scene in `SCENES` again, not only the new one, at the view and moment the live
scene opens on, into `platform/priv/static/images/animations/`:

| Picture | What it is | Size |
| --- | --- | --- |
| `splats-<name>-wide.png` | The box's still: the art grid of a 1440 by 960 stage, one pixel to an art pixel | 480 by 320 at q 3; 360 by 240 at q 4 |
| `splats-<name>-square.png` | The Splats page's still under 36rem, where its box turns square: the art grid of a 1080 by 1080 stage, where the camera steps back to fit, so its q can be smaller | 540 by 540 at q 2; 360 by 360 at q 3; 270 by 270 at q 4 |
| `splats-<name>-card.png` | The wide still at its stage's size, each art pixel a hard-edged square: Card on the Splats page and the link preview of a scene's own page | 1440 by 960 |
| `splats-<name>-item.png` | The square still at its stage's size: Picture on the Splats page and the image a trait file names | 1080 by 1080 |

q is the art pixel's side in screen pixels. On the wide stage q = round(1394 / (detail × dist)); on the square one
q = round(1157 / (detail × dist)), kept within 1 to 18 (`gridFor` at the opening zoom, with the toolkit's 38-degree view). So
detail × dist from 463 to 771 gives a square q of 2, 331 to 462 gives 3, and 258 to 330 gives 4. The grid is the stage's sides
divided by q, rounded up, and the card and item are that grid times q: exactly 1440 by 960 and 1080 by 1080 when q divides the sides,
as for every scene on the template, a few pixels larger when it does not. These sizes match all 108 pictures on the template. The
`width` and `height` the stage puts on the still (480 by 320, and 360 by 360 for the square) only give its shape before it loads;
the stylesheet sets its size.

## 4. The list entry

- **On the Splats page only:** a map in `@unnumbered` in `platform/lib/ash_template_web/live/splats_lab_live.ex`, with `name`,
  `title`, `number: nil` and `label`. Tabs follow the list's order. The page's bare address, and a `?scene=` naming no scene, show
  the first entry, and `scene_path/1` gives that entry's tab the bare address by its name, so an entry put first changes that
  clause too. The page's `@moduledoc` names its unnumbered tabs; add the new one there.
- **As a numbered scene:** a map in `@scenes` in `platform/lib/ash_template_web/scenes.ex`, with `number`, `name`, `title`, `kind`
  (`"Action"` or `"Chill"`), `description`, `rarity` and `traits` as `{category, trait, tier, share}` tuples. It then shows on the
  Splats page after the unnumbered ones, as a card on the Scenes page, on its own page at `/scenes/<number>` and in its trait file at
  `/scenes/<number>/metadata.json`. The Scenes page tags each card with `Scenes.headline/1`, the traits named World, Ground,
  Resident, Landmark and Hour, so a numbered scene carries all five. The module reads each numbered scene's sky from its file while
  it compiles (the backdrop's palette place at byte 56, its colour at byte 284 plus four times that place, with the file as an
  `@external_resource`), so the file must be in place before the site compiles.
- **Other places that name scenes**, for an unnumbered one: in `splats_lab_live.ex`, the comment above `@unnumbered` counts them
  ("The seven scenes that are not numbered"), and the `@moduledoc` lists the unnumbered tabs and their `?scene=` names; bring all
  three up to date. Its later line on traits, "The unnumbered scenes have none", needs no change. In
  `platform/assets/js/splats/studio/README.md`, "Scenes made elsewhere" names every scene made with the sibling skill, with its
  colours and whether it has fog: add the new one.

## 5. The words

- **Title:** one or two words (the tab, the card's heading, the page title). A proper name counts as one.
- **Label** (`@unnumbered`) or **description** (numbered): what the scene shows, in a sentence or two of plain words. The stage
  reads it to a screen reader, followed by how to move the scene (`@moving` in `splat_stage.ex`); the description is also the link
  preview's line and the trait file's.
- The controls' words (Zoom out, Zoom in, Reset view, Download GIF, Making, the failed line) live in the component, the same for
  every scene. The rules for words on screen are regent-workflow's (Words on screen).

## 6. Note it and check it

- **The source stays out of the site.** The site's repository carries the baked file and its pictures only. Keep the scene file
  with the team's scene sources, and name that place in the commit message.
- **The notes:** the scene in `CHANGELOG.md` and `platform/priv/public/changelog.md`, in the same commit.
- **A side branch**, for a scene not yet meant for release (a trial, say): commit on a local branch, check it there on the local
  site (references/checks.md) and hand the branch to the site's chief. regent-workflow treats a side branch as a handoff only:
  nothing ships from it. Otherwise check it and release as regent-workflow says.
