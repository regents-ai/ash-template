/**
 * The theme switch's two pictures, the moon for night and the sun for day, as
 * one 9 by 9 matrix of pixels each, drawn after the Lucide moon and sun the
 * still switch shows. The GPU draws them behind the glass knob, and every moon
 * pixel flies to the sun pixel it is paired with.
 *
 * This file is the one source of both pictures. Each has 29 pixels, so every
 * pixel of one has exactly one partner in the other.
 */

export const GRID = 9

// Row by row from the top; "#" is a lit pixel.
export const MOON = [
  "...##....",
  "..##.....",
  ".##......",
  ".##......",
  "###......",
  "###.....#",
  ".###...##",
  "..######.",
  "...###...",
] as const

export const SUN = [
  "....#....",
  ".#.....#.",
  "...###...",
  "..#####..",
  "#.#####.#",
  "..#####..",
  "...###...",
  ".#.....#.",
  "....#....",
] as const

/** A lit pixel, in cells from the matrix's centre: x to the right, y down. */
export type Pixel = {
  readonly x: number
  readonly y: number
  /** Clockwise on screen from straight right, in [0, 2π); 0 at the centre itself. */
  readonly angle: number
  readonly radius: number
}

/** A moon pixel and the sun pixel it becomes. */
export type Pair = {readonly moon: Pixel; readonly sun: Pixel}

const TURN = Math.PI * 2

/** Folds any angle into [0, 2π). */
export const wrapAngle = (angle: number): number => ((angle % TURN) + TURN) % TURN

/** The shortest signed turn from `from` to `to`, in (-π, π]. */
export const turnBetween = (from: number, to: number): number => {
  const turn = wrapAngle(to - from)
  return turn > Math.PI ? turn - TURN : turn
}

/** The lit pixels of a picture, in reading order. */
export function readPixels(rows: readonly string[]): Pixel[] {
  const centre = (rows.length - 1) / 2
  const pixels: Pixel[] = []
  rows.forEach((row, y) => {
    for (let x = 0; x < row.length; x++) {
      if (row[x] !== "#") continue
      const dx = x - centre
      const dy = y - centre
      pixels.push({x: dx, y: dy, angle: wrapAngle(Math.atan2(dy, dx)), radius: Math.hypot(dx, dy)})
    }
  })
  return pixels
}

const byAngle = (a: Pixel, b: Pixel) => a.angle - b.angle || a.radius - b.radius

/**
 * Pairs every pixel of one picture with one of the other by angle round the
 * centre. Both are walked in clockwise order; the walk round the second starts
 * wherever the pairs, taken together, turn least. The result keeps the first
 * picture's clockwise order, so neighbours stay neighbours in flight.
 */
export function pairByAngle(from: readonly Pixel[], to: readonly Pixel[]): Pair[] {
  if (from.length !== to.length) {
    throw new Error(`the pictures differ in size: ${from.length} and ${to.length} pixels`)
  }
  const moons = [...from].sort(byAngle)
  const suns = [...to].sort(byAngle)
  const count = moons.length
  let start = 0
  let least = Infinity
  for (let shift = 0; shift < count; shift++) {
    let turn = 0
    for (let i = 0; i < count; i++) turn += Math.abs(turnBetween(moons[i].angle, suns[(i + shift) % count].angle))
    if (turn < least - 1e-9) {
      least = turn
      start = shift
    }
  }
  return moons.map((moon, i) => ({moon, sun: suns[(i + start) % count]}))
}

/** The moon and the sun, paired once for every switch on the page. */
export const PAIRS: readonly Pair[] = pairByAngle(readPixels(MOON), readPixels(SUN))
