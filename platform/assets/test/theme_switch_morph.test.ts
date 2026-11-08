// Invariant: the knob's position scrubs the theme switch's swarm. At night every
// pixel is on the moon and by day on the sun; in between the swarm is part way,
// some pixels home, some in flight and some still waiting, in the order they
// leave, clockwise from the bottom. The knob can be moved back and forth and
// the swarm follows exactly.
import {describe, expect, it} from "vitest"
import {createMorph, departureOrder, PIXEL_STRIDE, SWIRL_TURNS} from "../js/theme_switch/morph"
import {PAIRS, turnBetween, wrapAngle} from "../js/theme_switch/pixels"

const morph = createMorph()
const out = new Float32Array(PAIRS.length * PIXEL_STRIDE)

/** Every pixel where knob position `p` puts it: x, y, size and share of day. */
function at(p: number) {
  morph.seek(p)
  morph.write(out)
  return PAIRS.map((_, i) => {
    const o = i * PIXEL_STRIDE
    return {x: out[o], y: out[o + 1], size: out[o + 2], day: out[o + 3]}
  })
}

describe("the swarm at either end", () => {
  it("sits on the moon at night", () => {
    at(0).forEach((pixel, i) => {
      expect(pixel.x).toBeCloseTo(PAIRS[i].moon.x, 5)
      expect(pixel.y).toBeCloseTo(PAIRS[i].moon.y, 5)
      expect(pixel.size).toBeCloseTo(1, 5)
      expect(pixel.day).toBe(0)
    })
  })

  it("sits on the sun by day", () => {
    at(1).forEach((pixel, i) => {
      expect(pixel.x).toBeCloseTo(PAIRS[i].sun.x, 4)
      expect(pixel.y).toBeCloseTo(PAIRS[i].sun.y, 4)
      expect(pixel.size).toBeCloseTo(1, 4)
      expect(pixel.day).toBeCloseTo(1, 5)
    })
  })

  it("comes back to the moon exactly after being dragged most of the way", () => {
    at(0.7)
    at(0.2)
    at(0).forEach((pixel, i) => {
      expect(pixel.x).toBeCloseTo(PAIRS[i].moon.x, 5)
      expect(pixel.y).toBeCloseTo(PAIRS[i].moon.y, 5)
    })
  })
})

describe("the swarm in between", () => {
  it("is mid-flight halfway: some home, some flying, some waiting", () => {
    const half = at(0.5)
    expect(half.filter(pixel => pixel.day === 0).length).toBeGreaterThan(0)
    expect(half.filter(pixel => pixel.day > 0.02 && pixel.day < 0.98).length).toBeGreaterThan(0)
    expect(half.filter(pixel => pixel.day >= 0.98).length).toBeGreaterThan(0)
  })

  it("has come as far as the knob, all told", () => {
    for (let k = 1; k < 20; k++) {
      const p = k / 20
      const pixels = at(p)
      const come = pixels.reduce((sum, pixel) => sum + pixel.day, 0) / pixels.length
      expect(Math.abs(come - p)).toBeLessThan(0.06)
    }
  })

  it("only ever comes further as the knob moves towards day", () => {
    let last = -1
    for (let k = 0; k <= 200; k++) {
      const pixels = at(k / 200)
      const come = pixels.reduce((sum, pixel) => sum + pixel.day, 0) / pixels.length
      expect(come).toBeGreaterThanOrEqual(last - 0.02)
      last = come
    }
  })

  it("shrinks a pixel in flight and makes it whole again when it lands", () => {
    for (let k = 1; k < 100; k++) {
      for (const pixel of at(k / 100)) {
        expect(pixel.size).toBeLessThanOrEqual(1 + 1e-6)
        if (pixel.day > 0.3 && pixel.day < 0.7) expect(pixel.size).toBeLessThan(0.8)
      }
    }
  })
})

describe("departures", () => {
  it("are one each, in order clockwise from straight down", () => {
    const departures = departureOrder(PAIRS)
    expect([...departures].sort((a, b) => a - b)).toEqual(PAIRS.map((_, i) => i))
    const byTurn = PAIRS.map((pair, i) => ({rank: departures[i], fromBottom: wrapAngle(pair.moon.angle - Math.PI / 2)}))
      .sort((a, b) => a.rank - b.rank)
    for (let i = 1; i < byTurn.length; i++) expect(byTurn[i].fromBottom).toBeGreaterThanOrEqual(byTurn[i - 1].fromBottom)
  })

  it("set each pixel off no sooner than the one before it", () => {
    const steps = 600
    const leaves = new Array<number>(PAIRS.length).fill(Infinity)
    for (let k = 0; k <= steps; k++) {
      at(k / steps).forEach((pixel, i) => {
        const moved = Math.hypot(pixel.x - PAIRS[i].moon.x, pixel.y - PAIRS[i].moon.y) > 1e-4
        if (moved && leaves[i] === Infinity) leaves[i] = k
      })
    }
    const inOrder = PAIRS.map((_, i) => i).sort((a, b) => morph.departures[a] - morph.departures[b])
    for (let i = 1; i < inOrder.length; i++) expect(leaves[inOrder[i]]).toBeGreaterThanOrEqual(leaves[inOrder[i - 1]])
  })
})

describe("the swirl", () => {
  it("carries each pixel the short way round to its partner plus whole turns", () => {
    const steps = 800
    const turned = new Array<number>(PAIRS.length).fill(0)
    let last = at(0)
    for (let k = 1; k <= steps; k++) {
      const now = at(k / steps)
      now.forEach((pixel, i) => {
        turned[i] += turnBetween(Math.atan2(last[i].y, last[i].x), Math.atan2(pixel.y, pixel.x))
      })
      last = now
    }
    PAIRS.forEach((pair, i) => {
      // A pixel that starts or lands on the centre has no direction there.
      if (pair.moon.radius === 0 || pair.sun.radius === 0) return
      const expected = turnBetween(pair.moon.angle, pair.sun.angle) + SWIRL_TURNS * 2 * Math.PI
      expect(turned[i]).toBeCloseTo(expected, 3)
    })
  })
})
