import {
  createCanvasIsland,
  type CanvasIslandController,
  type CanvasIslandOptions,
  type LoadRenderer,
} from "../canvas_island"
import type {HarbourLook, HarbourRenderer} from "../harbour/renderer"
import type {Agent} from "../harbour/sim"

export type HarbourController = CanvasIslandController & {
  /** Hands the crew the page shows now to the harbour on screen. */
  sync(): void
}

const browserLoadHarbour: LoadRenderer<HarbourRenderer> = async (canvas, size, onDeviceLost) => {
  const {createHarbourRenderer} = await import("../harbour/renderer")
  return createHarbourRenderer(canvas, size, onDeviceLost)
}

/** One agent as the server wrote it, with the name its ship shows under the pointer. */
type CrewMember = Agent & {readonly name: string}

/** The agents as the server wrote them: who, the place of their last action, and their colour. */
const crewOf = (root: HTMLElement): CrewMember[] => JSON.parse(root.dataset.harbourCrew!) as CrewMember[]

/** Space kept between the name tag and the harbour's sides, in pixels. */
const TAG_MARGIN = 4

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
 *
 * A mouse over a ship shows its agent's name above it. Pressing a ship hands
 * its agent to `open`; pressing the sea starts a ripple there.
 */
export const createHarbourController = (
  root: HTMLElement,
  open: (agentId: string) => void,
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
      const canvas = root.querySelector<HTMLCanvasElement>("[data-harbour-canvas]")!
      const tag = root.querySelector<HTMLElement>("[data-harbour-tag]")!
      let crew = crewOf(root)

      const pointOf = (event: MouseEvent): [number, number] => {
        const box = canvas.getBoundingClientRect()
        return [(event.clientX - box.left) / box.width, (event.clientY - box.top) / box.height]
      }
      const hideTag = () => {
        tag.hidden = true
        canvas.style.cursor = ""
      }
      const onPointerMove = (event: PointerEvent) => {
        if (event.pointerType !== "mouse") return
        const ship = renderer()?.shipAt(...pointOf(event))
        if (!ship) return hideTag()
        const agent = crew.find(member => member.id === ship.id)!
        tag.textContent = agent.name
        tag.style.setProperty("--sail", agent.color)
        tag.hidden = false
        const box = root.getBoundingClientRect()
        const half = tag.offsetWidth / 2
        const x = Math.min(Math.max(ship.u * box.width, half + TAG_MARGIN), box.width - half - TAG_MARGIN)
        tag.style.translate = `${x}px ${ship.v * box.height}px`
        canvas.style.cursor = "pointer"
      }
      const onClick = (event: MouseEvent) => {
        const harbour = renderer()
        if (!harbour) return
        const [u, v] = pointOf(event)
        const ship = harbour.shipAt(u, v)
        if (!ship) return harbour.ripple(u, v)
        hideTag()
        open(ship.id)
      }

      onReady(() => {
        const harbour = renderer()!
        harbour.setCalm(calm.matches)
        harbour.setLook(lookOf(root, light))
        harbour.setAgents(crew)
      })
      sync = () => {
        crew = crewOf(root)
        renderer()?.setAgents(crew)
        nudge()
      }
      themeObserver.observe(document.documentElement, {attributes: true, attributeFilter: ["data-theme"]})
      light.addEventListener("change", restyle)
      calm.addEventListener("change", onCalmChange)
      canvas.addEventListener("pointermove", onPointerMove)
      canvas.addEventListener("pointerleave", hideTag)
      canvas.addEventListener("click", onClick)

      return () => {
        sync = () => {}
        themeObserver.disconnect()
        light.removeEventListener("change", restyle)
        calm.removeEventListener("change", onCalmChange)
        canvas.removeEventListener("pointermove", onPointerMove)
        canvas.removeEventListener("pointerleave", hideTag)
        canvas.removeEventListener("click", onClick)
      }
    },
  })

  return {...island, sync: () => sync()}
}

type HarbourHook = {
  el: HTMLElement
  controller?: HarbourController
  pushEvent(event: string, payload: object): void
}

export const Harbour = {
  mounted(this: HarbourHook) {
    this.controller = createHarbourController(this.el, agentId => this.pushEvent("show_agent", {id: agentId}))
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
