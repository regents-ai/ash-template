/**
 * The splats page's island (`AshTemplateWeb.SplatsLabLive`): one canvas island over
 * the still picture the server sends, drawing the floating island in 3D splats once
 * WebGPU is there (`splats/renderer.ts`, loaded only when the box is on screen).
 *
 * A drag across the box turns the island under the pointer; a vertical drag on a
 * phone still scrolls the page. Focused, the left and right arrow keys turn it. With
 * less motion asked for, by the device or by a Less motion switch round the page, it
 * holds still unless dragged. Without WebGPU the still picture stays.
 */
import {createCanvasIsland} from "../canvas_island"
import type {SplatRenderer} from "../splats/renderer"
import {still} from "./motion/shared"

/** How far back a release looks to measure the pointer's speed (milliseconds). */
const RELEASE_WINDOW = 100

export function createSplatIsland(root: HTMLElement) {
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
      return createSplatRenderer(view, size, lost)
    },
    interact: island => {
      const events = new AbortController()
      const listen = <K extends keyof HTMLElementEventMap>(type: K, listener: (event: HTMLElementEventMap[K]) => void) =>
        root.addEventListener(type, listener, {signal: events.signal})
      let held: {id: number; x: number; trail: {at: number; x: number}[]} | undefined

      const letGo = (event: PointerEvent) => {
        if (!held || event.pointerId !== held.id) return
        const recent = held.trail.filter(point => event.timeStamp - point.at <= RELEASE_WINDOW)
        const first = recent[0]
        const last = recent.at(-1)
        const speed = first && last && last.at > first.at ? ((last.x - first.x) / (last.at - first.at)) * 1000 : 0
        held = undefined
        island.renderer()?.release(speed)
        island.nudge()
      }

      listen("pointerdown", event => {
        const renderer = island.renderer()
        // One pointer turns the island; a second finger changes nothing.
        if (held || !renderer || !event.isPrimary || event.button !== 0) return
        root.setPointerCapture(event.pointerId)
        held = {id: event.pointerId, x: event.clientX, trail: [{at: event.timeStamp, x: event.clientX}]}
        renderer.grab()
        island.nudge()
      })
      listen("pointermove", event => {
        if (!held || event.pointerId !== held.id) return
        const pixels = event.clientX - held.x
        held.x = event.clientX
        held.trail.push({at: event.timeStamp, x: event.clientX})
        held.trail = held.trail.filter(point => event.timeStamp - point.at <= RELEASE_WINDOW)
        island.renderer()?.drag(pixels)
        island.nudge()
      })
      listen("pointerup", letGo)
      listen("pointercancel", letGo)
      listen("lostpointercapture", letGo)
      listen("keydown", event => {
        const direction = event.key === "ArrowRight" ? 1 : event.key === "ArrowLeft" ? -1 : 0
        const renderer = island.renderer()
        if (!direction || !renderer) return
        event.preventDefault()
        renderer.press(direction)
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
