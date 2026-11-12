/**
 * Draws the grain lab's harbour water with WebGPU through vgpu, seen from
 * above: a slow swell and two boats' wakes make a height field, a low light
 * finds the slopes that face it, and a grain fixed to the page decides which
 * specks of those slopes catch it. The grain never moves; only the water under
 * it does, so the banner reads like a print and stays still enough to read over.
 *
 * Loaded only once the picture is really going to be drawn. The water moves by
 * itself, so the island draws it every frame while it is on screen; the hook
 * (hooks/grain_water.ts) keeps the time and the colours.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, init, surface} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import type {Rgb} from "../token_colour"

/** One frame, in CSS pixels measured from the canvas's top left. */
export type GrainScene = {
  /** The canvas's own CSS size; the drawing buffer's is this times the scale. */
  width: number
  height: number
  /** Seconds of water so far. */
  time: number
  /** How far down the banner its heading reaches; the water is calm above it. */
  calm: number
  colours: {ground: Rgb; ink: Rgb}
}

export type GrainWaterRenderer = IslandRenderer & {
  /** Where each frame's scene comes from, read afresh as the frame is drawn. */
  show(read: () => GrainScene): void
}

export const grainWaterWgsl = /* wgsl */ `
struct Params {
  // Drawing-buffer pixels per CSS pixel, the canvas's CSS width and height, seconds.
  frame: vec4f,
  // How far down the heading reaches; the rest unused.
  shape: vec4f,
  ground: vec4f,
  ink: vec4f,
}
@group(0) @binding(0) var<uniform> params: Params;

// One boat's wake at p: two arms trailing at the wake angle behind it, rippled, fading with
// distance. Gives the height it adds and how much foam lies there.
fn wake(p: vec2f, boat: vec2f, heading: vec2f, t: f32) -> vec2f {
  let q = p - boat;
  let behind = -dot(q, heading);
  let across = abs(dot(q, vec2f(-heading.y, heading.x)));
  let arm = across - behind * 0.36;
  let width = 9.0 + behind * 0.07;
  let ripple = sin((behind + across) * 0.12 - t * 1.2);
  let fade = exp(-behind / 320.0) * step(0.0, behind);
  let ridge = exp(-(arm * arm) / (width * width));
  // The churned water straight behind the stern.
  let churn = exp(-(across * across) / 30.0) * exp(-behind / 90.0);
  let h = (ridge * ripple + churn * sin(behind * 0.35 - t * 2.4) * 0.5) * fade * 2.2;
  // Foam lies in a thin line along each arm, so the wake's V reads clearly in the grain.
  let line = 3.0 + behind * 0.02;
  let foam = exp(-(arm * arm) / (line * line)) + churn;
  return vec2f(h, foam * fade);
}

fn boats(p: vec2f) -> array<vec2f, 2> {
  let t = params.frame.w;
  let size = params.frame.yz;
  // Two boats crossing slowly, one each way, each in its own lane.
  let span = size.x + 600.0;
  let one = vec2f(fract(t * 0.012) * span - 300.0, size.y * 0.66);
  let two = vec2f(size.x + 300.0 - fract(t * 0.009 + 0.16) * span, size.y * 0.86);
  return array<vec2f, 2>(wake(p, one, vec2f(1.0, 0.0), t), wake(p, two, vec2f(-1.0, 0.0), t));
}

fn height(p: vec2f) -> f32 {
  let t = params.frame.w;
  // A slow swell from three directions.
  var h = 1.0 * sin(dot(p, vec2f(0.052, 0.021)) + t * 0.45)
        + 0.8 * sin(dot(p, vec2f(-0.031, 0.047)) + t * 0.33)
        + 0.5 * sin(dot(p, vec2f(0.083, -0.064)) + t * 0.61)
        + 0.22 * sin(dot(p, vec2f(0.15, 0.11)) + t * 0.9);
  let wakes = boats(p);
  return h + wakes[0].x + wakes[1].x;
}

// A grain value fixed to one device pixel.
fn grain(cell: vec2f) -> f32 {
  var k = vec2u(cell + vec2f(4096.0));
  var n = k.x * 1664525u + k.y * 1013904223u;
  n = (n ^ (n >> 16u)) * 2246822519u;
  n = (n ^ (n >> 13u)) * 3266489917u;
  n = n ^ (n >> 16u);
  return f32(n & 0xffffffu) / 16777215.0;
}

@fragment fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let scale = params.frame.x;
  let p = position.xy / scale;
  let e = 1.0;
  let dx = (height(p + vec2f(e, 0.0)) - height(p - vec2f(e, 0.0))) / (2.0 * e);
  let dy = (height(p + vec2f(0.0, e)) - height(p - vec2f(0.0, e))) / (2.0 * e);
  let n = normalize(vec3f(-dx, -dy, 1.0));
  // A low light from the upper left: flat water reads 1, slopes facing it more.
  let light = normalize(vec3f(-0.55, -0.65, 0.5));
  let lit = max(0.0, dot(n, light)) / light.z;
  let catching = max(0.0, lit - 1.0);

  // The heading's water stays calm, so the words sit on an even ground.
  let calm = smoothstep(params.shape.x * 0.8, params.shape.x * 1.4, p.y);

  // Two grains, one per device pixel and one coarser, set the threshold each speck must pass.
  let g = mix(grain(floor(position.xy)), grain(floor(position.xy / 1.9) + vec2f(97.0, 13.0)), 0.4);
  // At most half the grains on even the brightest slope light, so specks never clump.
  // Foam behind each boat lights grains of its own, so the wakes read whatever the light.
  let wakes = boats(p);
  let density = min(catching * 0.8 + 0.6 * (wakes[0].y + wakes[1].y), 0.6);
  let speck = smoothstep(g - 0.04, g + 0.04, density) * smoothstep(0.02, 0.1, density) * calm;

  // The water itself: the ground, a shade deeper on slopes turned from the light.
  let shade = 0.03 * clamp(1.0 - lit, 0.0, 1.0) * calm;
  let colour = mix(params.ground.rgb, params.ink.rgb, clamp(shade + speck * 0.55, 0.0, 1.0));
  return vec4f(colour, 1.0);
}
`

const rgba = (colour: Rgb): [number, number, number, number] => [colour[0], colour[1], colour[2], 1]

export async function createGrainWaterRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<GrainWaterRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a picture still in use reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  try {
    const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "opaque", label: "grain-water"})
    stage.resize([size[0], size[1]])
    const shader = effect(gpu, prepareShader(grainWaterWgsl, "grain_water.wgsl"), {label: "grain-water.pass"})
    await shader.compile(stage)

    let read: (() => GrainScene) | undefined

    return {
      show(next) {
        read = next
      },
      resize(width, height) {
        stage.resize([width, height])
      },
      // The water never rests while it is shown: every frame is a new one.
      step() {
        return true
      },
      present() {
        if (!read) return
        const scene = read()
        const [width] = stage.size
        shader.set({
          params: {
            frame: [width / scene.width, scene.width, scene.height, scene.time],
            shape: [scene.calm, 0, 0, 0],
            ground: rgba(scene.colours.ground),
            ink: rgba(scene.colours.ink),
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
