/**
 * Draws the frosted glass with WebGPU through vgpu. Loaded only once the
 * picture is really going to be shown.
 *
 * Each frame the trees are drawn into a texture, that texture is blurred into
 * a soft copy and a softer one, the fog on the pane is wiped and left to creep
 * back, and the last pass looks at all of it through the leaning glass.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, init, sampler, surface, target, type Gpu} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import {ACROSS, DOWN, EYE, FACING, zoomFor} from "./lean"
import {LOOKS, type LookId} from "./looks"
import * as shaders from "./shaders"

/** What the page steers: where the lamp is, how bright, how far the visitor has travelled, and where a hand wiped the pane. */
export type GlassState = {
  /** The lamp, in shares of the pane from its top left, and its brightness from 0 to 1. */
  readonly lamp: {x: number; y: number; power: number}
  /** The lamp's own slow wandering, added to where it stands, and how much of it shows from 0 to 1. */
  readonly wander: {x: number; y: number; amount: number}
  /** Where the visitor looks from, each way from -1 to 1: near leaves slide more than far ones. */
  readonly gaze: {x: number; y: number}
  /** How far down the page the visitor is, from 0 at the top to 1 at the bottom: from among the boughs, out to the whole tree, then back into the forest. */
  readonly journey: {at: number}
  /** The stretches a hand crossed the pane along since the last frame, each from one place to the next, in shares of the window from its top left. */
  readonly wipes: Stroke[]
}

type Point = [number, number]
export type Stroke = readonly [Point, Point]

export type GlassRenderer = IslandRenderer & {
  setLook(look: LookId): void
  /** A calm picture stands still: no wind, no wandering lamp, no grain. */
  setCalm(calm: boolean): void
}

/** The tree is drawn smaller than the window: it is only ever seen through frosted glass. */
const PLANT_SCALE = 0.7
const SOFT_SCALE = 0.25
const SOFTER_SCALE = 0.125
/** How far apart each blur reads, in texels of the texture it writes. */
const SOFT_STRIDE = 1.6
const SOFTER_STRIDES = [1.5, 2.6] as const
const CLEAR: [number, number, number, number] = [0, 0, 0, 1]
/** How wide a hand wipes, as a share of the window's height, and how many seconds the fog takes to come back. */
const WIPE_RADIUS = 0.085
const FOG_RETURN = 9
/** The moment a calm picture is shown at. */
const CALM_TIME = 6
/** The longest step time takes between frames, so a picture coming back on screen does not jump. */
const MAX_STEP = 0.1
/** Nowhere on the pane: a wipe from here to here touches nothing. */
const AWAY: Point = [-10, -10]
/** The most stretches of a hand one frame wipes; any older ones are let go. */
const MAX_STROKES = 12

export async function createGlassRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
  state: GlassState,
  look: LookId,
): Promise<GlassRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a picture still on screen reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })
  try {
    return await build(gpu, canvas, size, state, look, () => disposed, () => void (disposed = true))
  } catch (error) {
    disposed = true
    gpu.dispose()
    throw error
  }
}

const scaled = (size: readonly [number, number], scale: number): [number, number] => [
  Math.max(1, Math.ceil(size[0] * scale)),
  Math.max(1, Math.ceil(size[1] * scale)),
]

async function build(
  gpu: Gpu,
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  state: GlassState,
  lookId: LookId,
  isDisposed: () => boolean,
  markDisposed: () => void,
): Promise<GlassRenderer> {
  const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "opaque", label: "glass"})
  stage.resize([size[0], size[1]])
  const smooth = sampler(gpu, {minFilter: "linear", magFilter: "linear"})
  let look = LOOKS[lookId]
  let calm = false
  // The share of the tree's picture the leaning window sees at its middle.
  let zoom = zoomFor(size[0] / size[1])
  const plantTarget = target(gpu, {size: scaled(size, PLANT_SCALE), label: "glass.plant"})
  const soft = [0, 1].map(index => target(gpu, {size: scaled(size, SOFT_SCALE), label: `glass.soft-${index}`}))
  const softer = [0, 1].map(index => target(gpu, {size: scaled(size, SOFTER_SCALE), label: `glass.softer-${index}`}))
  // The fog creeps back by a sliver each frame, finer than eight bits can hold.
  const fog = [0, 1].map(index =>
    target(gpu, {size: scaled(size, SOFT_SCALE), format: "rgba16float", label: `glass.fog-${index}`}),
  )
  let fogNow = 0
  let fogFresh = true

  const plantValues = (time: number) => ({
    resolution: [...plantTarget.size],
    shift: [state.gaze.x, state.gaze.y],
    time,
    wind: look.wind,
    journey: state.journey.at,
    zoom,
    leafDark: [...look.leafDark],
    leafLight: [...look.leafLight],
    leafGlow: [...look.leafGlow],
    sky: [...look.sky],
    shade: [...look.shade],
    bark: [...look.bark],
    glow: [...look.glow],
    glowing: look.glowing,
  })
  const glassValues = (time: number) => {
    const {lamp, wander} = state
    const wandering = calm ? 0 : wander.amount
    return {
      resolution: [...stage.size],
      light: [lamp.x + wander.x * wandering, lamp.y + wander.y * wandering],
      across: [...ACROSS],
      down: [...DOWN],
      facing: [...FACING],
      eye: EYE,
      zoom,
      time,
      // In a narrow window the lamp stands nearer, so its pool of light stays a part of the pane.
      lightHeight: look.lightHeight * Math.min(1, stage.size[0] / stage.size[1]),
      lightPower: lamp.power,
      pebble: look.pebble,
      bump: look.bump,
      bend: look.bend,
      frost: look.frost,
      cells: look.cells,
      wire: look.wire,
      wireWidth: look.wireWidth,
      wireTone: look.wireTone,
      wireWander: look.wireWander,
      veil: look.veil,
      sparkle: look.sparkle,
      grain: calm ? 0 : look.grain,
      room: look.room,
      scatter: look.scatter,
      surface: look.surface,
      mist: look.mist,
      bloom: look.bloom,
      milk: [...look.milk],
    }
  }
  const wipeValues = ([from, to]: Stroke, creep: number) => ({
    startAt: from,
    endAt: to,
    aspect: stage.size[0] / stage.size[1],
    radius: WIPE_RADIUS,
    creep,
    fresh: fogFresh ? 1 : 0,
  })

  const plant = effect(gpu, prepareShader(shaders.plant, "glass_plant.wgsl"), {
    label: "glass.plant",
    set: {plant: plantValues(0)},
  })
  const blur = effect(gpu, prepareShader(shaders.blur, "glass_blur.wgsl"), {
    label: "glass.blur",
    set: {blur: {stride: [0, 0]}, src: plantTarget, srcSampler: smooth},
  })
  const wipe = effect(gpu, prepareShader(shaders.wipe, "glass_wipe.wgsl"), {
    label: "glass.wipe",
    set: {wipe: wipeValues([AWAY, AWAY], 0), fog: fog[1]!, fogSampler: smooth},
  })
  const pane = effect(gpu, prepareShader(shaders.glass, "glass_pane.wgsl"), {
    label: "glass.pane",
    set: {
      glass: glassValues(0),
      sharp: plantTarget,
      soft: soft[1]!,
      softer: softer[1]!,
      fog: fog[0]!,
      glassSampler: smooth,
    },
  })
  await Promise.all([plant.compile(plantTarget), blur.compile(soft[0]!), wipe.compile(fog[0]!), pane.compile(stage)])

  let time = CALM_TIME
  let creep = 0
  let lastStep: number | undefined

  /** The wipes this frame makes: every stretch the hand crossed, the first also letting the fog creep back. */
  const fogSteps = () => {
    const strokes = state.wipes.splice(0).slice(-MAX_STROKES)
    const steps = strokes.length > 0 ? strokes : [[AWAY, AWAY] as const]
    return steps.map((stroke, index) => ({stroke, creep: index === 0 ? creep : 0}))
  }

  return {
    resize(width, height) {
      const next = [width, height] as const
      zoom = zoomFor(width / height)
      stage.resize([width, height])
      plantTarget.resize(scaled(next, PLANT_SCALE))
      for (const each of soft) each.resize(scaled(next, SOFT_SCALE))
      for (const each of softer) each.resize(scaled(next, SOFTER_SCALE))
      for (const each of fog) each.resize(scaled(next, SOFT_SCALE))
      fogFresh = true
    },
    step() {
      if (calm) return false
      const now = performance.now() / 1000
      const dt = lastStep === undefined ? 0 : Math.min(MAX_STEP, now - lastStep)
      lastStep = now
      time += dt
      creep += dt / FOG_RETURN
      return true
    },
    present() {
      plant.set({plant: plantValues(time)})
      const [softWidth, softHeight] = soft[0]!.size
      const [softerWidth, softerHeight] = softer[0]!.size
      // Only a fogged pane keeps its fog; the wipes on any other are let go.
      const fogPasses = look.mist > 0 ? fogSteps() : []
      state.wipes.length = 0
      creep = 0
      frame(gpu, current => {
        current.pass({target: plantTarget, clear: CLEAR}, pass => pass.draw(plant))
        // Each blur goes across into one texture and down into the other.
        blur.set({blur: {stride: [SOFT_STRIDE / softWidth, 0]}, src: plantTarget})
        current.pass(soft[0]!, blur)
        blur.set({blur: {stride: [0, SOFT_STRIDE / softHeight]}, src: soft[0]!})
        current.pass(soft[1]!, blur)
        // The softer copy starts from the soft one and is blurred twice, the second time wider.
        softer.forEach((_, round) => {
          const stride = SOFTER_STRIDES[round]!
          blur.set({blur: {stride: [stride / softerWidth, 0]}, src: round === 0 ? soft[1]! : softer[1]!})
          current.pass(softer[0]!, blur)
          blur.set({blur: {stride: [0, stride / softerHeight]}, src: softer[0]!})
          current.pass(softer[1]!, blur)
        })
        // The fog goes back and forth between its two textures, one wipe at a time.
        for (const {stroke, creep: back} of fogPasses) {
          wipe.set({wipe: wipeValues(stroke, back), fog: fog[fogNow]!})
          fogNow = 1 - fogNow
          current.pass(fog[fogNow]!, wipe)
          fogFresh = false
        }
        pane.set({glass: glassValues(time), fog: fog[fogNow]!})
        current.pass(stage, pane)
      })
    },
    setLook(next) {
      if (look.mist === 0 && LOOKS[next].mist > 0) fogFresh = true
      look = LOOKS[next]
    },
    setCalm(next) {
      calm = next
      lastStep = undefined
      if (calm) time = CALM_TIME
    },
    settled() {
      return gpu.settled()
    },
    dispose() {
      if (isDisposed()) return
      markDisposed()
      stage.dispose()
      gpu.dispose()
    },
  }
}
