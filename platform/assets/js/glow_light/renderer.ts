/**
 * Draws the glow lab's light with WebGPU through vgpu: a soft light behind one
 * status row, in that status's colour, over the page's own ground. Colours are
 * blended in OKLab, so a change from one status to another passes through
 * colours a person would expect rather than a grey middle. Loaded only once the
 * picture is really going to be drawn. The hook (hooks/glow_light.ts) owns the
 * light's life, moves it with Anime.js and hands a fresh scene over whenever it
 * changes; nothing here moves by itself.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, init, surface} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import type {Rgb} from "../token_colour"

/** One frame, in CSS pixels measured from the canvas's top left. */
export type GlowScene = {
  /** The canvas's own CSS size; the drawing buffer's is this times the scale. */
  width: number
  height: number
  /** How far in from the picture's edge the light fades out, the list's own room around its rows. */
  fade: number
  /** The lit row's box: left, top, width, height. */
  row: readonly [number, number, number, number]
  /** How present the light is (0 to 1), how far from the last status to this one (0 to 1), and where the pool along its lower edge has drifted to (0 to 1). */
  light: {on: number; change: number; drift: number}
  /** The page's ground, the status the light is leaving and the one it is going to. */
  colours: {ground: Rgb; from: Rgb; to: Rgb}
}

export type GlowLightRenderer = IslandRenderer & {
  /** Where each frame's scene comes from, read afresh as the frame is drawn. */
  show(read: () => GlowScene): void
}

export const glowLightWgsl = /* wgsl */ `
struct Params {
  // Drawing-buffer pixels per CSS pixel, the picture's CSS width and height, how far its edge fades.
  frame: vec4f,
  // The lit row: left, top, width, height in CSS pixels.
  row: vec4f,
  // How present, how far through the change of colour, where the pool has drifted.
  light: vec4f,
  ground: vec4f,
  leaving: vec4f,
  going: vec4f,
}
@group(0) @binding(0) var<uniform> params: Params;

fn toLinear(c: vec3f) -> vec3f {
  return select(pow((c + 0.055) / 1.055, vec3f(2.4)), c / 12.92, c <= vec3f(0.04045));
}

fn toSrgb(c: vec3f) -> vec3f {
  let k = clamp(c, vec3f(0.0), vec3f(1.0));
  return select(1.055 * pow(k, vec3f(1.0 / 2.4)) - 0.055, k * 12.92, k <= vec3f(0.0031308));
}

// Linear sRGB to OKLab and back (Ottosson's matrices).
fn toOklab(c: vec3f) -> vec3f {
  let lms = vec3f(
    0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b,
    0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b,
    0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b,
  );
  let r = pow(max(lms, vec3f(0.0)), vec3f(1.0 / 3.0));
  return vec3f(
    0.2104542553 * r.x + 0.7936177850 * r.y - 0.0040720468 * r.z,
    1.9779984951 * r.x - 2.4285922050 * r.y + 0.4505937099 * r.z,
    0.0259040371 * r.x + 0.7827717662 * r.y - 0.8086757660 * r.z,
  );
}

fn fromOklab(l: vec3f) -> vec3f {
  let r = vec3f(
    l.x + 0.3963377774 * l.y + 0.2158037573 * l.z,
    l.x - 0.1055613458 * l.y - 0.0638541728 * l.z,
    l.x - 0.0894841775 * l.y - 1.2914855480 * l.z,
  );
  let lms = r * r * r;
  return vec3f(
    4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z,
    -1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z,
    -0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z,
  );
}

fn sdBox(p: vec2f, half: vec2f) -> f32 {
  let q = abs(p) - half;
  return length(max(q, vec2f(0.0))) + min(max(q.x, q.y), 0.0);
}

@fragment fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let p = position.xy / params.frame.x;
  let row = params.row;
  let half = row.zw * 0.5;
  let centre = row.xy + half;
  let on = params.light.x;
  let change = params.light.y;
  let drift = params.light.z;

  let ground = toOklab(toLinear(params.ground.rgb));
  // The status colour, part way from the last one to this one, in OKLab.
  let status = mix(toOklab(toLinear(params.leaving.rgb)), toOklab(toLinear(params.going.rgb)), smoothstep(0.0, 1.0, change));
  // A light is never darker than the ground it falls on: on a pale page it keeps the
  // page's lightness and takes the status's hue, a little stronger so it still reads;
  // on a dark one it is the status itself.
  let pale = step(status.x, ground.x);
  let light = vec3f(max(ground.x, status.x), status.yz * (1.0 + 0.8 * pale));

  // A soft body over the row that thins out just past its edges.
  let reach = max(row.w * 0.35, 8.0);
  let body = 1.0 - smoothstep(-row.w * 0.2, reach, sdBox(p - centre, half));

  // A pool of light low in the row, drifting slowly along it and back.
  let along = row.x + row.z * (0.3 + 0.4 * (0.5 - 0.5 * cos(drift * 6.28318530)));
  let dx = (p.x - along) / (row.z * 0.3);
  let dy = (p.y - (row.y + row.w * 0.8)) / (row.w * 0.4);
  let pool = exp(-dx * dx - dy * dy);

  // Nothing reaches the picture's own edge, so its box never shows.
  let size = params.frame.yz;
  let edge = min(min(p.x, size.x - p.x), min(p.y, size.y - p.y));
  let fade = smoothstep(0.0, params.frame.w, edge);

  let amount = clamp(on * body * (0.2 + 0.24 * pool) * fade, 0.0, 1.0);
  return vec4f(toSrgb(fromOklab(mix(ground, light, amount))), 1.0);
}
`

const rgba = (colour: Rgb): [number, number, number, number] => [colour[0], colour[1], colour[2], 1]

export async function createGlowLightRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<GlowLightRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a picture still in use reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  try {
    const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "opaque", label: "glow-light"})
    stage.resize([size[0], size[1]])
    const shader = effect(gpu, prepareShader(glowLightWgsl, "glow_light.wgsl"), {label: "glow-light.pass"})
    await shader.compile(stage)

    let read: (() => GlowScene) | undefined

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
        const {light, colours} = scene
        shader.set({
          params: {
            frame: [width / scene.width, scene.width, scene.height, scene.fade],
            row: [...scene.row],
            light: [light.on, light.change, light.drift, 0],
            ground: rgba(colours.ground),
            leaving: rgba(colours.from),
            going: rgba(colours.to),
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
