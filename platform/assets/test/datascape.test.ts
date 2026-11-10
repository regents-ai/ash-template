// The datascape's rules that must hold wherever the camera flies: a place always
// holds the same things, a tube's pieces join end to end, the camera rests near
// the middle and never outruns its top speed, and the cells kept are the cells
// in reach.
import {describe, expect, it} from "vitest"
import {SPEED, createField, steerSpeed, topSpeed, type Cell} from "../js/datascape/field"
import {CELL, LAYERS, cellContents, random, type TubePiece} from "../js/datascape/world"

/** A few hundred cells scattered far and wide, the same ones every run. */
const cells = (() => {
  const next = random(20261110)
  return Array.from({length: 400}, () => ({
    layer: Math.floor(next() * LAYERS.length),
    column: Math.floor((next() - 0.5) * 20000),
    row: Math.floor((next() - 0.5) * 20000),
  }))
})()

/** Where a piece starts and ends, and how long it is. */
const span = (piece: TubePiece) => {
  if (!piece.turn) {
    return {start: [piece.x0, piece.y0], end: [piece.x1, piece.y1], length: Math.hypot(piece.x1 - piece.x0, piece.y1 - piece.y0)}
  }
  const at = (angle: number) => [piece.x + Math.cos(angle) * piece.radius, piece.y + Math.sin(angle) * piece.radius]
  return {start: at(piece.angle), end: at(piece.angle + (piece.sweep * Math.PI) / 2), length: (Math.PI / 2) * piece.radius}
}

describe("the world", () => {
  it("holds the same things in the same cell every time", () => {
    for (const {layer, column, row} of cells) {
      expect(cellContents(layer, column, row)).toEqual(cellContents(layer, column, row))
    }
  })

  it("joins a tube's pieces end to end, each starting at the length before it", () => {
    const tubes = cells.flatMap(({layer, column, row}) => cellContents(layer, column, row).tube ?? [])
    expect(tubes.length).toBeGreaterThan(50)
    for (const tube of tubes) {
      let along = 0
      let end: number[] | undefined
      for (const piece of tube.pieces) {
        const {start, end: next, length} = span(piece)
        expect(piece.from).toBeCloseTo(along, 6)
        if (end) {
          expect(start[0]).toBeCloseTo(end[0]!, 6)
          expect(start[1]).toBeCloseTo(end[1]!, 6)
        }
        expect(length).toBeGreaterThanOrEqual(0)
        along += length
        end = next
      }
      expect(tube.length).toBeCloseTo(along, 6)
    }
  })
})

describe("steering", () => {
  it("rests near the middle, never passes top speed, and goes the way the pointer is", () => {
    for (const [width, height] of [[320, 384], [390, 588], [1280, 644], [3840, 1024]] as const) {
      const top = topSpeed(width, height)
      expect(top).toBeGreaterThan(0)
      expect(top).toBeLessThanOrEqual(SPEED)
      let last = 0
      for (let offset = 0; offset <= 1.5; offset += 0.01) {
        const speed = steerSpeed(offset, top)
        expect(speed).toBeGreaterThanOrEqual(last)
        expect(speed).toBeLessThanOrEqual(top)
        expect(steerSpeed(-offset, top)).toBeCloseTo(-speed, 9)
        last = speed
      }
      expect(steerSpeed(0.05, top)).toBe(0)
      expect(steerSpeed(1, top)).toBe(top)
    }
  })
})

describe("the field", () => {
  const watched = () => {
    const here = new Map<string, Cell>()
    const field = createField({
      arrive: cell => {
        expect(here.has(cell.key)).toBe(false)
        here.set(cell.key, cell)
      },
      leave: cell => {
        expect(here.delete(cell.key)).toBe(true)
      },
      rest: () => {},
    })
    return {field, here}
  }

  it("flies towards the edge the pointer is at, bringing cells in and letting them go", () => {
    const {field, here} = watched()
    const [width, height] = [1280, 720]
    field.advance(0, width, height)
    const first = new Set(here.keys())
    expect(first.size).toBeGreaterThan(0)

    field.pointer = [width / 2, 0]
    for (let step = 0; step < 600; step++) field.advance(1 / 60, width, height)
    expect(field.camera.x).toBeGreaterThan(5 * CELL)
    expect(Math.abs(field.camera.y)).toBeLessThan(1)
    expect(Math.hypot(field.camera.vx, field.camera.vy)).toBeLessThanOrEqual(topSpeed(width, height))

    // Whoever watches was told of exactly the cells the field still holds, and the first ones are long gone.
    expect(new Set(here.keys())).toEqual(new Set(field.cells.keys()))
    for (const key of first) expect(here.has(key)).toBe(false)
    // Every cell the picture shows is there.
    for (const [layer, {depth}] of LAYERS.entries()) {
      const scale = depth * field.camera.zoom
      const column = Math.floor((field.camera.x + width / 2 / scale) / CELL)
      const row = Math.floor((field.camera.y - height / 2 / scale) / CELL)
      expect(field.cells.has(`${layer}:${column}:${row}`)).toBe(true)
    }
  })

  it("finds the panel under the pointer once it has opened, and tells whoever watches", () => {
    const rested: (string | null)[] = []
    const field = createField({arrive: () => {}, leave: () => {}, rest: panel => void rested.push(panel && `${panel.x}:${panel.y}`)})
    field.advance(0, 1280, 720)
    const near = LAYERS.length - 1
    const panel = [...field.cells.values()].filter(cell => cell.layer === near).flatMap(cell => cell.panels).find(each => each.w > 20)!
    const point: [number, number] = [panel.x - field.camera.x, panel.y - field.camera.y]

    expect(field.panelAt(...point)).toBeNull()
    panel.grow = 1
    expect(field.panelAt(...point)).toBe(panel)

    field.pointer = point
    field.advance(0, 1280, 720)
    field.pointer = null
    field.advance(0, 1280, 720)
    expect(rested).toEqual([`${panel.x}:${panel.y}`, null])
  })
})
