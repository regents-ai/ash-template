import {
  createCanvasIsland,
  type CanvasIslandController,
  type CanvasIslandOptions,
  type LoadRenderer,
} from "../canvas_island"
import type {HarbourLook, HarbourRenderer, HarbourView} from "../harbour/renderer"
import type {Agent, Place} from "../harbour/sim"

export type HarbourController = CanvasIslandController & {
  /** Hands the crew the page shows now to the harbour on screen. */
  sync(): void
}

/** The harbour in the view the server named on its root. */
const browserLoadHarbour =
  (view: HarbourView): LoadRenderer<HarbourRenderer> =>
  async (canvas, size, onDeviceLost) => {
    const {createHarbourRenderer} = await import("../harbour/renderer")
    return createHarbourRenderer(canvas, size, onDeviceLost, view)
  }

/** One agent as the server wrote it, with the name its ship shows under the pointer. */
type CrewMember = Agent & {readonly name: string}

/** The agents as the server wrote them: who, the place of their last action, and their colour. */
const crewOf = (root: HTMLElement): CrewMember[] => JSON.parse(root.dataset.harbourCrew!) as CrewMember[]

/** Space kept between a tag or an island's card and the harbour's sides, in pixels. */
const TAG_MARGIN = 4

/** How long an island's card stays after the mouse leaves the island, so it can reach the link, in milliseconds. */
const ISLE_LINGER = 300

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
 * A mouse over a ship shows its agent's name above it, and a mouse over an
 * island shows a card above its buildings with the link to the island's page.
 * Pressing a ship hands its agent to `open`, pressing an island follows its
 * link, and pressing the sea starts a ripple there.
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
    browserLoad: browserLoadHarbour(root.dataset.harbourView as HarbourView),
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
      const stage = root.querySelector<HTMLElement>("[data-harbour-stage]")!
      const canvas = root.querySelector<HTMLCanvasElement>("[data-harbour-canvas]")!
      const tag = root.querySelector<HTMLElement>("[data-harbour-tag]")!
      const isles = new Map(
        [...root.querySelectorAll<HTMLAnchorElement>("[data-harbour-isle]")].map(link => [
          link.dataset.harbourIsle as Place,
          link,
        ]),
      )
      let crew = crewOf(root)
      let leaving: number | undefined

      const pointOf = (event: MouseEvent): [number, number] => {
        const box = canvas.getBoundingClientRect()
        return [(event.clientX - box.left) / box.width, (event.clientY - box.top) / box.height]
      }
      /** Stands a tag or card on a point of the canvas, kept inside the harbour. */
      const standAt = (label: HTMLElement, u: number, v: number) => {
        label.hidden = false
        const box = root.getBoundingClientRect()
        const half = label.offsetWidth / 2
        const x = Math.min(Math.max(u * box.width, half + TAG_MARGIN), box.width - half - TAG_MARGIN)
        const y = Math.max(v * box.height, label.offsetHeight + TAG_MARGIN * 2)
        label.style.translate = `${x}px ${y}px`
      }
      const hideTag = () => {
        tag.hidden = true
      }
      const hideIsles = () => {
        window.clearTimeout(leaving)
        leaving = undefined
        for (const link of isles.values()) link.hidden = true
      }
      const leaveIsles = () => {
        leaving ??= window.setTimeout(hideIsles, ISLE_LINGER)
      }
      const onPointerMove = (event: PointerEvent) => {
        if (event.pointerType !== "mouse") return
        const harbour = renderer()
        if (!harbour) return
        if (event.target !== canvas) {
          // On an island's card: it stays while the mouse is on it.
          window.clearTimeout(leaving)
          leaving = undefined
          return hideTag()
        }
        const [u, v] = pointOf(event)
        const ship = harbour.shipAt(u, v)
        const island = ship ? null : harbour.islandAt(u, v)
        canvas.style.cursor = ship || island ? "pointer" : ""
        if (ship) {
          const agent = crew.find(member => member.id === ship.id)!
          tag.textContent = agent.name
          tag.style.setProperty("--sail", agent.color)
          standAt(tag, ship.u, ship.v)
          return hideIsles()
        }
        hideTag()
        if (!island) return leaveIsles()
        hideIsles()
        standAt(isles.get(island.place)!, island.u, island.v)
      }
      const onPointerLeave = () => {
        hideTag()
        hideIsles()
        canvas.style.cursor = ""
      }
      const onClick = (event: MouseEvent) => {
        const harbour = renderer()
        if (!harbour) return
        const [u, v] = pointOf(event)
        const ship = harbour.shipAt(u, v)
        if (ship) {
          hideTag()
          return open(ship.id)
        }
        const island = harbour.islandAt(u, v)
        if (island) return isles.get(island.place)!.click()
        harbour.ripple(u, v)
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
      stage.addEventListener("pointermove", onPointerMove)
      stage.addEventListener("pointerleave", onPointerLeave)
      canvas.addEventListener("click", onClick)

      return () => {
        sync = () => {}
        themeObserver.disconnect()
        light.removeEventListener("change", restyle)
        calm.removeEventListener("change", onCalmChange)
        hideIsles()
        stage.removeEventListener("pointermove", onPointerMove)
        stage.removeEventListener("pointerleave", onPointerLeave)
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
