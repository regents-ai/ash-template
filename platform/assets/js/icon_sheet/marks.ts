/** Marks several icons share, made of the pen's own shapes. */
import {TAU, stretch} from "./loop"
import type {Look, Pen, Point} from "./pen"

/** A node: a small ring over the ground, so the lines into it stop at its edge. */
export function node(pen: Pen, x: number, y: number, r: number, look?: Look) {
  pen.dot(x, y, r, {tone: "ground"})
  pen.circle(x, y, r, look)
}

/** The stretch of a path from share `a` to share `b`, drawn as one run. */
export function trail(pen: Pen, points: readonly Point[], a: number, b: number, look?: Look) {
  const run = stretch(points, a, b)
  if (run.length > 1) pen.path(run, look)
}

/** The way from a to b, in turns. */
export const heading = (a: Point, b: Point) => Math.atan2(b[1] - a[1], b[0] - a[0]) / TAU

/** The point `distance` from `from` on the way to `to`. */
export function toward(from: Point, to: Point, distance: number): Point {
  const length = Math.hypot(to[0] - from[0], to[1] - from[1])
  return [from[0] + ((to[0] - from[0]) / length) * distance, from[1] + ((to[1] - from[1]) / length) * distance]
}
