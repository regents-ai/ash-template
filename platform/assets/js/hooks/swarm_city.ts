import {animate, createScope, utils, type Scope} from "animejs"

import {createCanvasIsland, type CanvasIslandController, type LoadRenderer} from "../canvas_island"
import type {Place} from "../swarm_city/city"
import type {CityView, Framing, SwarmCityRenderer} from "../swarm_city/renderer"
import type {Agent} from "../swarm_city/swarm"

/** One agent as the server wrote it, with the name its disc shows under the pointer. */
type CrewMember = Agent & {readonly name: string}

const crewOf = (root: HTMLElement): CrewMember[] => JSON.parse(root.dataset.swarmCrew!) as CrewMember[]
const focusOf = (root: HTMLElement): Place | null => (root.dataset.swarmFocus || null) as Place | null

const PLACES: readonly Place[] = ["castle", "forge", "inn"]

/** The whole city, seen from above its southern edge. */
const OVERVIEW: Framing = {x: 0, y: 2.2, z: 0.4, yaw: 0.65, pitch: 0.62, distance: 36}

/** Space kept between a tag or a district's card and the picture's sides, in pixels. */
const TAG_MARGIN = 4
/** How long a district's card stays after the mouse leaves the district, so it can reach the link, in milliseconds. */
const CARD_LINGER = 300
/** How far a press may travel and still count as a press, not a drag, in pixels. */
const DRAG_SLOP = 5
/** How far one drag across the whole picture turns the city, and tips it, in radians. */
const TURN_ACROSS = Math.PI
const TIP_DOWN = 1.2
/** The camera never looks up from under the roofs or straight down on them. */
const LOWEST = 0.12
const HIGHEST = 1.15
/** How long the camera takes to fly to a district, and to light one, in milliseconds. */
const FLIGHT = 1600
const LIGHT = 320

const clamp = (value: number, low: number, high: number) => Math.min(high, Math.max(low, value))

/** The same turn as `to`, reached from `from` the short way round. */
const nearestTurn = (from: number, to: number) => from + Math.atan2(Math.sin(to - from), Math.cos(to - from))

type SwarmCityHook = {
  el: HTMLElement
  island?: CanvasIslandController
  scope?: Scope
  sync?: () => void
  pushEvent(event: string, payload: object): void
}

/**
 * The swarm city: a dense city of thin outlined towers with three downtowns, and
 * one yellow disc for each agent, flying to the district of its last action and
 * circling its towers.
 *
 * The city always moves, so it draws every frame while it is on screen. A visitor
 * who asked for less motion gets one composed, unmoving city, still turned by a
 * drag and redrawn when an agent moves on. Without WebGPU nothing is drawn, and
 * the picture the server rendered stays.
 *
 * Anime.js eases the camera and each district's light; the renderer reads both
 * when it draws. A drag turns the city. A mouse over a disc shows its agent's
 * name, and over a district shows a card with the link to the district's page.
 * Pressing a disc opens its agent's card; pressing a district follows its link.
 * On a district's page the camera flies to that district and lights it.
 */
export const SwarmCity = {
  mounted(this: SwarmCityHook) {
    const root = this.el
    const view: CityView = {...OVERVIEW, castle: 0, forge: 0, inn: 0}
    const calm = window.matchMedia("(prefers-reduced-motion: reduce)")
    const stage = root.querySelector<HTMLElement>("[data-swarm-stage]")!
    const canvas = root.querySelector<HTMLCanvasElement>("[data-swarm-canvas]")!
    const tag = root.querySelector<HTMLElement>("[data-swarm-tag]")!
    const cards = new Map(
      [...root.querySelectorAll<HTMLAnchorElement>("[data-swarm-district]")].map(link => [
        link.dataset.swarmDistrict as Place,
        link,
      ]),
    )
    let crew = crewOf(root)
    let focus = focusOf(root)
    let hovered: Place | null = null
    let city: SwarmCityRenderer | undefined
    let nudge = () => {}

    const scope = createScope({root})
    this.scope = scope
    /** Moves the camera to a framing: at once for a calm city, else flying there. */
    scope.add("frame", (framing: Framing) => {
      const to = {...framing, yaw: nearestTurn(view.yaw, framing.yaw)}
      if (calm.matches) {
        utils.remove(view)
        Object.assign(view, to)
        return nudge()
      }
      animate(view, {...to, duration: FLIGHT, ease: "inOutCubic"})
    })
    /** Lights the district on its own page and the one under the mouse; the others go dark. */
    scope.add("light", () => {
      for (const place of PLACES) {
        const level = place === focus || place === hovered ? 1 : 0
        if (view[place] === level) continue
        if (calm.matches) view[place] = level
        else animate(view, {[place]: level, duration: LIGHT, ease: "outQuad"})
      }
      if (calm.matches) nudge()
    })
    /** Lets a released drag carry on turning a little and come to rest. */
    scope.add("coast", (yaw: number, pitch: number) => {
      animate(view, {yaw, pitch, duration: 900, ease: "outCubic"})
    })

    const framingOf = (place: Place | null): Framing =>
      place ? city!.framing(place) : {...OVERVIEW, yaw: OVERVIEW.yaw - city!.turned()}

    const pointOf = (event: MouseEvent): [number, number] => {
      const box = canvas.getBoundingClientRect()
      return [(event.clientX - box.left) / box.width, (event.clientY - box.top) / box.height]
    }
    /** Stands a tag or card on a point of the canvas, kept inside the picture. */
    const standAt = (label: HTMLElement, u: number, v: number) => {
      label.hidden = false
      const box = root.getBoundingClientRect()
      const half = label.offsetWidth / 2
      const x = Math.min(Math.max(u * box.width, half + TAG_MARGIN), box.width - half - TAG_MARGIN)
      const y = Math.max(v * box.height, label.offsetHeight + TAG_MARGIN * 2)
      label.style.translate = `${x}px ${y}px`
    }
    let leaving: number | undefined
    const hover = (place: Place | null) => {
      if (place === hovered) return
      hovered = place
      scope.methods.light!()
    }
    const hideTag = () => {
      tag.hidden = true
    }
    const hideCards = () => {
      window.clearTimeout(leaving)
      leaving = undefined
      for (const link of cards.values()) link.hidden = true
      hover(null)
    }
    const leaveCards = () => {
      leaving ??= window.setTimeout(hideCards, CARD_LINGER)
    }

    // A drag: where it started, the view it started from, and how fast it was turning when let go.
    let drag: {id: number; x: number; y: number; yaw: number; pitch: number; moved: boolean} | undefined
    let turning = {yaw: 0, pitch: 0, at: 0}
    let dragged = false

    const onPointerDown = (event: PointerEvent) => {
      if (!city || event.button !== 0) return
      utils.remove(view, undefined, "yaw")
      utils.remove(view, undefined, "pitch")
      drag = {id: event.pointerId, x: event.clientX, y: event.clientY, yaw: view.yaw, pitch: view.pitch, moved: false}
      turning = {yaw: 0, pitch: 0, at: event.timeStamp}
      dragged = false
    }
    const onDrag = (event: PointerEvent) => {
      if (!drag || event.pointerId !== drag.id) return false
      const box = canvas.getBoundingClientRect()
      const dx = event.clientX - drag.x
      const dy = event.clientY - drag.y
      if (!drag.moved && Math.hypot(dx, dy) < DRAG_SLOP) return true
      if (!drag.moved) {
        drag.moved = true
        canvas.setPointerCapture(drag.id)
        hideTag()
        hideCards()
        stage.dataset.swarmDragging = ""
      }
      const yaw = drag.yaw - (dx / box.width) * TURN_ACROSS
      const pitch = clamp(drag.pitch + (dy / box.height) * TIP_DOWN, LOWEST, HIGHEST)
      const elapsed = Math.max(1, event.timeStamp - turning.at) / 1000
      turning = {yaw: (yaw - view.yaw) / elapsed, pitch: (pitch - view.pitch) / elapsed, at: event.timeStamp}
      view.yaw = yaw
      view.pitch = pitch
      if (calm.matches) nudge()
      return true
    }
    const onPointerUp = (event: PointerEvent) => {
      if (!drag || event.pointerId !== drag.id) return
      dragged = drag.moved
      drag = undefined
      delete stage.dataset.swarmDragging
      // A drag let go mid-swing carries on a little; one held still first stays put.
      if (!dragged || calm.matches || event.timeStamp - turning.at > 80) return
      scope.methods.coast!(view.yaw + turning.yaw * 0.25, clamp(view.pitch + turning.pitch * 0.25, LOWEST, HIGHEST))
    }
    const onPointerCancel = () => {
      drag = undefined
      delete stage.dataset.swarmDragging
    }
    const onPointerMove = (event: PointerEvent) => {
      if (onDrag(event) || event.pointerType !== "mouse" || !city) return
      if (event.target !== canvas) {
        // On a district's card: it stays while the mouse is on it.
        window.clearTimeout(leaving)
        leaving = undefined
        return hideTag()
      }
      const [u, v] = pointOf(event)
      const node = city.nodeAt(u, v)
      const district = node ? null : city.districtAt(u, v)
      canvas.style.cursor = node || district ? "pointer" : ""
      if (node) {
        const agent = crew.find(member => member.id === node.id)!
        tag.textContent = agent.name
        tag.style.setProperty("--sail", agent.color)
        standAt(tag, node.u, node.v)
        return hideCards()
      }
      hideTag()
      if (!district) return leaveCards()
      window.clearTimeout(leaving)
      leaving = undefined
      for (const [place, link] of cards) if (place !== district.place) link.hidden = true
      standAt(cards.get(district.place)!, district.u, district.v)
      hover(district.place)
    }
    const onPointerLeave = () => {
      if (drag?.moved) return
      hideTag()
      hideCards()
      canvas.style.cursor = ""
    }
    const onClick = (event: MouseEvent) => {
      if (dragged || !city) {
        dragged = false
        return
      }
      const [u, v] = pointOf(event)
      const node = city.nodeAt(u, v)
      if (node) {
        hideTag()
        return this.pushEvent("show_agent", {id: node.id})
      }
      const district = city.districtAt(u, v)
      if (district) cards.get(district.place)!.click()
    }
    const onCalmChange = () => {
      city?.setCalm(calm.matches)
      nudge()
    }

    const load: LoadRenderer<SwarmCityRenderer> = async (canvas, size, onDeviceLost) => {
      const {createSwarmCityRenderer} = await import("../swarm_city/renderer")
      return createSwarmCityRenderer(canvas, size, onDeviceLost, view)
    }

    this.island = createCanvasIsland<SwarmCityRenderer>(root, {}, {
      canvasSelector: "[data-swarm-canvas]",
      readyFlag: "swarmReady",
      browserLoad: load,
      motionSensitive: false,
      continuous: true,
      interact(island) {
        nudge = island.nudge
        island.onReady(() => {
          city = island.renderer()!
          city.setCalm(calm.matches)
          city.setAgents(crew)
          // The first frame already stands where the page asks.
          utils.remove(view)
          Object.assign(view, framingOf(focus))
          for (const place of PLACES) view[place] = place === focus ? 1 : 0
        })
        calm.addEventListener("change", onCalmChange)
        canvas.addEventListener("pointerdown", onPointerDown)
        stage.addEventListener("pointermove", onPointerMove)
        canvas.addEventListener("pointerup", onPointerUp)
        canvas.addEventListener("pointercancel", onPointerCancel)
        stage.addEventListener("pointerleave", onPointerLeave)
        canvas.addEventListener("click", onClick)
        return () => {
          nudge = () => {}
          city = undefined
          drag = undefined
          calm.removeEventListener("change", onCalmChange)
          hideTag()
          hideCards()
          canvas.removeEventListener("pointerdown", onPointerDown)
          stage.removeEventListener("pointermove", onPointerMove)
          canvas.removeEventListener("pointerup", onPointerUp)
          canvas.removeEventListener("pointercancel", onPointerCancel)
          stage.removeEventListener("pointerleave", onPointerLeave)
          canvas.removeEventListener("click", onClick)
        }
      },
    })

    this.sync = () => {
      crew = crewOf(root)
      city?.setAgents(crew)
      const next = focusOf(root)
      if (next !== focus) {
        focus = next
        if (city) {
          scope.methods.frame!(framingOf(focus))
          scope.methods.light!()
        }
      }
      nudge()
    }
    this.island.mount()
  },
  updated(this: SwarmCityHook) {
    this.sync?.()
  },
  disconnected(this: SwarmCityHook) {
    this.island?.pause()
  },
  reconnected(this: SwarmCityHook) {
    this.island?.resume()
  },
  destroyed(this: SwarmCityHook) {
    this.scope?.revert()
    this.island?.destroy()
  },
}
