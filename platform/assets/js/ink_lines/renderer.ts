/**
 * Draws the ink lab with WebGPU through vgpu, in the page's own ink on its own
 * ground. Two views share one shader:
 *
 * - Lines: a few hairline strokes, each drawn up to how far the hook says it
 *   has got, with a fixed wobble in its weight so it reads as drawn by hand.
 * - Hero: a ground ruled in squares seen through a lens that widens, keeping the
 *   width at the point it looks at, from a flat plan (far away, long lens) to a
 *   deep view whose rules meet at the horizon (spec 8.2's perspective trick).
 *
 * Loaded only once the picture is really going to be drawn. The hook
 * (hooks/ink_lines.ts) moves everything with Anime.js and hands a fresh scene
 * over whenever it changes; nothing here moves by itself.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, init, surface} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import type {Rgb} from "../token_colour"

/** The most straight pieces the strokes of the Lines view may be made of. */
export const SEGMENT_SLOTS = 128
/** The most strokes the Lines view may have. */
export const STROKE_SLOTS = 8

/** One straight piece of a stroke, in CSS pixels: where it starts and ends, how far along its stroke it starts, and which stroke. */
export type InkSegment = {a: readonly [number, number]; b: readonly [number, number]; start: number; stroke: number}

/** One frame, in CSS pixels measured from the canvas's top left. */
export type InkScene = {
  /** The canvas's own CSS size; the drawing buffer's is this times the scale. */
  width: number
  height: number
  view: "lines" | "hero"
  /** Lines: every stroke's pieces, each stroke's full length and how far it is drawn (0 to 1). */
  segments: readonly InkSegment[]
  lengths: readonly number[]
  drawn: readonly number[]
  /** Hero: how far the lens has widened, from flat (0) to deep (1). */
  widen: number
  colours: {ground: Rgb; ink: Rgb}
}

export type InkLinesRenderer = IslandRenderer & {
  /** Where each frame's scene comes from, read afresh as the frame is drawn. */
  show(read: () => InkScene): void
}

export const inkLinesWgsl = /* wgsl */ `
struct Params {
  // Drawing-buffer pixels per CSS pixel, the canvas's CSS width and height, the view (0 lines, 1 hero).
  frame: vec4f,
  // Lines: how many pieces; hero: how far the lens has widened.
  shape: vec4f,
  ground: vec4f,
  ink: vec4f,
  // Each stroke's full length and how far it is drawn, two strokes to a vec4.
  strokes: array<vec4f, ${STROKE_SLOTS / 2}>,
  // Each piece: start and end in CSS pixels.
  ends: array<vec4f, ${SEGMENT_SLOTS}>,
  // Each piece: how far along its stroke it starts, its length, which stroke.
  pieces: array<vec4f, ${SEGMENT_SLOTS}>,
}
@group(0) @binding(0) var<uniform> params: Params;

fn hash(p: vec2f) -> f32 {
  return fract(sin(dot(p, vec2f(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise, fixed in place, for the wobble in a stroke's weight.
fn noise(p: vec2f) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2f(1.0, 0.0)), u.x), mix(hash(i + vec2f(0.0, 1.0)), hash(i + vec2f(1.0, 1.0)), u.x), u.y);
}

fn toSegment(p: vec2f, a: vec2f, b: vec2f) -> f32 {
  let ab = b - a;
  let t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1.0e-6), 0.0, 1.0);
  return distance(p, a + ab * t);
}

fn lines(p: vec2f, scale: f32) -> f32 {
  var d = 1.0e6;
  let count = u32(params.shape.x);
  for (var i = 0u; i < ${SEGMENT_SLOTS}u; i = i + 1u) {
    if (i >= count) { break; }
    let piece = params.pieces[i];
    let k = u32(piece.z);
    let stroke = params.strokes[k / 2u];
    let pair = select(stroke.xy, stroke.zw, k % 2u == 1u);
    // How much of this piece the stroke has reached.
    let reach = clamp((pair.x * pair.y - piece.x) / max(piece.y, 1.0e-6), 0.0, 1.0);
    if (reach <= 0.0) { continue; }
    let end = params.ends[i];
    d = min(d, toSegment(p, end.xy, end.xy + (end.zw - end.xy) * reach));
  }
  // A hairline about 1.25 device pixels wide, its weight wobbling a little along the page.
  let weight = 1.25 * (0.85 + 0.3 * noise(p * 0.08));
  return 1.0 - smoothstep(weight * 0.5 - 0.5, weight * 0.5 + 0.5, d * scale);
}

// How strongly a pixel sits on a rule of the ground, given its place in squares.
fn rule(u: f32, weight: f32) -> f32 {
  let w = max(fwidth(u), 1.0e-5);
  let line = 1.0 - clamp(abs(fract(u - 0.5) - 0.5) / w - (weight * 0.5 - 0.5), 0.0, 1.0);
  // Rules closer than a few pixels apart fade out instead of shimmering.
  return line * (1.0 - smoothstep(0.12, 0.35, w));
}

fn hero(p: vec2f) -> f32 {
  let size = params.frame.yz;
  let widen = params.shape.y;
  // The camera's distance from the point it looks at, eased in log space from far to near.
  let near = 5.0;
  let d = exp(mix(log(400.0), log(near), widen));
  // The lens keeps eight squares across the picture at that point. The camera's height
  // keeps a fixed share of its distance, so the point is always seen at the same angle,
  // chosen so that, once near, the horizon settles a little above the middle.
  let f = size.x * d / 8.0;
  let h = d * 0.32 * size.y * 8.0 / (size.x * near);
  // The point looked at sits low in the picture; the horizon is f*h/d above it.
  let focus = vec2f(size.x * 0.5, size.y * 0.74);
  let below = (p.y - focus.y) + f * h / d;
  let ground = step(0.0, below);
  let depth = f * h / max(below, 1.0e-3);
  let x = (p.x - focus.x) * depth / f;
  let z = depth - d;
  // The heading's sky stays clear: the ground's rules start below it, where the horizon settles.
  let sky = smoothstep(size.y * 0.3, size.y * 0.4, p.y);
  let ink = max(rule(x, 1.25), rule(z, 1.25)) * ground * sky;
  // The horizon itself, a hairline.
  let horizon = 1.0 - smoothstep(0.125, 1.125, abs(below) * params.frame.x);
  return max(ink * 0.55, horizon * 0.8 * smoothstep(0.0, 1.0, widen * 3.0 - 1.5));
}

@fragment fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let scale = params.frame.x;
  let p = position.xy / scale;
  // Both views are worked out for every pixel, so the rules' screen-space measures stay valid.
  let ruled = hero(p);
  var amount = ruled;
  if (params.frame.w < 0.5) {
    amount = lines(p, scale);
  }
  return vec4f(mix(params.ground.rgb, params.ink.rgb, clamp(amount, 0.0, 1.0)), 1.0);
}
`

const rgba = (colour: Rgb): [number, number, number, number] => [colour[0], colour[1], colour[2], 1]

export async function createInkLinesRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<InkLinesRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a picture still in use reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  try {
    const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "opaque", label: "ink-lines"})
    stage.resize([size[0], size[1]])
    const shader = effect(gpu, prepareShader(inkLinesWgsl, "ink_lines.wgsl"), {label: "ink-lines.pass"})
    await shader.compile(stage)

    const strokes = Array.from({length: STROKE_SLOTS / 2}, () => new Float32Array(4))
    const ends = Array.from({length: SEGMENT_SLOTS}, () => new Float32Array(4))
    const pieces = Array.from({length: SEGMENT_SLOTS}, () => new Float32Array(4))
    let read: (() => InkScene) | undefined

    return {
      show(next) {
        read = next
      },
      resize(width, height) {
        stage.resize([width, height])
      },
      // Everything is moved by the hook's own animation; there is nothing to ease here.
      step() {
        return false
      },
      present() {
        if (!read) return
        const scene = read()
        const [width] = stage.size
        const count = Math.min(scene.segments.length, SEGMENT_SLOTS)
        for (let i = 0; i < count; i++) {
          const segment = scene.segments[i]!
          ends[i]!.set([segment.a[0], segment.a[1], segment.b[0], segment.b[1]])
          pieces[i]!.set([segment.start, Math.hypot(segment.b[0] - segment.a[0], segment.b[1] - segment.a[1]), segment.stroke, 0])
        }
        for (let k = 0; k < STROKE_SLOTS; k++) {
          strokes[k >> 1]![(k & 1) * 2] = scene.lengths[k] ?? 0
          strokes[k >> 1]![(k & 1) * 2 + 1] = scene.drawn[k] ?? 0
        }
        shader.set({
          params: {
            frame: [width / scene.width, scene.width, scene.height, scene.view === "hero" ? 1 : 0],
            shape: [count, scene.widen, 0, 0],
            ground: rgba(scene.colours.ground),
            ink: rgba(scene.colours.ink),
            strokes,
            ends,
            pieces,
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
