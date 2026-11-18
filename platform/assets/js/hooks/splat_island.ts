/**
 * A splat scene's box (`AshTemplateWeb.Components.SplatStage.stage/1`, on the Splats
 * page, the Scenes page and each scene's own page): one canvas island over the still
 * picture the server sends, drawing the scene baked in the file the box names
 * (`data-splats-file`) in 3D splats once WebGPU is there (`splats/renderer.ts`, loaded
 * only when the box is on screen; the still shows while the file downloads). Each scene
 * is its own box, so choosing another one ends this island, and its GPU device, before
 * the next begins.
 *
 * A mouse or pen dragged across the box turns the scene under it, and dragged up or
 * down tilts the view over it or under it. On a touch screen a sideways swipe turns
 * it and an up or down swipe scrolls the page, so tilting there is the keyboard's.
 * Focused, the left and right arrow keys turn it and the up and down keys tilt it.
 *
 * A pinch on a trackpad, or a wheel turned with Ctrl or Cmd held, zooms at the
 * pointer; a plain wheel scrolls the page. Two fingers on a touch screen pinch at
 * their midpoint until both have lifted. Focused, + (or =) zooms in, - out and 0 goes
 * back to the opening view, as a double-click or a double tap does. The box's three
 * buttons, `button[data-splats-zoom="in"]`, `"out"` and `"home"` (Zoom in, Zoom out,
 * Reset view), step the same way; each is `aria-disabled="true"` while it has nothing
 * left to do, and a press or drag on one is the button's alone, never the scene's.
 *
 * With less motion asked for, by the device or by a Less motion switch round the
 * page, it holds still unless moved. Without WebGPU the still picture stays.
 *
 * `rendererOf(box)` hands what draws a box to a page's Download GIF (`splat_gif.ts`).
 */
import {createCanvasIsland} from "../canvas_island"
import type {SplatRenderer, ZoomAction} from "../splats/renderer"
import {still} from "./motion/shared"

/** How far back a release looks to measure the pointer's speed (milliseconds). */
const RELEASE_WINDOW = 100
/** A trackpad's pinch, or a wheel with Ctrl or Cmd, zooms e times nearer for every this many pixels it scrolls up. */
const WHEEL_PIXELS = 100
/** The most one wheel event zooms, in its pixels: about one press of Zoom in, so a mouse wheel's notch is a step. */
const WHEEL_MOST = 35
const ZOOM_ACTIONS: readonly ZoomAction[] = ["in", "out", "home"]
const ZOOM_KEYS: Readonly<Record<string, ZoomAction>> = {"+": "in", "=": "in", "-": "out", "0": "home"}

/** Each mounted box's renderer, while it has one. */
const drawing = new WeakMap<HTMLElement, () => SplatRenderer | undefined>()

/** The renderer drawing in a box, once its scene has drawn; undefined before then, or with no island there. */
export const rendererOf = (root: HTMLElement) => drawing.get(root)?.()

export function createSplatIsland(root: HTMLElement) {
  // The server names the file the scene is baked into.
  const file = root.dataset.splatsFile!
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
      return createSplatRenderer(view, size, lost, file)
    },
    interact: island => {
      const events = new AbortController()
      const listen = <K extends keyof HTMLElementEventMap>(type: K, listener: (event: HTMLElementEventMap[K]) => void) =>
        root.addEventListener(type, listener, {signal: events.signal})
      type Point = {at: number; x: number; y: number}
      // A touch only turns the scene: its up and down belong to the page's scroll.
      let held: {id: number; tilts: boolean; last: Point; trail: Point[]} | undefined
      // Two fingers pinching, where each is now; the one left after the other lifts does nothing.
      let pinch: Map<number, {x: number; y: number}> | undefined
      const buttons = ZOOM_ACTIONS.map(action => [action, root.querySelector<HTMLButtonElement>(`button[data-splats-zoom="${action}"]`)!] as const)

      // Each button says whether it has anything left to do.
      const refresh = () => {
        const limits = island.renderer()?.limits()
        if (!limits) return
        for (const [action, button] of buttons) {
          const disabled = String(limits[action])
          if (button.getAttribute("aria-disabled") !== disabled) button.setAttribute("aria-disabled", disabled)
        }
      }
      const moved = () => {
        island.nudge()
        refresh()
      }
      // A press on a button in the box is the button's alone.
      const onButton = (event: Event) => event.target instanceof Element && event.target.closest("button") !== null
      // A point on the screen as shares of the stage's width and height from its top left.
      const onStage = (x: number, y: number) => {
        const {left, top, width, height} = island.canvas().getBoundingClientRect()
        return [(x - left) / width, (y - top) / height] as const
      }

      const letGo = (event: PointerEvent) => {
        if (pinch) {
          if (!pinch.delete(event.pointerId) || pinch.size > 0) return
          pinch = undefined
          held = undefined
          island.renderer()?.release(0, 0)
          moved()
          return
        }
        if (!held || event.pointerId !== held.id) return
        const recent = held.trail.filter(point => event.timeStamp - point.at <= RELEASE_WINDOW)
        const first = recent[0]
        const last = recent.at(-1)
        const speed = (axis: "x" | "y") => (first && last && last.at > first.at ? ((last[axis] - first[axis]) / (last.at - first.at)) * 1000 : 0)
        const down = held.tilts ? speed("y") : 0
        held = undefined
        island.renderer()?.release(speed("x"), down)
        moved()
      }

      listen("pointerdown", event => {
        const renderer = island.renderer()
        if (!renderer || pinch || onButton(event)) return
        // A second finger on a touch screen turns the touch into a pinch.
        if (held && !held.tilts && event.pointerType === "touch") {
          root.setPointerCapture(event.pointerId)
          pinch = new Map([
            [held.id, {x: held.last.x, y: held.last.y}],
            [event.pointerId, {x: event.clientX, y: event.clientY}],
          ])
          return
        }
        // One pointer turns the island.
        if (held || !event.isPrimary || event.button !== 0) return
        root.setPointerCapture(event.pointerId)
        const point = {at: event.timeStamp, x: event.clientX, y: event.clientY}
        held = {id: event.pointerId, tilts: event.pointerType !== "touch", last: point, trail: [point]}
        renderer.grab()
        moved()
      })
      listen("pointermove", event => {
        if (pinch) {
          const before = [...pinch.values()]
          if (before.length < 2 || !pinch.has(event.pointerId)) return
          pinch.set(event.pointerId, {x: event.clientX, y: event.clientY})
          const [a, b] = [...pinch.values()] as [{x: number; y: number}, {x: number; y: number}]
          const gap = Math.hypot(a.x - b.x, a.y - b.y)
          const was = Math.hypot(before[0]!.x - before[1]!.x, before[0]!.y - before[1]!.y)
          if (gap > 0 && was > 0) island.renderer()?.zoomAt(gap / was, ...onStage((a.x + b.x) / 2, (a.y + b.y) / 2))
          moved()
          return
        }
        if (!held || event.pointerId !== held.id) return
        const point = {at: event.timeStamp, x: event.clientX, y: event.clientY}
        const across = point.x - held.last.x
        const down = held.tilts ? point.y - held.last.y : 0
        held.last = point
        held.trail.push(point)
        held.trail = held.trail.filter(p => event.timeStamp - p.at <= RELEASE_WINDOW)
        island.renderer()?.drag(across, down)
        moved()
      })
      listen("pointerup", letGo)
      listen("pointercancel", letGo)
      listen("lostpointercapture", letGo)
      root.addEventListener(
        "wheel",
        event => {
          const renderer = island.renderer()
          if (!renderer || !(event.ctrlKey || event.metaKey)) return
          // Not the page's zoom: the scene's.
          event.preventDefault()
          // A wheel that counts in lines or pages turns a notch at a time.
          const pixels = event.deltaMode === WheelEvent.DOM_DELTA_PIXEL ? event.deltaY : Math.sign(event.deltaY) * WHEEL_MOST
          renderer.zoomAt(Math.exp(-Math.max(-WHEEL_MOST, Math.min(WHEEL_MOST, pixels)) / WHEEL_PIXELS), ...onStage(event.clientX, event.clientY))
          moved()
        },
        {passive: false, signal: events.signal},
      )
      listen("dblclick", event => {
        const renderer = island.renderer()
        if (!renderer || onButton(event)) return
        renderer.zoom("home")
        moved()
      })
      listen("keydown", event => {
        const renderer = island.renderer()
        if (!renderer) return
        const turn = event.key === "ArrowRight" ? 1 : event.key === "ArrowLeft" ? -1 : 0
        const tilt = event.key === "ArrowUp" ? 1 : event.key === "ArrowDown" ? -1 : 0
        // Ctrl or Cmd with + - 0 is the browser's own zoom.
        const zoom = event.ctrlKey || event.metaKey || event.altKey ? undefined : ZOOM_KEYS[event.key]
        if (turn || tilt) renderer.press(turn, tilt)
        else if (zoom) renderer.zoom(zoom)
        else return
        event.preventDefault()
        moved()
      })
      for (const [action, button] of buttons)
        button.addEventListener(
          "click",
          () => {
            const renderer = island.renderer()
            if (!renderer || button.getAttribute("aria-disabled") === "true") return
            renderer.zoom(action)
            moved()
          },
          {signal: events.signal},
        )

      hold = () => {
        island.renderer()?.hold(calm)
        moved()
      }
      island.onReady(() => {
        island.renderer()!.hold(calm)
        refresh()
      })
      drawing.set(root, island.renderer)
      return () => {
        events.abort()
        drawing.delete(root)
        held = undefined
        pinch = undefined
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
