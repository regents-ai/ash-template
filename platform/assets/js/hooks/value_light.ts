/**
 * The value cards' light (`AshTemplateWeb.ValueLabLive`): one canvas island
 * behind the whole grid of cards, so the row reads as one surface. The light
 * sits where the pointer or a finger is; the faster the pointer moves, the
 * brighter and further it reaches, settling back as it slows; a touch makes it
 * breathe once. Every move of the light is Anime.js: an Animatable carries its
 * place, presence and liveliness, and a breath is one animation. Each update
 * asks the island for a frame, so nothing is drawn while the light rests.
 *
 * The island draws nothing with less motion asked for, off screen or without
 * WebGPU, and the cards keep the flat surface and edge their stylesheet gives
 * them; forced colours pause it too. The words are the page's own text above it.
 */
import {animate, createAnimatable, createScope, type AnimatableObject, type JSAnimation, type Scope} from "animejs"

import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import {watchTheme} from "../theme"
import {colourReader, type Rgb} from "../token_colour"
import type {ValueLightRenderer, ValueScene} from "../value_light/renderer"
import {BASE, EASE_IN_OUT, EASE_OUT, FAST, SLOW} from "./motion/shared"

type ValueLightHook = {el: HTMLElement; island?: CanvasIslandController; scope?: Scope; release?: () => void}

/** A pointer moving this many CSS pixels a millisecond is as lively as the light gets. */
const LIVELIEST = 1.5

export const ValueLight = {
  mounted(this: ValueLightHook) {
    const root = this.el
    const canvas = root.querySelector<HTMLCanvasElement>("[data-value-canvas]")!
    const readColour = colourReader()
    const state = {x: 0, y: 0, on: 0, energy: 0, breath: 0}
    let colours: ValueScene["colours"] | undefined
    let ask = () => {}
    let light: AnimatableObject | undefined
    let breath: JSAnimation | undefined
    let last = {x: 0, y: 0, t: 0}
    // A finger is on the grid; its light stays until it lifts and its breath is out.
    let touching = false

    const readColours = (): ValueScene["colours"] => {
      const style = getComputedStyle(root)
      const token = (name: string, under?: Rgb) => readColour(style.getPropertyValue(name).trim(), under)
      const surface = token("--color-surface")
      return {surface, edge: token("--hairline-strong", surface), ink: token("--color-fg"), glow: token("--value-light")}
    }

    const scene = (): ValueScene => {
      const box = canvas.getBoundingClientRect()
      colours ??= readColours()
      return {
        width: canvas.clientWidth || 1,
        cards: [...root.querySelectorAll<HTMLElement>("[data-value-card]")].map(card => {
          const r = card.getBoundingClientRect()
          return [r.left - box.left, r.top - box.top, r.width, r.height] as const
        }),
        rule: parseFloat(getComputedStyle(root).getPropertyValue("--rg-rule-width")) || 1,
        light: state,
        colours,
      }
    }

    this.scope = createScope({root}).add(self => {
      light = createAnimatable(state, {
        x: FAST,
        y: FAST,
        on: BASE,
        energy: FAST,
        ease: EASE_OUT,
        onUpdate: () => ask(),
      })
      // Liveliness settles back once the pointer stops feeding it.
      light.animations.energy!.onComplete = () => {
        if (state.energy > 0) light!.energy(0, SLOW)
      }
      self!.add("breathe", () => {
        breath?.cancel()
        breath = animate(state, {
          breath: [0, 1],
          duration: SLOW * 2,
          ease: EASE_IN_OUT,
          onUpdate: () => ask(),
          onComplete: () => {
            if (!touching) light!.on(0, SLOW)
          },
        })
      })
    })

    const place = (event: PointerEvent) => {
      const box = canvas.getBoundingClientRect()
      const x = event.clientX - box.left
      const y = event.clientY - box.top
      const elapsed = Math.max(1, event.timeStamp - last.t)
      const speed = last.t ? Math.hypot(x - last.x, y - last.y) / elapsed : 0
      last = {x, y, t: event.timeStamp}
      // A light coming on starts where the pointer is; one already on follows it.
      const arriving = state.on < 0.01
      light!.x(x, arriving ? 0 : FAST).y(y, arriving ? 0 : FAST)
      light!.energy(Math.min(1, speed / LIVELIEST), FAST)
    }

    this.island = createCanvasIsland<ValueLightRenderer>(root, {}, {
      canvasSelector: "[data-value-canvas]",
      readyFlag: "valueReady",
      motionSensitive: true,
      continuous: false,
      browserLoad: async (view, size, onDeviceLost) => {
        const {createValueLightRenderer} = await import("../value_light/renderer")
        return createValueLightRenderer(view, size, onDeviceLost)
      },
      interact: ({renderer, nudge, onReady}) => {
        ask = nudge
        onReady(() => renderer()?.show(scene))
        const events = new AbortController()
        const options = {passive: true, signal: events.signal}
        root.addEventListener("pointermove", event => {
          if (event.pointerType === "mouse") light!.on(1, BASE)
          place(event)
        }, options)
        root.addEventListener("pointerleave", event => {
          if (event.pointerType === "mouse") light!.on(0, BASE)
        }, options)
        root.addEventListener("pointerdown", event => {
          if (event.pointerType === "mouse") return
          last = {x: 0, y: 0, t: 0}
          place(event)
          touching = true
          light!.on(1, FAST)
          this.scope!.methods.breathe()
        }, options)
        const lift = (event: PointerEvent) => {
          if (event.pointerType === "mouse") return
          touching = false
          // A breath still under way puts the light out itself when it ends.
          if (!breath || breath.completed) light!.on(0, SLOW)
        }
        root.addEventListener("pointerup", lift, options)
        root.addEventListener("pointercancel", lift, options)
        const follow = watchTheme(() => {
          colours = undefined
          nudge()
        })
        return () => {
          events.abort()
          follow()
          ask = () => {}
        }
      },
    })
    this.island.mount()

    // Forced colours draw the cards' edges in system colours; the picture steps aside.
    const forced = matchMedia("(forced-colors: active)")
    const syncForced = () => (forced.matches ? this.island?.pause() : this.island?.resume())
    forced.addEventListener("change", syncForced)
    this.release = () => forced.removeEventListener("change", syncForced)
    if (forced.matches) this.island.pause()
  },
  disconnected(this: ValueLightHook) {
    this.island?.pause()
  },
  reconnected(this: ValueLightHook) {
    if (!matchMedia("(forced-colors: active)").matches) this.island?.resume()
  },
  destroyed(this: ValueLightHook) {
    this.release?.()
    this.island?.destroy()
    this.scope?.revert()
  },
}
