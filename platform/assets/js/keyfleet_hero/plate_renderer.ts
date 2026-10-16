/**
 * Draws the raised hex plate under "Buy Agent Fleet Access Key" with WebGPU
 * through vgpu. It eases nothing itself: the hook's Anime.js moves set how
 * high the tiles stand, how far they have risen and how high the group under
 * the words stands, and each change is one frame. With nothing moving there
 * is nothing to draw.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, init, surface} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import {plateWgsl} from "./plate_shader"
import type {Rgb} from "./renderer"

type Vec4 = [number, number, number, number]
/** Left, top, right and bottom. */
export type Box = Vec4

export type PlateRenderer = IslandRenderer & {
  /** The faces' colour, the sides' colour, the raised group's colour and how dark the shadow is. */
  tones(face: Rgb, side: Rgb, deep: Rgb, shadow: number): void
  /** The plate's box and the words' box inside the canvas, in CSS pixels. */
  slab(plate: Box, words: Box): void
  /** How high the faces stand in CSS pixels, how far the tiles have risen (0..1) and their light (0..1). */
  raise(lift: number, rise: number, glow: number): void
  /** How much higher the group under the words stands in CSS pixels, and how far it has risen (0..1). */
  group(lift: number, amount: number): void
}

export async function createPlateRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
  cell: number,
): Promise<PlateRenderer> {
  // Device pixels per CSS pixel, so the tiles, the box and the lift keep their CSS size.
  let ratio = 1
  let plate: Box = [0, 0, 0, 0]
  let words: Box = [0, 0, 0, 0]
  let raised: Vec4 = [0, 0, 0, 0]
  let grouped: [number, number] = [0, 0]
  let shadow = 0
  const device = (box: Box): Vec4 => [box[0] * ratio, box[1] * ratio, box[2] * ratio, box[3] * ratio]
  const raise = (): Vec4 => [raised[0] * ratio, raised[1], raised[2], shadow]
  // The tallest a tile can stand now, so the shader looks through no more height than it needs.
  const group = (): Vec4 => [grouped[0] * ratio, grouped[1], (raised[0] + grouped[0]) * ratio, 0]

  const gpu = await init()
  let disposed = false
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  try {
    const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "premultiplied", label: "keyfleet-plate"})
    stage.resize([size[0], size[1]])
    const shader = effect(gpu, prepareShader(plateWgsl, "keyfleet-plate.wgsl"), {
      label: "keyfleet-plate.pass",
      set: {
        params: {
          size: [size[0], size[1], cell, 1],
          slab: device(plate),
          raise: raise(),
          words: device(words),
          group: group(),
          face: [1, 1, 1, 1],
          side: [1, 1, 1, 1],
          deep: [1, 1, 1, 1],
        },
      },
    })
    await shader.compile({colors: [stage.format]})
    const unsubscribe = stage.onResize(({width, height}) => {
      ratio = width / Math.max(1, canvas.clientWidth)
      shader.set({
        params: {
          size: [width, height, cell * ratio, ratio],
          slab: device(plate),
          words: device(words),
          raise: raise(),
          group: group(),
        },
      })
    })

    return {
      tones(face, side, deep, dark) {
        shadow = dark
        shader.set({params: {face: [...face, 1], side: [...side, 1], deep: [...deep, 1], raise: raise()}})
      },
      slab(box, inner) {
        plate = box
        words = inner
        shader.set({params: {slab: device(plate), words: device(words)}})
      },
      raise(lift, rise, glow) {
        raised = [lift, rise, glow, 0]
        shader.set({params: {raise: raise(), group: group()}})
      },
      group(lift, amount) {
        grouped = [lift, amount]
        shader.set({params: {group: group()}})
      },
      resize(width, height) {
        stage.resize([width, height])
      },
      step() {
        return false
      },
      present() {
        frame(gpu, current => current.pass(stage, shader))
      },
      async settled() {
        await gpu.gpu.queue.onSubmittedWorkDone()
        await gpu.settled()
      },
      dispose() {
        if (disposed) return
        disposed = true
        unsubscribe()
        stage.dispose()
        gpu.dispose()
      },
    }
  } catch (error) {
    gpu.dispose()
    throw error
  }
}
