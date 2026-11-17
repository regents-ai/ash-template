/**
 * How a baked scene moves over its loop (studio/FORMAT.md sections 2.5 to 4), worked on
 * the processor: where a splat is at a moment, for ordering the few splats that are
 * drawn far to near (order.ts), and for the tests. The painter's shader (painter.ts)
 * works the same rules on the graphics card for every splat.
 */
import {clothCentre, FRAME_RATE, restCentre, type Header, type Scene} from "./scene.ts"

export type Vec3 = [number, number, number]

/** The kinds of motion a style's code names (code & 15). */
export const FLICKER = 1
export const FALL = 2
export const RISE = 3
export const BLINK = 4
export const ORBIT = 5
export const BOB = 6
export const PULSE = 7
export const SWAY = 11

const TAU = Math.PI * 2

/** The smooth step: 0 below a, 1 above b, and an S between. */
export const sstep = (a: number, b: number, x: number) => {
  const u = Math.min(1, Math.max(0, (x - a) / (b - a)))
  return u * u * (3 - 2 * u)
}
const frac = (x: number) => x - Math.floor(x)

/** The stored frame shown `seconds` into the loop: the one before, held until the next. */
export const frameAt = (header: Header, seconds: number) => Math.min(header.frames - 1, Math.floor(seconds * FRAME_RATE))

/** A moving splat's motion numbers (FORMAT.md 2.5): its kind, whole cycles a loop, phase, range and extra number. */
export type Motion = {kind: number; cycles: number; phase: number; range: number; extra: number}

export function motionOf({blocks}: Scene, n: number): Motion {
  const m = blocks.motion[n]!
  return {
    kind: blocks.styleCode[blocks.style[n]!]! & 15,
    cycles: blocks.cycles[n]!,
    phase: blocks.phase[n]! / 65536,
    range: blocks.motionRange[m]!,
    extra: blocks.motionExtra[m]!,
  }
}

/** What a kind of motion does at clock t (FORMAT.md 4), from the centre its part carried it to. */
export type Moved = {centre: Vec3; alpha: number; grow: number; glow: number}

/**
 * Its kind's change to a splat at clock t in a loop of `loop` seconds: its centre, a factor
 * on its density, a factor on its size, and light added to each colour channel.
 *
 * Every speed is a whole number of cycles a loop, so the maths is written in cycles: `turns`
 * is ωt over a full turn for most kinds, and ωt / r for falling and rising, which come to
 * the same number. The phase is a part of a cycle here for every kind.
 */
export function moved({kind, cycles, phase, range: r, extra: e}: Motion, [x, y, z]: Vec3, t: number, loop: number): Moved {
  const turns = (cycles * t) / loop
  const angle = TAU * (turns + phase)
  const still = {centre: [x, y, z] as Vec3, alpha: 1, grow: 1, glow: 0}
  switch (kind) {
    case FLICKER:
      return {...still, alpha: 0.62 + 0.38 * Math.sin(angle)}
    case FALL: {
      const u = frac(turns + phase)
      return {centre: [x, y - u * r, z], alpha: 1 - u * u, grow: 1 + u * e, glow: 0}
    }
    case RISE: {
      const u = frac(turns + phase)
      return {
        centre: [x + 0.25 * u * Math.sin(7 * u + 50 * phase), y + u * r, z],
        alpha: (1 - u) * sstep(0, 0.1, u),
        grow: 0.6 + u * e,
        glow: 0,
      }
    }
    case BLINK:
      return {...still, glow: 0.3 * sstep(0.75, 1, Math.sin(angle))}
    case ORBIT: {
      const turn = TAU * turns
      return {...still, centre: [x * Math.cos(turn) + z * Math.sin(turn), y, z * Math.cos(turn) - x * Math.sin(turn)]}
    }
    case BOB:
      return {...still, centre: [x, y + r * Math.sin(angle), z]}
    case PULSE:
      return {...still, alpha: 0.82 + 0.18 * Math.sin(angle)}
    case SWAY:
      return {
        ...still,
        centre: [
          x + r * Math.sin(TAU * turns + 1.3 * y + 0.9 * z + TAU * phase),
          y + 0.6 * r * Math.sin(1.3 * TAU * turns + 1.1 * x + TAU * phase),
          z,
        ],
      }
    default:
      return still
  }
}

/** Splat n's centre `seconds` into the loop: carried by its part, or the cloth, then moved by its kind. */
export function centreAt(scene: Scene, n: number, seconds: number): Vec3 {
  const {header, blocks} = scene
  const f = frameAt(header, seconds)
  const dab = n - header.clothFirst
  const [x, y, z] = dab >= 0 && dab < header.cloth ? clothCentre(scene, dab, f) : restCentre(scene, n)
  const a = blocks.track
  const o = (f * header.parts + blocks.stylePart[blocks.style[n]!]!) * 12
  const carried: Vec3 = [
    a[o]! * x + a[o + 1]! * y + a[o + 2]! * z + a[o + 9]!,
    a[o + 3]! * x + a[o + 4]! * y + a[o + 5]! * z + a[o + 10]!,
    a[o + 6]! * x + a[o + 7]! * y + a[o + 8]! * z + a[o + 11]!,
  ]
  return n < header.moving ? moved(motionOf(scene, n), carried, header.clockStart + seconds, header.loop).centre : carried
}
