import {
  createCanvasIsland,
  type CanvasIslandController,
  type CanvasIslandOptions,
  type LoadRenderer,
} from "../canvas_island"
import type {HarbourLook, HarbourRenderer, HarbourStyle} from "../harbour/renderer"
import type {Agent} from "../harbour/sim"

export type HarbourController = CanvasIslandController & {
  /** Hands the crew and the style the page shows now to the harbour on screen. */
  sync(): void
}

const browserLoadHarbour: LoadRenderer<HarbourRenderer> = async (canvas, size, onDeviceLost) => {
  const {createHarbourRenderer} = await import("../harbour/renderer")
  return createHarbourRenderer(canvas, size, onDeviceLost)
}

/** The agents as the server wrote them: who, the place of their last action, and their colour. */
const crewOf = (root: HTMLElement): Agent[] => JSON.parse(root.dataset.harbourCrew!) as Agent[]

/** The art style the page asked for. */
const styleOf = (root: HTMLElement): HarbourStyle => root.dataset.harbourStyle as HarbourStyle

/** Dark unless the page or the device asks for light, the same reading as the theme switch. */
const lookOf = (root: HTMLElement, light: MediaQueryList): HarbourLook => {
  const theme = document.documentElement.dataset.theme
  return {
    night: theme ? theme === "dark" : !light.matches,
    haze: getComputedStyle(root).getPropertyValue("--harbour-haze").trim(),
  }
}

/**
 * The agent harbour: one ship for each agent, sailing to the island of its last
 * action and circling it.
 *
 * The sea always moves, so the harbour draws every frame while it is on screen.
 * A visitor who asked for less motion gets the harbour as one still picture,
 * redrawn only when an agent moves on or the theme changes. Without WebGPU
 * nothing is drawn, and the picture the server rendered stays.
 */
export const createHarbourController = (
  root: HTMLElement,
  options: CanvasIslandOptions<HarbourRenderer> = {},
): HarbourController => {
  let sync = () => {}

  const island = createCanvasIsland(root, options, {
    canvasSelector: "[data-harbour-canvas]",
    readyFlag: "harbourReady",
    browserLoad: browserLoadHarbour,
    motionSensitive: false,
    continuous: true,
    interact({renderer, nudge, onReady}) {
      const calm = (options.motionQuery ?? (() => window.matchMedia("(prefers-reduced-motion: reduce)")))()
      const light = window.matchMedia("(prefers-color-scheme: light)")
      const restyle = () => {
        renderer()?.setLook(lookOf(root, light))
        nudge()
      }
      const onCalmChange = () => {
        renderer()?.setCalm(calm.matches)
        nudge()
      }
      const themeObserver = new MutationObserver(restyle)

      onReady(() => {
        const harbour = renderer()!
        harbour.setCalm(calm.matches)
        harbour.setLook(lookOf(root, light))
        harbour.setStyle(styleOf(root))
        harbour.setAgents(crewOf(root))
      })
      sync = () => {
        renderer()?.setStyle(styleOf(root))
        renderer()?.setAgents(crewOf(root))
        nudge()
      }
      themeObserver.observe(document.documentElement, {attributes: true, attributeFilter: ["data-theme"]})
      light.addEventListener("change", restyle)
      calm.addEventListener("change", onCalmChange)

      return () => {
        sync = () => {}
        themeObserver.disconnect()
        light.removeEventListener("change", restyle)
        calm.removeEventListener("change", onCalmChange)
      }
    },
  })

  return {...island, sync: () => sync()}
}

type HarbourHook = {
  el: HTMLElement
  controller?: HarbourController
}

export const Harbour = {
  mounted(this: HarbourHook) {
    this.controller = createHarbourController(this.el)
    this.controller.mount()
  },
  updated(this: HarbourHook) {
    this.controller?.sync()
  },
  disconnected(this: HarbourHook) {
    this.controller?.pause()
  },
  reconnected(this: HarbourHook) {
    this.controller?.resume()
  },
  destroyed(this: HarbourHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
