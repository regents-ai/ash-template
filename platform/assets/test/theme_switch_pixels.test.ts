// Invariant: the theme switch's moon and sun are drawn from one source, have
// the same number of pixels, and every moon pixel is paired with exactly one sun
// pixel by angle round the centre, so the swarm neither loses nor doubles a
// pixel on its way across.
import {describe, expect, it} from "vitest"
import {GRID, MOON, PAIRS, SUN, pairByAngle, readPixels, turnBetween, wrapAngle, type Pixel} from "../js/theme_switch/pixels"

// A small, seeded source of numbers, so every run checks the same cases.
function numbers(seed: number) {
  let state = seed >>> 0
  return () => {
    state = (state * 1664525 + 1013904223) >>> 0
    return state / 2 ** 32
  }
}

function randomPicture(next: () => number, count: number): Pixel[] {
  return Array.from({length: count}, () => {
    const x = Math.round(next() * 8 - 4)
    const y = Math.round(next() * 8 - 4)
    return {x, y, angle: wrapAngle(Math.atan2(y, x)), radius: Math.hypot(x, y)}
  })
}

const key = (pixel: Pixel) => `${pixel.x},${pixel.y}`

function expectOneToOne(from: readonly Pixel[], to: readonly Pixel[], pairs: readonly {moon: Pixel; sun: Pixel}[]) {
  expect(pairs).toHaveLength(from.length)
  expect(new Set(pairs.map(pair => pair.moon))).toEqual(new Set(from))
  expect(new Set(pairs.map(pair => pair.sun))).toEqual(new Set(to))
}

describe("the two pictures", () => {
  it("are each a full matrix with the same number of lit pixels", () => {
    for (const rows of [MOON, SUN]) {
      expect(rows).toHaveLength(GRID)
      for (const row of rows) expect(row).toMatch(new RegExp(`^[.#]{${GRID}}$`))
    }
    expect(readPixels(MOON)).toHaveLength(readPixels(SUN).length)
  })

  it("pair every moon pixel with exactly one sun pixel", () => {
    const moon = readPixels(MOON)
    const sun = readPixels(SUN)
    expect(new Set(PAIRS.map(pair => key(pair.moon)))).toEqual(new Set(moon.map(key)))
    expect(new Set(PAIRS.map(pair => key(pair.sun)))).toEqual(new Set(sun.map(key)))
    expect(PAIRS).toHaveLength(moon.length)
  })
})

describe("pairing by angle", () => {
  it("is one to one for any two pictures of the same size", () => {
    const next = numbers(7)
    for (let round = 0; round < 200; round++) {
      const count = 1 + Math.floor(next() * 40)
      const from = randomPicture(next, count)
      const to = randomPicture(next, count)
      expectOneToOne(from, to, pairByAngle(from, to))
    }
  })

  it("keeps the first picture's clockwise order", () => {
    const next = numbers(11)
    for (let round = 0; round < 100; round++) {
      const count = 2 + Math.floor(next() * 30)
      const pairs = pairByAngle(randomPicture(next, count), randomPicture(next, count))
      for (let i = 1; i < pairs.length; i++) expect(pairs[i].moon.angle).toBeGreaterThanOrEqual(pairs[i - 1].moon.angle)
    }
  })

  it("turns no further, all told, than any other clockwise pairing", () => {
    const next = numbers(13)
    for (let round = 0; round < 100; round++) {
      const count = 1 + Math.floor(next() * 25)
      const from = randomPicture(next, count)
      const to = randomPicture(next, count)
      const total = (pairs: readonly {moon: Pixel; sun: Pixel}[]) =>
        pairs.reduce((sum, pair) => sum + Math.abs(turnBetween(pair.moon.angle, pair.sun.angle)), 0)
      const chosen = total(pairByAngle(from, to))
      const moons = [...from].sort((a, b) => a.angle - b.angle || a.radius - b.radius)
      const suns = [...to].sort((a, b) => a.angle - b.angle || a.radius - b.radius)
      for (let shift = 0; shift < count; shift++) {
        const other = moons.map((moon, i) => ({moon, sun: suns[(i + shift) % count]}))
        expect(chosen).toBeLessThanOrEqual(total(other) + 1e-9)
      }
    }
  })

  it("pairs a picture with itself pixel for pixel", () => {
    const moon = readPixels(MOON)
    for (const pair of pairByAngle(moon, moon)) expect(key(pair.sun)).toBe(key(pair.moon))
  })

  it("refuses two pictures of different sizes", () => {
    const next = numbers(17)
    expect(() => pairByAngle(randomPicture(next, 3), randomPicture(next, 4))).toThrow()
  })
})

describe("turns between angles", () => {
  it("are the shortest way round, never more than half a turn", () => {
    const next = numbers(19)
    for (let round = 0; round < 500; round++) {
      const from = next() * 20 - 10
      const to = next() * 20 - 10
      const turn = turnBetween(from, to)
      expect(Math.abs(turn)).toBeLessThanOrEqual(Math.PI + 1e-9)
      expect(Math.abs(turnBetween(from + turn, to))).toBeLessThan(1e-9)
    }
  })
})
