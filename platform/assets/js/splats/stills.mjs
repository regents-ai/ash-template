// Draws the splats page's still picture into priv/static/images/animations/splats.png:
// the island at the angle and moment the live picture opens on, one pixel per picture
// pixel, so the browser scales it up in crisp squares. The island, colours and shaders
// are the page's own, read from the files beside this one.
//
//   npm run stills:splats            (from platform/, after changing the island)
//
// vgpu draws the frame on this machine's GPU; a headless browser only packs the
// pixels as PNG. Needs Node 22.18 or newer, which reads the .ts files as they are.
import {writeFileSync} from "node:fs"
import {createRequire} from "node:module"
import {dirname, join} from "node:path"
import {fileURLToPath} from "node:url"
import {frame, init, target} from "vgpu/node"
import {buildIsland, SPLAT_FLOATS} from "./island.ts"
import {depthOrder} from "./order.ts"
import {PITCH, ROWS, STILL_SECONDS, STILL_TURN, bob, createPainter, flicker} from "./painter.ts"
import {NIGHT, oklab, rgb} from "./palette.ts"

const {chromium} = createRequire(import.meta.url)("playwright")
const here = dirname(fileURLToPath(import.meta.url))
const out = join(here, "../../../priv/static/images/animations/splats.png")
const [width, height] = [ROWS * 1.5, ROWS]

const gpu = await init()
const island = buildIsland()
const palette = NIGHT.map(rgb)
const painter = createPainter(gpu, island, palette, palette.map(oklab))
const still = target(gpu, {size: [width, height], format: "rgba8unorm"})
const grid = painter.resize(width, height)
painter.order(depthOrder(island.data, island.count, SPLAT_FLOATS, island.reach)(STILL_TURN, PITCH))
const moment = {turn: STILL_TURN, bob: bob(STILL_SECONDS, grid.rows), flicker: flicker(STILL_SECONDS), seconds: STILL_SECONDS}
frame(gpu, current => painter.encode(current, moment, still))
const pixels = await still.color.read({mipLevel: 0, region: "all"})

const browser = await chromium.launch()
const page = await browser.newPage()
const png = await page.evaluate(
  async ([base64, size]) => {
    const bytes = Uint8ClampedArray.from(atob(base64), character => character.charCodeAt(0))
    const canvas = new OffscreenCanvas(size[0], size[1])
    canvas.getContext("2d").putImageData(new ImageData(bytes, size[0], size[1]), 0, 0)
    const packed = new Uint8Array(await (await canvas.convertToBlob({type: "image/png"})).arrayBuffer())
    return btoa(Array.from(packed, byte => String.fromCharCode(byte)).join(""))
  },
  [Buffer.from(pixels.buffer, pixels.byteOffset, width * height * 4).toString("base64"), [width, height]],
)
writeFileSync(out, Buffer.from(png, "base64"))
console.log("splats.png")

await browser.close()
gpu.dispose()
