# Splat studio

The sources of the two pixel-art splat scenes, the floating island and the factory, and the tools that turn them into the files the
page draws: `platform/priv/static/splats/island.bin` and `platform/priv/static/splats/factory.bin`. [FORMAT.md](FORMAT.md)
describes those files, field by field, with the maths a painter needs to draw them.

## The toolkit

The scenes are sculpted with ink-studio, an outside toolkit
([github.com/siliconjungle/shapeshift-labs-ink-studio](https://github.com/siliconjungle/shapeshift-labs-ink-studio)), at commit
`0713810ca9a763a012fc0cea272a5620a6e853e9`. The toolkit is not in this repository and must never be copied into it: its package is
marked unlicensed and private. These files only call it. It is needed only to bake the scenes again; the page, its painter and its
tests read the baked files and never load it.

To bake, keep a checkout of the toolkit at that commit anywhere outside this repository and point `INK_STUDIO` at it. Nothing else is
installed: the toolkit runs on Node alone.

## Files

| File | What it is |
| --- | --- |
| `island.cjs`, `factory.cjs` | The two scenes: every shape, colour, light and motion. |
| `floating-island.cjs` | What the two scenes share: the island's body and skirt, roots, the sky, the clumped tree, and the rule that makes every motion come round in one loop. |
| `kit.cjs` | Loads the toolkit from `INK_STUDIO`, builds a scene, and walks it to a moment. |
| `format.cjs` | The file layout and the small codecs the baker and the decoder share. |
| `bake.cjs` | Writes the scene files and prints what each part costs and how far each stored number can be from the toolkit's. |
| `decode.cjs` | Reads a scene file back into the toolkit's own rows, without the toolkit. |
| `verify.cjs` | Has the toolkit draw the live scene and the decoded file side by side, counts the art pixels that differ, and keeps the toolkit's pictures as the reference for the page's painter. |

## Commands

Run from `platform/`, with `INK_STUDIO` set to the toolkit checkout:

```sh
# bake both scenes into priv/static/splats/ (about a minute); name one scene to bake only that one
INK_STUDIO=/path/to/ink-studio node assets/js/splats/studio/bake.cjs
INK_STUDIO=/path/to/ink-studio node assets/js/splats/studio/bake.cjs factory

# prove the files: six views at three moments of the loop for each scene (a little over a minute); the toolkit's pictures and
# reference.json go to the folder named
INK_STUDIO=/path/to/ink-studio node assets/js/splats/studio/verify.cjs /path/to/reference
```

Baking is repeatable: the same scene sources give the same bytes.

## What the proof shows

Every number that changes the picture comes back from a file either exactly or within the error FORMAT.md states, and the toolkit's
renderer drawing a decoded file differs from it drawing the live scene on 0.06% to 0.16% of art pixels (85 to 253 of 153,600 a view).
Those are mostly lone pixels tipped between two near shades; FORMAT.md gives the numbers for every view and what each stored field
adds.

The flag on the factory is a cloth the toolkit simulates step by step, so where it is depends on the steps taken, not only on the time.
The bake, and the proof, walk the loop one frame (a thirtieth of a second) at a time from fifteen loops in.
