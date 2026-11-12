// Invariant: every shape of the particle field is exactly GRAINS homes, each
// inside the shape's box at both ends of the value, facing no further over than
// edge on, laid out the same way every time and in left-to-right order where
// the grains sit; the lit part of a fill follows the value; and a drawing's
// grains lie only where it is drawn.
import {describe, expect, it} from "vitest"
import {controlShape, GRAINS, HOME_FLOATS, pictureShape, through, type Picture, type Shape} from "../js/particle_field/shapes"

/** Each control with the box it is drawn for, as the page's CSS sets it. */
const CONTROLS = [
  ["switch", 2],
  ["slider", 6],
  ["bar", 9],
  ["ring", 1],
  ["spinner", 1],
  ["checkbox", 1],
  ["radio", 3],
  ["steps:5", 4],
] as const

const homeAt = (shape: Shape, g: number) => shape.homes.subarray(g * HOME_FLOATS, (g + 1) * HOME_FLOATS)

/** Where a grain sits at a value: between its two places as far as the value has moved it. */
function placeAt(home: Float32Array, value: number) {
  const m = through(value, [home[6]!, home[7]!])
  return {x: home[0]! + (home[2]! - home[0]!) * m, y: home[1]! + (home[3]! - home[1]!) * m}
}

/** The grains with a home outside the box at either end of the value, or facing past edge on. */
function strays(shape: Shape, aspect: number) {
  // A little room: a grain lands anywhere in the cell it was drawn into.
  const slack = 0.01
  let count = 0
  for (let g = 0; g < GRAINS; g++) {
    const home = homeAt(shape, g)
    const outside = [
      [home[0]!, home[1]!],
      [home[2]!, home[3]!],
    ].some(([x, y]) => Math.abs(x!) > aspect / 2 + slack || Math.abs(y!) > 0.5 + slack)
    if (!home.every(Number.isFinite) || outside || Math.hypot(home[4]!, home[5]!) > 1 + 1e-6) count++
  }
  return count
}

/** The grains sitting left of the grain before them at this value, by more than the order's own fineness. */
function outOfOrder(shape: Shape, value: number) {
  let count = 0
  let last = -Infinity
  for (let g = 0; g < GRAINS; g++) {
    const {x} = placeAt(homeAt(shape, g), value)
    if (x < last - 1e-6) count++
    last = x
  }
  return count
}

/** A picture of one filled block, as a cell grid fitted into a box `aspect` wide. */
function blockPicture(aspect: number, cell: number, block: {left: number; top: number; right: number; bottom: number}): Picture {
  const width = Math.ceil(aspect / cell)
  const height = Math.ceil(1 / cell)
  const mask = new Uint8Array(width * height)
  for (let j = 0; j < height; j++) {
    for (let i = 0; i < width; i++) {
      const x = -aspect / 2 + (i + 0.5) * cell
      const y = -0.5 + (j + 0.5) * cell
      if (x > block.left && x < block.right && y > block.top && y < block.bottom) mask[j * width + i] = 1
    }
  }
  return {mask, width, height, cell, left: -aspect / 2, top: -0.5}
}

describe("control shapes", () => {
  for (const [name, aspect] of CONTROLS) {
    it(`${name}: every grain has one home inside the box, the same each time, in order across`, () => {
      const value = 0.4
      const shape = controlShape(name, aspect, value)
      expect(shape.homes.length).toBe(GRAINS * HOME_FLOATS)
      expect(shape.area).toBeGreaterThan(0)
      expect(strays(shape, aspect)).toBe(0)
      expect(outOfOrder(shape, value)).toBe(0)
      expect(controlShape(name, aspect, value).homes).toEqual(shape.homes)
    })
  }

  it("a fill's lit part follows the value: none at 0, about half at a half, all at 1", () => {
    for (const [name, aspect] of [
      ["ring", 1],
      ["bar", 9],
    ] as const) {
      const shape = controlShape(name, aspect, 0)
      const litAt = (value: number) => {
        let lit = 0
        for (let g = 0; g < GRAINS; g++) {
          const home = homeAt(shape, g)
          if (through(value, [home[8]!, home[9]!]) >= 0.5) lit++
        }
        return lit / GRAINS
      }
      expect(litAt(0)).toBe(0)
      expect(litAt(1)).toBe(1)
      expect(litAt(0.5)).toBeGreaterThan(0.3)
      expect(litAt(0.5)).toBeLessThan(0.7)
    }
  })

  it("the switch's knob rolls from one end of the track to the other", () => {
    expect(controlShape("switch", 2, 0).knob).toEqual({x0: -0.5, y0: 0, x1: 0.5, y1: 0, r: 0.39})
  })
})

describe("picture shapes", () => {
  it("lays every grain on the drawn block and nowhere else", () => {
    const aspect = 1.4
    const cell = aspect / 120
    const block = {left: -0.3, top: -0.2, right: 0.1, bottom: 0.25}
    const shape = pictureShape("block", blockPicture(aspect, cell, block), 0)
    expect(shape.homes.length).toBe(GRAINS * HOME_FLOATS)
    expect(strays(shape, aspect)).toBe(0)
    let off = 0
    for (let g = 0; g < GRAINS; g++) {
      const {x, y} = placeAt(homeAt(shape, g), 0)
      if (x < block.left - cell || x > block.right + cell || y < block.top - cell || y > block.bottom + cell) off++
    }
    expect(off).toBe(0)
  })
})
