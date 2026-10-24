/**
 * Ripple pool: a tiled pool seen through moving water. Every tap drops a ripple;
 * rings that meet add up and cancel out, bending the tiles and the light on the
 * floor. Rain drops a scatter of them one after another.
 */
import {animate, createTimeline, utils} from "animejs"

import {across, all, listen, onAction, type Wonder} from "./wonder"

type Ripple = {x: number; y: number; age: number; height: number}
type Ripples = {ripples: Ripple[]}

const RIPPLES = 10

const wgsl = /* wgsl */ `
struct Params { view: vec4f, ripples: array<vec4f, ${RIPPLES}>, }
@group(0) @binding(0) var<uniform> params: Params;

fn water(p: vec2f, aspect: f32) -> f32 {
  var h = 0.0;
  for (var i = 0; i < ${RIPPLES}; i++) {
    let ripple = params.ripples[i];
    if (ripple.w <= 0.0005) { continue; }
    let d = length(p - ripple.xy * vec2f(aspect, 1.0));
    let front = ripple.z * 0.95;
    let band = exp(-pow((d - front) / (0.05 + ripple.z * 0.12), 2.0));
    h += sin((d - front) * 70.0) * band * ripple.w / (1.0 + d * 3.0);
  }
  return h;
}

fn tiles(p: vec2f) -> vec3f {
  let grid = p * 9.0;
  let line = min(abs(fract(grid.x) - 0.5), abs(fract(grid.y) - 0.5));
  let checker = step(0.5, fract((floor(grid.x) + floor(grid.y)) * 0.5));
  let tile = mix(vec3f(0.11, 0.42, 0.5), vec3f(0.13, 0.47, 0.55), checker);
  return mix(vec3f(0.85, 0.9, 0.88), tile, smoothstep(0.43, 0.47, 0.5 - line));
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let aspect = params.view.x / max(params.view.y, 1.0);
  let p = uv * vec2f(aspect, 1.0);
  let e = 0.002;
  let h = water(p, aspect);
  let slope = vec2f(water(p + vec2f(e, 0.0), aspect) - h, water(p + vec2f(0.0, e), aspect) - h) / e;
  let floor_at = p + slope * 0.012;
  var color = tiles(floor_at);
  // Light gathers where the surface curves inwards: the bright lines on a pool's floor.
  let gather = clamp(-(slope.x + slope.y) * 0.02 + length(slope) * 0.012, 0.0, 1.0);
  color += vec3f(0.85, 0.95, 1.0) * gather * 0.8;
  let n = normalize(vec3f(-slope * 0.02, 1.0));
  let glint = pow(max(dot(reflect(vec3f(0.0, 0.0, -1.0), n), normalize(vec3f(0.4, -0.5, 0.75))), 0.0), 40.0);
  color = color * 0.82 + vec3f(1.0) * glint * 0.6;
  let depth = smoothstep(1.4, 0.2, length(uv - vec2f(0.5, 0.45)));
  return vec4f(color * (0.6 + 0.4 * depth), 1.0);
}`

export const ripples: Wonder<Ripples> = {
  wgsl,
  continuous: false,
  state: () => ({ripples: Array.from({length: RIPPLES}, () => ({x: 0, y: 0, age: 0, height: 0}))}),
  bindings: (state, view) => ({
    params: {
      view: [view.width, view.height, 0, 0],
      ripples: state.ripples.map(ripple => [ripple.x, ripple.y, ripple.age, ripple.height]),
    },
  }),
  play({root, stage, state, nudge, say}) {
    let next = 0
    let drops = 0
    const count = () => say(drops === 1 ? "1 drop" : `${drops} drops`)
    count()

    const drop = (x: number, y: number) => {
      const ripple = state.ripples[next]!
      next = (next + 1) % RIPPLES
      Object.assign(ripple, {x, y, age: 0, height: 1})
      drops += 1
      count()
      animate(ripple, {age: 1, height: 0, duration: 3600, ease: "outSine", onUpdate: nudge})
    }

    return {
      ready: () => drop(0.5, 0.5),
      release: all(
        listen(stage, "pointerdown", event => drop(...across(stage, event))),
        onAction(root, "rain", () => {
          const rain = createTimeline()
          for (let i = 0; i < 8; i++)
            rain.call(() => drop(utils.random(0.1, 0.9, 3), utils.random(0.12, 0.88, 3)), i * 170 + utils.random(0, 90))
        }),
      ),
    }
  },
}
