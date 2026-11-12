/**
 * The grain lab's harbour water (`AshTemplateWeb.GrainLabLive`): one canvas
 * island behind the banner's heading. The water moves by itself, slowly, so the
 * island draws it every frame while it is on screen and in a visible tab, and
 * nothing at all otherwise. Here the hook keeps the water's clock, which only
 * runs while frames are drawn, and the page's ground and ink for the shader.
 *
 * The island draws nothing with less motion asked for, without WebGPU or in
 * forced colours, and the banner is the plain ground with its heading.
 */
import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import type {GrainScene, GrainWaterRenderer} from "../grain_water/renderer"
import {watchTheme} from "../theme"
import {colourReader, type Rgb} from "../token_colour"

type GrainWaterHook = {el: HTMLElement; island?: CanvasIslandController; release?: () => void}

/** Where the water's clock starts: both boats already crossing the banner. */
const START = 37.5
/** The longest step the clock takes between two frames, in seconds, so a pause never jumps. */
const LONGEST_STEP = 0.05

export const GrainWater = {
  mounted(this: GrainWaterHook) {
    const root = this.el
    const canvas = root.querySelector<HTMLCanvasElement>("[data-grain-canvas]")!
    const words = root.querySelector<HTMLElement>("[data-grain-words]")!
    const readColour = colourReader()
    let colours: GrainScene["colours"] | undefined
    let time = START
    let last: number | undefined

    const token = (name: string): Rgb => readColour(getComputedStyle(root).getPropertyValue(name).trim())

    const scene = (): GrainScene => {
      const now = performance.now() / 1000
      time += last === undefined ? 0 : Math.min(LONGEST_STEP, now - last)
      last = now
      const box = canvas.getBoundingClientRect()
      const below = words.getBoundingClientRect().bottom - box.top
      colours ??= {ground: token("--color-bg"), ink: token("--color-fg")}
      return {width: canvas.clientWidth || 1, height: canvas.clientHeight || 1, time, calm: below, colours}
    }

    this.island = createCanvasIsland<GrainWaterRenderer>(root, {}, {
      canvasSelector: "[data-grain-canvas]",
      readyFlag: "grainReady",
      motionSensitive: true,
      continuous: true,
      maxDevicePixelRatio: 2,
      browserLoad: async (view, size, onDeviceLost) => {
        const {createGrainWaterRenderer} = await import("../grain_water/renderer")
        return createGrainWaterRenderer(view, size, onDeviceLost)
      },
      interact: ({renderer, nudge, onReady}) => {
        onReady(() => {
          last = undefined
          renderer()?.show(scene)
        })
        const follow = watchTheme(() => {
          colours = undefined
          nudge()
        })
        return () => {
          follow()
          last = undefined
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
  disconnected(this: GrainWaterHook) {
    this.island?.pause()
  },
  reconnected(this: GrainWaterHook) {
    if (!matchMedia("(forced-colors: active)").matches) this.island?.resume()
  },
  destroyed(this: GrainWaterHook) {
    this.release?.()
    this.island?.destroy()
  },
}
