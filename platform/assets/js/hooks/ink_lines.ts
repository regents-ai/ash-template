/**
 * The ink lab's picture (`AshTemplateWeb.InkLabLive`): one canvas island for
 * both views the page names in `data-ink-view`.
 *
 * - Lines: a few hairline strokes, hills, a sun, a road and two birds, draw
 *   themselves one after another when the view arrives, then rest.
 * - Hero: a ruled ground seen from far away through a long lens, flat as a
 *   plan, widens once into a deep view whose rules meet at the horizon, then rests.
 *
 * Every move is Anime.js, and each update asks the island for one frame, so
 * nothing is drawn while the picture rests. The island draws nothing with less
 * motion asked for, off screen, without WebGPU or in forced colours; the page's
 * own words stand without it.
 */
import {animate, createScope, stagger, type JSAnimation, type Scope} from "animejs"

import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import type {InkLinesRenderer, InkScene, InkSegment} from "../ink_lines/renderer"
import {watchTheme} from "../theme"
import {colourReader, type Rgb} from "../token_colour"
import {BASE, EASE_IN_OUT, SLOW} from "./motion/shared"

type InkLinesHook = {
  el: HTMLElement
  island?: CanvasIslandController
  scope?: Scope
  release?: () => void
  /** The view showing when the picture last arrived. */
  view?: string
}

type Point = readonly [number, number]

/**
 * The Lines view's strokes, in the order they are drawn. A point is [across, down],
 * across as a share of the picture's width and down as a share of its height; a
 * circle's radius is a share of the height, so it stays round.
 */
function strokes(width: number, height: number): Point[][] {
  const at = (x: number, y: number): Point => [x * width, y * height]
  const curve = (from: number, to: number, f: (x: number) => number, steps = 32) =>
    Array.from({length: steps + 1}, (_, i) => {
      const x = from + (to - from) * (i / steps)
      return at(x, f(x))
    })
  const hill = (centre: number, spread: number, rise: number) => (x: number) =>
    0.62 - rise * Math.exp(-(((x - centre) / spread) ** 2))
  const sun = Array.from({length: 49}, (_, i) => {
    const a = (i / 48) * Math.PI * 2 - Math.PI / 2
    return [0.74 * width + Math.cos(a) * 0.09 * height, 0.28 * height + Math.sin(a) * 0.09 * height] as Point
  })
  const bird = (x: number, y: number, s: number) => [at(x - s, y - s * 0.6), at(x, y), at(x + s, y - s * 0.6)]
  return [
    [at(0.04, 0.62), at(0.96, 0.62)],
    curve(0.04, 0.5, hill(0.24, 0.12, 0.2)),
    curve(0.5, 0.96, hill(0.74, 0.11, 0.13)),
    sun,
    [at(0.3, 0.98), at(0.49, 0.62)],
    [at(0.7, 0.98), at(0.51, 0.62)],
    bird(0.3, 0.3, 0.025),
    bird(0.38, 0.24, 0.018),
  ]
}

/** Every stroke as straight pieces, with each stroke's full length. */
function pieces(lines: Point[][]): {segments: InkSegment[]; lengths: number[]} {
  const segments: InkSegment[] = []
  const lengths = lines.map((line, stroke) => {
    let start = 0
    for (let i = 1; i < line.length; i++) {
      const a = line[i - 1]!
      const b = line[i]!
      segments.push({a, b, start, stroke})
      start += Math.hypot(b[0] - a[0], b[1] - a[1])
    }
    return start
  })
  return {segments, lengths}
}

export const InkLines = {
  mounted(this: InkLinesHook) {
    const root = this.el
    this.view = root.dataset.inkView
    const canvas = root.querySelector<HTMLCanvasElement>("[data-ink-canvas]")!
    const readColour = colourReader()
    const drawn = Array.from({length: 8}, () => ({at: 0}))
    const lens = {widen: 0}
    let colours: InkScene["colours"] | undefined
    let shape: {width: number; height: number; segments: InkSegment[]; lengths: number[]} | undefined
    let ask = () => {}
    let moves: JSAnimation[] = []

    const token = (name: string): Rgb => readColour(getComputedStyle(root).getPropertyValue(name).trim())

    const scene = (): InkScene => {
      const width = canvas.clientWidth || 1
      const height = canvas.clientHeight || 1
      if (shape?.width !== width || shape.height !== height) shape = {width, height, ...pieces(strokes(width, height))}
      colours ??= {ground: token("--color-bg"), ink: token("--color-fg")}
      return {
        width,
        height,
        view: root.dataset.inkView === "hero" ? "hero" : "lines",
        segments: shape.segments,
        lengths: shape.lengths,
        drawn: drawn.map(stroke => stroke.at),
        widen: lens.widen,
        colours,
      }
    }

    this.scope = createScope({root}).add(self => {
      // The view arrives once: its strokes draw in turn, or its lens widens, then all rests.
      self!.add("arrive", () => {
        for (const move of moves) move.cancel()
        for (const stroke of drawn) stroke.at = 0
        lens.widen = 0
        moves =
          root.dataset.inkView === "hero"
            ? [animate(lens, {widen: 1, duration: SLOW * 12, ease: EASE_IN_OUT, onUpdate: () => ask()})]
            : [animate(drawn, {at: 1, duration: SLOW * 3, delay: stagger(BASE), ease: EASE_IN_OUT, onUpdate: () => ask()})]
        ask()
      })
    })

    this.island = createCanvasIsland<InkLinesRenderer>(root, {}, {
      canvasSelector: "[data-ink-canvas]",
      readyFlag: "inkReady",
      motionSensitive: true,
      continuous: false,
      maxDevicePixelRatio: 2,
      browserLoad: async (view, size, onDeviceLost) => {
        const {createInkLinesRenderer} = await import("../ink_lines/renderer")
        return createInkLinesRenderer(view, size, onDeviceLost)
      },
      interact: ({renderer, nudge, onReady}) => {
        ask = nudge
        onReady(() => {
          renderer()?.show(scene)
          this.scope!.methods.arrive()
        })
        const follow = watchTheme(() => {
          colours = undefined
          nudge()
        })
        return () => {
          follow()
          for (const move of moves) move.cancel()
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
  updated(this: InkLinesHook) {
    if (this.el.dataset.inkView === this.view) return
    this.view = this.el.dataset.inkView
    if (this.el.dataset.inkReady === "true") this.scope?.methods.arrive()
  },
  disconnected(this: InkLinesHook) {
    this.island?.pause()
  },
  reconnected(this: InkLinesHook) {
    if (!matchMedia("(forced-colors: active)").matches) this.island?.resume()
  },
  destroyed(this: InkLinesHook) {
    this.release?.()
    this.island?.destroy()
    this.scope?.revert()
  },
}
