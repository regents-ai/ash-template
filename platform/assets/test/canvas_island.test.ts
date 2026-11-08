// R-20261019-failed-start-lets-go: an island whose GPU never started kept every
// listener it had added, including whatever steered the picture, until the page
// left (found by the design lane in Keyfleet, 19 Oct).
import {afterEach, beforeEach, expect, it, vi} from "vitest"
import {createCanvasIsland, type IslandRenderer} from "../js/canvas_island"

const drawing: IslandRenderer = {
  resize() {},
  step: () => false,
  present() {},
  settled: async () => {},
  dispose() {},
}

let disconnected = 0
let visibilityListeners = 0

beforeEach(() => {
  disconnected = 0
  visibilityListeners = 0
  vi.stubGlobal("document", {
    hidden: false,
    addEventListener: () => void (visibilityListeners += 1),
    removeEventListener: () => void (visibilityListeners -= 1),
  })
  vi.stubGlobal("ResizeObserver", class {
    observe() {}
    disconnect() { disconnected += 1 }
  })
  // A canvas stub may carry the size its layout gives it; one without is not laid out.
  vi.stubGlobal("getComputedStyle", (element: {laidOut?: object}) => element.laidOut ?? {width: "auto", height: "auto"})
  vi.stubGlobal("IntersectionObserver", class {
    constructor(private seen: (entries: {isIntersecting: boolean}[]) => void) {}
    observe() { this.seen([{isIntersecting: true}]) }
    disconnect() { disconnected += 1 }
  })
})

afterEach(() => vi.unstubAllGlobals())

// An island on screen in a showing tab, its first frame handed out at once. It
// answers how often what steered the picture was let go, and the root's flag.
async function runIsland(
  load: (canvas: HTMLCanvasElement, size: readonly [number, number]) => Promise<IslandRenderer>,
  screen: {canvas?: object; devicePixelRatio?: number; maxDevicePixelRatio?: number} = {},
) {
  let released = 0
  const canvas = screen.canvas ?? {getBoundingClientRect: () => ({width: 300, height: 200})}
  const root = {dataset: {} as Record<string, string>, querySelector: () => canvas} as unknown as HTMLElement

  createCanvasIsland(root, {
    requestFrame: callback => { queueMicrotask(() => callback(0)); return 1 },
    cancelFrame() {},
    devicePixelRatio: () => screen.devicePixelRatio ?? 1,
    motionQuery: () => ({matches: false, addEventListener() {}, removeEventListener() {}}),
    supportsWebGpu: () => true,
    loadRenderer: load,
  }, {
    canvasSelector: "canvas",
    readyFlag: "ready",
    browserLoad: load,
    motionSensitive: false,
    continuous: false,
    maxDevicePixelRatio: screen.maxDevicePixelRatio,
    interact: () => () => void (released += 1),
  }).mount()

  for (let turn = 0; turn < 20; turn += 1) await Promise.resolve()
  return {released, ready: root.dataset.ready}
}

it("lets go of everything it watches with, once, when its GPU does not start", async () => {
  const {released, ready} = await runIsland(() => Promise.reject(new Error("no device")))
  expect(ready).toBe("false")
  expect(released).toBe(1)
  expect(disconnected).toBe(2)
  expect(visibilityListeners).toBe(0)
})

it("keeps hold of them while the picture draws", async () => {
  const {released, ready} = await runIsland(async () => drawing)
  expect(ready).toBe("true")
  expect(released).toBe(0)
  expect(visibilityListeners).toBe(1)
})

// Invariant: the backing store follows the canvas's own laid-out size, not what
// a transform on an ancestor makes of it (a menu scaling in as it opens), so the
// picture is not drawn a shade small and stretched. An island may ask for more
// of a sharp screen than the default ceiling.
it("sizes its backing store from the canvas's layout, under a transform", async () => {
  let size: readonly number[] = []
  const canvas = {laidOut: {width: "300px", height: "200px"}, getBoundingClientRect: () => ({width: 294, height: 196})}
  await runIsland(async (_, given) => ((size = given), drawing), {
    canvas,
    devicePixelRatio: 3,
    maxDevicePixelRatio: 3,
  })
  expect(size).toEqual([900, 600])
})

it("keeps to the default ceiling when an island does not ask for more", async () => {
  let size: readonly number[] = []
  await runIsland(async (_, given) => ((size = given), drawing), {devicePixelRatio: 3})
  expect(size).toEqual([450, 300])
})
