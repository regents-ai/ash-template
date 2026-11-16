/**
 * The splats page's Download GIF (`AshTemplateWeb.SplatsLabLive`, splat_island.ts): one
 * seamless loop of the scene showing, as a GIF in the scene's own palette. Loaded only
 * when the button is pressed.
 *
 * The scene turns once round at its resting tilt, with every moving part running. Each
 * frame is drawn by the page's own painter (painter.ts) on a device of its own, so the
 * picture on the page carries on, as the low picture alone, and read back. The loop
 * runs on from its last frame into its first: every moving thing comes round a whole
 * number of times in it (build.ts `rate`), steam and sparks too, since each lives a
 * share of its own cycle; the motes each live once round the loop, fading in and out;
 * the clouds hold still.
 *
 * Every pixel the painter draws is one of the palette's colours, so the GIF's one colour
 * table is the palette as it is, with one more entry that marks a pixel unchanged since
 * the frame before. Nothing is matched to a colour again or dithered here. Each frame is
 * scaled up by a whole number, every pixel a square.
 */
import {GIFEncoder} from "gifenc"
import {frame, init} from "vgpu"

import {SPLAT_FLOATS, type Scene} from "./build.ts"
import {depthOrder} from "./order.ts"
import {bob, createPainter, flicker, viewFrom} from "./painter.ts"
import {oklab, rgb} from "./palette.ts"

/** The loop: this many frames, each shown this many hundredths of a second (as a GIF counts time), and its length in seconds. */
export const FRAMES = 160
export const DELAY = 5
export const LOOP = (FRAMES * DELAY) / 100
/** The low picture each frame is drawn on, three wide by two high, and the whole number its pixels are scaled up by. */
export const COLUMNS = 432
export const ROWS = 288
export const SCALE = 2

const channel = (value: string, at: number) => Number.parseInt(value.slice(at, at + 2), 16)
const packed = (r: number, g: number, b: number) => (r << 16) | (g << 8) | b

/**
 * A GIF that loops for ever, in `palette`, of frames `columns` by `rows` pixels scaled up
 * `scale` times. Each frame comes as the painter's RGBA bytes, one palette colour per
 * pixel; a pixel unchanged since the frame before is left clear, so the last frame shows
 * through it.
 */
export function createGif(palette: readonly string[], columns: number, rows: number, scale: number) {
  // Each colour as the three bytes a picture stores.
  const colours = palette.map(value => [channel(value, 1), channel(value, 3), channel(value, 5)])
  const index = new Map(colours.map(([r, g, b], i) => [packed(r!, g!, b!), i]))
  const unchanged = colours.length
  const table = [...colours, [0, 0, 0]]
  const depth = Math.ceil(Math.log2(table.length))
  const width = columns * scale
  const height = rows * scale
  const encoder = GIFEncoder()
  let last: Uint8Array | undefined

  return {
    add(rgba: Uint8Array) {
      const low = new Uint8Array(columns * rows)
      for (let p = 0; p < low.length; p++) {
        const found = index.get(packed(rgba[p * 4]!, rgba[p * 4 + 1]!, rgba[p * 4 + 2]!))
        if (found === undefined) throw new Error(`Pixel ${p} is not one of the palette's colours`)
        low[p] = found
      }
      const big = new Uint8Array(width * height)
      for (let y = 0; y < rows; y++) {
        const line = y * scale * width
        for (let x = 0; x < columns; x++) {
          const p = y * columns + x
          big.fill(last?.[p] === low[p] ? unchanged : low[p]!, line + x * scale, line + (x + 1) * scale)
        }
        for (let k = 1; k < scale; k++) big.copyWithin(line + k * width, line, line + width)
      }
      // The first frame carries the colour table and the loop; every frame stays on as the next is laid over it.
      encoder.writeFrame(big, width, height, {
        ...(last ? {transparent: true, transparentIndex: unchanged} : {palette: table, repeat: 0}),
        delay: DELAY * 10,
        dispose: 1,
        colorDepth: depth,
      })
      last = low
    },
    finish() {
      encoder.finish()
      return encoder.bytes()
    },
  }
}

/** Draws and encodes the loop of `scene`, telling `progress` the share done after each frame; stops at the next frame once `signal` is aborted. */
export async function makeGif(scene: Scene, progress: (share: number) => void, signal: AbortSignal) {
  const gpu = await init()
  try {
    signal.throwIfAborted()
    const palette = scene.palette.map(rgb)
    const painter = createPainter(gpu, scene, palette, palette.map(oklab))
    const grid = painter.resize(COLUMNS, ROWS)
    await painter.compile()
    const sort = depthOrder(scene.data, scene.count, SPLAT_FLOATS, scene.reach)
    const parts = new Float32Array(Math.max(1, scene.parts) * 16)
    const gif = createGif(scene.palette, grid.columns, grid.rows, SCALE)
    const pitch = scene.camera.pitch
    for (let i = 0; i < FRAMES; i++) {
      signal.throwIfAborted()
      const seconds = (i / FRAMES) * LOOP
      const turn = scene.still.turn + (i / FRAMES) * 2 * Math.PI
      scene.pose(seconds, parts, LOOP)
      painter.pose(parts)
      painter.order(sort(viewFrom(scene.camera, turn, pitch).ahead, parts))
      const moment = {turn, pitch, bob: bob(seconds, grid.rows, LOOP), flicker: flicker(seconds, LOOP), seconds, loop: LOOP}
      frame(gpu, f => painter.encode(f, moment))
      gif.add(await painter.pixels.color.read({mipLevel: 0, region: "all"}))
      progress((i + 1) / FRAMES)
    }
    signal.throwIfAborted()
    return gif.finish()
  } finally {
    gpu.dispose()
  }
}
