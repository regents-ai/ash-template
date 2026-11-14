import {readFileSync} from "node:fs"
import {expect, it} from "vitest"
import {ICON_GROUPS, ICONS} from "../js/icon_sheet/icons"
import {createSheet, SHAPE_FLOATS} from "../js/icon_sheet/pen"

const LIVE_VIEW = new URL("../../lib/ash_template_web/live/icons_lab_live.ex", import.meta.url)

// The page's sections as the LiveView lists them: each id with its icons' names, in order.
const pageGroups = (): Record<string, string[]> => {
  const source = readFileSync(LIVE_VIEW, "utf8")
  const groups = [...source.matchAll(/\{"(\w+)", "\w+", ~w\(([^)]*)\)\}/g)]
  return Object.fromEntries(groups.map(([, id, names]) => [id!, names!.trim().split(/\s+/)]))
}

// Every shape of one icon drawn at phase p in a box 100 pixels wide at the origin.
const shapes = (id: string, p: number): Float32Array[] => {
  const sheet = createSheet()
  sheet.place({x: 0, y: 0, size: 100}, 1)
  ICONS[id]!.draw(sheet.pen, p)
  const data = sheet.data()
  return Array.from({length: sheet.count()}, (_, i) => data.slice(i * SHAPE_FLOATS, (i + 1) * SHAPE_FLOATS))
}

// The points a shape reaches, outward by half its stroke where it is drawn as a line.
const reach = (s: Float32Array): {points: [number, number][]; pad: number} => {
  const [kind, , , fill] = s
  const pad = fill === 0 ? s[8]! / 2 : 0
  const [x, y] = [s[4]!, s[5]!]
  const turn = (t: number): [number, number] => [Math.cos(t * Math.PI * 2), Math.sin(t * Math.PI * 2)]
  if (kind === 0) return {points: [[x, y], [s[6]!, s[7]!]], pad: s[8]! / 2}
  if (kind === 1) {
    const [r, start, sweep] = [s[6]!, s[9]!, s[10]!]
    // An arc reaches only the points along it; a clip that keeps inside a circle bounds it too.
    const points = Array.from({length: 65}, (_, i): [number, number] => {
      const [c, n] = turn(start + (sweep * i) / 64)
      return [x + c * r, y + n * r]
    })
    if (s[19] === 1) {
      const [cx, cy, cr] = [s[16]!, s[17]!, s[18]!]
      return {points: points.filter(([px, py]) => Math.hypot(px - cx, py - cy) <= cr + 0.01), pad}
    }
    return {points, pad}
  }
  if (kind === 2) {
    const [hw, hh] = [s[6]!, s[7]!]
    const [c, n] = turn(s[9]!)
    const corners: [number, number][] = [[-hw, -hh], [hw, -hh], [hw, hh], [-hw, hh]]
    return {points: corners.map(([u, v]) => [x + u * c - v * n, y + u * n + v * c]), pad}
  }
  return {points: [0, 1, 2].map((k): [number, number] => {
    const [c, n] = turn(s[9]! + k / 3)
    return [x + c * s[6]!, y + n * s[6]!]
  }), pad}
}

// Fields that are a turn or a dash's phase say the same picture a whole turn on.
const WRAPS = new Set([9, 14])
const sameField = (field: number, a: number, b: number) => {
  const gap = Math.abs(a - b)
  return WRAPS.has(field) ? Math.min(gap % 1, 1 - (gap % 1)) < 1e-3 : gap < 1e-3
}

const PHASES = Array.from({length: 97}, (_, i) => i / 96)

it("names fifty-six icons, eight to each of the page's sections, in its order", () => {
  const groups = pageGroups()
  expect(Object.keys(groups)).toEqual(Object.keys(ICON_GROUPS))
  for (const [id, names] of Object.entries(groups)) {
    expect(names).toHaveLength(8)
    expect(Object.keys(ICON_GROUPS[id as keyof typeof ICON_GROUPS])).toEqual(names)
  }
  expect(Object.keys(ICONS)).toHaveLength(56)
})

// Invariant: a loop's last frame runs straight into its first.
it.each(Object.keys(ICONS))("%s loops without a seam", id => {
  const first = shapes(id, 0)
  const last = shapes(id, 1 - 1e-9)
  expect(last.length).toBe(first.length)
  first.forEach((shape, i) => {
    shape.forEach((value, field) => {
      if (!sameField(field, value, last[i]![field]!)) {
        throw new Error(`${id}: shape ${i}, field ${field}: ${value} at the start, ${last[i]![field]} at the end`)
      }
    })
  })
})

// Invariant: nothing an icon draws reaches past its own box, at any point in its loop.
it.each(Object.keys(ICONS))("%s stays inside its box", id => {
  for (const p of PHASES) {
    shapes(id, p).forEach((shape, i) => {
      const {points, pad} = reach(shape)
      for (const [x, y] of points) {
        const out = Math.max(pad - x, pad - y, x + pad - 100, y + pad - 100)
        if (out > 0.01) throw new Error(`${id} at ${p.toFixed(3)}: shape ${i} reaches ${out.toFixed(2)} past its box`)
      }
    })
  }
})

it.each(Object.keys(ICONS))("%s holds a still frame and a calm loop", id => {
  const icon = ICONS[id]!
  expect(icon.period).toBeGreaterThanOrEqual(3)
  expect(icon.period).toBeLessThanOrEqual(6)
  expect(icon.still).toBeGreaterThanOrEqual(0)
  expect(icon.still).toBeLessThan(1)
  expect(shapes(id, icon.still).length).toBeGreaterThan(0)
})
