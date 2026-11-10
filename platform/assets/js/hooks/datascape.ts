import {animate, createScope, utils, type Scope} from "animejs"

import {createCanvasIsland, type CanvasIslandController, type LoadRenderer} from "../canvas_island"
import type {Cell, Panel} from "../datascape/field"
import type {DatascapeRenderer} from "../datascape/renderer"

/** How long a panel takes to open, and to put together what it shows, in milliseconds. */
const OPENING = 750
const ASSEMBLY = 2400
/** How white a panel is as it opens, from 0 to 1. */
const FLASH = 0.55
/** How far a panel's opening may be held back, so a cell's panels do not all open at once, in milliseconds. */
const STAGGER = 500
/** The first picture fills outward from its middle over this long, in milliseconds. */
const FIRST_WAVE = 900
/** How fast a tube is drawn, in world units a second. */
const TUBE_SPEED = 1300
/** How long a panel takes to grow under the pointer and to settle back, in milliseconds. */
const REACTION = 350
/** Half the width, in world units, from which a panel opens with a bounce, a flash and sparks; smaller ones just appear. */
const LARGE = 8
/** Sparks thrown as a panel opens, and when it is pressed. */
const OPENING_SPARKS = 3
const PRESS_SPARKS = 14

type DatascapeHook = {
  el: HTMLElement
  island?: CanvasIslandController
  scope?: Scope
}

/**
 * The datascape at /animations/datascape: an endless dark plane of panels,
 * tubes and specks in three layers of depth, flown over by moving the pointer
 * towards an edge of the picture, or holding a finger there.
 *
 * The picture always moves, so it draws every frame while it is on screen. A
 * visitor who asked for less motion, or whose browser cannot draw it, keeps
 * the still picture the server rendered.
 *
 * The field decides what is near enough to show and what the pointer rests on;
 * Anime.js brings each panel in, draws each tube, and grows the panel under
 * the pointer. It only ever changes numbers on the field's panels and tubes,
 * which the renderer reads when it draws.
 */
export const Datascape = {
  mounted(this: DatascapeHook) {
    const root = this.el
    const canvas = root.querySelector<HTMLCanvasElement>("[data-datascape-canvas]")!
    let scape: DatascapeRenderer | undefined
    let rested: Panel | null = null

    const scope = createScope({root})
    this.scope = scope
    /** Opens a cell's panels and draws its tube. */
    scope.add("arrive", (cell: Cell) => {
      // Everything in the first picture arrives before the field's clock has moved.
      const wait = scape!.field.time === 0 ? cell.distance * FIRST_WAVE : 0
      for (const panel of cell.panels) {
        const large = panel.w > LARGE
        animate(panel, {
          grow: {to: 1, duration: large ? OPENING : OPENING / 2, ease: large ? "outBack(1.6)" : "outExpo"},
          flash: {from: large ? FLASH : 0, to: 0, duration: OPENING, ease: "outQuad"},
          assemble: {to: 1, duration: ASSEMBLY, ease: "outCubic"},
          delay: wait + panel.seed * STAGGER,
          onBegin: () => {
            if (large) scape?.field.burst(panel, OPENING_SPARKS)
          },
        })
      }
      const tube = cell.tube
      if (!tube) return
      animate(tube, {
        drawn: tube.length,
        duration: (tube.length / TUBE_SPEED) * 1000,
        delay: wait + tube.seed * STAGGER,
        ease: "inOutQuad",
      })
    })
    /** Stops whatever is still moving in a cell that has gone. */
    scope.add("leave", (cell: Cell) => {
      utils.remove(cell.panels)
      if (cell.tube) utils.remove(cell.tube)
    })
    /** Grows the panel the pointer came to rest on, and lets the one it left settle back. */
    scope.add("rest", (panel: Panel | null) => {
      if (rested) animate(rested, {hover: 0, duration: REACTION, ease: "outExpo"})
      if (panel) animate(panel, {hover: 1, duration: REACTION, ease: "outExpo"})
      rested = panel
      canvas.style.cursor = panel ? "pointer" : ""
    })
    /** A pressed panel flashes, throws sparks and puts itself together again. */
    scope.add("press", (panel: Panel) => {
      animate(panel, {
        flash: {from: 0.85, to: 0, duration: OPENING, ease: "outQuad"},
        assemble: {from: 0, to: 1, duration: ASSEMBLY / 2, ease: "outCubic"},
      })
      scape?.field.burst(panel, PRESS_SPARKS)
    })

    const load: LoadRenderer<DatascapeRenderer> = async (canvas, size, onDeviceLost) => {
      const {createDatascapeRenderer} = await import("../datascape/renderer")
      return createDatascapeRenderer(canvas, size, onDeviceLost, {
        arrive: cell => scope.methods.arrive!(cell),
        leave: cell => scope.methods.leave!(cell),
        rest: panel => scope.methods.rest!(panel),
      })
    }

    /** Where a pointer is, measured from the picture's middle in CSS pixels. */
    const pointOf = (event: MouseEvent): [number, number] => {
      const box = canvas.getBoundingClientRect()
      return [event.clientX - box.left - box.width / 2, event.clientY - box.top - box.height / 2]
    }
    const onPointerMove = (event: PointerEvent) => {
      // A finger steers only while it is held down; a mouse steers wherever it is.
      if (!scape || (event.pointerType !== "mouse" && event.buttons === 0)) return
      scape.field.pointer = pointOf(event)
    }
    const onPointerDown = (event: PointerEvent) => {
      if (!scape) return
      scape.field.pointer = pointOf(event)
      // A finger that slides off the picture keeps steering until it lifts.
      if (event.pointerType !== "mouse") canvas.setPointerCapture(event.pointerId)
    }
    const onPointerAway = (event: PointerEvent) => {
      if (!scape || (event.type === "pointerup" && event.pointerType === "mouse")) return
      scape.field.pointer = null
    }
    const onClick = (event: MouseEvent) => {
      const panel = scape?.field.panelAt(...pointOf(event))
      if (panel) scope.methods.press!(panel)
    }

    this.island = createCanvasIsland<DatascapeRenderer>(root, {}, {
      canvasSelector: "[data-datascape-canvas]",
      readyFlag: "datascapeReady",
      browserLoad: load,
      motionSensitive: true,
      continuous: true,
      interact(island) {
        island.onReady(() => {
          // A renderer that lands, the first or one after a lost device, brings a field of its own.
          scape = island.renderer()!
          rested = null
        })
        canvas.addEventListener("pointermove", onPointerMove)
        canvas.addEventListener("pointerdown", onPointerDown)
        canvas.addEventListener("pointerup", onPointerAway)
        canvas.addEventListener("pointercancel", onPointerAway)
        canvas.addEventListener("pointerleave", onPointerAway)
        canvas.addEventListener("click", onClick)
        return () => {
          scape = undefined
          rested = null
          canvas.style.cursor = ""
          canvas.removeEventListener("pointermove", onPointerMove)
          canvas.removeEventListener("pointerdown", onPointerDown)
          canvas.removeEventListener("pointerup", onPointerAway)
          canvas.removeEventListener("pointercancel", onPointerAway)
          canvas.removeEventListener("pointerleave", onPointerAway)
          canvas.removeEventListener("click", onClick)
        }
      },
    })
    this.island.mount()
  },
  disconnected(this: DatascapeHook) {
    this.island?.pause()
  },
  reconnected(this: DatascapeHook) {
    this.island?.resume()
  },
  destroyed(this: DatascapeHook) {
    this.island?.destroy()
    this.scope?.revert()
  },
}
