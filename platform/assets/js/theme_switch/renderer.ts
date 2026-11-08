/**
 * Draws the theme switch with WebGPU through vgpu, on a clear canvas so the
 * light can spill onto the page round it. Loaded only once the switch is
 * really going to be drawn; the switch's script owns the knob and hands over a
 * picture whenever it changes, and nothing here moves by itself.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, init, surface} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import {stripAngle} from "./knob"
import {asLight, distance, LIGHT_DISTANCE, type Rgb} from "./light"
import {PIXEL_STRIDE} from "./morph"
import {GRID} from "./pixels"
import {PIXEL_SLOTS, themeSwitchWgsl} from "./shader"

export type {Rgb}

/** One frame of the switch, in CSS pixels measured from the canvas's top left. */
export type SwitchPicture = {
  /** Knob position: 0 at night, 1 by day. */
  p: number
  /** The canvas's own CSS size. */
  width: number
  height: number
  /** The track's box. */
  track: {x: number; y: number; width: number; height: number}
  /** The glass lens's side. */
  lens: number
  /** Icon pixels, PIXEL_STRIDE floats apiece (morph.ts). */
  pixels: Float32Array
  count: number
  colours: {page: Rgb; ink: Rgb; night: Rgb; day: Rgb}
}

export type ThemeSwitchRenderer = IslandRenderer & {
  /** The picture the next present() draws. */
  show(picture: SwitchPicture): void
}

const smoothstep = (from: number, to: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - from) / (to - from)))
  return t * t * (3 - 2 * t)
}

const rgba = (colour: Rgb): [number, number, number, number] => [colour[0], colour[1], colour[2], 1]

/**
 * The strip's lights stand LIGHT_DISTANCE from the page whatever its theme. The
 * icon keeps its own colours unless they lie nearer the page than that.
 */
function lightsFor({page, night, day}: SwitchPicture["colours"]) {
  const clear = (colour: Rgb) => asLight(colour, page, Math.max(LIGHT_DISTANCE, distance(colour, page)))
  return {night: asLight(night, page), day: asLight(day, page), iconNight: clear(night), iconDay: clear(day)}
}

export async function createThemeSwitchRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<ThemeSwitchRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a switch still on
  // screen reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  try {
    const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "premultiplied", label: "theme-switch"})
    stage.resize([size[0], size[1]])
    const shader = effect(gpu, prepareShader(themeSwitchWgsl, "theme_switch.wgsl"), {label: "theme-switch.glass"})
    await shader.compile(stage)

    // Every slot is sent each frame; the shader reads only the first `count`.
    const data = new Float32Array(PIXEL_SLOTS * PIXEL_STRIDE)
    const slots = Array.from({length: PIXEL_SLOTS}, (_, i) => data.subarray(i * PIXEL_STRIDE, (i + 1) * PIXEL_STRIDE))
    let picture: SwitchPicture | undefined
    let lit: {colours: SwitchPicture["colours"]; lights: ReturnType<typeof lightsFor>} | undefined

    return {
      show(next) {
        picture = next
      },
      resize(width, height) {
        stage.resize([width, height])
      },
      // The knob is moved by the page's own animation; there is nothing to ease here.
      step() {
        return false
      },
      present() {
        if (!picture) return
        const [width, height] = stage.size
        const scale = width / picture.width
        const {track, lens, p} = picture
        const half = (lens / 2) * scale
        const travel = (track.width - lens) * scale
        const count = Math.min(picture.count, PIXEL_SLOTS)
        if (lit?.colours !== picture.colours) lit = {colours: picture.colours, lights: lightsFor(picture.colours)}
        const {lights} = lit
        data.fill(0)
        data.set(picture.pixels.subarray(0, count * PIXEL_STRIDE))
        shader.set({
          params: {
            size: [width, height],
            scale,
            p,
            track: [
              (track.x + track.width / 2) * scale,
              (track.y + track.height / 2) * scale,
              (track.width / 2) * scale,
              (track.height / 2) * scale,
            ],
            lens: [track.x * scale + half + p * travel, (track.y + track.height / 2) * scale, half, 0.3 * lens * scale],
            shape: [0.32 * track.height * scale, (0.64 * lens * scale) / GRID, stripAngle(p), smoothstep(0.3, 0.7, p)],
            page: rgba(picture.colours.page),
            ink: rgba(picture.colours.ink),
            night: rgba(lights.night),
            day: rgba(lights.day),
            icon_night: rgba(lights.iconNight),
            icon_day: rgba(lights.iconDay),
            count,
            pixels: slots,
          },
        })
        frame(gpu, current => current.pass({target: stage, clear: [0, 0, 0, 0]}, shader))
      },
      settled() {
        return gpu.settled()
      },
      dispose() {
        if (disposed) return
        disposed = true
        stage.dispose()
        gpu.dispose()
      },
    }
  } catch (error) {
    gpu.dispose()
    throw error
  }
}
