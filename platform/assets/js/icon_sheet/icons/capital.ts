/** Capital: what is staked, claimed, shared out, raised and written over a holding. */
import type {IconSet} from "../icon"
import {TAU, along, clamp01, curve, fract, mix, pulse, span, stretch, swing} from "../loop"
import {heading, node, trail} from "../marks"
import type {Point} from "../pen"

const STAKERS = [-30, -10, 10, 30] as const

const LAUNCH_PATH = curve([-28, 30], [-18, -26], [34, -36], 24)

// A price that repeats once a loop as it slides past: three whole waves of it.
const price = (u: number) =>
  12 * Math.sin(TAU * u) + 6 * Math.sin(TAU * 2 * u + 1) + 3 * Math.sin(TAU * 3 * u + 2)
const STRIKE = -6

const BRACKET_CORNERS = [
  [-1, -1],
  [1, -1],
  [1, 1],
  [-1, 1],
] as const

export const capital: IconSet = {
  stake: {
    period: 6,
    still: 0.7,
    draw(pen, p) {
      const shown = 1 - span(p, 0.86, 0.98)
      pen.line(-26, 30, 26, 30)
      for (let k = 0; k < 4; k += 1) {
        const start = 0.06 + k * 0.12
        const placed = span(p, start, start + 0.12)
        const y = mix(-38, 25 - k * 8, placed)
        pen.rect(0, y, 16, 2.6, {fill: "solid", alpha: clamp01((p - start) / 0.03) * shown})
      }
      // Held: a bracket closes round the stack.
      const held = pulse(p, 0.58, 0.66, 0.84, 0.92)
      for (const [sx, sy] of BRACKET_CORNERS) {
        const x = sx * 23
        const y = 12 + sy * 15
        pen.line(x, y, x - sx * 6, y, {tone: "accent", alpha: held})
        pen.line(x, y, x, y - sy * 6, {tone: "accent", alpha: held})
      }
    },
  },
  claim: {
    period: 5.5,
    still: 0.45,
    draw(pen, p) {
      pen.rect(24, 0, 11, 11, {tone: "quiet", dash: [2, 2.5]})
      node(pen, -26, 0, 8)
      // A line reaches out to the token, brings it home, and lets go.
      const reach = mix(-18, 20, span(p, 0.08, 0.32)) - 38 * span(p, 0.38, 0.68)
      if (reach > -17.9) pen.line(-18, 0, reach, 0)
      const moving = p < 0.75
      const x = moving ? mix(24, -26, span(p, 0.38, 0.7)) : 24
      const alpha = moving ? 1 - span(p, 0.66, 0.72) : span(p, 0.8, 0.98)
      pen.dot(x, 0, 4, {tone: "accent", alpha})
      pen.dot(-26, 0, 8, {tone: "accent", alpha: pulse(p, 0.68, 0.74, 0.85, 0.95)})
    },
  },
  share: {
    period: 5,
    still: 0.56,
    draw(pen, p) {
      pen.circle(0, -26, 10, {fill: "hatch"})
      pen.circle(0, -26, 10)
      for (const [k, x] of STAKERS.entries()) {
        const route: Point[] = [[0, -16], [x, 23]]
        const lag = k * 0.04
        pen.path(route, {tone: "quiet"})
        node(pen, x, 28, 5)
        const [dx, dy] = along(route, span(p, 0.12 + lag, 0.52 + lag))
        pen.dot(dx, dy, 2.8, {tone: "accent", alpha: pulse(p, 0.1 + lag, 0.15 + lag, 0.52 + lag, 0.57 + lag)})
        pen.dot(x, 28, 5, {alpha: pulse(p, 0.54 + lag, 0.6 + lag, 0.85, 0.97)})
      }
    },
  },
  treasury: {
    period: 6,
    still: 0.5,
    draw(pen, p) {
      // The reserve rises and falls inside the vault; drops come in at the top.
      const level = 28 - 50 * mix(0.3, 0.72, swing(p))
      pen.rect(0, (28 + level) / 2, 21, (28 - level) / 2, {fill: "hatch", tone: "quiet"})
      pen.line(-21, level, 21, level)
      pen.line(-24, -26, -6, -26)
      pen.line(6, -26, 24, -26)
      pen.line(-24, -26, -24, 31)
      pen.line(24, -26, 24, 31)
      pen.line(-24, 31, 24, 31)
      pen.line(-24, -2, 24, -2, {tone: "quiet", dash: [2, 3]})
      pen.tri(31, level, 4.5, {tone: "accent", turn: 0.5})
      for (let k = 0; k < 2; k += 1) {
        const f = fract(2 * p + k * 0.5)
        pen.dot(0, mix(-40, level - 5, span(f, 0, 0.8)), 2.6, {alpha: clamp01(f / 0.1) * (1 - span(f, 0.7, 0.85))})
      }
    },
  },
  raise: {
    period: 5.5,
    still: 0.72,
    draw(pen, p) {
      const shown = 1 - span(p, 0.86, 0.98)
      const filled = 0.8 * span(p, 0.1, 0.62)
      pen.rect(0, -6, 34, 5)
      if (filled > 0.002) pen.rect(-34 + 34 * filled, -6, 34 * filled, 5, {fill: "solid", alpha: shown})
      const goal = -34 + 68 * 0.8
      pen.line(goal, -16, goal, 4, {tone: "accent", weight: 1.4})
      pen.circle(goal, -16, 3, {tone: "accent", fill: "solid", alpha: pulse(p, 0.6, 0.66, 0.84, 0.94)})
      // Each gift rises from below into the bar.
      for (let k = 0; k < 4; k += 1) {
        const start = 0.1 + k * 0.12
        const x = -30 + 68 * 0.8 * (k + 0.6) * 0.25
        const y = mix(36, -1, span(p, start, start + 0.14))
        pen.dot(x, y, 2.6, {alpha: pulse(p, start - 0.02, start + 0.02, start + 0.12, start + 0.14)})
      }
    },
  },
  launch: {
    period: 5,
    still: 0.56,
    draw(pen, p) {
      pen.line(-42, 34, -14, 34, {tone: "quiet"})
      pen.path(LAUNCH_PATH, {tone: "quiet", dash: [1.4, 3]})
      const t = span(p, 0.1, 0.75)
      const shown = pulse(p, 0.08, 0.14, 0.74, 0.8)
      trail(pen, LAUNCH_PATH, t - 0.35, t, {alpha: shown, weight: 1.2})
      const run = stretch(LAUNCH_PATH, Math.max(0, t - 0.02), Math.max(t, 0.02))
      const [x, y] = along(LAUNCH_PATH, t)
      pen.tri(x, y, 5, {tone: "accent", turn: heading(run[0]!, run.at(-1)!), alpha: shown})
      const left = span(p, 0.1, 0.35)
      if (left > 0) pen.circle(-28, 30, 4 + 12 * left, {tone: "quiet", alpha: 1 - left})
    },
  },
  cover: {
    period: 6,
    still: 0.5,
    draw(pen, p) {
      pen.rect(0, 18, 20, 12, {fill: "hatch"})
      pen.rect(0, 18, 20, 12)
      pen.line(-40, -18, 40, -18, {tone: "quiet", dash: [2.5, 3]})
      // The call comes down over the holding, rests on it, and lifts away.
      const y = mix(-38, 1, pulse(p, 0.1, 0.42, 0.64, 0.92))
      pen.path(
        [
          [-25, y + 11],
          [-25, y],
          [25, y],
          [25, y + 11],
        ],
        {tone: "accent", weight: 1.5},
      )
    },
  },
  strike: {
    period: 6,
    still: 0.4,
    draw(pen, p) {
      pen.line(-44, STRIKE, 44, STRIKE, {tone: "accent", dash: [3, 2.5]})
      const path: Point[] = []
      for (let x = -40; x <= 28; x += 2) path.push([x, price(x / 40 - p)])
      pen.path(path)
      const y = price(28 / 40 - p)
      const over = clamp01((STRIKE - y) / 4)
      pen.dot(28, y, 3.4)
      pen.circle(28, y, 7, {tone: "accent", alpha: over})
    },
  },
}
