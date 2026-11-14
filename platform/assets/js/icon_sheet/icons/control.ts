/** Control: what is kept safe, held, kept in line and agreed. */
import type {IconSet} from "../icon"
import {TAU, along, bounce, clamp01, mix, polar, pulse, span, swing} from "../loop"
import {node} from "../marks"
import type {Point} from "../pen"

const GLANCE: readonly Point[] = [[-44, -26], [-27, 0], [-44, 26]]

const PERIMETER: readonly Point[] = [[-30, -30], [0, -30], [30, -30], [30, 0], [30, 30], [0, 30], [-30, 30], [-30, 0]]

const WORDS: readonly (readonly [number, number])[][] = [
  [[-38, -20], [-16, 4], [10, 36]],
  [[-38, -4], [2, 24]],
  [[-38, -26], [-20, 0], [6, 30]],
  [[-38, -8], [-2, 16]],
]
const WORD_ROWS = [-21, -7, 7, 21] as const

const TILTS = [
  [0.35, 6],
  [-0.22, -8],
  [0.48, 4],
  [-0.4, -5],
  [0.26, 9],
] as const

export const control: IconSet = {
  shield: {
    period: 4.5,
    still: 0.5,
    draw(pen, p) {
      pen.circle(0, 0, 24, {tone: "quiet", dash: [28, 0.55]})
      pen.circle(0, 0, 10, {fill: "hatch"})
      pen.circle(0, 0, 10)
      // In from above at a steady speed, turned away at the edge, and off below.
      const [x, y] = along(GLANCE, clamp01((p - 0.08) / 0.84))
      pen.rect(x, y, 3.5, 3.5, {fill: "solid", alpha: pulse(p, 0.08, 0.36, 0.64, 0.92)})
      const struck = pulse(p, 0.42, 0.5, 0.52, 0.7)
      pen.circle(0, 0, 24, {arc: [0.43, 0.14], tone: "accent", weight: 1.6, alpha: struck})
    },
  },
  isolate: {
    period: 6,
    still: 0.2,
    draw(pen, p) {
      for (let k = 0; k < 8; k += 2) {
        const [ax, ay] = PERIMETER[k]!
        const [bx, by] = PERIMETER[(k + 2) % 8]!
        pen.line(ax, ay, bx, by, {tone: "quiet", dash: [1.4, 3]})
      }
      const size = 9 + 2.5 * swing(p * 2)
      pen.rect(0, 0, size, size, {fill: "hatch", tone: "quiet"})
      pen.rect(0, 0, size, size)
      for (const [x, y] of PERIMETER) node(pen, x, y, 3.6)
      const stop = Math.min(7, Math.floor(p * 8))
      const from = PERIMETER[stop]!
      const to = PERIMETER[(stop + 1) % 8]!
      const t = span(p * 8 - stop, 0.35, 0.9)
      pen.dot(mix(from[0], to[0], t), mix(from[1], to[1], t), 3.6, {tone: "accent"})
    },
  },
  encrypt: {
    period: 5.5,
    still: 0.45,
    draw(pen, p) {
      const bar = mix(-44, 44, span(p, 0.08, 0.62))
      const back = span(p, 0.78, 0.96)
      for (const [row, words] of WORDS.entries()) {
        const y = WORD_ROWS[row]!
        for (const [x0, x1] of words) {
          const covered = clamp01((bar - x0) / (x1 - x0)) * (1 - back)
          const edge = mix(x0, x1, covered)
          if (covered < 0.999) pen.line(edge, y, x1, y, {tone: "quiet", weight: 1.3})
          // A sliver of hatching would read as a mark of its own, so a block shows as it widens.
          if (covered > 0.001) pen.rect((x0 + edge) / 2, y, (edge - x0) / 2, 3, {fill: "hatch", alpha: clamp01((edge - x0 - 3) / 6)})
        }
      }
      pen.line(bar, -30, bar, 30, {tone: "accent", alpha: pulse(p, 0.04, 0.1, 0.6, 0.68)})
    },
  },
  hold: {
    period: 6,
    still: 0,
    draw(pen, p) {
      pen.rect(-7, 0, 3, 12, {fill: "solid"})
      pen.rect(7, 0, 3, 12, {fill: "solid"})
      // Six dashes on round once a loop, and the outer ring breathing.
      pen.circle(0, 0, 24, {tone: "accent", dash: [24, 0.55, 6 * p]})
      pen.circle(0, 0, 31 + 3 * swing(p), {tone: "quiet"})
    },
  },
  contain: {
    period: 6,
    still: 0.13,
    draw(pen, p) {
      pen.rect(0, 0, 30, 30)
      for (let k = 5; k >= 0; k -= 1) {
        const q = p - k * 0.012
        const x = 25 * bounce(2 * q + 0.1)
        const y = 25 * bounce(3 * q + 0.35)
        if (k) pen.dot(x, y, 2.2, {tone: "quiet", alpha: 0.6 - k * 0.1})
        else pen.dot(x, y, 3.6, {tone: "accent"})
      }
    },
  },
  balance: {
    period: 5,
    still: 0.25,
    draw(pen, p) {
      const tilt = 0.16 * Math.sin(TAU * p)
      const dx = Math.cos(tilt)
      const dy = Math.sin(tilt)
      const end = (side: number): Point => [side * 34 * dx, 7 + side * 34 * dy]
      const [lx, ly] = end(-1)
      const [rx, ry] = end(1)
      pen.line(-20, 20.5, 20, 20.5, {tone: "quiet"})
      pen.tri(0, 16, 9, {fill: "line", turn: -0.25})
      pen.line(lx, ly, rx, ry, {weight: 1.3})
      // Each weight sits on the beam, square to it.
      pen.rect(lx + 5 * dy, ly - 5 * dx, 5, 5, {fill: "solid", turn: tilt / TAU})
      pen.dot(rx + 4.5 * dy, ry - 4.5 * dx, 4.5, {tone: "accent"})
    },
  },
  align: {
    period: 5,
    still: 0.55,
    draw(pen, p) {
      const lined = pulse(p, 0.1, 0.45, 0.65, 0.95)
      for (const [k, [tilt, shift]] of TILTS.entries()) {
        const x = -28 + k * 14
        const angle = tilt * (1 - lined)
        const cy = shift * (1 - lined)
        const sx = 16 * Math.sin(angle)
        const sy = 16 * Math.cos(angle)
        pen.line(x - sx, cy - sy, x + sx, cy + sy, {weight: 1.3})
      }
      pen.line(-38, 20, 38, 20, {tone: "accent", dash: [2.5, 2.5], alpha: lined})
      pen.line(-38, -20, 38, -20, {tone: "quiet", dash: [2.5, 2.5], alpha: lined})
    },
  },
  consensus: {
    period: 6,
    still: 0.68,
    draw(pen, p) {
      const shown = 1 - span(p, 0.82, 0.97)
      for (let k = 0; k < 8; k += 1) {
        const [ax, ay] = polar(0, 0, 10, k / 8 - 0.25)
        const [bx, by] = polar(0, 0, 27, k / 8 - 0.25)
        const [nx, ny] = polar(0, 0, 31, k / 8 - 0.25)
        pen.line(ax, ay, bx, by, {tone: "quiet"})
        pen.line(ax, ay, bx, by, {tone: "accent", alpha: span(p, 0.05 + k * 0.06, 0.12 + k * 0.06) * shown})
        pen.dot(nx, ny, 3)
      }
      pen.circle(0, 0, 7)
      pen.dot(0, 0, 7, {tone: "accent", alpha: span(p, 0.55, 0.65) * shown})
    },
  },
}
