# Splat studio

The sources of the page's pixel-art splat scenes, and the tools that turn them into the files the page draws, one a scene:
`platform/priv/static/splats/<scene>.bin`. [FORMAT.md](FORMAT.md) describes those files, field by field, with the maths a painter
needs to draw them.

## The toolkit

The scenes are sculpted with ink-studio, an outside toolkit
([github.com/siliconjungle/shapeshift-labs-ink-studio](https://github.com/siliconjungle/shapeshift-labs-ink-studio)), at commit
`0713810ca9a763a012fc0cea272a5620a6e853e9`. The toolkit is not in this repository and must never be copied into it: its package is
marked unlicensed and private. These files only call it. It is needed only to bake the scenes again; the page and its painter read
the baked files and never load it.

To bake, keep a checkout of the toolkit at that commit anywhere outside this repository and point `INK_STUDIO` at it. Nothing else is
installed: the toolkit runs on Node alone.

## Scenes made elsewhere

The numbered scenes from 6 on are put together from their trait lists (the lists their entries in `AshTemplateWeb.Scenes` carry) with
tools kept privately by the Regent team, outside this repository. Only their baked files, their pictures and their trait data are here;
their sources are not. `bake.cjs` and `verify.cjs` cover only the scenes whose source is in this folder. When one of these scenes is
baked again, the design lane does it and the new file replaces the old one. What proves one is the private tools' own check (no
faults, 48 colours, an eight-second loop) and the page's decoder reading the file.

## Files

| File | What it is |
| --- | --- |
| `island.cjs`, `factory.cjs`, `campfire-stories.cjs`, `trainer-battle.cjs`, `missile-circus.cjs`, `fishing.cjs`, `meteor-strike.cjs` | The scenes, one a file: every shape, colour, light and motion. |
| `floating-island.cjs` | What the scenes share: the island's body and skirt, roots, the sky, the clumped tree, and the rule that makes every motion come round in one loop. |
| `kit.cjs` | Loads the toolkit from `INK_STUDIO`, builds a scene, and walks it to a moment. |
| `format.cjs` | The file layout and the small codecs the baker and the decoder share. |
| `bake.cjs` | Writes the scene files and prints what each part costs and how far each stored number can be from the toolkit's. |
| `decode.cjs` | Reads a scene file back into the toolkit's own rows, without the toolkit. |
| `verify.cjs` | Has the toolkit draw the live scene and the decoded file side by side, counts the art pixels that differ, and keeps the toolkit's pictures as the reference for the page's painter. |

## Commands

Run from `platform/`, with `INK_STUDIO` set to the toolkit checkout:

```sh
# bake every scene into priv/static/splats/ (about two and a half minutes); name scenes to bake only those
INK_STUDIO=/path/to/ink-studio node assets/js/splats/studio/bake.cjs
INK_STUDIO=/path/to/ink-studio node assets/js/splats/studio/bake.cjs factory

# prove the files: six views at three moments of the loop for each scene (about three minutes); the toolkit's pictures and
# reference.json go to the folder named
INK_STUDIO=/path/to/ink-studio node assets/js/splats/studio/verify.cjs /path/to/reference
```

Baking is repeatable: the same scene sources give the same bytes.

## What the proof shows

Every number that changes the picture comes back from a file either exactly or within the error FORMAT.md states, and the toolkit's
renderer drawing a decoded file differs from it drawing the live scene on 0.02% to 0.20% of the art pixels of a view:

| Scene | Art pixels | Differing |
| --- | --- | --- |
| island | 153,600 | 98 to 253 |
| factory | 153,600 | 85 to 165 |
| campfire-stories | 153,600 | 69 to 190 |
| trainer-battle | 153,600 | 36 to 241 |
| missile-circus | 153,600 | 49 to 283 |
| fishing | 86,400 | 17 to 57 |
| meteor-strike | 153,600 | 109 to 302 |

The fishing scene's camera is nearer, so its art pixels are four screen pixels wide, not three, and a view holds fewer of them. On the
island and the factory the differing pixels are mostly lone pixels tipped between two near shades; FORMAT.md gives those two scenes'
numbers for every view and what each stored field adds.

The flag on the factory is a cloth the toolkit simulates step by step, so where it is depends on the steps taken, not only on the time.
The bake, and the proof, walk the loop one frame (a thirtieth of a second) at a time from fifteen loops in.
