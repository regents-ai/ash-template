/**
 * Which splats the painter (painter.ts) must draw far to near, and in what order.
 *
 * FORMAT.md 5.3 draws every splat far to near. A solid splat whose density never changes
 * hides what is behind it, so for those the graphics card's depth test keeps the nearest
 * at each art pixel and they are drawn in file order, unsorted. The rest are sorted here
 * every frame: soft splats, which only tint what is behind them; splats that never write
 * depth; and those whose kind changes their density (flicker, fall, rise and pulse),
 * since they can be solid at one moment and soft at the next. That is 3,063 of the
 * island's 294,707 splats and 5,889 of the factory's 399,656.
 */
import {centreAt, FALL, FLICKER, PULSE, RISE} from "./motion.ts"
import {NO_DEPTH, type Scene} from "./scene.ts"

type Vec3 = readonly [number, number, number]

const FADING = new Set([FLICKER, FALL, RISE, PULSE])

export function createOrder(scene: Scene) {
  const {header, blocks} = scene
  const solid: number[] = []
  const sorted: number[] = []
  for (let n = 0; n < header.splats; n++) {
    const style = blocks.style[n]!
    const code = blocks.styleCode[style]!
    const fades = n < header.moving && FADING.has(code & 15)
    const blends = blocks.styleDensity[style]! < 1 || (code & NO_DEPTH) !== 0 || fades
    ;(blends ? sorted : solid).push(n)
  }
  const keys = new Float64Array(sorted.length)
  const places = new Uint32Array(sorted.length)
  const ids = new Uint32Array(sorted.length)

  return {
    /** The solid splats, in file order. */
    solid: Uint32Array.from(solid),
    /** The rest, farthest first `seconds` into the loop for a camera whose back axis is `back`; ties keep file order. */
    farToNear(back: Vec3, seconds: number): Uint32Array<ArrayBuffer> {
      for (let i = 0; i < sorted.length; i++) {
        const [x, y, z] = centreAt(scene, sorted[i]!, seconds)
        keys[i] = back[0] * x + back[1] * y + back[2] * z
        places[i] = i
      }
      places.sort((a, b) => keys[a]! - keys[b]! || a - b)
      for (let i = 0; i < sorted.length; i++) ids[i] = sorted[places[i]!]!
      return ids
    },
  }
}
