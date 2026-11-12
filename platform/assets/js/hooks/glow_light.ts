/**
 * The glow lab's light (`AshTemplateWeb.GlowLabLive`): one canvas island behind
 * the status rows, lighting the row the page names in `data-glow-lit` in that
 * row's status colour. Each time the lit row changes, the light lives once: it
 * slides to the row while its colour turns from the last status to this one,
 * holds while a pool of light drifts along the row's lower edge, then fades to
 * an ember and rests. Nothing loops. Every move is Anime.js, and each update asks
 * the island for one frame, so nothing is drawn while the light rests.
 *
 * The island draws nothing with less motion asked for, off screen, without
 * WebGPU or in forced colours, and the rows stay flat on the page. The words are
 * the page's own text above it.
 */
import {createScope, createTimeline, type Scope, type Timeline} from "animejs"

import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import type {GlowLightRenderer, GlowScene} from "../glow_light/renderer"
import {watchTheme} from "../theme"
import {colourReader, type Rgb} from "../token_colour"
import {EASE_IN_OUT, EASE_OUT, SLOW} from "./motion/shared"

type GlowLightHook = {
  el: HTMLElement
  island?: CanvasIslandController
  scope?: Scope
  release?: () => void
  /** The row lit when the light last began a life. */
  lit?: string
}

/** How much light is left once it has faded: enough to say which row is lit. */
const EMBER = 0.4

export const GlowLight = {
  mounted(this: GlowLightHook) {
    const root = this.el
    this.lit = root.dataset.glowLit
    const canvas = root.querySelector<HTMLCanvasElement>("[data-glow-canvas]")!
    const list = root.querySelector<HTMLElement>(".glow-lab__rows")!
    const rows = () => [...list.querySelectorAll<HTMLElement>("[data-glow-row]")]
    const readColour = colourReader()
    // `at` is the lit row's place in the list, between two rows while the light moves.
    const state = {at: 0, on: 0, change: 1, drift: 0}
    const tones = {from: "", to: ""}
    let colours: Map<string, Rgb> | undefined
    let ask = () => {}
    let life: Timeline | undefined

    const colour = (token: string): Rgb => {
      colours ??= new Map()
      if (!colours.has(token)) colours.set(token, readColour(getComputedStyle(root).getPropertyValue(token).trim()))
      return colours.get(token)!
    }

    const scene = (): GlowScene => {
      const box = canvas.getBoundingClientRect()
      const boxes = rows().map(row => row.getBoundingClientRect())
      const below = Math.min(Math.floor(state.at), boxes.length - 1)
      const above = Math.min(below + 1, boxes.length - 1)
      const k = state.at - below
      const a = boxes[below]!
      const b = boxes[above]!
      const mid = (x: number, y: number) => x + (y - x) * k
      return {
        width: canvas.clientWidth || 1,
        height: canvas.clientHeight || 1,
        fade: parseFloat(getComputedStyle(list).paddingTop) || 1,
        row: [mid(a.left, b.left) - box.left, mid(a.top, b.top) - box.top, mid(a.width, b.width), mid(a.height, b.height)],
        light: state,
        colours: {ground: colour("--color-bg"), from: colour(tones.from), to: colour(tones.to)},
      }
    }

    this.scope = createScope({root}).add(self => {
      // The light's one life for the row now lit: arrive, hold, fade to an ember.
      self!.add("light", (arriving: boolean) => {
        const list = rows()
        const index = Math.max(0, list.findIndex(row => row.dataset.glowRow === root.dataset.glowLit))
        const tone = `--color-${list[index]!.dataset.glowTone}`
        life?.cancel()
        tones.from = arriving ? tone : tones.to
        tones.to = tone
        if (arriving) {
          state.at = index
          state.on = 0
        }
        life = createTimeline({onUpdate: () => ask()})
          .add(state, {at: index, on: 1, change: [0, 1], duration: SLOW * 2, ease: EASE_OUT}, 0)
          .add(state, {drift: [0, 1], duration: SLOW * 15, ease: EASE_IN_OUT}, 0)
          .add(state, {on: EMBER, duration: SLOW * 4, ease: EASE_IN_OUT}, SLOW * 11)
      })
    })

    this.island = createCanvasIsland<GlowLightRenderer>(root, {}, {
      canvasSelector: "[data-glow-canvas]",
      readyFlag: "glowReady",
      motionSensitive: true,
      continuous: false,
      maxDevicePixelRatio: 2,
      browserLoad: async (view, size, onDeviceLost) => {
        const {createGlowLightRenderer} = await import("../glow_light/renderer")
        return createGlowLightRenderer(view, size, onDeviceLost)
      },
      interact: ({renderer, nudge, onReady}) => {
        ask = nudge
        onReady(() => {
          renderer()?.show(scene)
          this.scope!.methods.light(true)
        })
        const follow = watchTheme(() => {
          colours = undefined
          nudge()
        })
        return () => {
          follow()
          life?.cancel()
          ask = () => {}
        }
      },
    })
    this.island.mount()

    // Forced colours draw the page in system colours; the picture steps aside.
    const forced = matchMedia("(forced-colors: active)")
    const syncForced = () => (forced.matches ? this.island?.pause() : this.island?.resume())
    forced.addEventListener("change", syncForced)
    this.release = () => forced.removeEventListener("change", syncForced)
    if (forced.matches) this.island.pause()
  },
  updated(this: GlowLightHook) {
    if (this.el.dataset.glowLit === this.lit) return
    this.lit = this.el.dataset.glowLit
    if (this.el.dataset.glowReady === "true") this.scope?.methods.light(false)
  },
  disconnected(this: GlowLightHook) {
    this.island?.pause()
  },
  reconnected(this: GlowLightHook) {
    if (!matchMedia("(forced-colors: active)").matches) this.island?.resume()
  },
  destroyed(this: GlowLightHook) {
    this.release?.()
    this.island?.destroy()
    this.scope?.revert()
  },
}
