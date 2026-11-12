import {animate, createAnimatable, createScope, createTimeline, onScroll, type Scope} from "animejs"

import {createCanvasIsland, type CanvasIslandController, type LoadRenderer} from "../canvas_island"
import type {LookId} from "../frosted_glass/looks"
import type {GlassRenderer, GlassState} from "../frosted_glass/renderer"

/** Where the lamp rests before the visitor has moved, and how far it wanders from there. */
const REST = {x: 0.3, y: 0.26}
const WANDER = 0.42
/** How long the lamp waits after the pointer stops before it wanders again, in milliseconds. */
const IDLE_MS = 3500

const lookOf = (root: HTMLElement): LookId => root.dataset.glassLook as LookId

type FrostedGlassHook = {
  el: HTMLElement
  island?: CanvasIslandController
  scope?: Scope
  sync?: () => void
}

/**
 * The frosted glass: a large tree seen through a leaning pane of glass, in
 * the look the page's address names. At the top of the page the visitor is
 * among its boughs; scrolling down steps back to the whole tree, and on back
 * until it stands in a forest.
 *
 * The leaves move in the wind, so it draws every frame while it is on screen.
 * A visitor who asked for less motion gets one unmoving picture, redrawn only
 * as they scroll. Without WebGPU nothing is drawn, and the picture the server
 * rendered stays.
 *
 * Anime.js moves the lamp in front of the pane, which goes the other way from
 * the pointer and wanders by itself when left alone, and eases the journey
 * behind the scroll. On the fogged pane, the pointer or a finger wipes the fog
 * away. Another look repaints the glass where it stands.
 */
export const FrostedGlass = {
  mounted(this: FrostedGlassHook) {
    const root = this.el
    const stage = root.querySelector<HTMLElement>("[data-glass-stage]")!
    const calm = window.matchMedia("(prefers-reduced-motion: reduce)")
    const state: GlassState = {
      lamp: {x: REST.x, y: REST.y, power: 0},
      wander: {x: 0, y: 0, amount: 1},
      gaze: {x: 0, y: 0},
      journey: {at: 0},
      wipes: [],
    }
    let look = lookOf(root)
    let glass: GlassRenderer | undefined
    let nudge = () => {}
    let last: [number, number] | undefined

    const load: LoadRenderer<GlassRenderer> = async (canvas, size, onDeviceLost) => {
      const {createGlassRenderer} = await import("../frosted_glass/renderer")
      return createGlassRenderer(canvas, size, onDeviceLost, state, look)
    }

    const scope = createScope({root})
    this.scope = scope
    let lamp: ReturnType<typeof createAnimatable> | undefined
    let gaze: ReturnType<typeof createAnimatable> | undefined
    let wander: ReturnType<typeof createAnimatable> | undefined
    scope.add(() => {
      lamp = createAnimatable(state.lamp, {x: 900, y: 900, ease: "out(3)"})
      gaze = createAnimatable(state.gaze, {x: 1200, y: 1200, ease: "out(3)"})
      // Left alone, the lamp crosses the pane by itself and comes back. Its wandering is
      // kept apart from where the pointer puts it, and fades out while the pointer moves.
      wander = createAnimatable(state.wander, {amount: 1400, ease: "inOut(2)"})
      createTimeline({loop: true, alternate: true, defaults: {ease: "inOutSine"}})
        .add(state.wander, {x: [0, WANDER], duration: 7000}, 0)
        .add(state.wander, {y: [{to: 0.1, duration: 3500}, {to: 0, duration: 3500}]}, 0)
      // Scrolling down the page carries the visitor out from among the boughs, back to the
      // whole tree and on into the forest; a little behind the scroll, or at once when calm.
      animate(state.journey, {
        at: [0, 1],
        ease: "linear",
        autoplay: onScroll({target: root, enter: "top top", leave: "bottom bottom", sync: calm.matches || 0.12}),
        onUpdate: () => nudge(),
      })
    })

    /** Where the pointer is, in shares of the picture from its top left. */
    const pointOf = (event: PointerEvent): [number, number] => {
      const box = stage.getBoundingClientRect()
      return [(event.clientX - box.left) / box.width, (event.clientY - box.top) / box.height]
    }
    /** The hand crossed the pane from where it last was to here. */
    const wipe = (point: [number, number]) => {
      state.wipes.push([last ?? point, point])
      last = point
      nudge()
    }

    this.island = createCanvasIsland<GlassRenderer>(root, {}, {
      canvasSelector: "[data-glass-canvas]",
      readyFlag: "glassReady",
      browserLoad: load,
      motionSensitive: false,
      continuous: true,
      interact(island) {
        nudge = island.nudge
        let idle: number | undefined

        const rest = () => {
          lamp!.x!(REST.x)
          lamp!.y!(REST.y)
          gaze!.x!(0)
          gaze!.y!(0)
          wander!.amount!(1)
        }

        // The lamp stands across the pane from the pointer, as a light does in a tilted pane.
        const onMove = (event: PointerEvent) => {
          const [x, y] = pointOf(event)
          if (lookOf(root) === "mist") wipe([x, y])
          if (calm.matches) return
          window.clearTimeout(idle)
          wander!.amount!(0)
          lamp!.x!(0.5 - (x - 0.5) * 1.5)
          lamp!.y!(0.3 - (y - 0.5) * 0.7)
          gaze!.x!((x - 0.5) * 2)
          gaze!.y!((y - 0.5) * 2)
          idle = window.setTimeout(rest, IDLE_MS)
        }
        /** A new touch, or the pointer coming back, starts a new stroke. */
        const onBreak = () => {
          last = undefined
        }
        const onCalmChange = () => {
          glass?.setCalm(calm.matches)
          nudge()
        }

        island.onReady(() => {
          glass = island.renderer()!
          glass.setCalm(calm.matches)
          // The look may have changed while the glass was loading.
          glass.setLook(look)
          if (calm.matches) {
            state.lamp.power = 1
            return
          }
          animate(state.lamp, {power: [0, 1], duration: 1600, ease: "out(3)"})
        })

        stage.addEventListener("pointermove", onMove)
        stage.addEventListener("pointerdown", onBreak)
        stage.addEventListener("pointerleave", onBreak)
        stage.addEventListener("pointercancel", onBreak)
        calm.addEventListener("change", onCalmChange)
        return () => {
          window.clearTimeout(idle)
          nudge = () => {}
          glass = undefined
          stage.removeEventListener("pointermove", onMove)
          stage.removeEventListener("pointerdown", onBreak)
          stage.removeEventListener("pointerleave", onBreak)
          stage.removeEventListener("pointercancel", onBreak)
          calm.removeEventListener("change", onCalmChange)
        }
      },
    })

    this.sync = () => {
      const next = lookOf(root)
      if (next === look) return
      look = next
      glass?.setLook(look)
      nudge()
    }
    this.island.mount()
  },
  updated(this: FrostedGlassHook) {
    this.sync?.()
  },
  disconnected(this: FrostedGlassHook) {
    this.island?.pause()
  },
  reconnected(this: FrostedGlassHook) {
    this.island?.resume()
  },
  destroyed(this: FrostedGlassHook) {
    this.island?.destroy()
    this.scope?.revert()
  },
}
