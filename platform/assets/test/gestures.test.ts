import {describe, expect, it} from "vitest"
import {GESTURE, dismisses, resist, velocity} from "../js/hooks/motion/gestures"

// A finger moving `speed` px/ms for `ms`, sampled every 16ms.
const moves = (speed: number, ms: number) =>
  Array.from({length: Math.floor(ms / 16) + 1}, (_, i) => ({t: i * 16, at: i * 16 * speed}))

describe("velocity", () => {
  it("measures px/ms over the last five moves only", () => {
    const slowThenFast = [...moves(0.01, 160), ...moves(1, 64).map(s => ({t: s.t + 176, at: s.at + 2}))]
    expect(velocity(slowThenFast)).toBeCloseTo(1, 5)
  })

  it("falls when the finger stops before it lifts", () => {
    const thrown = moves(0.5, 64)
    const last = thrown.at(-1)!
    const held = [...thrown, {t: last.t + 200, at: last.at}]
    expect(velocity(held)).toBeLessThan(0.5)
  })

  it("is nothing without two moves apart in time", () => {
    expect(velocity([])).toBe(0)
    expect(velocity([{t: 5, at: 40}])).toBe(0)
  })
})

describe("resist", () => {
  it("follows 1:1 toward where it leaves", () => {
    expect(resist(120, 1, GESTURE.edgeFriction.sheet)).toBe(120)
    expect(resist(-80, -1, GESTURE.edgeFriction.sheet)).toBe(-80)
    expect(resist(-50, 0, 0)).toBe(-50)
  })

  it("moves a fraction of the finger past the open edge", () => {
    expect(resist(-100, 1, GESTURE.edgeFriction.sheet)).toBeCloseTo(-15, 5)
    expect(resist(100, -1, GESTURE.edgeFriction.pan)).toBeCloseTo(50, 5)
  })
})

describe("dismisses", () => {
  const sheet = {threshold: 400 * GESTURE.sheetDismissFraction, leaves: 1 as const}

  it("a fast flick dismisses whatever the distance", () => {
    expect(dismisses({...sheet, offset: 12, speed: 0.6, heldMs: 120})).toBe(1)
  })

  it("a slow drag past the threshold dismisses", () => {
    expect(dismisses({...sheet, offset: 130, speed: 0.02, heldMs: 900})).toBe(1)
  })

  it("a short slow drag snaps back", () => {
    expect(dismisses({...sheet, offset: 40, speed: 0.02, heldMs: 900})).toBe(0)
  })

  it("a throw back toward open keeps it, however far it was pulled", () => {
    expect(dismisses({...sheet, offset: 300, speed: -0.5, heldMs: 400})).toBe(0)
  })

  it("a speed before minDragMs is not a throw", () => {
    expect(dismisses({...sheet, offset: 10, speed: 2, heldMs: GESTURE.minDragMs - 1})).toBe(0)
  })

  it("lands where the speed carries it for projectionMs", () => {
    // Just under the dismiss speed: 40px + 0.1 px/ms × 200ms = 60px, past a 50px threshold.
    expect(dismisses({threshold: 50, leaves: 1, offset: 40, speed: 0.1, heldMs: 300})).toBe(1)
    expect(dismisses({threshold: 70, leaves: 1, offset: 40, speed: 0.1, heldMs: 300})).toBe(0)
  })

  it("a note goes the way it was swiped, either way, at 30px or a throw", () => {
    const note = {threshold: GESTURE.toastDismissPx, leaves: 0 as const}
    expect(dismisses({...note, offset: -31, speed: 0, heldMs: 400})).toBe(-1)
    expect(dismisses({...note, offset: 31, speed: 0, heldMs: 400})).toBe(1)
    expect(dismisses({...note, offset: 20, speed: 0, heldMs: 400})).toBe(0)
    expect(dismisses({...note, offset: -5, speed: -0.2, heldMs: 150})).toBe(-1)
  })
})
