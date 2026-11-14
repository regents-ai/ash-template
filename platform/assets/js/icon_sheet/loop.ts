/**
 * The timeline every icon on the icon sheet is written in. Each icon is drawn at a
 * phase from 0 to 1 of its own loop, and draws the same picture at both ends of it, so
 * the loop never shows its seam. Every move eases on the design system's ease-in-out.
 */
import {EASE_IN_OUT} from "../hooks/motion/shared"

import type {Point} from "./pen"

export const TAU = Math.PI * 2

export const clamp01 = (x: number) => (x < 0 ? 0 : x > 1 ? 1 : x)
export const fract = (x: number) => x - Math.floor(x)
export const mix = (a: number, b: number, t: number) => a + (b - a) * t
export const ease = (t: number) => EASE_IN_OUT(clamp01(t))

/** Eased from 0 at phase `a` to 1 at phase `b`. */
export const span = (p: number, a: number, b: number) => ease((p - a) / (b - a))

/** Up from `a` to `b`, held, and back down from `c` to `d`. */
export const pulse = (p: number, a: number, b: number, c: number, d: number) => span(p, a, b) * (1 - span(p, c, d))

/** From 0 to 1 and back once a loop, as smoothly as a cosine. */
export const swing = (p: number) => 0.5 - 0.5 * Math.cos(TAU * p)

/** Out to 1 and back once a loop, resting at each end. */
export const there = (p: number) => ease(1 - Math.abs(1 - 2 * fract(p)))

/** Straight to and fro between -1 and 1, `u` going once through each turn. */
export const bounce = (u: number) => 4 * Math.abs(fract(u + 0.25) - 0.5) - 1

/** A ring of something fading in as it starts out and away as it ends (`f` from 0 to 1). */
export const ripple = (f: number) => (1 - f) * clamp01(f / 0.12)

/** Where an angle in turns points, `r` from a centre. */
export const polar = (x: number, y: number, r: number, turn: number): Point => [
  x + r * Math.cos(turn * TAU),
  y + r * Math.sin(turn * TAU),
]

/** Points along a quadratic curve from `a` to `b` bent toward `c`. */
export function curve(a: Point, c: Point, b: Point, steps = 16): Point[] {
  const points: Point[] = []
  for (let i = 0; i <= steps; i += 1) {
    const t = i / steps
    const u = 1 - t
    points.push([u * u * a[0] + 2 * u * t * c[0] + t * t * b[0], u * u * a[1] + 2 * u * t * c[1] + t * t * b[1]])
  }
  return points
}

const lengths = (points: readonly Point[]) => {
  const out = [0]
  for (let i = 1; i < points.length; i += 1) {
    out.push(out[i - 1]! + Math.hypot(points[i]![0] - points[i - 1]![0], points[i]![1] - points[i - 1]![1]))
  }
  return out
}

const at = (points: readonly Point[], sums: readonly number[], distance: number): Point => {
  const last = points.length - 1
  for (let i = 1; i <= last; i += 1) {
    if (distance <= sums[i]! || i === last) {
      const piece = sums[i]! - sums[i - 1]!
      const t = piece > 0 ? clamp01((distance - sums[i - 1]!) / piece) : 0
      return [mix(points[i - 1]![0], points[i]![0], t), mix(points[i - 1]![1], points[i]![1], t)]
    }
  }
  return points[0]!
}

/** The point a share `t` of the way along a path. */
export function along(points: readonly Point[], t: number): Point {
  const sums = lengths(points)
  return at(points, sums, clamp01(t) * sums.at(-1)!)
}

/** The stretch of a path from share `a` to share `b` of the way along it. */
export function stretch(points: readonly Point[], a: number, b: number): Point[] {
  const sums = lengths(points)
  const total = sums.at(-1)!
  const from = clamp01(a) * total
  const to = clamp01(b) * total
  if (to <= from) return []
  const out: Point[] = [at(points, sums, from)]
  for (let i = 1; i < points.length - 1; i += 1) {
    if (sums[i]! > from && sums[i]! < to) out.push(points[i]!)
  }
  out.push(at(points, sums, to))
  return out
}

/** The stretch of a closed path from share `a` to share `b`, either of which may run past its start. */
export function stretchRound(points: readonly Point[], a: number, b: number): Point[][] {
  const from = fract(a)
  const to = from + (b - a)
  if (to <= 1) return [stretch(points, from, to)]
  return [stretch(points, from, 1), stretch(points, 0, to - 1)]
}
