// Draws the splats page's still pictures into priv/static/images/animations/: for each
// scene, splats-<scene>-wide.png (three by two, for the wide box) and
// splats-<scene>-square.png (for a phone's square box), at the view and moment its live
// picture opens on (the scene's starting yaw and pitch, the start of its loop), one
// pixel per art pixel, so the browser scales them up in crisp squares. The scenes are
// the baked files the page draws (priv/static/splats/), painted by the page's own
// painter as a 1440 by 960 stage and a 1080 by 1080 one would show them.
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
const SHAPES = [["wide", [1440, 960]], ["square", [1080, 1080]]]

const gpu = await init()
const browser = await chromium.launch()
const page = await browser.newPage()

for (const name of ["factory", "island"]) {
  const file = readFileSync(join(priv, `splats/${name}.bin`))
  const scene = decodeScene(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength))
  const painter = createPainter(gpu, scene)
  const moment = {yaw: scene.header.camYaw, pitch: scene.header.camPitch, seconds: 0}

  for (const [shape, [width, height]] of SHAPES) {
    const {columns, rows} = painter.resize(width, height)
    await painter.compile()
    frame(gpu, current => painter.encode(current, moment))
    const pixels = await painter.picture.color.read({mipLevel: 0, region: "all"})
    const png = await page.evaluate(
      async ([base64, width, height]) => {
        const bytes = Uint8ClampedArray.from(atob(base64), character => character.charCodeAt(0))
        const canvas = new OffscreenCanvas(width, height)
        canvas.getContext("2d").putImageData(new ImageData(bytes, width, height), 0, 0)
        const packed = new Uint8Array(await (await canvas.convertToBlob({type: "image/png"})).arrayBuffer())
        return btoa(Array.from(packed, byte => String.fromCharCode(byte)).join(""))
      },
      [Buffer.from(pixels.buffer, pixels.byteOffset, columns * rows * 4).toString("base64"), columns, rows],
    )
    const out = `splats-${name}-${shape}.png`
    writeFileSync(join(priv, `images/animations/${out}`), Buffer.from(png, "base64"))
    console.log(out, `${columns} x ${rows}`)
  }
}

await browser.close()
gpu.dispose()
