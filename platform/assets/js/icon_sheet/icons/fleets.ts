/** Fleets: how a person and their agents pair, gather, decide and wear the crown. */
import type {IconSet} from "../icon"
import {TAU, clamp01, curve, mix, polar, pulse, span} from "../loop"
import {node} from "../marks"
import type {Point} from "../pen"

const FORMATION = [
  [22, 0],
  [6, -14],
  [6, 14],
  [-10, -28],
  [-10, 28],
] as const

const POLL_SHARES = [0.5, 0.3, 0.2] as const
const POLL_GAP = 0.02

const VOTES = [-1, 1, -1, -1, 1] as const

const CHAIN: readonly Point[] = [[-34, 12], [-18, 12], [-2, 12]]
const PROPOSAL: Point = [24, -14]

// The Regents crown: thirteen blocks in rows of 3, 5 and 5 on a grid five wide, the
// top row at the first, third and fifth columns. It is built from the bottom row up.
const CROWN: readonly Point[] = [
  ...[-28, -14, 0, 14, 28].map(x => [x, 14] as const),
  ...[-28, -14, 0, 14, 28].map(x => [x, 0] as const),
  ...[-28, 0, 28].map(x => [x, -14] as const),
]

export const fleets: IconSet = {
  pair: {
    period: 5.5,
    still: 0.56,
    draw(pen, p) {
      pen.dot(-24, 0, 6)
      pen.rect(24, 0, 7, 7)
      // Each side reaches for the other; where they meet the pair holds.
      const reach = 16 * (span(p, 0.08, 0.4) - span(p, 0.8, 0.95))
      if (reach > 0.02) {
        pen.line(-16, 0, -16 + reach, 0, {tone: "quiet", dash: [2.5, 2.5]})
        pen.line(16, 0, 16 - reach, 0, {tone: "quiet", dash: [2.5, 2.5]})
      }
      const held = pulse(p, 0.4, 0.48, 0.78, 0.88)
      pen.line(-16, 0, 16, 0, {tone: "accent", weight: 1.4, alpha: held})
      pen.circle(-24, 0, 11, {tone: "quiet", alpha: held})
      pen.rect(24, 0, 11, 11, {tone: "quiet", alpha: held})
    },
  },
  key: {
    period: 6,
    still: 0.1,
    draw(pen, p) {
      pen.circle(0, 0, 26, {tone: "quiet", dash: [36, 0.5]})
      const [ax, ay] = polar(0, 0, 26, p - 0.125)
      const [bx, by] = polar(0, 0, 26, p + 0.375)
      pen.line(ax, ay, bx, by)
      pen.dot(0, 0, 2.2)
      node(pen, bx, by, 5.5)
      pen.dot(ax, ay, 5, {tone: "accent"})
    },
  },
  fleet: {
    period: 5,
    still: 0.3,
    draw(pen, p) {
      for (const [k, [x0, y0]] of FORMATION.entries()) {
        const x = x0 + 2.5 * Math.sin(TAU * (p + k * 0.21))
        const y = y0 + 3 * Math.sin(TAU * (p + k * 0.13))
        pen.line(x - 7, y, x - 18, y, {tone: "quiet", dash: [2, 2.5]})
        pen.tri(x, y, 6, {tone: k ? "ink" : "accent"})
      }
    },
  },
  patch: {
    period: 5.5,
    still: 0.5,
    draw(pen, p) {
      pen.rect(-28, 16, 7, 7)
      pen.rect(28, 16, 7, 7)
      pen.dot(-28, 16, 2.4)
      pen.dot(28, 16, 2.4, {tone: "quiet"})
      // One end stays in the left socket; the other is carried over to the right one.
      const t = span(p, 0.1, 0.45) - span(p, 0.66, 0.92)
      const end: Point = [mix(-28, 28, t), 16 - 30 * Math.sin(Math.PI * t)]
      if (t > 0.01) {
        const top = Math.min(16, end[1]) - 22
        const cable = curve([-28, 16], [(end[0] - 28) / 2, top], end, 18)
        pen.path(cable, {weight: 1.3})
      }
      pen.rect(end[0], end[1], 3.4, 3.4, {fill: "solid"})
      const plugged = clamp01((t - 0.94) / 0.06)
      pen.dot(28, 16, 2.4, {tone: "accent", alpha: plugged})
      pen.rect(28, 16, 10.5, 10.5, {tone: "accent", alpha: plugged})
    },
  },
  poll: {
    period: 6,
    still: 0.62,
    draw(pen, p) {
      pen.circle(0, 0, 24, {tone: "quiet"})
      const grown = span(p, 0.1, 0.55)
      const shown = 1 - span(p, 0.82, 0.97)
      let start = -0.25
      for (const [k, share] of POLL_SHARES.entries()) {
        const sweep = (share - POLL_GAP) * grown
        if (sweep > 0.001) {
          pen.circle(0, 0, 24, {arc: [start, sweep], weight: 3, tone: k ? "ink" : "accent", alpha: shown})
        }
        start += share * grown
      }
    },
  },
  propose: {
    period: 5.5,
    still: 0.62,
    draw(pen, p) {
      pen.path(CHAIN)
      for (const [x, y] of CHAIN) pen.dot(x, y, 3.6)
      const out = span(p, 0.1, 0.4) - span(p, 0.84, 0.96)
      if (out > 0.01) {
        pen.line(-2, 12, mix(-2, PROPOSAL[0], out), mix(12, PROPOSAL[1], out), {tone: "quiet", dash: [2.5, 2.5]})
      }
      const shown = pulse(p, 0.34, 0.46, 0.8, 0.92)
      pen.circle(PROPOSAL[0], PROPOSAL[1], mix(5, 10, shown), {tone: "accent", dash: [12, 0.55, 3 * p], alpha: shown})
      pen.dot(PROPOSAL[0], PROPOSAL[1], 2.4, {tone: "accent", alpha: shown})
    },
  },
  vote: {
    period: 6,
    still: 0.72,
    draw(pen, p) {
      const counted = span(p, 0.6, 0.68) * (1 - span(p, 0.84, 0.94))
      pen.line(-38, -18, 38, -18)
      pen.line(-38, -18, 38, -18, {tone: "accent", weight: 1.4, alpha: counted})
      pen.line(-38, 18, 38, 18, {tone: "quiet"})
      const back = span(p, 0.84, 0.96)
      for (const [k, side] of VOTES.entries()) {
        const x = -28 + k * 14
        const y = side * 13 * span(p, 0.06 + k * 0.1, 0.16 + k * 0.1) * (1 - back)
        node(pen, x, y, 4, {tone: "quiet"})
        if (side < 0) pen.dot(x, y, 4, {alpha: counted})
      }
    },
  },
  crown: {
    period: 6,
    still: 0.76,
    draw(pen, p) {
      const shown = 1 - span(p, 0.86, 0.97)
      for (const [k, [x, y]] of CROWN.entries()) {
        const start = 0.04 + k * 0.045
        const placed = span(p, start, start + 0.07)
        if (placed <= 0) continue
        const at = y - 8 * (1 - placed)
        pen.rect(x, at, 5.5, 5.5, {fill: "solid", alpha: placed * shown})
        // Each block lands in the accent and settles into ink.
        pen.rect(x, at, 5.5, 5.5, {fill: "solid", tone: "accent", alpha: placed * (1 - span(p, start + 0.07, start + 0.18)) * shown})
      }
    },
  },
}
