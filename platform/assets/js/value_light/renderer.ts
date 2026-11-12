/**
 * Draws the value cards' surface with WebGPU through vgpu: every card on the
 * page in one picture, its fill and its edge, lit round the pointer. Loaded
 * only once the picture is really going to be drawn. The hook (hooks/value_light.ts)
 * owns the light, moves it with Anime.js and hands a fresh scene over whenever it
 * changes; nothing here moves by itself.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, init, surface} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import type {Rgb} from "../token_colour"

/** The most cards one picture holds. */
export const CARD_SLOTS = 8

/** One frame, in CSS pixels measured from the canvas's top left. */
export type ValueScene = {
  /** The canvas's own CSS width; the drawing buffer's is this times the scale. */
  width: number
  /** Each card's box: left, top, width, height. */
  cards: readonly (readonly [number, number, number, number])[]
  /** The edge's width, the page's rule. */
  rule: number
  /** The light: where it is, how present (0 to 1), how lively (0 to 1), how far into a breath (0 to 1). */
  light: {x: number; y: number; on: number; energy: number; breath: number}
  /** The card fill, its edge, the ink the edge firms towards and the site's light the fill warms towards. */
  colours: {surface: Rgb; edge: Rgb; ink: Rgb; glow: Rgb}
}

export type ValueLightRenderer = IslandRenderer & {
  /** Where each frame's scene comes from, read afresh as the frame is drawn. */
  show(read: () => ValueScene): void
}

export const valueLightWgsl = /* wgsl */ `
struct Params {
  // Drawing-buffer pixels per CSS pixel, the rule's width, how many cards.
  frame: vec4f,
  // The light's place (CSS pixels), how present, how lively.
  light: vec4f,
  // How far into a breath; the rest unused.
  breath: vec4f,
  surface: vec4f,
  edge: vec4f,
  ink: vec4f,
  glow: vec4f,
  cards: array<vec4f, ${CARD_SLOTS}>,
}
@group(0) @binding(0) var<uniform> params: Params;

fn sdBox(p: vec2f, half: vec2f) -> f32 {
  let q = abs(p) - half;
  return length(max(q, vec2f(0.0))) + min(max(q.x, q.y), 0.0);
}

@fragment fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let scale = params.frame.x;
  let rule = params.frame.y;
  let count = u32(params.frame.z);
  // This pixel's centre in CSS pixels, so every length below is a page length.
  let p = position.xy / scale;

  // The card under this pixel, if any: how far inside its edge, and its size.
  var inside = -1.0e6;
  var span = 1.0;
  for (var i = 0u; i < ${CARD_SLOTS}u; i = i + 1u) {
    if (i >= count) { break; }
    let card = params.cards[i];
    let half = card.zw * 0.5;
    let d = -sdBox(p - (card.xy + half), half);
    if (d > inside) {
      inside = d;
      span = min(card.z, card.w);
    }
  }
  // Between the cards the page shows through.
  if (inside < 0.0) { return vec4f(0.0); }

  // The light falls off from the pointer across the whole grid, so a card's
  // neighbours catch it too. A lively pointer throws it further; a breath swells it.
  let breath = sin(params.breath.x * 3.14159265);
  let reach = span * (0.6 + 0.35 * params.light.w + 0.3 * breath);
  let d = distance(p, params.light.xy) / reach;
  let fall = exp(-d * d * 2.0) * params.light.z;

  // The fill takes a little of the site's light; the edge firms towards the ink.
  let wash = fall * (0.06 + 0.05 * params.light.w + 0.06 * breath);
  let lift = fall * (0.5 + 0.3 * params.light.w + 0.3 * breath);
  let onEdge = 1.0 - smoothstep(rule * 0.5, rule * 0.5 + 1.0 / scale, inside - rule * 0.5);
  let fill = mix(params.surface.rgb, params.glow.rgb, wash);
  let edge = mix(params.edge.rgb, params.ink.rgb, min(lift, 1.0));
  let colour = mix(fill, edge, onEdge);
  // Premultiplied, opaque inside a card; a half-covered pixel at its outer edge blends.
  let cover = smoothstep(0.0, 1.0 / scale, inside);
  return vec4f(colour * cover, cover);
}
`

const rgba = (colour: Rgb): [number, number, number, number] => [colour[0], colour[1], colour[2], 1]

export async function createValueLightRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<ValueLightRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a picture still in use reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  try {
    const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "premultiplied", label: "value-light"})
    stage.resize([size[0], size[1]])
    const shader = effect(gpu, prepareShader(valueLightWgsl, "value_light.wgsl"), {label: "value-light.surface"})
    await shader.compile(stage)

    const cards = Array.from({length: CARD_SLOTS}, () => new Float32Array(4))
    let read: (() => ValueScene) | undefined

    return {
      show(next) {
        read = next
      },
      resize(width, height) {
        stage.resize([width, height])
      },
      // The light is moved by the hook's own animation; there is nothing to ease here.
      step() {
        return false
      },
      present() {
        if (!read) return
        const scene = read()
        const [width] = stage.size
        const count = Math.min(scene.cards.length, CARD_SLOTS)
        for (let i = 0; i < count; i++) cards[i]!.set(scene.cards[i]!)
        const {light, colours} = scene
        shader.set({
          params: {
            frame: [width / scene.width, scene.rule, count, 0],
            light: [light.x, light.y, light.on, light.energy],
            breath: [light.breath, 0, 0, 0],
            surface: rgba(colours.surface),
            edge: rgba(colours.edge),
            ink: rgba(colours.ink),
            glow: rgba(colours.glow),
            cards,
          },
        })
        frame(gpu, current => current.pass(stage, shader))
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
