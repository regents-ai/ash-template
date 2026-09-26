import {afterEach, beforeEach, expect, it, vi} from "vitest"

// The moves themselves are Anime.js's; these tests hold the rules around them:
// who gets to move, that a press is never held up by its motion, and that a
// move begun over another still ends at rest.
const moved = vi.hoisted(() => ({squish: [] as unknown[], nope: [] as unknown[]}))

vi.mock("../js/hooks/motion/press", () => ({
  squish: (el: unknown) => moved.squish.push(el),
  nope: (el: unknown) => moved.nope.push(el),
  deny: vi.fn(),
}))

vi.mock("animejs", async original => ({
  ...(await original<typeof import("animejs")>()),
  animate: () => ({revert: vi.fn()}),
}))

import {press} from "../js/motion"
import {play} from "../js/hooks/motion/shared"

class FakeElement {
  label = {label: true}
  constructor(private attrs: Record<string, string> = {}, private wallet = false) {}
  closest(selector: string) {
    return selector.includes("data-motion='reduced'") ? null : this
  }
  getAttribute(name: string) {
    return this.attrs[name] ?? null
  }
  querySelector(selector: string) {
    return selector === "[data-press-label]" && this.wallet ? this.label : null
  }
}

let lessMotion = false

beforeEach(() => {
  lessMotion = false
  vi.stubGlobal("Element", FakeElement)
  vi.stubGlobal("matchMedia", () => ({matches: lessMotion}))
})

afterEach(() => {
  vi.unstubAllGlobals()
  moved.squish.length = moved.nope.length = 0
})

// A click from a pointer reports how many presses made it; Enter and Space report none.
function click(target: unknown, detail: number) {
  return {target, detail, preventDefault: vi.fn(), stopPropagation: vi.fn()} as unknown as MouseEvent & {
    preventDefault: ReturnType<typeof vi.fn>
    stopPropagation: ReturnType<typeof vi.fn>
  }
}

it("a wallet button's press is never held up: nothing stops it and only its label squishes", () => {
  const button = new FakeElement({}, true)
  const first = click(button, 1)
  const second = click(button, 2)

  press(first)
  press(second)

  expect(moved.squish).toEqual([button.label, button.label])
  for (const event of [first, second]) {
    expect(event.preventDefault).not.toHaveBeenCalled()
    expect(event.stopPropagation).not.toHaveBeenCalled()
  }
})

it("a keyboard press answers at once, without a squish", () => {
  press(click(new FakeElement(), 0))
  expect(moved.squish).toEqual([])
})

it("a reader who asked for less motion sees no squish", () => {
  lessMotion = true
  press(click(new FakeElement(), 1))
  expect(moved.squish).toEqual([])
})

it("a control that cannot be used yet shakes instead of squishing", () => {
  const button = new FakeElement({"aria-disabled": "true"})
  press(click(button, 1))
  expect(moved.nope).toEqual([button])
  expect(moved.squish).toEqual([])
})

// Anime.js tidies up by restoring the style it found when a move began, so a
// move begun over another's half-way frame would end stuck on that frame.
it("a move begun over another first puts the element back at rest", () => {
  const card = new FakeElement() as unknown as Element
  const first = play(card, {opacity: [0, 1]})
  play(card, {opacity: [0, 1]})
  expect(first.revert).toHaveBeenCalledOnce()
})
