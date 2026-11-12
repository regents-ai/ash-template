import {describe, expect, it} from "vitest"
import {cellAt, edges} from "../js/hooks/motion/travel"
import {compare} from "../js/hooks/motion/crumbs"
import {nearest} from "../js/hooks/motion/chart"

describe("cellAt", () => {
  it("names the cell under a point, and the end cells past the edges", () => {
    expect(cellAt(10, 300, 3)).toBe(0)
    expect(cellAt(150, 300, 3)).toBe(1)
    expect(cellAt(299, 300, 3)).toBe(2)
    expect(cellAt(-40, 300, 3)).toBe(0)
    expect(cellAt(400, 300, 3)).toBe(2)
  })
})

describe("edges", () => {
  it("leads with the end going forward and the start going back", () => {
    expect(edges(0, 2)).toEqual({
      lead: {edge: "--rg-travel-end", at: 3},
      trail: {edge: "--rg-travel-start", at: 2},
    })
    expect(edges(2, 0)).toEqual({
      lead: {edge: "--rg-travel-start", at: 0},
      trail: {edge: "--rg-travel-end", at: 1},
    })
  })
})

describe("compare", () => {
  it("rises the new page showing and fades the levels that left", () => {
    const deep = {here: "Photos", names: ["Home", "Garden"]}
    const up = {here: "Garden", names: ["Home"]}
    expect(compare(deep, up)).toEqual({rises: true, left: ["Garden"]})
    expect(compare(up, deep)).toEqual({rises: true, left: []})
    expect(compare(up, up)).toEqual({rises: false, left: []})
  })
})

describe("nearest", () => {
  it("finds the point closest to a place across", () => {
    const across = [0, 25, 50, 75, 100]
    expect(nearest(across, 0)).toBe(0)
    expect(nearest(across, 37)).toBe(1)
    expect(nearest(across, 38)).toBe(2)
    expect(nearest(across, 120)).toBe(4)
  })
})
