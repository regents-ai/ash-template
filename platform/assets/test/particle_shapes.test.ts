// Invariant: every shape of the particle field is exactly GRAINS homes, each
// inside the shape's box at both ends of the value, facing no further over than
// edge on, and laid out the same way every time; its flying order keeps every
// home once and runs in columns from left to right, each from top to bottom,
// where the grains sit at that value; the lit part of a fill follows the value;
// and a drawing's grains lie only where it is drawn.
import {describe, expect, it} from "vitest"
import {
  ACROSS_STEPS,
  COLUMN,
  controlShape,
  DOWN_STEPS,
  finish,
  GRAINS,
  HOME_FLOATS,
  inFlightOrder,
  pictureShape,
  through,
  type Picture,
} from "../js/particle_field/shapes"

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

const homeAt = (homes: Float32Array, g: number) => homes.subarray(g * HOME_FLOATS, (g + 1) * HOME_FLOATS)

/** Where a grain sits at a value: between its two places as far as the value has moved it. */
function placeAt(home: Float32Array, value: number) {
  const m = through(value, [home[6]!, home[7]!])
  return {x: home[0]! + (home[2]! - home[0]!) * m, y: home[1]! + (home[3]! - home[1]!) * m}
}

/** The grains with a home outside the box at either end of the value, or facing past edge on. */
function strays(homes: Float32Array, aspect: number) {
  // A little room: a grain lands anywhere in the cell it was drawn into.
  const slack = 0.01
  let count = 0
  for (let g = 0; g < GRAINS; g++) {
    const home = homeAt(homes, g)
    const outside = [
      [home[0]!, home[1]!],
      [home[2]!, home[3]!],
    ].some(([x, y]) => Math.abs(x!) > aspect / 2 + slack || Math.abs(y!) > 0.5 + slack)
    if (!home.every(Number.isFinite) || outside || Math.hypot(home[4]!, home[5]!) > 1 + 1e-6) count++
  }
  return count
}

const spread = (values: number[]) => ({low: values.reduce((a, b) => Math.min(a, b)), high: values.reduce((a, b) => Math.max(a, b))})

/**
 * The grains out of flying order at this value: a column reaching left of the
 * one before it, or a grain above the one before it in its column, by more
 * than the order tells places apart.
 */
function outOfOrder(homes: Float32Array, value: number) {
  const places = Array.from({length: GRAINS}, (_, g) => placeAt(homeAt(homes, g), value))
  const across = spread(places.map(place => place.x))
  const step = (across.high - across.low) / (ACROSS_STEPS - 1) + 1e-6
  let count = 0
  let lastRight = -Infinity
  for (let start = 0; start < GRAINS; start += COLUMN) {
    const column = places.slice(start, start + COLUMN)
    const xs = spread(column.map(place => place.x))
    if (xs.low < lastRight - step) count++
    lastRight = xs.high
    const ys = spread(column.map(place => place.y))
    const down = (ys.high - ys.low) / (DOWN_STEPS - 1) + 1e-6
    for (let k = 1; k < column.length; k++) if (column[k]!.y < column[k - 1]!.y - down) count++
  }
  return count
}

/** One of a home's floats for every grain, sorted, so two sets of homes can be compared whatever their order. */
const sortedFloat = (homes: Float32Array, f: number) => Float32Array.from({length: GRAINS}, (_, g) => homes[g * HOME_FLOATS + f]!).sort()

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
    it(`${name}: every grain has one home inside the box, the same each time, and flies in columns`, () => {
      const value = 0.4
      const shape = finish(controlShape(name, aspect))
      expect(shape.homes.length).toBe(GRAINS * HOME_FLOATS)
      expect(shape.area).toBeGreaterThan(0)
      expect(strays(shape.homes, aspect)).toBe(0)
      expect(finish(controlShape(name, aspect)).homes).toEqual(shape.homes)

      const ordered = finish(inFlightOrder(shape.homes, value))
      expect(outOfOrder(ordered, value)).toBe(0)
      for (const f of [0, 1, 2, 3, 8]) expect(sortedFloat(ordered, f)).toEqual(sortedFloat(shape.homes, f))
    })
  }

  it("a fill's lit part follows the value: none at 0, about half at a half, all at 1", () => {
    for (const [name, aspect] of [
      ["ring", 1],
      ["bar", 9],
    ] as const) {
      const {homes} = finish(controlShape(name, aspect))
      const litAt = (value: number) => {
        let lit = 0
        for (let g = 0; g < GRAINS; g++) {
          const home = homeAt(homes, g)
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
    expect(finish(controlShape("switch", 2)).knob).toEqual({x0: -0.5, y0: 0, x1: 0.5, y1: 0, r: 0.39})
  })
})

describe("picture shapes", () => {
  it("lays every grain on the drawn block and nowhere else", () => {
    const aspect = 1.4
    const cell = aspect / 120
    const block = {left: -0.3, top: -0.2, right: 0.1, bottom: 0.25}
    const {homes} = finish(pictureShape("block", blockPicture(aspect, cell, block)))
    expect(homes.length).toBe(GRAINS * HOME_FLOATS)
    expect(strays(homes, aspect)).toBe(0)
    let off = 0
    for (let g = 0; g < GRAINS; g++) {
      const {x, y} = placeAt(homeAt(homes, g), 0)
      if (x < block.left - cell || x > block.right + cell || y < block.top - cell || y > block.bottom + cell) off++
    }
    expect(off).toBe(0)
  })
})
