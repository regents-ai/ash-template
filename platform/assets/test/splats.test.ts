// The splats page's island without a GPU: the same seed always grows the same
// island, the sort hands back every splat once and farthest first from any side, and
// the pixel grid always covers its canvas in whole-pixel squares.
import {describe, expect, it} from "vitest"
import {buildIsland, SPLAT_FLOATS} from "../js/splats/island"
import {depthOrder} from "../js/splats/order"
import {PITCH, pixelGrid} from "../js/splats/painter"

const island = buildIsland()

describe("the island", () => {
  it("grows the same from its seed every time, tens of thousands of splats", () => {
    const again = buildIsland()
    expect(again.count).toBe(island.count)
    expect(again.data).toEqual(island.data)
    expect(island.count).toBeGreaterThan(40_000)
    expect(island.count).toBeLessThan(80_000)
    expect(island.data.length).toBe(island.count * SPLAT_FLOATS)
  })

  it("gives every splat a shape that is a real ellipsoid, and a visible opacity", () => {
    for (let i = 0; i < island.count; i++) {
      const o = i * SPLAT_FLOATS
      const [x, y, z, opacity, xx, xy, xz, yy, yz, zz] = island.data.subarray(o, o + 10)
      expect(Number.isFinite(x! + y! + z!)).toBe(true)
      expect(opacity).toBeGreaterThan(0)
      expect(opacity).toBeLessThanOrEqual(1)
      // A covariance is positive definite: its leading minors are all positive.
      expect(xx).toBeGreaterThan(0)
      expect(xx! * yy! - xy! * xy!).toBeGreaterThan(0)
      const det = xx! * (yy! * zz! - yz! * yz!) - xy! * (xy! * zz! - yz! * xz!) + xz! * (xy! * yz! - yy! * xz!)
      expect(det).toBeGreaterThan(0)
    }
  })
})

describe("the sort", () => {
  const sort = depthOrder(island.data, island.count, SPLAT_FLOATS, island.reach)

  for (const turn of [0, 1.1, Math.PI, -2.4]) {
    it(`hands back every splat once, farthest first, turned ${turn}`, () => {
      const order = sort(turn, PITCH)
      expect(new Set(order).size).toBe(island.count)
      // How far ahead of the camera each splat stands, in the island's own frame.
      const ahead = (i: number) => {
        const o = i * SPLAT_FLOATS
        return island.data[o]! * Math.sin(turn) * Math.cos(PITCH) - island.data[o + 1]! * Math.sin(PITCH) - island.data[o + 2]! * Math.cos(turn) * Math.cos(PITCH)
      }
      // Within one step of the sort's 16-bit keys, each splat is no nearer than the next.
      const step = (2 * island.reach) / 65_535
      for (let k = 1; k < order.length; k++) expect(ahead(order[k - 1]!)).toBeGreaterThanOrEqual(ahead(order[k]!) - step)
    })
  }
})

describe("the pixel grid", () => {
  for (const [width, height] of [[2172, 1446], [972, 972], [576, 384], [288, 192], [641, 427], [100, 60]] as const) {
    it(`covers a ${width} by ${height} canvas in whole-pixel squares`, () => {
      const grid = pixelGrid(width, height)
      expect(Number.isInteger(grid.scale)).toBe(true)
      expect(grid.scale).toBeGreaterThanOrEqual(1)
      expect(grid.columns * grid.scale).toBeGreaterThanOrEqual(width)
      expect(grid.rows * grid.scale).toBeGreaterThanOrEqual(height)
      expect(grid.offset[0]).toBeLessThanOrEqual(0)
      expect(grid.offset[1]).toBeLessThanOrEqual(0)
      expect(grid.offset[0] + grid.columns * grid.scale).toBeGreaterThanOrEqual(width)
      expect(grid.offset[1] + grid.rows * grid.scale).toBeGreaterThanOrEqual(height)
    })
  }
})
