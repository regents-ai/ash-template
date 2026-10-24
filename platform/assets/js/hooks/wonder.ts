import {createScope, type Scope} from "animejs"

import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import {wonders} from "../wonders"
import type {IslandRenderer} from "../canvas_island"

type WonderHook = {
  el: HTMLElement
  island?: CanvasIslandController
  scope?: Scope
}

/**
 * One of the ten wonders at /animations/wonders: a picture drawn on the GPU in
 * the shared canvas island, and the Anime.js motion that moves it.
 *
 * The motion only ever changes numbers in the wonder's state; the island decides
 * when a frame is worth drawing, and the renderer reads the numbers when it draws.
 * A visitor who asked for less motion keeps the still picture the server drew.
 */
export const Wonder = {
  mounted(this: WonderHook) {
    const name = this.el.dataset.wonder!
    const wonder = wonders[name]!
    const state = wonder.state()
    const stage = this.el.querySelector<HTMLElement>("[data-wonder-stage]")!
    const line = this.el.querySelector<HTMLElement>("[data-wonder-line]")!
    let nudge = () => {}

    const scope = createScope({root: this.el})
    this.scope = scope
    scope.add(() => {
      const played = wonder.play({
        root: this.el,
        stage,
        state,
        nudge: () => nudge(),
        scope,
        say: text => {
          if (line.textContent !== text) line.textContent = text
        },
      })
      if (played?.ready) scope.add("ready", played.ready)
      return played?.release
    })

    this.island = createCanvasIsland<IslandRenderer>(this.el, {}, {
      canvasSelector: "[data-wonder-canvas]",
      readyFlag: "wonderReady",
      browserLoad: async (canvas, size, onDeviceLost) => {
        const {createWonderRenderer} = await import("../wonders/renderer")
        return createWonderRenderer(canvas, size, onDeviceLost, name, wonder, state)
      },
      motionSensitive: true,
      continuous: wonder.continuous,
      interact(island) {
        nudge = island.nudge
        island.onReady(() => scope.methods.ready?.())
        return () => {
          nudge = () => {}
        }
      },
    })
    this.island.mount()
  },
  disconnected(this: WonderHook) {
    this.island?.pause()
  },
  reconnected(this: WonderHook) {
    this.island?.resume()
  },
  destroyed(this: WonderHook) {
    this.scope?.revert()
    this.island?.destroy()
  },
}
