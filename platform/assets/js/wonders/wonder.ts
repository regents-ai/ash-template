/**
 * What one of the ten wonders at /animations/wonders is made of.
 *
 * Each wonder is one picture vgpu draws on the GPU and one plain object of numbers
 * that Anime.js moves. The hook owns the object and the controls around the
 * picture; the renderer reads the object each time it draws. Nothing else passes
 * between them.
 */
import type {Scope} from "animejs"

/** The picture's size in pixels and, for a picture that moves by itself, seconds since it began. */
export type View = {width: number; height: number; time: number}

/** Uniform values by WGSL variable name, the shape vgpu's `set()` takes. */
export type Bindings = Record<string, unknown>

/** A picture that grows from its own last frame: two textures it reads and writes in turn. */
export type Simulation<State> = {
  readonly wgsl: string
  readonly size: readonly [number, number]
  /** Steps run before each frame is drawn. Each step reads one texture and writes the other. */
  readonly steps: number
  bindings(state: State, view: View): Bindings
}

/** What a wonder's motion gets to work with, inside the hook's Anime.js scope. */
export type Stage<State> = {
  readonly root: HTMLElement
  /** The picture's box, which takes the pointer. */
  readonly stage: HTMLElement
  readonly state: State
  /** Asks for a frame; for a picture that only moves while Anime.js does. */
  readonly nudge: () => void
  readonly scope: Scope
  /** Writes a short line under the picture, for people and screen readers alike. */
  say(text: string): void
}

export type Wonder<State extends object> = {
  readonly wgsl: string
  /** True for a picture that moves by itself. Otherwise it is drawn only while Anime.js moves it. */
  readonly continuous: boolean
  readonly simulation?: Simulation<State>
  state(): State
  /** Every member of the picture's uniform struct, on every call: vgpu's first `set()` needs them all. */
  bindings(state: State, view: View): Bindings
  /**
   * Wires the controls. Runs inside the hook's scope; whatever it returns runs when the
   * scope is reverted. `ready`, when given, runs each time a renderer lands.
   */
  play(stage: Stage<State>): {ready?: () => void; release?: () => void} | void
}

/** The pointer's place across a box, from its top left, each axis 0 to 1. */
export const across = (box: HTMLElement, event: PointerEvent): [number, number] => {
  const {left, top, width, height} = box.getBoundingClientRect()
  return [(event.clientX - left) / width, (event.clientY - top) / height]
}

/** Listens on an element and hands back the way to stop. */
export const listen = <K extends keyof HTMLElementEventMap>(
  el: HTMLElement,
  type: K,
  listener: (event: HTMLElementEventMap[K]) => void,
): (() => void) => {
  el.addEventListener(type, listener)
  return () => el.removeEventListener(type, listener)
}

/** Every button marked `data-wonder-action="<name>"` inside the wonder. */
export const onAction = (root: HTMLElement, name: string, act: (button: HTMLButtonElement) => void) => {
  const stops = [...root.querySelectorAll<HTMLButtonElement>(`[data-wonder-action="${name}"]`)].map(button =>
    listen(button, "click", () => act(button)),
  )
  return () => stops.forEach(stop => stop())
}

export const all = (...stops: (() => void)[]) => () => stops.forEach(stop => stop())

/** Hash, value noise and fractal noise, shared by the wonders' shaders. */
export const noiseWgsl = /* wgsl */ `
fn hash21(p: vec2f) -> f32 {
  var q = fract(p * vec2f(123.34, 456.21));
  q = q + vec2f(dot(q, q + 45.32));
  return fract(q.x * q.y);
}
fn hash22(p: vec2f) -> vec2f {
  let n = vec2f(dot(p, vec2f(127.1, 311.7)), dot(p, vec2f(269.5, 183.3)));
  return fract(sin(n) * 43758.5453);
}
fn noise(p: vec2f) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2f(1.0, 0.0)), u.x),
             mix(hash21(i + vec2f(0.0, 1.0)), hash21(i + vec2f(1.0, 1.0)), u.x), u.y);
}
fn fbm(start: vec2f) -> f32 {
  var p = start;
  var amount = 0.5;
  var sum = 0.0;
  for (var i = 0; i < 5; i++) {
    sum += amount * noise(p);
    p = mat2x2f(1.6, 1.2, -1.2, 1.6) * p;
    amount *= 0.5;
  }
  return sum;
}
`
