/**
 * The splats page's picture (`AshTemplateWeb.SplatsLabLive`): one canvas island over
 * the still picture the server sends, drawing the scene the box names
 * (`data-splats-scene`) in 3D splats once WebGPU is there (`splats/renderer.ts`,
 * loaded only when the box is on screen). Each scene is its own box, so choosing the
 * other one ends this island, and its GPU device, before the next begins.
 *
 * A mouse or pen dragged across the box turns the scene under it, and dragged up or
 * down tilts the view over it or under it. On a touch screen a sideways swipe turns
 * it and an up or down swipe scrolls the page, so tilting there is the keyboard's.
 * Focused, the left and right arrow keys turn it and the up and down keys tilt it.
 * With less motion asked for, by the device or by a Less motion switch round the
 * page, it holds still unless moved. Without WebGPU the still picture stays.
 */
import {createCanvasIsland} from "../canvas_island"
import type {SceneName, SplatRenderer} from "../splats/renderer"
import {still} from "./motion/shared"

/** How far back a release looks to measure the pointer's speed (milliseconds). */
const RELEASE_WINDOW = 100

export function createSplatIsland(root: HTMLElement) {
  // The server names one of the scenes the renderer grows.
  const scene = root.dataset.splatsScene as SceneName
  let calm = still(root)
  // Holds the island still or lets it turn, once it is drawing.
  let hold = () => {}

  const island = createCanvasIsland<SplatRenderer>(root, {}, {
    canvasSelector: "[data-splats-canvas]",
    readyFlag: "splatsReady",
    // Less motion still gets the island, held still.
    motionSensitive: false,
    continuous: true,
    // Every picture pixel a square of whole device pixels, on every screen.
    maxDevicePixelRatio: 3,
    maxDrawingBufferPixels: 5_000_000,
    browserLoad: async (view, size, lost) => {
      const {createSplatRenderer} = await import("../splats/renderer")
      return createSplatRenderer(view, size, lost, scene)
    },
    interact: island => {
      const events = new AbortController()
      const listen = <K extends keyof HTMLElementEventMap>(type: K, listener: (event: HTMLElementEventMap[K]) => void) =>
        root.addEventListener(type, listener, {signal: events.signal})
      type Point = {at: number; x: number; y: number}
      // A touch only turns the scene: its up and down belong to the page's scroll.
      let held: {id: number; tilts: boolean; last: Point; trail: Point[]} | undefined

      const letGo = (event: PointerEvent) => {
        if (!held || event.pointerId !== held.id) return
        const recent = held.trail.filter(point => event.timeStamp - point.at <= RELEASE_WINDOW)
        const first = recent[0]
        const last = recent.at(-1)
        const speed = (axis: "x" | "y") => (first && last && last.at > first.at ? ((last[axis] - first[axis]) / (last.at - first.at)) * 1000 : 0)
        const down = held.tilts ? speed("y") : 0
        held = undefined
        island.renderer()?.release(speed("x"), down)
        island.nudge()
      }

      listen("pointerdown", event => {
        const renderer = island.renderer()
        // One pointer turns the island; a second finger changes nothing.
        if (held || !renderer || !event.isPrimary || event.button !== 0) return
        root.setPointerCapture(event.pointerId)
        const point = {at: event.timeStamp, x: event.clientX, y: event.clientY}
        held = {id: event.pointerId, tilts: event.pointerType !== "touch", last: point, trail: [point]}
        renderer.grab()
        island.nudge()
      })
      listen("pointermove", event => {
        if (!held || event.pointerId !== held.id) return
        const point = {at: event.timeStamp, x: event.clientX, y: event.clientY}
        const across = point.x - held.last.x
        const down = held.tilts ? point.y - held.last.y : 0
        held.last = point
        held.trail.push(point)
        held.trail = held.trail.filter(p => event.timeStamp - p.at <= RELEASE_WINDOW)
        island.renderer()?.drag(across, down)
        island.nudge()
      })
      listen("pointerup", letGo)
      listen("pointercancel", letGo)
      listen("lostpointercapture", letGo)
      listen("keydown", event => {
        const turn = event.key === "ArrowRight" ? 1 : event.key === "ArrowLeft" ? -1 : 0
        const tilt = event.key === "ArrowUp" ? 1 : event.key === "ArrowDown" ? -1 : 0
        const renderer = island.renderer()
        if ((!turn && !tilt) || !renderer) return
        event.preventDefault()
        renderer.press(turn, tilt)
        island.nudge()
      })

      hold = () => {
        island.renderer()?.hold(calm)
        island.nudge()
      }
      island.onReady(() => island.renderer()!.hold(calm))
      return () => {
        events.abort()
        held = undefined
        hold = () => {}
      }
    },
  })

  const syncCalm = () => {
    calm = still(root)
    hold()
  }
  const reduced = matchMedia("(prefers-reduced-motion: reduce)")
  const calmSwitch = new MutationObserver(syncCalm)
  const events = new AbortController()

  return {
    mount() {
      calmSwitch.observe(document.documentElement, {subtree: true, attributes: true, attributeFilter: ["data-motion"]})
      reduced.addEventListener("change", syncCalm, {signal: events.signal})
      island.mount()
    },
    pause() {
      island.pause()
    },
    resume() {
      island.resume()
    },
    destroy() {
      events.abort()
      calmSwitch.disconnect()
      island.destroy()
    },
  }
}

type SplatIslandHook = {el: HTMLElement; controller?: ReturnType<typeof createSplatIsland>}

export const SplatIsland = {
  mounted(this: SplatIslandHook) {
    this.controller = createSplatIsland(this.el)
    this.controller.mount()
  },
  disconnected(this: SplatIslandHook) {
    this.controller?.pause()
  },
  reconnected(this: SplatIslandHook) {
    this.controller?.resume()
  },
  destroyed(this: SplatIslandHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
