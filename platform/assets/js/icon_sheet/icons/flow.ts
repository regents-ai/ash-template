/** Flow: how work waits, is ordered, finds its way and comes together. */
import type {IconSet} from "../icon"
import {along, clamp01, fract, mix, polar, pulse, span, stretch} from "../loop"
import {node} from "../marks"
import type {Point} from "../pen"

const PRIORITY_BARS = [40, 32, 24] as const
const PRIORITY_SLOTS = [-18, -6, 6, 18] as const

const ROUTE_GRID = [-28, 0, 28] as const
const ROUTE: readonly Point[] = [[-28, 28], [-28, 0], [0, 0], [0, -28], [28, -28]]

const DETOUR: readonly Point[] = [[-32, 12], [-20, -18], [20, -18], [32, 12]]

const CYCLE_STOPS = [0, 0.25, 0.5, 0.75] as const

export const flow: IconSet = {
  queue: {
    period: 4,
    still: 0.3,
    draw(pen, p) {
      const step = span(p, 0.25, 0.75)
      pen.line(24, -16, 24, -7)
      pen.line(24, 7, 24, 16)
      pen.rect(36, 0, 7, 7, {tone: "quiet", fill: "line"})
      for (let k = -1; k <= 3; k += 1) {
        const x = -30 + 15 * (k + step)
        // In from nothing at the back, gone by the time it reaches the box at the front.
        const alpha = clamp01((x + 45) / 15) * (1 - clamp01((x - 20) / 10))
        pen.rect(x, 0, 4, 4, {fill: "solid", alpha})
        pen.rect(x, 0, 4, 4, {fill: "solid", tone: "accent", alpha: alpha * clamp01(x / 15)})
      }
    },
  },
  prioritize: {
    period: 5,
    still: 0.5,
    draw(pen, p) {
      const lift = pulse(p, 0.1, 0.45, 0.6, 0.95)
      for (const [k, length] of PRIORITY_BARS.entries()) {
        pen.rect(-24 + length / 2, mix(PRIORITY_SLOTS[k]!, PRIORITY_SLOTS[k + 1]!, lift), length / 2, 2.4, {
          fill: "solid",
          tone: k ? "quiet" : "ink",
        })
      }
      // The short one goes first: out to the side, up past the others, and in at the top.
      const aside = 14 * Math.sin(Math.PI * lift)
      pen.rect(-24 + 7 - aside, mix(PRIORITY_SLOTS[3], PRIORITY_SLOTS[0], lift), 7, 2.4, {fill: "solid", tone: "accent"})
    },
  },
  route: {
    period: 5.5,
    still: 0.62,
    draw(pen, p) {
      for (const x of ROUTE_GRID) for (const y of ROUTE_GRID) pen.dot(x, y, 2.2, {tone: "quiet"})
      const drawn = span(p, 0.05, 0.6)
      const shown = 1 - span(p, 0.78, 0.98)
      const run = stretch(ROUTE, 0, drawn)
      if (run.length > 1) pen.path(run, {alpha: shown, weight: 1.2})
      node(pen, -28, 28, 5)
      node(pen, 28, -28, 5)
      const [x, y] = along(ROUTE, drawn)
      pen.dot(x, y, 3.2, {tone: "accent", alpha: shown * span(p, 0, 0.05)})
    },
  },
  reroute: {
    period: 5,
    still: 0.5,
    draw(pen, p) {
      pen.line(-27, 12, 27, 12, {tone: "quiet", dash: [2.5, 3]})
      pen.line(-5, 7, 5, 17)
      pen.line(-5, 17, 5, 7)
      pen.path(DETOUR)
      node(pen, -32, 12, 5)
      node(pen, 32, 12, 5)
      const [x, y] = along(DETOUR, span(p, 0.1, 0.85))
      pen.rect(x, y, 3.2, 3.2, {fill: "solid", tone: "accent", alpha: pulse(p, 0.05, 0.12, 0.82, 0.92)})
    },
  },
  filter: {
    period: 5,
    still: 0.42,
    draw(pen, p) {
      pen.line(4, -30, 4, 30, {tone: "quiet", dash: [3, 2.5]})
      for (const [lane, y] of [-16, 0, 16].entries()) {
        for (let k = 0; k < 4; k += 1) {
          const free = mix(-44, 44, fract(p + k / 4 + lane * 0.13))
          const arriving = clamp01((free + 44) / 10)
          if ((k + lane) % 3 === 0) {
            // Kept back at the gate, where it fades.
            pen.dot(Math.min(free, -2), y, 3, {tone: "accent", alpha: arriving * (1 - clamp01((free + 2) / 14))})
          } else {
            pen.dot(free, y, 3, {alpha: arriving * clamp01((44 - free) / 10)})
          }
        }
      }
    },
  },
  escalate: {
    period: 5,
    still: 0.7,
    draw(pen, p) {
      const shown = 1 - span(p, 0.8, 0.96)
      for (let k = 0; k < 5; k += 1) {
        const x = -28 + k * 14
        const h = 12 + k * 10
        const lit = span(p, 0.08 + k * 0.1, 0.16 + k * 0.1) * shown
        pen.rect(x, 28 - h / 2, 4.5, h / 2, {tone: "quiet"})
        pen.rect(x, 28 - h / 2, 4.5, h / 2, {fill: "solid", tone: k === 4 ? "accent" : "ink", alpha: lit})
      }
    },
  },
  cycle: {
    period: 6,
    still: 0.08,
    draw(pen, p) {
      pen.circle(0, 0, 28, {tone: "quiet"})
      for (const stop of CYCLE_STOPS) {
        const between = polar(0, 0, 28, stop + 0.125 - 0.25)
        pen.head(between[0], between[1], stop + 0.125, 5, {tone: "quiet"})
      }
      const turn = p - 0.25
      for (const stop of CYCLE_STOPS) {
        const [x, y] = polar(0, 0, 28, stop - 0.25)
        const gap = Math.abs(fract(turn - (stop - 0.25) + 0.5) - 0.5)
        node(pen, x, y, 5)
        pen.dot(x, y, 5, {tone: "ink", alpha: clamp01(1 - gap / 0.07)})
      }
      const [x, y] = polar(0, 0, 28, turn)
      pen.dot(x, y, 3.4, {tone: "accent"})
    },
  },
  fuse: {
    period: 5,
    still: 0.55,
    draw(pen, p) {
      const join = pulse(p, 0.1, 0.45, 0.65, 0.95)
      for (let k = 0; k < 3; k += 1) {
        const start = polar(0, 0, 30, k / 3 - 0.25)
        pen.line(start[0], start[1], 0, 0, {tone: "quiet", dash: [2, 3]})
        const [x, y] = polar(0, 0, mix(30, 0, join), k / 3 - 0.25)
        pen.dot(x, y, 4, {alpha: 1 - clamp01((join - 0.8) / 0.2)})
      }
      const core = clamp01((join - 0.75) / 0.25)
      if (core > 0) pen.dot(0, 0, 7 * core, {tone: "accent"})
      pen.circle(0, 0, 14, {alpha: clamp01((join - 0.85) / 0.15)})
    },
  },
}

