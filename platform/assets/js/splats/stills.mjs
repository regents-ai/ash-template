// Draws the splats page's still pictures into priv/static/images/animations/: for each
// scene, splats-<scene>-wide.png (three by two, for the wide box) and
// splats-<scene>-square.png (for a phone's square box), at the view and moment its live
// picture opens on and framed as the live picture is in a box of that shape, one pixel
// per picture pixel, so the browser scales them up in crisp squares. The scenes,
// colours and shaders are the page's own, read from the files beside this one.
//
//   npm run stills:splats            (from platform/, after changing a scene)
//
// vgpu draws the frames on this machine's GPU; a headless browser only packs the
// pixels as PNG. Needs Node 22.18 or newer, which reads the .ts files as they are.
import {writeFileSync} from "node:fs"
import {createRequire} from "node:module"
import {dirname, join} from "node:path"
import {fileURLToPath} from "node:url"
import {frame, init, target} from "vgpu/node"
import {SPLAT_FLOATS} from "./build.ts"
import {buildFactory} from "./factory.ts"
import {buildIsland} from "./island.ts"
import {depthOrder} from "./order.ts"
import {bob, createPainter, flicker, viewFrom} from "./painter.ts"
import {oklab, rgb} from "./palette.ts"

const {chromium} = createRequire(import.meta.url)("playwright")
const here = dirname(fileURLToPath(import.meta.url))
const SHAPES = [["wide", [432, 288]], ["square", [432, 432]]]

const gpu = await init()
const browser = await chromium.launch()
const page = await browser.newPage()

for (const [name, build] of [["factory", buildFactory], ["island", buildIsland]]) {
  const scene = build()
  const palette = scene.palette.map(rgb)
  const painter = createPainter(gpu, scene, palette, palette.map(oklab))
  const {turn, pitch, seconds} = scene.still
  const parts = new Float32Array(Math.max(1, scene.parts) * 16)
  scene.pose(seconds, parts, 0)
  painter.pose(parts)
  painter.order(depthOrder(scene.data, scene.count, SPLAT_FLOATS, scene.reach)(viewFrom(scene.camera, turn, pitch).ahead, parts))

  for (const [shape, [width, height]] of SHAPES) {
    const still = target(gpu, {size: [width, height], format: "rgba8unorm"})
    const grid = painter.resize(width, height)
    const moment = {turn, pitch, bob: bob(seconds, grid.rows, 0), flicker: flicker(seconds, 0), seconds, loop: 0}
    frame(gpu, current => painter.encode(current, moment, still))
    const pixels = await still.color.read({mipLevel: 0, region: "all"})
    const png = await page.evaluate(
      async ([base64, width, height]) => {
        const bytes = Uint8ClampedArray.from(atob(base64), character => character.charCodeAt(0))
        const canvas = new OffscreenCanvas(width, height)
        canvas.getContext("2d").putImageData(new ImageData(bytes, width, height), 0, 0)
        const packed = new Uint8Array(await (await canvas.convertToBlob({type: "image/png"})).arrayBuffer())
        return btoa(Array.from(packed, byte => String.fromCharCode(byte)).join(""))
      },
      [Buffer.from(pixels.buffer, pixels.byteOffset, width * height * 4).toString("base64"), width, height],
    )
    const file = `splats-${name}-${shape}.png`
    writeFileSync(join(here, `../../../priv/static/images/animations/${file}`), Buffer.from(png, "base64"))
    console.log(file)
  }
}

await browser.close()
gpu.dispose()
