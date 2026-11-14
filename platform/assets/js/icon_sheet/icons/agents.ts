/** Agents: what an agent does with a question, a tool and what it learns. */
import type {IconSet} from "../icon"
import {along, clamp01, curve, mix, pulse, span} from "../loop"
import {node, toward, trail} from "../marks"
import type {Point} from "../pen"

const ASKER: Point = [-26, 22]
const ASKED: Point = [22, -18]
// The line between them, from edge to edge.
const ASK_FROM = toward(ASKER, ASKED, 4.5)
const ASK_TO = toward(ASKED, ASKER, 11)

const TESTS = [1, 1, 0, 1, 1] as const

const LOSS: readonly Point[] = Array.from({length: 33}, (_, i) => {
  const u = i / 32
  const fall = (1 - Math.exp(-3.5 * u)) / (1 - Math.exp(-3.5))
  return [-32 + 68 * u, -26 + 46 * fall + 2.2 * Math.sin(u * 37) * (1 - u)] as const
})

const CITED_LINES = [
  [-2, 40, -18],
  [-2, 30, -6],
  [-2, 36, 6],
  [-2, 22, 18],
] as const
const CITE_LINK = curve([33, -13], [6, -44], [-28, 0], 20)

const FORK_TRUNK: readonly Point[] = [[0, 36], [0, 6]]
const FORK_LEFT = curve([0, 6], [0, -16], [-24, -32], 12)
const FORK_RIGHT = curve([0, 6], [0, -16], [24, -32], 12)

export const agents: IconSet = {
  ask: {
    period: 5,
    still: 0.5,
    draw(pen, p) {
      pen.line(ASK_FROM[0], ASK_FROM[1], ASK_TO[0], ASK_TO[1], {tone: "quiet", dash: [2.5, 3]})
      pen.dot(ASKER[0], ASKER[1], 4.5)
      pen.circle(ASKED[0], ASKED[1], 11)
      const t = span(p, 0.1, 0.5)
      pen.dot(mix(ASKER[0], ASKED[0], t), mix(ASKER[1], ASKED[1], t), 3.2, {
        tone: "accent",
        alpha: pulse(p, 0.05, 0.12, 0.47, 0.53),
      })
      // It arrives, and the question opens out.
      const heard = span(p, 0.5, 0.88)
      if (heard > 0) pen.circle(ASKED[0], ASKED[1], 11 + 11 * heard, {tone: "quiet", alpha: 1 - heard})
    },
  },
  answer: {
    period: 5,
    still: 0.58,
    draw(pen, p) {
      pen.line(ASK_FROM[0], ASK_FROM[1], ASK_TO[0], ASK_TO[1])
      pen.circle(ASKED[0], ASKED[1], 11, {fill: "hatch"})
      pen.circle(ASKED[0], ASKED[1], 11)
      node(pen, ASKER[0], ASKER[1], 5)
      const t = span(p, 0.15, 0.55)
      pen.dot(mix(ASKED[0], ASKER[0], t), mix(ASKED[1], ASKER[1], t), 3.2, {
        tone: "accent",
        alpha: pulse(p, 0.12, 0.18, 0.52, 0.57),
      })
      pen.dot(ASKER[0], ASKER[1], 5, {tone: "accent", alpha: pulse(p, 0.52, 0.6, 0.84, 0.96)})
    },
  },
  tool: {
    period: 5,
    still: 0.48,
    draw(pen, p) {
      pen.line(-44, 0, -13, 0, {tone: "quiet"})
      pen.line(13, 0, 44, 0, {tone: "quiet"})
      const working = pulse(p, 0.3, 0.38, 0.55, 0.62)
      pen.rect(0, 0, 13, 13, {fill: "hatch", alpha: working})
      pen.rect(0, 0, 13, 13)
      pen.dot(mix(-40, -6, span(p, 0.05, 0.35)), 0, 3.2, {alpha: pulse(p, 0, 0.05, 0.3, 0.36)})
      pen.dot(mix(6, 40, span(p, 0.6, 0.9)), 0, 3.2, {tone: "accent", alpha: pulse(p, 0.58, 0.64, 0.88, 0.95)})
    },
  },
  skill: {
    period: 5.5,
    still: 0.5,
    draw(pen, p) {
      pen.circle(-22, 0, 14)
      pen.line(-8, -7, 8, -7)
      pen.line(-8, 7, 8, 7)
      const docked = pulse(p, 0.1, 0.4, 0.65, 0.92)
      const x = mix(32, 6, docked)
      pen.rect(x, 0, 5.5, 5.5, {tone: "accent"})
      pen.rect(x, 0, 5.5, 5.5, {fill: "solid", tone: "accent", alpha: clamp01((docked - 0.9) / 0.1)})
      // It clicks in, and the agent has it.
      const taken = span(p, 0.4, 0.62)
      if (taken > 0) pen.circle(-22, 0, 14 + 7 * taken, {tone: "quiet", alpha: 1 - taken})
    },
  },
  eval: {
    period: 6,
    still: 0.76,
    draw(pen, p) {
      const shown = 1 - span(p, 0.86, 0.98)
      for (const [k, passed] of TESTS.entries()) {
        const x = -28 + k * 14
        const done = span(p, 0.12 + k * 0.12, 0.15 + k * 0.12) * shown
        pen.circle(x, -6, 4.5, {tone: "quiet"})
        if (passed) pen.dot(x, -6, 4.5, {alpha: done})
        else {
          pen.line(x - 3, -9, x + 3, -3, {alpha: done})
          pen.line(x - 3, -3, x + 3, -9, {alpha: done})
        }
      }
      // A ring steps along the tests, then the score fills to four in five.
      const at = Math.min(4, Math.max(0, (p - 0.08) / 0.12))
      const k = Math.floor(at)
      const cx = -28 + 14 * Math.min(4, k + span(at - k, 0.6, 1))
      pen.circle(cx, -6, 8.5, {tone: "accent", alpha: pulse(p, 0.04, 0.1, 0.66, 0.72)})
      pen.rect(0, 16, 30, 2.6, {tone: "quiet"})
      const score = 48 * span(p, 0.68, 0.78)
      if (score > 0.01) pen.rect(-30 + score / 2, 16, score / 2, 2.6, {fill: "solid", alpha: shown})
    },
  },
  train: {
    period: 6,
    still: 0.72,
    draw(pen, p) {
      const shown = 1 - span(p, 0.82, 0.97)
      pen.path(
        [
          [-38, -32],
          [-38, 30],
          [40, 30],
        ],
        {tone: "quiet"},
      )
      pen.line(-34, 20, 38, 20, {tone: "quiet", dash: [2, 3]})
      const drawn = span(p, 0.05, 0.7)
      trail(pen, LOSS, 0, drawn, {alpha: shown, weight: 1.2})
      const [x, y] = along(LOSS, drawn)
      pen.dot(x, y, 3.2, {tone: "accent", alpha: shown * span(p, 0, 0.05)})
    },
  },
  cite: {
    period: 5.5,
    still: 0.62,
    draw(pen, p) {
      for (const [x0, x1, y] of CITED_LINES) pen.line(x0, y, x1, y, {tone: "quiet", weight: 1.3})
      pen.rect(-28, 12, 11, 11, {fill: "hatch"})
      pen.rect(-28, 12, 11, 11)
      pen.rect(-28, 12, 11, 11, {tone: "accent", alpha: pulse(p, 0.5, 0.58, 0.76, 0.86)})
      trail(pen, CITE_LINK, span(p, 0.74, 0.94), span(p, 0.18, 0.52), {tone: "quiet", dash: [2.5, 2.5]})
      pen.dot(33, -10, 2.6, {tone: "accent", alpha: pulse(p, 0.04, 0.14, 0.86, 0.97)})
    },
  },
  fork: {
    period: 5,
    still: 0.64,
    draw(pen, p) {
      pen.path(FORK_TRUNK)
      pen.path(FORK_LEFT)
      pen.path(FORK_RIGHT)
      pen.dot(0, 36, 4)
      node(pen, 0, 6, 3.4)
      node(pen, -24, -32, 4)
      node(pen, 24, -32, 4)
      const up = span(p, 0.08, 0.42)
      const [tx, ty] = along(FORK_TRUNK, up)
      pen.dot(tx, ty, 3, {alpha: pulse(p, 0.04, 0.1, 0.42, 0.44)})
      const out = span(p, 0.44, 0.78)
      const shown = pulse(p, 0.42, 0.44, 0.8, 0.9)
      const [lx, ly] = along(FORK_LEFT, out)
      const [rx, ry] = along(FORK_RIGHT, out)
      pen.dot(lx, ly, 3, {alpha: shown})
      pen.dot(rx, ry, 3, {tone: "accent", alpha: shown})
    },
  },
}
