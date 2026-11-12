// Invariant: the moving Cells meter lays its cells out exactly as the design
// system's cells.css lays out the still ones: as many whole cells as fit across,
// each run from the nearest cell edge to the nearest cell edge, a half rounding up,
// every run ending where the next begins. Its runs then move only by whole cells:
// a change lands in well under a second, a change part-way through starts from the
// cells on screen, lost cells break off as sparks that are gone within a second,
// and the first frame shows the runs where the still meter has them, with nothing
// hot and no sparks.
import {describe, expect, it} from "vitest"
import {columnsIn, runOf, type Grid} from "../js/cells_meter/layout"
import {EASE_OUT} from "../js/hooks/motion/shared"
import {COLUMN_FLOATS, IN_RUN, createCellsPicture, type MeterScene, type Part} from "../js/cells_meter/picture"

const GRID: Grid = {cell: 3, gap: 2, rows: 10}
const FRAME = 1 / 60

describe("the bar's columns", () => {
  it("are as many whole cells as fit, the last with no gap after it", () => {
    expect(columnsIn(0, GRID)).toBe(0)
    expect(columnsIn(2, GRID)).toBe(0)
    expect(columnsIn(3, GRID)).toBe(1)
    expect(columnsIn(7.9, GRID)).toBe(1)
    expect(columnsIn(8, GRID)).toBe(2)
    expect(columnsIn(1280, GRID)).toBe(256)
    expect(columnsIn(357.5, GRID)).toBe(71)
  })
})

describe("a part's run", () => {
  it("rounds each edge to the nearest cell edge, a half rounding up, as CSS round() does", () => {
    expect(runOf(0.25, 0.5, 10)).toEqual({from: 3, to: 8})
    expect(runOf(0, 0.24, 10)).toEqual({from: 0, to: 2})
    expect(runOf(0, 0.26, 10)).toEqual({from: 0, to: 3})
    expect(runOf(0.999999, 0.000001, 70)).toEqual({from: 70, to: 70})
  })

  it("ends where the next one begins, and the runs never pass the bar's end", () => {
    // Shares as the design system writes them: millionths, each part starting where the last ended.
    const values = [24, 18, 12, 9, 6, 8, 0, 1]
    for (const columns of [0, 1, 7, 61, 71, 256, 1000]) {
      let sum = 0
      let previous = 0
      for (const value of values) {
        const start = Math.round((sum / 100) * 1e6) / 1e6
        sum += value
        const share = Math.round((sum / 100) * 1e6) / 1e6 - start
        const run = runOf(start, share, columns)
        expect(run.from).toBe(previous)
        expect(run.to).toBeGreaterThanOrEqual(run.from)
        expect(run.to).toBeLessThanOrEqual(columns)
        previous = run.to
      }
    }
  })
})

const colour = [0.4, 0.6, 0.9] as const

/** Parts from values out of 100, as the meter writes their starts and shares. */
const partsOf = (values: Record<string, number>): Part[] => {
  let sum = 0
  return Object.entries(values).map(([key, value]) => {
    const start = sum / 100
    sum += value
    return {key, start, share: value / 100, colour}
  })
}

const sceneOf = (values: Record<string, number>, counting = false): MeterScene => ({
  width: 1000 * 5 - 2,
  grid: GRID,
  parts: partsOf(values),
  counting,
  lit: new Set(),
  dim: [0.5, 0.5, 0.5],
  dimAlpha: 0.14,
  fg: [1, 1, 1],
})

/** Each column's run as the picture shows it: its seed, or 0 for a dim column; and its heat. */
const shownColumns = (picture: ReturnType<typeof createCellsPicture>) => {
  const data = picture.columnData()
  const runs: number[] = []
  const heat: number[] = []
  for (let c = 0; c < picture.columns(); c++) {
    const o = c * COLUMN_FLOATS
    runs.push(data[o + 7]! & IN_RUN ? data[o + 5]! : 0)
    heat.push(data[o + 6]!)
  }
  return {runs, heat}
}

const lengthOf = (runs: number[], seed: number) => runs.filter(run => run === seed).length

describe("the moving picture", () => {
  it("first shows the runs where the still meter has them, cold and with no sparks", () => {
    const picture = createCellsPicture(EASE_OUT)
    picture.step(sceneOf({a: 30, b: 20}), 0, true)
    const {runs, heat} = shownColumns(picture)
    expect(runs.filter(run => run !== 0)).toHaveLength(500)
    expect(runs.slice(0, 300).every(run => run === runs[0])).toBe(true)
    expect(runs[300]).not.toBe(runs[0])
    expect(heat.every(h => h === 0)).toBe(true)
    expect(picture.sparkCount()).toBe(0)
  })

  it("grows a run with hot new cells, and lands in well under a second", () => {
    const picture = createCellsPicture(EASE_OUT)
    picture.step(sceneOf({a: 10, b: 10}), 0, true)
    const a = shownColumns(picture).runs[0]!
    let frames = 0
    picture.step(sceneOf({a: 40, b: 10}, true), FRAME, false)
    const early = shownColumns(picture)
    expect(lengthOf(early.runs, a)).toBeGreaterThan(100)
    expect(lengthOf(early.runs, a)).toBeLessThan(400)
    expect(early.heat[lengthOf(early.runs, a) - 1]).toBeGreaterThan(0.9)
    const b = shownColumns(picture).runs[199]!
    while (lengthOf(shownColumns(picture).runs, a) !== 400 && frames < 120) {
      picture.step(sceneOf({a: 40, b: 10}, true), FRAME, false)
      frames += 1
      // The run after it slides along whole: it neither gains nor loses a cell on the way.
      expect(lengthOf(shownColumns(picture).runs, b)).toBe(100)
      expect(picture.sparkCount()).toBe(0)
    }
    expect(frames * FRAME).toBeLessThan(0.7)
    const {runs} = shownColumns(picture)
    expect(runs.slice(400, 500).every(run => run === b)).toBe(true)
  })

  it("lets a run that only moves round to a cell less without sparks or heat", () => {
    // The lab's own case: 218 columns, Treasury grows from 24 to 54 and Liquidity,
    // moving along unchanged, rounds from 40 cells to 39.
    const scene = (treasury: number): MeterScene => ({...sceneOf({treasury, liquidity: 18, team: 12}), width: 218 * 5 - 2})
    const picture = createCellsPicture(EASE_OUT)
    picture.step(scene(24), 0, true)
    const liquidity = shownColumns(picture).runs[60]!
    expect(lengthOf(shownColumns(picture).runs, liquidity)).toBe(40)
    for (let n = 0; n < 60; n++) {
      picture.step(scene(54), FRAME, false)
      expect(picture.sparkCount()).toBe(0)
      const {runs, heat} = shownColumns(picture)
      expect(runs.every((run, c) => run !== liquidity || heat[c] === 0)).toBe(true)
    }
    expect(lengthOf(shownColumns(picture).runs, liquidity)).toBe(39)
  })

  it("holds the leading edge of the total hot while counting, and lets it cool after", () => {
    const picture = createCellsPicture(EASE_OUT)
    picture.step(sceneOf({a: 10, b: 10}, true), 0, true)
    for (let n = 0; n < 60; n++) picture.step(sceneOf({a: 10, b: 10}, true), FRAME, false)
    expect(shownColumns(picture).heat[199]).toBe(1)
    for (let n = 0; n < 90; n++) picture.step(sceneOf({a: 10, b: 10}), FRAME, false)
    expect(shownColumns(picture).heat[199]).toBeLessThan(0.01)
  })

  it("breaks a part let go into sparks, closes the runs up, and leaves no sparks within a second", () => {
    const picture = createCellsPicture(EASE_OUT)
    picture.step(sceneOf({a: 10, b: 20, c: 10}), 0, true)
    const {runs: before} = shownColumns(picture)
    const c = before[350]!
    picture.step(sceneOf({a: 10, c: 10}), FRAME, false)
    expect(picture.sparkCount()).toBeGreaterThan(0)
    let frames = 1
    while (frames < 120) {
      picture.step(sceneOf({a: 10, c: 10}), FRAME, false)
      frames += 1
      const {runs} = shownColumns(picture)
      if (lengthOf(runs, c) === 100 && runs[100] === c && picture.sparkCount() === 0) break
    }
    expect(frames * FRAME).toBeLessThan(1)
    const {runs} = shownColumns(picture)
    expect(runs.slice(100, 200).every(run => run === c)).toBe(true)
    expect(runs.slice(200).every(run => run === 0)).toBe(true)
  })

  it("takes a change part-way through from the cells on screen", () => {
    const picture = createCellsPicture(EASE_OUT)
    picture.step(sceneOf({a: 10}), 0, true)
    const a = shownColumns(picture).runs[0]!
    for (let n = 0; n < 6; n++) picture.step(sceneOf({a: 60}), FRAME, false)
    const midway = lengthOf(shownColumns(picture).runs, a)
    expect(midway).toBeGreaterThan(100)
    expect(midway).toBeLessThan(600)
    picture.step(sceneOf({a: 20}), FRAME, false)
    const turned = lengthOf(shownColumns(picture).runs, a)
    // One frame on, the run is still about where it was, not back at the start or at either end.
    expect(Math.abs(turned - midway)).toBeLessThan(80)
  })
})
