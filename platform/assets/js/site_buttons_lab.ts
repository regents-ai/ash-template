/** Lab-only: each site's main button with the template's motion. The page owns every state. */
import {createCanvasIsland, type CanvasIslandController} from "./canvas_island"
import {still} from "./hooks/motion/shared"
import type {LightAim, LightRenderer, Rgb} from "./site_buttons_light"

type ButtonsHook = {el: HTMLElement; release?: () => void}

/** The site's motion kit plays every press and hover. This only notes whether the last input was
 *  a pointer or a key, which the stylesheet reads to swap a key press's words at once. */
export const LabSiteButtons = {
  mounted(this: ButtonsHook) {
    const root = this.el
    const events = new AbortController()
    root.addEventListener("pointerdown", () => { root.dataset.input = "pointer" }, {signal: events.signal})
    root.addEventListener("keydown", () => { root.dataset.input = "key" }, {signal: events.signal})
    this.release = () => events.abort()
  },
  destroyed(this: ButtonsHook) { this.release?.() },
}

// How bright the light sits for each state of the button, and how much a pointer over the frame adds.
const GLOW: Record<string, number> = {idle: .4, wait0: .75, wait1: .75, done: .55}
const HOVER_GLOW = .25

let probe: CanvasRenderingContext2D | null | undefined

/** Any colour the stylesheet computes, as the three channels the shader takes. */
const rgb = (color: string): Rgb => {
  probe ??= Object.assign(document.createElement("canvas"), {width: 1, height: 1}).getContext("2d", {willReadFrequently: true})
  if (!probe) return [0, 0, 0]
  probe.clearRect(0, 0, 1, 1)
  probe.fillStyle = "#000"
  probe.fillStyle = color
  probe.fillRect(0, 0, 1, 1)
  const [r, g, b] = probe.getImageData(0, 0, 1, 1).data
  return [r / 255, g / 255, b / 255]
}

type LightHook = {el: HTMLElement; controller?: CanvasIslandController; sync?: () => void; release?: () => void}

/** The VGPU light behind one site's button: it follows the pointer over the frame and the button's
 *  state, then stops drawing. The still face underneath is what shows until a frame lands. */
export const LabSiteLight = {
  mounted(this: LightHook) {
    const root = this.el
    const stage = root.parentElement!
    const button = () => stage.querySelector<HTMLElement>(".sb-button")
    let pointer: {x: number; y: number} | null = null

    const aim = (): LightAim => {
      const box = root.getBoundingClientRect()
      const state = root.dataset.state ?? "idle"
      const glow = GLOW[state] ?? GLOW.idle
      if (pointer) return {x: pointer.x, y: pointer.y, glow: glow + HOVER_GLOW}
      const at = button()?.getBoundingClientRect()
      if (!at || box.width === 0 || box.height === 0) return {x: .5, y: .5, glow}
      return {x: (at.left + at.width / 2 - box.left) / box.width, y: (at.top + at.height / 2 - box.top) / box.height, glow}
    }

    this.controller = createCanvasIsland<LightRenderer>(root, {}, {
      canvasSelector: "[data-light-canvas]",
      readyFlag: "lightReady",
      motionSensitive: true,
      // The light moves only when the pointer or the button's state does.
      continuous: false,
      browserLoad: async (canvas, size, lost) => {
        const {createLightRenderer} = await import("./site_buttons_light")
        return createLightRenderer(canvas, size, lost)
      },
      interact: ({renderer, nudge, onReady}) => {
        // Colours are read when they can change (a new renderer, the theme, the button's state),
        // never per pointer move; the shader is only written what changed.
        const paint = () => {
          const style = getComputedStyle(root)
          renderer()?.colors(rgb(style.backgroundColor), rgb(style.color))
        }
        const sync = (jump = false) => {
          renderer()?.aim(aim(), jump)
          nudge()
        }
        const keyed = () => root.closest<HTMLElement>("[data-input]")?.dataset.input === "key"
        const events = new AbortController()
        const options = {signal: events.signal}
        stage.addEventListener("pointermove", event => {
          if (event.pointerType !== "mouse") return
          const box = root.getBoundingClientRect()
          pointer = {x: (event.clientX - box.left) / box.width, y: (event.clientY - box.top) / box.height}
          sync()
        }, options)
        stage.addEventListener("pointerleave", () => { pointer = null; sync() }, options)
        stage.addEventListener("focusin", () => sync(keyed()), options)
        // A theme switch repaints the ground at once; only the light itself eases.
        const repaint = () => { paint(); sync(true) }
        const theme = new MutationObserver(repaint)
        theme.observe(document.documentElement, {attributes: true, attributeFilter: ["data-theme"]})
        const scheme = matchMedia("(prefers-color-scheme: dark)")
        scheme.addEventListener("change", repaint)
        this.sync = () => { paint(); sync(keyed()) }
        onReady(repaint)
        return () => {
          events.abort()
          theme.disconnect()
          scheme.removeEventListener("change", repaint)
          this.sync = undefined
        }
      },
    })
    this.controller.mount()
    const lab = root.closest(".motion-lab")
    const syncMotion = () => {
      if (still(root) || matchMedia("(forced-colors: active)").matches) this.controller?.pause()
      else this.controller?.resume()
    }
    const observer = new MutationObserver(syncMotion)
    if (lab) observer.observe(lab, {attributes: true, attributeFilter: ["data-motion"]})
    const colors = matchMedia("(forced-colors: active)")
    colors.addEventListener("change", syncMotion)
    this.release = () => { observer.disconnect(); colors.removeEventListener("change", syncMotion) }
    syncMotion()
  },
  updated(this: LightHook) { this.sync?.() },
  disconnected(this: LightHook) { this.controller?.pause() },
  reconnected(this: LightHook) { if (!still(this.el) && !matchMedia("(forced-colors: active)").matches) this.controller?.resume() },
  destroyed(this: LightHook) { this.release?.(); this.controller?.destroy() },
}

export const hooks = {LabSiteButtons, LabSiteLight}
