/**
 * The particle field (`AshTemplateWeb.Components.ParticleField.particle_field/1`):
 * 80,000 grains drawn over a real control, an icon or a brand mark.
 *
 * Two attributes on the root are the whole of it. `data-particle-shape` names
 * the shape (a control such as `switch`, `ring`, `slider`, `bar`, `checkbox`,
 * `radio`, `spinner` or `steps:5`; `icon:<lucide name>`; or `mark:<name>`) and
 * `data-particle-value` holds its value from 0 to 1. Changing the shape flies
 * every grain to a new home; changing the value moves the knob or the lit part.
 * Whoever changes them, the server or a script, the field follows.
 *
 * The shape fills the root's box, drawn `--particle-aspect` wide for each unit
 * tall (particle_field.css says it for each shape), and the canvas reaches past
 * the box on every side for the flight and the halo. An icon or a mark is the
 * server's own drawing inside the root, which the grains are laid on.
 *
 * A value set by a press moves across on the design system's on-screen curve;
 * one set by a key lands at once; a stream of them, as from a drag, is followed
 * as it comes, so the knob stays under the finger. The grains' own springs
 * smooth what is left.
 *
 * Without WebGPU, with less motion asked for or in forced colours, the canvas
 * never starts and the real control below is the whole picture.
 */
import {createAnimatable} from "animejs"

import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import {pictureOf} from "../particle_field/picture"
import type {FieldScene, ParticleFieldRenderer} from "../particle_field/renderer"
import {controlShape, isPicture, pictureShape, type Shape} from "../particle_field/shapes"
import {showingTheme, watchTheme} from "../theme"
import {colourReader} from "../token_colour"
import {EASE_IN_OUT, SLOW, lastInputByPointer, still} from "./motion/shared"

export type ParticleFieldController = Pick<CanvasIslandController, "mount" | "pause" | "resume" | "destroy">

/** Values closer together than this are a drag, followed as they come. */
const STREAM_MS = 120

export function createParticleField(root: HTMLElement): ParticleFieldController {
  const canvas = root.querySelector<HTMLCanvasElement>("[data-particle-canvas]")!
  const readColour = colourReader()
  const valueNow = () => Number(root.dataset.particleValue)

  // What Anime.js moves: the value the grains show.
  const shown = {value: valueNow()}
  let name = root.dataset.particleShape!
  let target = shown.value
  let shape: Shape | undefined
  let aspect = 1
  let box = {width: 1, height: 1}
  let view = {width: 1, height: 1}
  let light = showingTheme() === "light"
  let colours: FieldScene["colours"] | undefined
  let lastValueAt = -Infinity
  let renderer: () => ParticleFieldRenderer | undefined = () => undefined
  let draw = () => {}
  let connected = true

  const motion = createAnimatable(shown, {value: 0, onUpdate: () => draw()})

  /** The shape as it stands now, laid out at the value it shows. */
  const build = (): Shape => {
    aspect = Number(getComputedStyle(root).getPropertyValue("--particle-aspect"))
    shape = isPicture(name)
      ? pictureShape(
          name,
          pictureOf(root.querySelector<SVGSVGElement>(`svg[data-particle-source="${CSS.escape(name)}"]`)!, aspect),
          shown.value,
        )
      : controlShape(name, aspect, shown.value)
    return shape
  }

  const readColours = (): FieldScene["colours"] => {
    const style = getComputedStyle(root)
    const token = (property: string) => readColour(style.getPropertyValue(property).trim())
    return {muted: token("--particle-muted"), lit: token("--particle-lit"), far: token("--particle-far")}
  }

  const scene = (): FieldScene => {
    colours ??= readColours()
    return {
      width: view.width,
      height: view.height,
      scale: Math.min(box.width / aspect, box.height),
      half: box.width / 2,
      value: shown.value,
      area: shape!.area,
      knob: shape!.knob,
      turns: shape!.turns,
      light,
      colours,
    }
  }

  const measure = () => {
    box = {width: root.clientWidth || 1, height: root.clientHeight || 1}
    view = {width: canvas.clientWidth || 1, height: canvas.clientHeight || 1}
  }

  const jumpTo = (value: number) => {
    motion.value(value, 0)
    shown.value = value
    draw()
  }

  const follow = () => {
    const nextName = root.dataset.particleShape!
    const nextValue = valueNow()
    if (nextName !== name) {
      name = nextName
      target = nextValue
      jumpTo(nextValue)
      renderer()?.place(build().homes)
      return
    }
    if (nextValue === target) return
    target = nextValue
    const now = performance.now()
    const streaming = now - lastValueAt < STREAM_MS
    lastValueAt = now
    if (streaming || !lastInputByPointer()) jumpTo(nextValue)
    else motion.value(nextValue, SLOW, EASE_IN_OUT)
  }

  const island = createCanvasIsland<ParticleFieldRenderer>(root, {}, {
    canvasSelector: "[data-particle-canvas]",
    readyFlag: "particleReady",
    motionSensitive: true,
    // The grains keep moving after every change until they come to rest; the
    // renderer says when they have.
    continuous: true,
    // Each grain is a speck a pixel or two across; below the screen's own
    // sharpness the specks smear into a haze.
    maxDevicePixelRatio: 2,
    browserLoad: async (view, size, lost) => {
      const {createParticleFieldRenderer} = await import("../particle_field/renderer")
      return createParticleFieldRenderer(view, size, lost)
    },
    interact: island => {
      renderer = island.renderer
      draw = island.nudge
      island.onReady(() => {
        const current = island.renderer()!
        current.show(scene)
        current.place(build().homes)
      })
      return () => {
        renderer = () => undefined
        draw = () => {}
      }
    },
  })

  const forced = window.matchMedia("(forced-colors: active)")
  // A page's own Less motion switch (`data-motion="reduced"` round it) and forced
  // colours keep the real control alone, as the device setting does.
  const syncMotion = () => {
    if (!connected || still(root) || forced.matches) island.pause()
    else island.resume()
  }
  const calm = new MutationObserver(syncMotion)
  const changes = new MutationObserver(follow)
  const resized = new ResizeObserver(() => {
    measure()
    draw()
  })
  const events = new AbortController()
  let stopWatchingTheme = () => {}

  return {
    mount() {
      measure()
      changes.observe(root, {attributes: true, attributeFilter: ["data-particle-shape", "data-particle-value"]})
      calm.observe(document.documentElement, {subtree: true, attributes: true, attributeFilter: ["data-motion"]})
      forced.addEventListener("change", syncMotion, {signal: events.signal})
      resized.observe(root)
      stopWatchingTheme = watchTheme(theme => {
        light = theme === "light"
        colours = undefined
        draw()
      })
      island.mount()
      syncMotion()
    },
    pause() {
      connected = false
      island.pause()
    },
    resume() {
      connected = true
      syncMotion()
    },
    destroy() {
      events.abort()
      stopWatchingTheme()
      calm.disconnect()
      changes.disconnect()
      resized.disconnect()
      island.destroy()
      motion.revert()
    },
  }
}

type ParticleFieldHook = {el: HTMLElement; controller?: ParticleFieldController}

export const ParticleField = {
  mounted(this: ParticleFieldHook) {
    this.controller = createParticleField(this.el)
    this.controller.mount()
  },
  disconnected(this: ParticleFieldHook) {
    this.controller?.pause()
  },
  reconnected(this: ParticleFieldHook) {
    this.controller?.resume()
  },
  destroyed(this: ParticleFieldHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
