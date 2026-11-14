/** Connect: how things meet, join and pass between each other. */
import type {IconSet} from "../icon"
import {along, fract, mix, polar, pulse, span, stretchRound, swing, there} from "../loop"
import {node} from "../marks"
import type {Point} from "../pen"

const TREE_ROOT: Point = [0, -32]
const TREE_KIDS: readonly Point[] = [[-22, -2], [22, -2]]
const TREE_LEAVES: readonly Point[] = [[-33, 30], [-11, 30], [11, 30], [33, 30]]

const HEX: readonly Point[] = Array.from({length: 6}, (_, k) => polar(0, 0, 32, k / 6))
// Three triangles out from the centre, so the route closes where it starts.
const MESH_ROUTE: readonly Point[] = [[0, 0], HEX[0]!, HEX[1]!, [0, 0], HEX[2]!, HEX[3]!, [0, 0], HEX[4]!, HEX[5]!, [0, 0]]

const RELAY_STOPS = [-32, 0, 32]
const RELAY_HOPS = [[0, 1], [1, 2], [2, 1], [1, 0]] as const

export const connect: IconSet = {
  merge: {
    period: 5,
    still: 0.5,
    draw(pen, p) {
      const join = pulse(p, 0.08, 0.42, 0.6, 0.94)
      const a = mix(-24, -9, join)
      const b = mix(24, 9, join)
      pen.circle(a, 0, 18)
      pen.circle(b, 0, 18)
      pen.circle(a, 0, 18, {fill: "hatch", tone: "accent", clip: {x: b, y: 0, r: 18, keep: "in"}})
    },
  },
  converge: {
    period: 4.5,
    still: 0.5,
    draw(pen, p) {
      const near = pulse(p, 0.1, 0.45, 0.6, 0.95)
      const d = mix(27, 9, near)
      for (const [sx, sy] of [[-1, -1], [1, -1], [1, 1], [-1, 1]] as const) {
        pen.line(sx * 34, sy * 34, sx * 42, sy * 34, {tone: "quiet"})
        pen.line(sx * 34, sy * 34, sx * 34, sy * 42, {tone: "quiet"})
        pen.dot(sx * d, sy * d, 4)
      }
      pen.circle(0, 0, mix(2, 5.5, near), {tone: "accent", alpha: near})
    },
  },
  hierarchy: {
    period: 6,
    still: 0.36,
    draw(pen, p) {
      for (const [k, kid] of TREE_KIDS.entries()) {
        pen.line(TREE_ROOT[0], TREE_ROOT[1], kid[0], kid[1])
        for (const leaf of TREE_LEAVES.slice(k * 2, k * 2 + 2)) pen.line(kid[0], kid[1], leaf[0], leaf[1])
      }
      pen.dot(TREE_ROOT[0], TREE_ROOT[1], 4.5)
      for (const [x, y] of [...TREE_KIDS, ...TREE_LEAVES]) node(pen, x, y, 4)

      // Down to each leaf in turn.
      const leg = Math.min(3, Math.floor(p * 4))
      const f = p * 4 - leg
      const leaf = TREE_LEAVES[leg]!
      const [x, y] = along([TREE_ROOT, TREE_KIDS[leg >> 1]!, leaf], span(f, 0.1, 0.7))
      pen.dot(x, y, 3, {tone: "accent", alpha: pulse(f, 0, 0.1, 0.86, 1)})
      pen.dot(leaf[0], leaf[1], 4, {tone: "accent", alpha: pulse(f, 0.66, 0.76, 0.86, 1)})
    },
  },
  spread: {
    period: 4,
    still: 0.5,
    draw(pen, p) {
      const out = swing(p)
      const inner = mix(9, 13, out)
      const outer = mix(25, 37, out)
      for (let k = 0; k < 8; k += 1) {
        const look = {tone: k % 2 ? "quiet" : "ink"} as const
        const [ax, ay] = polar(0, 0, inner, k / 8)
        const [bx, by] = polar(0, 0, outer, k / 8)
        pen.line(ax, ay, bx, by, look)
        pen.head(bx, by, k / 8, 5, look)
      }
      pen.dot(0, 0, 3.5, {tone: "accent"})
    },
  },
  relay: {
    period: 6,
    still: 0.18,
    draw(pen, p) {
      pen.line(-44, 8, 44, 8, {tone: "quiet", dash: [3, 3]})
      for (const x of RELAY_STOPS) node(pen, x, 8, 5)
      const hop = Math.min(3, Math.floor(p * 4))
      const f = p * 4 - hop
      const [from, to] = RELAY_HOPS[hop]!
      const t = span(f, 0.15, 0.72)
      const x = mix(RELAY_STOPS[from]!, RELAY_STOPS[to]!, t)
      pen.rect(x, 8 - 20 * Math.sin(Math.PI * t), 3.2, 3.2, {fill: "solid", tone: "accent"})
      // The stop it lands on answers.
      const landed = span(f, 0.72, 1)
      if (landed > 0) pen.circle(RELAY_STOPS[to]!, 8, 5 + 10 * landed, {tone: "quiet", alpha: 1 - landed})
    },
  },
  handshake: {
    period: 5,
    still: 0.5,
    draw(pen, p) {
      const t = there(p)
      pen.circle(-26, 0, 12, {fill: "hatch"})
      pen.circle(-26, 0, 12)
      pen.circle(26, 0, 12)
      pen.line(-13, 0, 13, 0, {tone: "quiet", dash: [2, 3]})
      pen.circle(-26, 0, 17, {tone: "quiet", alpha: 1 - span(t, 0, 0.14)})
      pen.circle(26, 0, 17, {tone: "quiet", alpha: span(t, 0.86, 1)})
      pen.rect(mix(-10, 10, t), 0, 3.6, 3.6, {fill: "solid", tone: "accent", turn: 0.125})
    },
  },
  mesh: {
    period: 6,
    still: 0.36,
    draw(pen, p) {
      for (let k = 0; k < 6; k += 1) {
        const a = HEX[k]!
        const b = HEX[(k + 1) % 6]!
        pen.line(a[0], a[1], b[0], b[1], {tone: "quiet"})
        pen.line(0, 0, a[0], a[1], {tone: "quiet"})
      }
      for (const run of stretchRound(MESH_ROUTE, p - 0.1, p)) {
        if (run.length > 1) pen.path(run, {tone: "accent", weight: 1.4})
      }
      for (const [x, y] of [...HEX, [0, 0] as const]) pen.dot(x, y, 3)
      const [x, y] = along(MESH_ROUTE, fract(p))
      pen.dot(x, y, 3, {tone: "accent"})
    },
  },
  bridge: {
    period: 5,
    still: 0.5,
    draw(pen, p) {
      pen.line(-44, 13, -24, 13)
      pen.line(24, 13, 44, 13)
      pen.line(-24, 21, 24, 21, {tone: "quiet", dash: [3, 3]})
      const gone = span(p, 0.7, 0.95)
      const sweep = 0.5 * (span(p, 0.05, 0.35) - gone)
      if (sweep > 0.002) pen.circle(0, 13, 34, {arc: [0.5 + 0.5 * gone, sweep]})
      const [x, y] = polar(0, 13, 34, 0.5 + 0.5 * span(p, 0.33, 0.7))
      pen.rect(x, y, 3.2, 3.2, {fill: "solid", tone: "accent", alpha: pulse(p, 0.3, 0.36, 0.68, 0.74)})
    },
  },
}
