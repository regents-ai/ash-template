// Invariant: pages closed together come back spread out. Every wait falls
// between half and all of its step, the first reconnect within half a second,
// and two pages that draw differently wait differently.
import {afterEach, describe, expect, it, vi} from "vitest"
import {reconnectAfterMs, rejoinAfterMs} from "../js/reconnect"

afterEach(() => vi.restoreAllMocks())

const drawing = (draw: number) => vi.spyOn(Math, "random").mockReturnValue(draw)

describe("reconnectAfterMs", () => {
  it("tries again within half a second the first time", () => {
    drawing(0)
    expect(reconnectAfterMs(1)).toBe(250)
    drawing(0.999999)
    expect(reconnectAfterMs(1)).toBeLessThan(500)
  })

  it("keeps every wait between half and all of its step, up to five seconds", () => {
    const steps = [500, 1000, 2000, 5000, 5000, 5000]

    steps.forEach((step, index) => {
      for (const draw of [0, 0.25, 0.5, 0.75, 0.999999]) {
        drawing(draw)
        const wait = reconnectAfterMs(index + 1)
        expect(wait).toBeGreaterThanOrEqual(step / 2)
        expect(wait).toBeLessThan(step)
      }
    })
  })

  it("spreads pages that draw differently", () => {
    drawing(0.1)
    const first = reconnectAfterMs(1)
    drawing(0.9)
    expect(reconnectAfterMs(1) - first).toBe(200)
  })
})

describe("rejoinAfterMs", () => {
  it("keeps every wait between half and all of its step, up to ten seconds", () => {
    const steps = [1000, 2000, 5000, 10000, 10000]

    steps.forEach((step, index) => {
      for (const draw of [0, 0.5, 0.999999]) {
        drawing(draw)
        const wait = rejoinAfterMs(index + 1)
        expect(wait).toBeGreaterThanOrEqual(step / 2)
        expect(wait).toBeLessThan(step)
      }
    })
  })
})
