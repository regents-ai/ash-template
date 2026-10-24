/**
 * Fractal flight: the Mandelbulb, a shape that keeps its detail however close you
 * fly. Drag to turn it. The tour flies in close while the shape's power changes,
 * so it melts from a smooth bulb into a spiky crown and back.
 *
 * The picture is costly, so it is drawn only while it moves.
 */
import {createAnimatable, createTimeline, type Timeline} from "animejs"

import {across, all, listen, onAction, type Wonder} from "./wonder"

type Fractal = {yaw: number; pitch: number; distance: number; power: number}

const wgsl = /* wgsl */ `
struct Params { view: vec4f, camera: vec4f, }
@group(0) @binding(0) var<uniform> params: Params;

fn bulb(p: vec3f, power: f32) -> vec2f {
  var z = p;
  var dr = 1.0;
  var r = 0.0;
  var trap = 1e9;
  for (var i = 0; i < 8; i++) {
    r = length(z);
    if (r > 2.0) { break; }
    let safe = max(r, 0.000001);
    let theta = acos(clamp(z.z / safe, -1.0, 1.0)) * power;
    let phi = atan2(z.y, z.x) * power;
    dr = pow(safe, power - 1.0) * power * dr + 1.0;
    z = pow(safe, power) * vec3f(sin(theta) * cos(phi), sin(phi) * sin(theta), cos(theta)) + p;
    trap = min(trap, dot(z, z));
  }
  return vec2f(0.5 * log(max(r, 0.000001)) * r / dr, trap);
}

fn normal(p: vec3f, power: f32, e: f32) -> vec3f {
  let k = vec2f(1.0, -1.0);
  return normalize(k.xyy * bulb(p + k.xyy * e, power).x + k.yyx * bulb(p + k.yyx * e, power).x
                 + k.yxy * bulb(p + k.yxy * e, power).x + k.xxx * bulb(p + k.xxx * e, power).x);
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let aspect = params.view.x / max(params.view.y, 1.0);
  let yaw = params.camera.x;
  let pitch = params.camera.y;
  let distance = params.camera.z;
  let power = params.camera.w;
  let eye = distance * vec3f(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw));
  let forward = normalize(-eye);
  let right = normalize(cross(vec3f(0.0, 1.0, 0.0), forward));
  let up = cross(forward, right);
  let screen = (uv - 0.5) * vec2f(aspect, -1.0);
  let ray = normalize(forward * 1.2 + right * screen.x + up * screen.y);

  var t = max(0.0, distance - 1.4);
  var hit = false;
  var steps = 0.0;
  var closest = 1e9;
  var trap = 0.0;
  for (var i = 0; i < 110; i++) {
    let found = bulb(eye + ray * t, power);
    closest = min(closest, found.x);
    if (found.x < 0.0006 * t) { hit = true; trap = found.y; break; }
    t += found.x * 0.9;
    steps += 1.0;
    if (t > distance + 2.0) { break; }
  }
  let sky = mix(vec3f(0.035, 0.035, 0.045), vec3f(0.09, 0.07, 0.06), uv.y);
  var color = sky + vec3f(1.0, 0.357, 0.098) * exp(-closest * 22.0) * 0.35;
  if (hit) {
    let point = eye + ray * t;
    let n = normal(point, power, 0.0005 * t);
    let sun = normalize(vec3f(0.6, 0.8, 0.4));
    let lit = max(dot(n, sun), 0.0);
    let rim = pow(1.0 - max(dot(n, -ray), 0.0), 3.0);
    let hollow = 1.0 - steps / 110.0;
    let shade = clamp(sqrt(trap) * 0.9, 0.0, 1.0);
    let base = mix(vec3f(1.0, 0.357, 0.098), mix(vec3f(0.682, 0.792, 0.804), vec3f(0.898, 0.89, 0.824), shade), shade);
    color = base * (0.18 + 0.9 * lit) * hollow * hollow + vec3f(0.682, 0.792, 0.804) * rim * 0.45;
  }
  color = pow(color, vec3f(0.9));
  return vec4f(color, 1.0);
}`

const STOPS = [
  {power: 8, distance: 3.4, yaw: 0, pitch: 0.35},
  {power: 3, distance: 2.3, yaw: 1.4, pitch: 0.9},
  {power: 12, distance: 1.75, yaw: 3.1, pitch: -0.25},
  {power: 5, distance: 2.7, yaw: 4.6, pitch: 0.55},
  {power: 8, distance: 3.4, yaw: 6.283, pitch: 0.35},
]

export const fractal: Wonder<Fractal> = {
  wgsl,
  continuous: false,
  state: () => ({yaw: 0, pitch: 0.35, distance: 3.4, power: 8}),
  bindings: (state, view) => ({
    params: {view: [view.width, view.height, 0, 0], camera: [state.yaw, state.pitch, state.distance, state.power]},
  }),
  play({root, stage, state, nudge, say}) {
    const turn = createAnimatable(state, {yaw: 600, pitch: 600, ease: "out(3)", onUpdate: nudge})
    let from: {x: number; y: number; yaw: number; pitch: number} | undefined
    let tour: Timeline | undefined
    const read = () => say(`Power ${state.power.toFixed(1)}`)
    read()

    return {
      release: all(
        listen(stage, "pointerdown", event => {
          tour?.pause()
          stage.setPointerCapture(event.pointerId)
          const [x, y] = across(stage, event)
          from = {x, y, yaw: state.yaw, pitch: state.pitch}
        }),
        listen(stage, "pointermove", event => {
          if (!from) return
          const [x, y] = across(stage, event)
          turn.yaw!(from.yaw + (x - from.x) * 4)
          turn.pitch!(Math.min(1.3, Math.max(-1.3, from.pitch + (y - from.y) * 3)))
        }),
        listen(stage, "pointerup", () => {
          from = undefined
        }),
        onAction(root, "tour", () => {
          tour?.cancel()
          tour = createTimeline({defaults: {duration: 2400, ease: "inOutSine"}, onUpdate: () => (nudge(), read())})
          state.yaw %= Math.PI * 2
          for (const stop of STOPS.slice(1)) tour.add(state, stop)
        }),
      ),
    }
  },
}
