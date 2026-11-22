// Draws the splats page's still pictures into priv/static/images/animations/: for each
// scene, splats-<scene>-wide.png (three by two, for the wide box) and
// splats-<scene>-square.png (for a phone's square box), at the view and moment its live
// picture opens on (the scene's starting yaw and pitch, the start of its loop), one
// pixel per art pixel, so the browser scales them up in crisp squares. The scenes are
// the baked files the page draws (priv/static/splats/), painted by the page's own
// painter as a 1440 by 960 stage and a 1080 by 1080 one would show them.
//
// Every scene is also shown off the site, where a small picture is scaled up smoothly
// and blurs. So each also gets the same two pictures at their stage's own size, every
// art pixel a hard-edged square of whole pixels, as the stage shows it:
// splats-<scene>-card.png (1440 by 960, from the wide one) and splats-<scene>-item.png
// (1080 by 1080, from the square one). The Splats page offers both as Card and Picture;
// for the numbered scenes (AshTemplateWeb.Scenes) the card is also the link preview
// of the scene's own page and the item the picture its trait file names.
//
//   npm run stills:splats            (from platform/, after baking a scene again)
//
// vgpu draws the frames on this machine's GPU; a headless browser only packs the
// pixels as PNG. Needs Node 22.18 or newer, which reads the .ts files as they are.
import {readFileSync, writeFileSync} from "node:fs"
import {createRequire} from "node:module"
import {dirname, join} from "node:path"
import {fileURLToPath} from "node:url"
import {frame, init} from "vgpu/node"
import {createPainter} from "./painter.ts"
import {decodeScene} from "./scene.ts"

const {chromium} = createRequire(import.meta.url)("playwright")
const here = dirname(fileURLToPath(import.meta.url))
const priv = join(here, "../../../priv/static")
/** Each shape: its stage in screen pixels, and the name of its full-size picture. */
const SHAPES = [["wide", [1440, 960], "card"], ["square", [1080, 1080], "item"]]
/** Every scene the site draws, by its baked file's name. */
const SCENES = [
  "factory", "island", "gallery", "museum", "lighthouse", "doomsday-heroes", "doomsday-throne",
  "campfire-stories", "trainer-battle", "missile-circus", "fishing", "meteor-strike",
  "dice-owl", "robot-toad", "drive-in", "black-slab", "fishing-dragon", "reef-owl", "missile-dragon",
  "snow-toad", "striped-owl", "petal-storm", "chase", "boulder-run", "nap", "stargazing", "portal-opens",
]

/** The art-pixel picture `scale` times as wide and high, each art pixel a square of `scale` by `scale`. */
const enlarge = (art, columns, rows, scale) => {
  const out = Buffer.alloc(columns * scale * rows * scale * 4)
  for (let y = 0; y < rows * scale; y++)
    for (let x = 0; x < columns * scale; x++) {
      const from = (Math.floor(y / scale) * columns + Math.floor(x / scale)) * 4
      art.copy(out, (y * columns * scale + x) * 4, from, from + 4)
    }
  return out
}

const gpu = await init()
const browser = await chromium.launch()
const page = await browser.newPage()

/** Packs RGBA pixels as PNG and writes them to images/animations/. */
const save = async (out, rgba, width, height) => {
  const png = await page.evaluate(
    async ([base64, width, height]) => {
      const bytes = Uint8ClampedArray.from(atob(base64), character => character.charCodeAt(0))
      const canvas = new OffscreenCanvas(width, height)
      canvas.getContext("2d").putImageData(new ImageData(bytes, width, height), 0, 0)
      const packed = new Uint8Array(await (await canvas.convertToBlob({type: "image/png"})).arrayBuffer())
      return btoa(Array.from(packed, byte => String.fromCharCode(byte)).join(""))
    },
    [rgba.toString("base64"), width, height],
  )
  writeFileSync(join(priv, `images/animations/${out}`), Buffer.from(png, "base64"))
  console.log(out, `${width} x ${height}`)
}

for (const name of SCENES) {
  const file = readFileSync(join(priv, `splats/${name}.bin`))
  const scene = decodeScene(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength))
  const painter = createPainter(gpu, scene)
  const moment = {yaw: scene.header.camYaw, pitch: scene.header.camPitch, target: scene.header.camTarget, seconds: 0}

  for (const [shape, [width, height], full] of SHAPES) {
    const {columns, rows, scale} = painter.resize(width, height, 1)
    await painter.compile()
    frame(gpu, current => painter.encode(current, moment))
    const pixels = await painter.picture.color.read({mipLevel: 0, region: "all"})
    const art = Buffer.from(pixels.buffer, pixels.byteOffset, columns * rows * 4)
    await save(`splats-${name}-${shape}.png`, art, columns, rows)
    await save(`splats-${name}-${full}.png`, enlarge(art, columns, rows, scale), columns * scale, rows * scale)
  }
}

await browser.close()
gpu.dispose()
