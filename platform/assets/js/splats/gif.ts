/**
 * The splats page's Download GIF (`AshTemplateWeb.SplatsLabLive`, splat_island.ts): one
 * seamless loop of the scene showing, as a GIF in the scene's own palette. Loaded only
 * when the button is pressed.
 *
 * The camera goes once round the scene at its resting tilt while everything in it plays
 * its loop once, so the last frame runs on into the first. Each frame is drawn by the
 * page's own painter (painter.ts) on a device of its own, so the picture on the page
 * carries on, and read back.
 *
 * Every pixel the painter draws is one of the palette's colours, so the GIF's one colour
 * table is the palette as it is, with one more entry that marks a pixel unchanged since
 * the frame before. Nothing is matched to a colour again or dithered here. Each frame is
 * scaled up by a whole number, every pixel a square.
 */
import {GIFEncoder} from "gifenc"
import {frame, init} from "vgpu"

import {createPainter} from "./painter.ts"
import type {Scene} from "./scene.ts"

/** The loop: this many frames, each shown this many hundredths of a second (as a GIF counts time). */
export const FRAMES = 160
export const DELAY = 5
/**
 * The stage each frame is drawn for, three wide by two high, and the GIF's size: each art
 * pixel is scaled up to the square of screen pixels it is on that stage (two for most
 * scenes, 432 by 288 art pixels; three for one whose camera stands nearer).
 */
export const STAGE = [864, 576] as const

/**
 * A GIF that loops for ever, in `palette` (0xRRGGBB), of frames `columns` by `rows`
 * pixels scaled up `scale` times. Each frame comes as the painter's RGBA bytes, one
 * palette colour per pixel; a pixel unchanged since the frame before is left clear, so
 * the last frame shows through it.
 */
export function createGif(palette: ArrayLike<number>, columns: number, rows: number, scale: number) {
  const colours = Array.from(palette, value => [(value >> 16) & 255, (value >> 8) & 255, value & 255])
  const index = new Map(Array.from(palette, (value, i) => [value, i]))
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
        const found = index.get((rgba[p * 4]! << 16) | (rgba[p * 4 + 1]! << 8) | rgba[p * 4 + 2]!)
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
    const {header} = scene
    const painter = createPainter(gpu, scene)
    // The scene's own framing, whatever the page is zoomed to.
    const grid = painter.resize(...STAGE, 1)
    await painter.compile()
    const gif = createGif(scene.blocks.palette, grid.columns, grid.rows, grid.scale)
    for (let i = 0; i < FRAMES; i++) {
      signal.throwIfAborted()
      // The page's cruise: the near side drifts right as the yaw falls.
      const moment = {
        yaw: header.camYaw - (i / FRAMES) * 2 * Math.PI,
        pitch: header.camPitch,
        target: header.camTarget,
        seconds: (i * header.loop) / FRAMES,
      }
      frame(gpu, f => painter.encode(f, moment))
      gif.add(await painter.picture.color.read({mipLevel: 0, region: "all"}))
      progress((i + 1) / FRAMES)
    }
    signal.throwIfAborted()
    return gif.finish()
  } finally {
    gpu.dispose()
  }
}
