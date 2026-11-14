/** Signals: what is sent, heard, kept in time and picked out. */
import type {IconSet} from "../icon"
import {TAU, clamp01, fract, mix, polar, ripple, there} from "../loop"
import type {Point} from "../pen"

// Each bar of noise rises and falls on two whole-loop rhythms, so it repeats exactly.
const NOISE_BARS = [
  [1, 3, 0.1, 0.7],
  [2, 1, 0.5, 0.2],
  [3, 2, 0.3, 0.9],
  [1, 4, 0.8, 0.4],
  [2, 3, 0.6, 0.1],
  [3, 1, 0.2, 0.6],
  [1, 2, 0.9, 0.3],
  [2, 4, 0.4, 0.8],
  [3, 2, 0.7, 0.5],
] as const

const SCAN_DOTS: readonly Point[] = [-32, -16, 0, 16, 32].flatMap(x => [-32, -16, 0, 16, 32].map(y => [x, y] as const))

const DETECT_TARGETS = [
  {turn: 0.1, r: 24},
  {turn: 0.58, r: 34},
] as const

export const signals: IconSet = {
  influence: {
    period: 4.5,
    still: 0.3,
    draw(pen, p) {
      for (let k = 0; k < 3; k += 1) {
        const f = fract(p + k / 3)
        pen.circle(0, 0, mix(7, 41, f), {tone: "quiet", dash: [20, 0.5], alpha: ripple(f)})
      }
      pen.circle(0, 0, 8)
      pen.dot(0, 0, 3.6, {tone: "accent"})
    },
  },
  broadcast: {
    period: 4,
    still: 0.45,
    draw(pen, p) {
      for (let k = 0; k < 3; k += 1) {
        const f = fract(p + k / 3)
        pen.circle(0, 22, mix(8, 44, f), {arc: [0.625, 0.25], alpha: ripple(f)})
      }
      pen.line(0, 22, 0, 36, {tone: "quiet"})
      pen.dot(0, 22, 3.6, {tone: "accent"})
    },
  },
  signal: {
    period: 4,
    still: 0.2,
    draw(pen, p) {
      pen.line(-44, 0, 44, 0, {tone: "quiet", dash: [2, 3]})
      const wave: Point[] = []
      for (let x = -44; x <= 44; x += 2) wave.push([x, -16 * Math.sin(TAU * (x / 44 - p))])
      pen.path(wave)
      pen.dot(0, 16 * Math.sin(TAU * p), 3.6, {tone: "accent"})
    },
  },
  noise: {
    period: 5,
    still: 0.37,
    draw(pen, p) {
      for (const [k, [a, b, sa, sb]] of NOISE_BARS.entries()) {
        const x = -36 + k * 9
        const level = Math.abs(0.6 * Math.sin(TAU * (a * p + sa)) + 0.4 * Math.sin(TAU * (b * p + sb)))
        const h = 3 + 30 * level
        pen.line(x, -h, x, h, {tone: k === 4 ? "accent" : k % 2 ? "quiet" : "ink", weight: 1.4})
      }
    },
  },
  sync: {
    period: 5,
    still: 0.12,
    draw(pen, p) {
      const turn = p - 0.25
      const [ax, ay] = polar(-21, 0, 15, turn)
      const [bx, by] = polar(21, 0, 15, turn)
      pen.circle(-21, 0, 15)
      pen.circle(21, 0, 15)
      pen.dot(-21, 0, 1.8, {tone: "quiet"})
      pen.dot(21, 0, 1.8, {tone: "quiet"})
      pen.line(ax, ay, bx, by, {tone: "accent", dash: [3, 2.5]})
      pen.dot(ax, ay, 3.2)
      pen.dot(bx, by, 3.2)
    },
  },
  tempo: {
    period: 3.6,
    still: 0.25,
    draw(pen, p) {
      const swingAngle = 0.42 * Math.sin(TAU * p)
      const bob: Point = [56 * Math.sin(swingAngle), -32 + 56 * Math.cos(swingAngle)]
      pen.line(-10, -32, 10, -32, {tone: "quiet"})
      pen.circle(0, -32, 56, {arc: [0.25 - 0.075, 0.15], tone: "quiet", dash: [90, 0.45]})
      pen.line(0, -32, bob[0], bob[1])
      pen.dot(0, -32, 2.4)
      pen.dot(bob[0], bob[1], 5, {tone: "accent"})
    },
  },
  scan: {
    period: 5,
    still: 0.3,
    draw(pen, p) {
      const x = mix(-41, 41, there(p))
      for (const [dx, dy] of SCAN_DOTS) {
        const near = clamp01(1 - Math.abs(x - dx) / 14)
        pen.dot(dx, dy, 2.4, {tone: "quiet"})
        pen.dot(dx, dy, 2.4, {alpha: near})
      }
      pen.line(x, -42, x, 42, {tone: "accent"})
    },
  },
  detect: {
    period: 5,
    still: 0.2,
    draw(pen, p) {
      pen.circle(0, 0, 14, {tone: "quiet"})
      pen.circle(0, 0, 28, {tone: "quiet"})
      pen.circle(0, 0, 41, {tone: "quiet", dash: [40, 0.5]})
      const beam = p - 0.25
      for (let k = 4; k >= 0; k -= 1) {
        const [x, y] = polar(0, 0, 41, beam - k * 0.018)
        pen.line(0, 0, x, y, {tone: k ? "quiet" : "ink", alpha: k ? 0.5 - k * 0.09 : 1})
      }
      for (const target of DETECT_TARGETS) {
        const since = fract(beam - target.turn)
        const lit = Math.exp(-since * 7)
        const [x, y] = polar(0, 0, target.r, target.turn)
        pen.dot(x, y, 2.6, {tone: "quiet"})
        pen.dot(x, y, 3, {tone: "accent", alpha: lit})
        pen.circle(x, y, 4 + 10 * since, {tone: "accent", alpha: lit * 0.8})
      }
    },
  },
}
