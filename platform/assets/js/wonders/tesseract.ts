/**
 * Tesseract: a cube with a fourth dimension, its sixteen corners turned in four
 * dimensions and cast down to the screen. Drag to turn it the ordinary way; turn it
 * inside out and it rolls through the fourth dimension, the inner cube passing
 * through the outer one.
 *
 * The corners are worked out here on each frame; the GPU draws the glowing edges.
 */
import {animate, createAnimatable, type JSAnimation} from "animejs"

import {across, all, listen, onAction, type Wonder} from "./wonder"

type Tesseract = {xy: number; xz: number; yz: number; xw: number; yw: number; zw: number}

const wgsl = /* wgsl */ `
struct Params { view: vec4f, corners: array<vec4f, 16>, }
@group(0) @binding(0) var<uniform> params: Params;

fn segment(p: vec2f, a: vec2f, b: vec2f) -> f32 {
  let ab = b - a;
  let t = clamp(dot(p - a, ab) / max(dot(ab, ab), 0.000001), 0.0, 1.0);
  return length(p - a - ab * t);
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let aspect = params.view.x / max(params.view.y, 1.0);
  let p = (uv - 0.5) * vec2f(aspect, 1.0);
  let tints = array<vec3f, 4>(
    vec3f(1.0, 0.357, 0.098), vec3f(0.682, 0.792, 0.804),
    vec3f(0.494, 0.847, 0.663), vec3f(1.0, 0.608, 0.561));
  var color = mix(vec3f(0.03, 0.032, 0.04), vec3f(0.07, 0.065, 0.06), uv.y);
  for (var i = 0u; i < 16u; i++) {
    let a = params.corners[i];
    for (var axis = 0u; axis < 4u; axis++) {
      let j = i ^ (1u << axis);
      if (j < i) { continue; }
      let b = params.corners[j];
      let d = segment(p, a.xy, b.xy);
      let near = (a.z + b.z) * 0.5;
      color += tints[axis] * (smoothstep(0.004, 0.0, d - 0.0015) * near + 0.0022 / (d + 0.004) * near * 0.35);
    }
    color += vec3f(0.898, 0.89, 0.824) * smoothstep(0.012, 0.0, length(p - a.xy) - 0.004) * a.z;
  }
  return vec4f(vec3f(1.0) - exp(-color * 1.3), 1.0);
}`

const rotate = (v: number[], i: number, j: number, angle: number) => {
  const [c, s] = [Math.cos(angle), Math.sin(angle)]
  const [a, b] = [v[i]!, v[j]!]
  v[i] = a * c - b * s
  v[j] = a * s + b * c
}

const PLANES: [keyof Tesseract, number, number][] = [
  ["xy", 0, 1], ["xz", 0, 2], ["yz", 1, 2], ["xw", 0, 3], ["yw", 1, 3], ["zw", 2, 3],
]

/** Each corner turned through all six planes, then cast from four dimensions to three and three to two. */
const corners = (state: Tesseract, aspect: number) =>
  Array.from({length: 16}, (_, index) => {
    const v = [0, 1, 2, 3].map(bit => (index >> bit & 1 ? 1 : -1) * 0.5)
    for (const [plane, i, j] of PLANES) rotate(v, i, j, state[plane])
    const fromW = 1 / (2.2 - v[3]!)
    const [x, y, z] = [v[0]! * fromW, v[1]! * fromW, v[2]! * fromW]
    const fromZ = 1.2 / (2.4 - z)
    const scale = Math.min(1, aspect) * 1.7
    return [x * fromZ * scale, y * fromZ * scale, Math.min(1.2, 0.25 + 1.4 * fromZ * fromW), 0]
  })

export const tesseract: Wonder<Tesseract> = {
  wgsl,
  continuous: false,
  state: () => ({xy: 0, xz: 0.5, yz: 0.35, xw: 0, yw: 0.3, zw: 0}),
  bindings: (state, view) => ({
    params: {view: [view.width, view.height, 0, 0], corners: corners(state, view.width / Math.max(1, view.height))},
  }),
  play({root, stage, state, nudge, say}) {
    const turn = createAnimatable(state, {xz: 500, yz: 500, ease: "out(3)", onUpdate: nudge})
    let from: {x: number; y: number; xz: number; yz: number} | undefined
    let rolling: JSAnimation | undefined
    let half = 0
    const read = () => say(`${Math.round(((state.xw / Math.PI) * 180) % 360)}° through the fourth dimension`)
    read()

    return {
      release: all(
        listen(stage, "pointerdown", event => {
          stage.setPointerCapture(event.pointerId)
          const [x, y] = across(stage, event)
          from = {x, y, xz: state.xz, yz: state.yz}
        }),
        listen(stage, "pointermove", event => {
          if (!from) return
          const [x, y] = across(stage, event)
          turn.xz!(from.xz + (x - from.x) * 5)
          turn.yz!(from.yz + (y - from.y) * 5)
        }),
        listen(stage, "pointerup", () => {
          from = undefined
        }),
        onAction(root, "roll", () => {
          rolling?.complete()
          half += 1
          rolling = animate(state, {
            xw: half * Math.PI,
            zw: [{to: state.zw + 0.6, duration: 1300}, {to: state.zw, duration: 1300}],
            duration: 2600,
            ease: "inOutCubic",
            onUpdate: () => (nudge(), read()),
          })
        }),
      ),
    }
  },
}
