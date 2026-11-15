// The splats page's scenes without a GPU: each grows the same from its seed, in the
// standard layout of Gaussian splatting; a splat's quaternion and scales give back the
// shape it was placed with, and its spherical harmonics brighten it toward the view a
// gleam was baked for; moving parts move as rigid turns; the sort hands back every
// splat once, farthest first, from above and below too; each scene fills a wide box and
// a phone's square without being cut off; the pixel grid covers its canvas in
// whole-pixel squares; and the .ply file reads back as written.
import {describe, expect, it} from "vitest"
import {
  after, createBuilder, PART_FLOAT, SH_C0, SH_C1, SPLAT_FLOATS, SURFACE, turning, unit,
  type Lighting, type Pose, type Scene, type Vec3,
} from "../js/splats/build"
import {buildFactory} from "../js/splats/factory"
import {buildIsland} from "../js/splats/island"
import {depthOrder} from "../js/splats/order"
import {focal, pixelGrid, TILT_LIMIT, viewFrom} from "../js/splats/painter"
import {PLY_PROPERTIES, readPlyHeader, toPly} from "../js/splats/ply"

const scenes: [string, () => Scene][] = [["factory", buildFactory], ["island", buildIsland]]
const built = new Map(scenes.map(([name, build]) => [name, build()]))

type Matrix = number[][]
const product = (a: Matrix, b: Matrix) => a.map(row => b[0]!.map((_, j) => row.reduce((sum, value, k) => sum + value * b[k]![j]!, 0)))
const transpose = (a: Matrix) => a[0]!.map((_, j) => a.map(row => row[j]!))

/** The rotation of a unit quaternion, real part first, as Gaussian splatting builds it. */
const rotation = ([w, x, y, z]: number[]): Matrix => [
  [1 - 2 * (y! * y! + z! * z!), 2 * (x! * y! - w! * z!), 2 * (x! * z! + w! * y!)],
  [2 * (x! * y! + w! * z!), 1 - 2 * (x! * x! + z! * z!), 2 * (y! * z! - w! * x!)],
  [2 * (x! * z! - w! * y!), 2 * (y! * z! + w! * x!), 1 - 2 * (x! * x! + y! * y!)],
]

/** Where splat `i` stands with its moving part where `parts` puts it. */
const posed = (data: Float32Array, parts: Float32Array, i: number): Vec3 => {
  const o = i * SPLAT_FLOATS
  const p = data[o + PART_FLOAT]! * 16
  const [x, y, z] = [data[o]!, data[o + 1]!, data[o + 2]!]
  const at = (a: number) => parts[p + a]! * x + parts[p + 4 + a]! * y + parts[p + 8 + a]! * z + parts[p + 12 + a]!
  return [at(0), at(1), at(2)]
}

/** A splat's colour seen along `d` (from the camera toward it), as Gaussian splatting evaluates degrees 0 and 1. */
const seen = (data: Float32Array, i: number, d: Vec3) => {
  const o = i * SPLAT_FLOATS
  return [0, 1, 2].map(c => {
    const s = data.subarray(o + 16 + c * 4, o + 19 + c * 4)
    return 0.5 + SH_C0 * data[o + 12 + c]! + SH_C1 * (-d[1] * s[0]! + d[2] * s[1]! - d[0] * s[2]!)
  })
}

const LIGHT: Lighting = {
  key: [-0.7, 0.4, 0.5], keyColour: [1, 0.8, 0.6], sky: [0.4, 0.4, 0.6], bounce: [0.3, 0.2, 0.2],
  rim: [0.6, 0.42, -0.68], rimColour: [0.6, 0.8, 0.8], shineColour: [0.5, 0.7, 0.9], warm: [1, 0.5, 0.2], lamps: [],
}

describe.each(scenes)("the %s", name => {
  const scene = built.get(name)!

  it("grows the same from its seed every time, a few hundred thousand splats", () => {
    const again = scenes.find(([n]) => n === name)![1]()
    expect(again.count).toBe(scene.count)
    expect(again.data).toEqual(scene.data)
    expect(scene.count).toBeGreaterThan(150_000)
    expect(scene.count).toBeLessThan(450_000)
    expect(scene.data.length).toBe(scene.count * SPLAT_FLOATS)
  })

  it("keeps every splat in the standard layout: a place, a unit quaternion, log scales, an opacity before the sigmoid, and colour", () => {
    const wrong: number[] = []
    for (let i = 0; i < scene.count; i++) {
      const o = i * SPLAT_FLOATS
      const [x, y, z, opacity, qw, qx, qy, qz, s0, s1, s2] = scene.data.subarray(o, o + 11)
      const part = scene.data[o + PART_FLOAT]!
      const fine =
        Math.hypot(x!, y!, z!) <= scene.reach &&
        Math.abs(Math.hypot(qw!, qx!, qy!, qz!) - 1) < 1e-5 &&
        [s0!, s1!, s2!].every(s => Math.exp(s) > 0 && Math.exp(s) < 0.2) &&
        1 / (1 + Math.exp(-opacity!)) > 0 &&
        1 / (1 + Math.exp(-opacity!)) < 1 &&
        scene.data.subarray(o + 12, o + 27).every(Number.isFinite) &&
        Number.isInteger(part) && part >= 0 && part < Math.max(1, scene.parts)
      if (!fine) wrong.push(i)
    }
    expect(wrong).toEqual([])
  })

  it("moves each moving part as a rigid turn, at any moment", () => {
    const parts = new Float32Array(Math.max(1, scene.parts) * 16)
    for (const seconds of [0, 1.7, 6.5, 29.3, 1234.5]) {
      scene.pose(seconds, parts)
      for (let p = 0; p < Math.max(1, scene.parts); p++) {
        const m = [0, 4, 8].map(k => Array.from(parts.subarray(p * 16 + k, p * 16 + k + 3)))
        const identity = product(m, transpose(m))
        identity.forEach((row, r) => row.forEach((value, c) => expect(value).toBeCloseTo(r === c ? 1 : 0, 5)))
        expect(parts[p * 16 + 15]).toBeGreaterThanOrEqual(0)
        expect(parts[p * 16 + 15]).toBeLessThanOrEqual(1)
      }
    }
  })

  describe("the sort", () => {
    const sort = depthOrder(scene.data, scene.count, SPLAT_FLOATS, scene.reach)
    const parts = new Float32Array(Math.max(1, scene.parts) * 16)
    scene.pose(3.7, parts)

    for (const [turn, pitch] of [[0, scene.camera.pitch], [2.2, TILT_LIMIT], [-1.4, -TILT_LIMIT], [Math.PI, 0]] as const) {
      it(`hands back every splat once, farthest first, turned ${turn} and tilted ${pitch.toFixed(2)}`, () => {
        const {ahead} = viewFrom(scene.camera, turn, pitch)
        const order = sort(ahead, parts)
        expect(new Set(order).size).toBe(scene.count)
        // How far ahead each splat stands, where its part is now.
        const depth = (i: number) => {
          const place = posed(scene.data, parts, i)
          return place[0] * ahead[0] + place[1] * ahead[1] + place[2] * ahead[2]
        }
        // Within one step of the sort's 16-bit keys, each splat is no nearer than the next.
        const step = (2 * scene.reach) / 65_535
        let nearer = 0
        for (let k = 1; k < order.length; k++) if (depth(order[k - 1]!) < depth(order[k]!) - step) nearer += 1
        expect(nearer).toBe(0)
      })
    }
  })

  // The wide box's picture, and a phone's square.
  for (const grid of [{columns: 435, rows: 290}, {columns: 324, rows: 324}]) {
    it(`fills a ${grid.columns} by ${grid.rows} picture as it turns, cutting none of it off`, () => {
      const parts = new Float32Array(Math.max(1, scene.parts) * 16)
      scene.pose(scene.still.seconds, parts)
      const f = focal(scene.camera, grid)
      // Only splats that stay where they were grown: steam, sparks and fireflies drift.
      const fixed = Array.from({length: scene.count}, (_, i) => i).filter(i => scene.data[i * SPLAT_FLOATS + 11] === SURFACE)
      const xs = new Float64Array(fixed.length)
      const ys = new Float64Array(fixed.length)
      // The scene's span past its farthest few splats (a stray root or blade of grass).
      const span = (values: Float64Array) => {
        values.sort()
        return [values[Math.floor(values.length * 0.0005)]!, values[Math.floor(values.length * 0.9995)]!]
      }
      let fill = 0
      for (let turn = 0; turn < 2 * Math.PI; turn += Math.PI / 6) {
        const {right, up, ahead, eye} = viewFrom(scene.camera, turn, scene.camera.pitch)
        fixed.forEach((i, k) => {
          const p = posed(scene.data, parts, i)
          const v = [p[0] - eye[0], p[1] - eye[1], p[2] - eye[2]]
          const z = v[0]! * ahead[0] + v[1]! * ahead[1] + v[2]! * ahead[2]
          xs[k] = grid.columns / 2 + (f * (v[0]! * right[0] + v[1]! * right[1] + v[2]! * right[2])) / z
          ys[k] = grid.rows / 2 - (f * (v[0]! * up[0] + v[1]! * up[1] + v[2]! * up[2])) / z
        })
        const [left, rightmost] = span(xs)
        const [top, bottom] = span(ys)
        expect(left).toBeGreaterThan(0)
        expect(rightmost).toBeLessThan(grid.columns)
        expect(top).toBeGreaterThan(0)
        expect(bottom).toBeLessThan(grid.rows)
        fill = Math.max(fill, (rightmost - left) / grid.columns, (bottom - top) / grid.rows)
      }
      expect(fill).toBeGreaterThan(0.8)
    })
  }
})

describe("a splat", () => {
  it("keeps the shape it was placed with: Σ = R S Sᵀ Rᵀ from its quaternion and scales", () => {
    const b = createBuilder(7)
    const turned = turning(unit([0.3, -0.8, 0.5]), 1.1, [0, 0, 0]).columns
    const sets: (readonly [Vec3, Vec3, Vec3])[] = [turned, [turned[1], turned[0], turned[2]], [[1, 0, 0], [0, 1, 0], [0, 0, 1]]]
    const reaches: Vec3[] = [[0.03, 0.01, 0.002], [0.02, 0.005, 0.004], [0.01, 0.01, 0.01]]
    sets.forEach((axes, k) => b.place({at: [0, 0, 0], axes, reach: reaches[k]!, colour: [0.5, 0.5, 0.5], opacity: 0.9, facing: [0, 1, 0], open: 1}))
    const {data} = b.finish(LIGHT)
    sets.forEach((axes, k) => {
      const o = k * SPLAT_FLOATS
      const rs = product(rotation(Array.from(data.subarray(o + 4, o + 8))), [0, 1, 2].map(r => [0, 1, 2].map(c => (r === c ? Math.exp(data[o + 8 + c]!) : 0))))
      const sigma = product(rs, transpose(rs))
      const placed = transpose(axes.map(a => [...a]))
      const expected = product(product(placed, reaches[k]!.map((r, i) => [0, 1, 2].map(c => (i === c ? r * r : 0)))), transpose(placed))
      sigma.forEach((row, r) => row.forEach((value, c) => expect(value).toBeCloseTo(expected[r]![c]!, 8)))
    })
  })

  it("gleams toward the view its shine was baked for, through its degree-1 harmonics", () => {
    const b = createBuilder(7)
    const up: Vec3 = [0, 1, 0]
    b.place({at: [0, 0, 0], axes: [[1, 0, 0], [0, 0, 1], up], reach: [0.02, 0.02, 0.004], colour: [0.2, 0.3, 0.4], opacity: 0.9, facing: up, open: 1, shine: 0.6})
    const {data} = b.finish(LIGHT)
    // Looking down at it along the rim light's mirror image, against looking up from below.
    const rim = unit(LIGHT.rim)
    const gleam: Vec3 = [rim[0], -rim[1], rim[2]]
    const toward = seen(data, 0, gleam)
    const away = seen(data, 0, [-gleam[0], -gleam[1], -gleam[2]])
    toward.forEach((value, c) => expect(value - away[c]!).toBeCloseTo(LIGHT.shineColour[c]! * 0.6, 5))
  })
})

describe("moving parts", () => {
  it("carry a part on a part: the forearm turns with the arm that holds it", () => {
    const apply = ({columns: [a, b, c], move}: Pose, [x, y, z]: Vec3): Vec3 => [
      a[0] * x + b[0] * y + c[0] * z + move[0],
      a[1] * x + b[1] * y + c[1] * z + move[1],
      a[2] * x + b[2] * y + c[2] * z + move[2],
    ]
    const outer = turning([0, 1, 0], 0.7, [0.2, 0, 0.1], [0, 0.05, 0])
    const inner = turning([0, 0, 1], -0.4, [0.3, 0.2, 0])
    const point: Vec3 = [0.4, 0.25, -0.1]
    const together = apply(after(outer, inner), point)
    apply(outer, apply(inner, point)).forEach((value, a) => expect(together[a]).toBeCloseTo(value, 9))
    // A turn keeps its pivot where it is.
    apply(inner, [0.3, 0.2, 0]).forEach((value, a) => expect(value).toBeCloseTo([0.3, 0.2, 0][a]!, 9))
  })
})

describe("the pixel grid", () => {
  for (const [width, height] of [[2172, 1446], [972, 972], [1074, 1074], [576, 384], [288, 192], [641, 427], [100, 60]] as const) {
    it(`covers a ${width} by ${height} canvas in whole-pixel squares`, () => {
      const grid = pixelGrid(width, height)
      expect(Number.isInteger(grid.scale)).toBe(true)
      expect(grid.scale).toBeGreaterThanOrEqual(1)
      expect(grid.offset[0]).toBeLessThanOrEqual(0)
      expect(grid.offset[1]).toBeLessThanOrEqual(0)
      expect(grid.offset[0] + grid.columns * grid.scale).toBeGreaterThanOrEqual(width)
      expect(grid.offset[1] + grid.rows * grid.scale).toBeGreaterThanOrEqual(height)
    })
  }

  it("is about 450 pixels across on a wide screen and at least 300 on a phone", () => {
    expect(pixelGrid(2172, 1448).columns).toBeGreaterThanOrEqual(400)
    expect(pixelGrid(2172, 1448).columns).toBeLessThanOrEqual(480)
    expect(pixelGrid(1074, 1074).columns).toBeGreaterThanOrEqual(300)
    expect(pixelGrid(716, 716).columns).toBeGreaterThanOrEqual(300)
  })
})

describe("the .ply file", () => {
  const scene = built.get("island")!
  const bytes = toPly(scene)
  const header = readPlyHeader(bytes)

  it("has the standard header and one vertex per splat", () => {
    expect(header.format).toBe("binary_little_endian 1.0")
    expect(header.count).toBe(scene.count)
    expect(header.properties).toEqual(PLY_PROPERTIES)
    expect(bytes.length).toBe(header.body + scene.count * PLY_PROPERTIES.length * 4)
  })

  it("holds each splat's values where a reader looks for them", () => {
    const values = new DataView(bytes.buffer, header.body)
    const read = (i: number, name: string) => values.getFloat32((i * PLY_PROPERTIES.length + PLY_PROPERTIES.indexOf(name)) * 4, true)
    for (const i of [0, 1234, scene.count - 1]) {
      const o = i * SPLAT_FLOATS
      expect([read(i, "x"), read(i, "y"), read(i, "z")]).toEqual(Array.from(scene.data.subarray(o, o + 3)))
      expect(read(i, "opacity")).toBe(scene.data[o + 3])
      expect([0, 1, 2, 3].map(k => read(i, `rot_${k}`))).toEqual(Array.from(scene.data.subarray(o + 4, o + 8)))
      expect([0, 1, 2].map(k => read(i, `scale_${k}`))).toEqual(Array.from(scene.data.subarray(o + 8, o + 11)))
      expect([0, 1, 2].map(k => read(i, `f_dc_${k}`))).toEqual(Array.from(scene.data.subarray(o + 12, o + 15)))
      // Degree 1, channel by channel: red's three, then green's, then blue's.
      expect([3, 4, 5].map(k => read(i, `f_rest_${k}`))).toEqual(Array.from(scene.data.subarray(o + 20, o + 23)))
      expect([read(i, "nx"), read(i, "ny"), read(i, "nz")]).toEqual([0, 0, 0])
    }
  })
})
