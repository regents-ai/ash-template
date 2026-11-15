/**
 * The splats page's picture (`AshTemplateWeb.SplatsLabLive`): the island grown in
 * island.ts, painted by painter.ts on one canvas through WebGPU, turning once every
 * thirty seconds and bobbing gently.
 *
 * A drag turns it under the pointer, one to one; let go, and it eases from the speed
 * it was let go at back into its slow turn. The arrow keys turn it a step at a time.
 * Held still (less motion asked for), nothing moves by itself: it opens at the still
 * picture's angle and moment, and a drag still turns it, stopping where it is let go.
 *
 * The splats are sorted farthest first on the main thread only once the island has
 * turned a little since the last sort: well under a millisecond each time.
 */
import {frame, init, surface} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import {buildIsland, SPLAT_FLOATS} from "./island"
import {depthOrder} from "./order"
import {bob, createPainter, flicker, PITCH, RADIUS_IN_HEIGHT, STILL_SECONDS, STILL_TURN, type PixelGrid} from "./painter"
import {NIGHT, oklab, rgb} from "./palette"

/** One full turn every thirty seconds, in radians a second. */
const CRUISE = (Math.PI * 2) / 30
/** How quickly a released island eases back into its turn, and a key's step settles (seconds). */
const SETTLE = 0.9
const KEY_SETTLE = 0.18
/** How far one press of an arrow key turns the island. */
const KEY_STEP = (20 * Math.PI) / 180
/** The fastest a flick sets the island turning: once a second. */
const FASTEST = Math.PI * 2
/** How far the island turns before its splats are sorted again. */
const RESORT = (0.6 * Math.PI) / 180
/** A frame after a long pause counts as this long, so nothing jumps. */
const LONGEST_STEP = 1 / 30

export type SplatRenderer = IslandRenderer & {
  /** Holds the island still (less motion) or lets it turn and bob. */
  hold(calm: boolean): void
  /** A pointer took hold of the island. */
  grab(): void
  /** The pointer moved this many CSS pixels across: the island's near edge moves with it. */
  drag(pixels: number): void
  /** The pointer let go, moving this many CSS pixels a second across. */
  release(pixelsPerSecond: number): void
  /** One arrow key's step: 1 turns the near side right, -1 left. */
  press(direction: 1 | -1): void
}

export async function createSplatRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<SplatRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a picture still in use reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  try {
    const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "opaque", label: "splats"})
    const island = buildIsland()
    const palette = NIGHT.map(rgb)
    const painter = createPainter(gpu, island, palette, palette.map(oklab))
    const sort = depthOrder(island.data, island.count, SPLAT_FLOATS, island.reach)
    stage.resize([size[0], size[1]])
    let grid: PixelGrid = painter.resize(size[0], size[1])
    await painter.compile(stage)

    let calm = false
    let held = false
    let turn = STILL_TURN
    let seconds = STILL_SECONDS
    let speed = CRUISE
    // Turning still owed to arrow presses, and to drags since the last frame.
    let keyed = 0
    let dragged = 0
    let sortedAt: number | undefined
    let drawnAt: number | undefined
    let last: number | undefined
    // Radians per CSS pixel across, so the island's near edge keeps up with the pointer.
    const radians = (pixels: number) => pixels / (Math.max(1, canvas.clientHeight) * RADIUS_IN_HEIGHT)

    return {
      hold(next) {
        calm = next
        if (calm) {
          // A key's step still settling lands at once, as a step does when held still.
          dragged += keyed
          keyed = 0
          speed = 0
        } else if (!held) speed = CRUISE
      },
      grab() {
        held = true
        speed = 0
      },
      drag(pixels) {
        dragged += radians(pixels)
      },
      release(pixelsPerSecond) {
        held = false
        speed = calm ? 0 : Math.max(-FASTEST, Math.min(FASTEST, radians(pixelsPerSecond)))
      },
      press(direction) {
        if (calm) dragged += direction * KEY_STEP
        else keyed += direction * KEY_STEP
      },
      resize(width, height) {
        stage.resize([width, height])
        grid = painter.resize(width, height)
        drawnAt = undefined
      },
      step() {
        const now = performance.now() / 1000
        const dt = last === undefined ? 0 : Math.min(now - last, LONGEST_STEP)
        last = now
        turn += dragged
        dragged = 0
        if (!calm) {
          seconds += dt
          const toward = held ? 0 : CRUISE
          speed += (toward - speed) * (1 - Math.exp(-dt / SETTLE))
          const keyStep = Math.abs(keyed) < 1e-4 ? keyed : keyed * (1 - Math.exp(-dt / KEY_SETTLE))
          keyed -= keyStep
          turn += speed * dt + keyStep
        }
        return !calm || turn !== drawnAt
      },
      present() {
        if (sortedAt === undefined || Math.abs(turn - sortedAt) > RESORT) {
          painter.order(sort(turn, PITCH))
          sortedAt = turn
        }
        drawnAt = turn
        const moment = {turn, bob: bob(seconds, grid.rows), flicker: flicker(seconds), seconds}
        frame(gpu, f => painter.encode(f, moment, stage))
      },
      settled() {
        return gpu.settled()
      },
      dispose() {
        if (disposed) return
        disposed = true
        stage.dispose()
        gpu.dispose()
      },
    }
  } catch (error) {
    gpu.dispose()
    throw error
  }
}
