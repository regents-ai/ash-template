/**
 * The particles lab's stage (`AshTemplateWeb.ParticlesLabLive`): its loop and its
 * controls.
 *
 * Every real control under the field, and the Amount slider below it, names the
 * shape it belongs to (`data-particle-for`). Using one sets the field's value and
 * keeps the others for that shape in step, so the ring's progress bar always says
 * what the grains show.
 *
 * With no shape chosen (`data-loop="on"`) the stage plays the reference film's
 * sequence: the switch turns on, the grains fly into a ring that fills, then into
 * a slider whose knob slides across, then back to the switch. Pause holds it, and
 * using a control holds it too, so the control is the visitor's. It waits while
 * the stage is off screen, and Anime.js holds it while the tab is hidden. With
 * less motion asked for it does not start by itself.
 */
import {createTimeline} from "animejs"

import {EASE_IN_OUT, still} from "./motion/shared"

type Step = {shape: string; value: number}

export function createParticleLab(root: HTMLElement) {
  const field = root.querySelector<HTMLElement>("[data-particle-shape]")!
  const looping = () => root.dataset.loop === "on"
  const events = new AbortController()
  const signal = events.signal

  // What the loop shows now, so a page the server draws again can be put back.
  const step: Step = {shape: "switch", value: 0}
  let wanted = !still(root)
  let onscreen = false

  const parts = (shape: string) =>
    root.querySelectorAll<HTMLElement>(`[data-particle-for="${CSS.escape(shape)}"], [data-particle-for="${CSS.escape(shape)}"] input`)

  /** Every control for the shape shows the value: the switch's state, the bar's fill, the slider's place, the chosen radio. */
  const reflect = (shape: string, value: number) => {
    for (const part of parts(shape)) {
      if (part.getAttribute("role") === "switch") part.setAttribute("aria-checked", String(value >= 0.5))
      else if (part instanceof HTMLProgressElement) part.value = value * part.max
      else if (part instanceof HTMLInputElement && part.type === "range")
        part.value = String(Number(part.min) + value * (Number(part.max) - Number(part.min)))
      else if (part instanceof HTMLInputElement && part.type === "checkbox") part.checked = value >= 0.5
      else if (part instanceof HTMLInputElement && part.type === "radio") {
        const options = [...part.closest("fieldset")!.querySelectorAll("input")]
        part.checked = options.indexOf(part) === Math.round(value * (options.length - 1))
      }
    }
  }

  const set = (shape: string, value: number) => {
    field.dataset.particleValue = String(value)
    reflect(shape, value)
  }

  /** The field takes a shape, and only that shape's controls show. */
  const show = (shape: string, value: number) => {
    step.shape = shape
    step.value = value
    for (const part of root.querySelectorAll<HTMLElement>("[data-particle-for]")) part.hidden = part.dataset.particleFor !== shape
    field.dataset.particleShape = shape
    set(shape, value)
  }

  const label = () => root.querySelector<HTMLElement>("[data-particle-play] .rg-button__label")

  const tween = (shape: string, from: number, to: number, duration: number) => {
    const moving = {value: from}
    return [
      moving,
      {
        value: {from, to},
        duration,
        ease: EASE_IN_OUT,
        onUpdate: () => {
          step.value = moving.value
          set(shape, moving.value)
        },
      },
    ] as const
  }

  // The film's sequence, timed from it: each shape rests, changes its value, rests, then tears loose.
  const loop = createTimeline({loop: true, autoplay: false})
    .call(() => show("switch", 0), 0)
    .add(...tween("switch", 0, 1, 450), 600)
    .call(() => show("ring", 0), 3600)
    .add(...tween("ring", 0, 0.72, 1100), 5400)
    .call(() => show("slider", 0.06), 8600)
    .add(...tween("slider", 0.06, 0.85, 900), 10600)
    .call(() => show("switch", 0), 13600)
    .call(() => {}, 15600)

  const sync = () => {
    if (looping() && wanted && onscreen) loop.play()
    else loop.pause()
    const words = label()
    if (words) words.textContent = wanted ? "Pause" : "Play"
  }

  /** The visitor used a control: the loop holds and the value is theirs. */
  const take = (shape: string, value: number) => {
    wanted = false
    sync()
    set(shape, value)
  }

  const shapeOf = (el: Element) => el.closest<HTMLElement>("[data-particle-for]")!.dataset.particleFor!

  const fraction = (input: HTMLInputElement) =>
    (Number(input.value) - Number(input.min)) / (Number(input.max) - Number(input.min))

  root.addEventListener(
    "click",
    event => {
      const target = event.target as Element
      if (target.closest("[data-particle-play]")) {
        wanted = !wanted
        sync()
        return
      }
      const toggle = target.closest("[role='switch'][data-particle-for]")
      if (toggle) take(shapeOf(toggle), toggle.getAttribute("aria-checked") === "true" ? 0 : 1)
    },
    {signal},
  )

  root.addEventListener(
    "input",
    event => {
      const input = event.target as HTMLInputElement
      if (input.type === "range") take(shapeOf(input), fraction(input))
    },
    {signal},
  )

  root.addEventListener(
    "change",
    event => {
      const input = event.target as HTMLInputElement
      if (input.type === "checkbox") take(shapeOf(input), input.checked ? 1 : 0)
      if (input.type === "radio") {
        const options = [...input.closest("fieldset")!.querySelectorAll("input")]
        take(shapeOf(input), options.indexOf(input) / (options.length - 1))
      }
    },
    {signal},
  )

  const watching = new IntersectionObserver(entries => {
    onscreen = entries.at(-1)?.isIntersecting ?? onscreen
    sync()
  })

  let wasLooping = looping()

  return {
    mount() {
      watching.observe(root)
      sync()
    },
    /** The server drew the stage again: a loop that comes back starts afresh; one that never left is put back where it was. */
    updated() {
      if (looping() && !wasLooping) {
        wanted = !still(root)
        loop.seek(0, true)
        show("switch", 0)
      } else if (looping()) {
        show(step.shape, step.value)
      }
      wasLooping = looping()
      sync()
    },
    destroy() {
      events.abort()
      watching.disconnect()
      loop.revert()
    },
  }
}

type ParticleLabHook = {el: HTMLElement; lab?: ReturnType<typeof createParticleLab>}

export const ParticleLab = {
  mounted(this: ParticleLabHook) {
    this.lab = createParticleLab(this.el)
    this.lab.mount()
  },
  updated(this: ParticleLabHook) {
    this.lab?.updated()
  },
  destroyed(this: ParticleLabHook) {
    this.lab?.destroy()
    this.lab = undefined
  },
}
