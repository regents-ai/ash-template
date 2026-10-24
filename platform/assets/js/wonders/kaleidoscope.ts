/**
 * Kaleidoscope: coloured glass between mirrors, in the Regents colours. Move across
 * it to shift the glass; turn it and the mirrors swing round while their number
 * changes, so the pattern folds into a new one.
 */
import {createAnimatable, createTimeline, type Timeline} from "animejs"

import {across, all, listen, noiseWgsl, onAction, type Wonder} from "./wonder"

type Kaleidoscope = {mirrors: number; turn: number; zoom: number; shiftX: number; shiftY: number; bloom: number}

const MIRRORS = [6, 8, 12, 5, 7]

const wgsl = noiseWgsl + /* wgsl */ `
struct Params { view: vec4f, glass: vec4f, shift: vec4f, }
@group(0) @binding(0) var<uniform> params: Params;

fn palette(t: f32) -> vec3f {
  let band = fract(t) * 5.0;
  let i = floor(band);
  let f = smoothstep(0.42, 0.58, fract(band));
  var a = vec3f(1.0, 0.357, 0.098);
  var b = vec3f(0.682, 0.792, 0.804);
  if (i == 1.0) { a = vec3f(0.682, 0.792, 0.804); b = vec3f(0.494, 0.847, 0.663); }
  if (i == 2.0) { a = vec3f(0.494, 0.847, 0.663); b = vec3f(1.0, 0.608, 0.561); }
  if (i == 3.0) { a = vec3f(1.0, 0.608, 0.561); b = vec3f(0.898, 0.89, 0.824); }
  if (i == 4.0) { a = vec3f(0.898, 0.89, 0.824); b = vec3f(1.0, 0.357, 0.098); }
  return mix(a, b, f);
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let aspect = params.view.x / max(params.view.y, 1.0);
  let mirrors = max(params.glass.x, 2.0);
  let turn = params.glass.y;
  let zoom = params.glass.z;
  let bloom = params.glass.w;
  let p = (uv - 0.5) * vec2f(aspect, 1.0);
  let r = length(p);
  let wedge = 6.2831853 / mirrors;
  var angle = atan2(p.y, p.x) + turn * 6.2831853;
  angle = abs(angle - wedge * floor(angle / wedge) - wedge * 0.5);
  let q = vec2f(cos(angle), sin(angle)) * r * zoom * 3.2 + params.shift.xy * 2.0;
  // Shards of glass: cells of noise cut into hard-edged facets.
  let cut = q * 2.4 + fbm(q * 1.3) * 1.5;
  let facet = floor(cut);
  let tint = palette(hash21(facet) + r * 0.25);
  // Dark lead between the pieces, where either edge of a piece is near.
  let edge = abs(fract(cut) - 0.5);
  let lead = smoothstep(0.43, 0.48, max(edge.x, edge.y));
  var color = tint * (0.7 + 0.35 * fbm(q * 6.0));
  color = mix(color, vec3f(0.086), lead * 0.85);
  color += vec3f(1.0, 0.92, 0.8) * bloom * exp(-r * 4.0) * 0.8;
  let lens = smoothstep(0.62, 0.55, r / max(aspect, 1.0) * 1.4);
  return vec4f(mix(vec3f(0.06), color, lens), 1.0);
}`

export const kaleidoscope: Wonder<Kaleidoscope> = {
  wgsl,
  continuous: false,
  state: () => ({mirrors: MIRRORS[0]!, turn: 0, zoom: 1, shiftX: 0, shiftY: 0, bloom: 0}),
  bindings: (state, view) => ({
    params: {
      view: [view.width, view.height, 0, 0],
      glass: [state.mirrors, state.turn, state.zoom, state.bloom],
      shift: [state.shiftX, state.shiftY, 0, 0],
    },
  }),
  play({root, stage, state, nudge, say}) {
    const shift = createAnimatable(state, {shiftX: 900, shiftY: 900, ease: "out(4)", onUpdate: nudge})
    let next = 1
    let turning: Timeline | undefined
    const read = () => say(`${Math.round(state.mirrors)} mirrors`)
    read()

    return {
      release: all(
        listen(stage, "pointermove", event => {
          const [x, y] = across(stage, event)
          shift.shiftX!(x - 0.5)
          shift.shiftY!(y - 0.5)
        }),
        onAction(root, "turn", () => {
          turning?.complete()
          const mirrors = MIRRORS[next]!
          next = (next + 1) % MIRRORS.length
          turning = createTimeline({onUpdate: () => (nudge(), read())})
            .add(state, {turn: state.turn + 0.5, duration: 2200, ease: "inOutQuart"})
            .add(state, {zoom: [{to: 0.55, duration: 1100, ease: "inQuad"}, {to: 1, duration: 1100, ease: "outBack(1.6)"}]}, 0)
            .add(state, {mirrors, duration: 1300, ease: "inOutSine", modifier: Math.round}, 500)
            .add(state, {bloom: [{to: 1, duration: 260}, {to: 0, duration: 900}]}, 1050)
        }),
      ),
    }
  },
}
