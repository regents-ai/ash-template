# A scene as a GIF

## 1. From the command line

```sh
env INK_STUDIO=/path/to/ink-studio node kit/gif.cjs out/scene/scene.bin out/scene/scene.gif
```

An 8-second loop makes **120 frames on an 864 by 576 stage** (15 a second; the size is a few pixels off when the art pixel does not
divide it), and a finished scene makes **5 to 11 MB**. It prints the frame count, the size, the length of a loop, how long it took,
and the seam (below). On ink-studio's `sculpt.js`: 120 frames of 865 x 580, 0.41 MB, made in 2 to 4 s.

**How long it takes.** The toolkit's CPU renderer draws all 120 frames one after another, so the time grows with the splats, and more
when splats are large on screen. Measured on a Mac with 8-second loops:

| Scene | Splats | Made in | GIF |
| --- | --- | --- | --- |
| ink-studio's `sculpt.js` | 4,027 | 2 to 4 s | 0.41 MB |
| Test scene, small splats | 50,023 | 58 s | 2.20 MB |
| Test scene, small splats | 100,000 | 100 s | 8.51 MB |
| Test scene, small splats | 200,000 | 204 s | 8.13 MB |
| A scene with a large far backdrop | 41,997 | 170 to 210 s | 1.60 MB |
| A lighthouse scene | 259,070 | 251 s | 4.82 MB |
| A throne-hall scene | 371,821 | 406 s (about 7 minutes on its first run) | 10.74 MB |
| A mansion-grounds scene | 390,661 | 497 s (510 s on its first run) | 9.55 MB |

So allow about a second per thousand splats, more when much of the picture is big splats (a sky, far ground): 4 to 9 minutes for
a finished scene. It prints nothing until it is done. Meanwhile: run it in the background (or as the last step), and look at
`stills.cjs`'s `sheet.png` and `moments.png`, which take seconds and show the same views and moments; the player itself plays the
loop as soon as the scene is baked. Make the GIF once the scene is settled, not on every change.

What it does:

- **One loop, once round.** The camera goes once round at the resting tilt (yaw = camYaw - 2π f / frames, the file's pitch) while
  every motion plays its loop once, so the last frame runs on into the first. Every second stored frame is drawn: 15 a second.
- **The toolkit draws it.** ink-studio's own renderer draws the decoded file on an 864 by 576 stage, each art pixel blown up to a
  square of screen pixels (so the size is the grid times the art pixel, a few pixels off 864 x 576).
- **Palette exact.** Every pixel the renderer draws is one palette colour, so the GIF's single colour table is the palette as it is,
  plus one entry for "unchanged since the frame before" (see-through, each frame left in place under the next: dispose 1). Nothing is
  matched to a colour again and nothing is dithered by the encoder; a pixel off the palette stops it with an error naming the frame
  and pixel. A GIF holds 256 entries, so a palette may have at most 255 colours.
- **Delays add up to the loop.** GIF delays are whole hundredths of a second; each frame's delay is the rounded time of the next frame
  less the rounded time of this one, so 15 a second comes out as 7, 7, 6, ... and the loop lasts exactly its length.
- **Plays for ever** (the NETSCAPE2.0 block with a count of 0).
- **The seam check.** It counts the pixels that change from the last frame to the first, against the range between neighbouring
  frames. A seam inside that range does not show; one far above it means something in the scene does not come round in the loop
  (SKILL.md, The loop). `sculpt.js`: 5,600 against 4,975 to 9,725. `cloth.js`: 13,575 against 4,225 to 7,275, because its gusty wind
  leaves the cloth 0.61 world units from where it began (the bake prints that seam too).
- **A seam just above the range** is one more ordinary step when the bake's own seams are small or explained (parts about 1e-11, or
  a ring of like clouds turned one place as in recipes.md, 8; a cloth well under an art pixel): the step from the last frame to the
  first is one more sample beside the 119 others. The mansion-grounds scene gave 223,328 against 167,704 to 221,788, 0.7% over, with
  its cloud ring printed 1.27 off and its cloth 0.004 units off; the lighthouse scene and the throne-hall scene came inside their
  ranges. A real jump stands far above the range, as `cloth.js` does at nearly twice its top; then read the bake's seams to find
  what does not come round.

## 2. In a page

A page can offer a GIF of the scene it shows, drawn by the same painter the page uses (`player/painter.js`), which gives the same
picture as the toolkit within a few art pixels (references/painter.md). The player does not carry a GIF button; this is how to add one.

- **Own device.** `init()` a second vgpu device for the GIF, `createPainter(gpu, scene)` on it, `resize(864, 576)`, then for each frame
  `frame(gpu, f => painter.encode(f, { yaw, pitch, seconds }))` with no stage and read the art-pixel picture back with
  `await painter.picture.color.read({ mipLevel: 0, region: 'all' })` (an RGBA `Uint8Array` in vgpu 0.6.0; see
  `npx vgpu docs cat /vgpu/core/texture.docs.md`). `gpu.dispose()` in a `finally`. The live scene keeps turning on its own device, and
  stopping between frames frees everything.
- **Same frames as the command line.** Frame i of n at yaw = camYaw - 2π i / n, the file's pitch, seconds = i L / n for the file's loop
  L. Every motion in a baked file already comes round in L.
- **Same table.** The picture is `rgba8unorm` and every pixel is exactly one palette colour, so map the bytes back to palette indices
  (a pixel off the palette is an error) and use the palette, plus one "unchanged" entry, as the GIF's one table, as `kit/gif.cjs`
  does. Its `lzw` and `writeGif` are a complete encoder in about 90 lines with no dependencies (they use Node's `Buffer`; a page uses
  `Uint8Array` and a `Blob`); gifenc (pin an exact version, 1.0.3 was used before)
  works too: it writes no frame offsets, so mark unchanged pixels with the see-through index and dispose 1, and set
  `colorDepth` = ceil(log2(palette + 1)). Blow each art pixel up to a square with `fill` per pixel and `copyWithin` per row.
- **Sizes to expect.** A scene of a few hundred thousand splats, 160 frames at 5 hundredths (8 s, 20 a second), 864 x 576: about 8 to
  9 MB, 4 to 5 s to make in headless Chromium on a Mac. ink-studio's examples come out well under 1 MB.
- **The button.** Offer it only once the scene has drawn (so never without WebGPU), in a place held for it so nothing moves when it
  appears. Keep its width fixed while it works: stack the idle label and a "Making 40%" label in one grid cell, with tabular figures.
  Mark it `aria-busy` and `aria-disabled` while it works, announce progress politely every quarter, and hold room beside it for a
  failure line. Import the GIF code on the first press, not with the page.
- **Seam check in a browser.** Decode the finished GIF with `ImageDecoder` and compare the last frame with the first, as above.
