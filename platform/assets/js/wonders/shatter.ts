/**
 * Glass key: a frosted pane with a key etched in it. Tap the glass and it cracks
 * from that spot, then bursts into shards that spin away from the blow, freeing
 * the key glowing behind. Tap again and the shards spring back into a whole pane.
 */
import {createTimeline, spring, type Timeline} from "animejs"

import {across, all, listen, noiseWgsl, onAction, type Wonder} from "./wonder"

type Shatter = {x: number; y: number; burst: number; glow: number}

const wgsl = noiseWgsl + /* wgsl */ `
struct Params { view: vec4f, blow: vec4f, }
@group(0) @binding(0) var<uniform> params: Params;

const CELLS = 7.0;

fn seed(cell: vec2f) -> vec2f { return cell + 0.15 + hash22(cell) * 0.7; }

// The nearest shard to a point, and how far that point is from the shard's edge.
fn nearest(p: vec2f) -> vec3f {
  let home = floor(p);
  var first = 9.0;
  var second = 9.0;
  var owner = home;
  for (var y = -1; y <= 1; y++) {
    for (var x = -1; x <= 1; x++) {
      let cell = home + vec2f(f32(x), f32(y));
      let d = length(p - seed(cell));
      if (d < first) { second = first; first = d; owner = cell; } else if (d < second) { second = d; }
    }
  }
  return vec3f(owner, second - first);
}

fn spin(p: vec2f, angle: f32) -> vec2f {
  let c = cos(angle);
  let s = sin(angle);
  return vec2f(c * p.x - s * p.y, s * p.x + c * p.y);
}

fn key(p: vec2f) -> f32 {
  let bow = abs(length(p - vec2f(-0.42, 0.0)) - 0.17) - 0.05;
  let shaft = max(abs(p.x - 0.16) - 0.42, abs(p.y) - 0.045);
  let tooth = max(abs(p.x - 0.42) - 0.035, abs(p.y - 0.1) - 0.07);
  let tooth2 = max(abs(p.x - 0.27) - 0.03, abs(p.y - 0.085) - 0.05);
  return min(min(bow, shaft), min(tooth, tooth2));
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let aspect = params.view.x / max(params.view.y, 1.0);
  let burst = params.blow.z;
  let glow = params.blow.w;
  let p = uv * vec2f(aspect, 1.0) * CELLS;
  let blow = params.blow.xy * vec2f(aspect, 1.0) * CELLS;

  // Behind the glass: a deep sea, and the key glowing in it.
  let world = (uv - 0.5) * vec2f(aspect, 1.0) * 1.6;
  let k = key(world);
  var color = mix(vec3f(0.02, 0.05, 0.08), vec3f(0.05, 0.12, 0.16), fbm(world * 3.0));
  color += vec3f(1.0, 0.62, 0.3) * (smoothstep(0.012, 0.0, k) * (0.4 + glow) + exp(-max(k, 0.0) * 14.0) * glow * 0.6);

  // Each shard near this pixel may have flown over it: undo that shard's flight
  // and see whether the pixel lands back inside it.
  let home = floor(p);
  for (var y = -1; y <= 1; y++) {
    for (var x = -1; x <= 1; x++) {
      let cell = home + vec2f(f32(x), f32(y));
      let centre = seed(cell);
      let away = centre - blow;
      let reach = length(away);
      let late = clamp(burst * 1.8 - reach * 0.12, 0.0, 1.0);
      let shrink = 1.0 - 0.5 * late;
      let angle = (hash21(cell + 4.2) - 0.5) * 3.2 * late;
      let drift = normalize(away + vec2f(0.0001)) * 0.42 * late + (hash22(cell + 1.7) - 0.5) * 0.3 * late;
      let local = spin(p - centre - drift, -angle) / shrink + centre;
      let found = nearest(local);
      if (all(found.xy == cell)) {
        let surface = local / CELLS;
        let etched = smoothstep(0.02, 0.0, abs(key((surface / vec2f(aspect, 1.0) - 0.5) * vec2f(aspect, 1.0) * 1.6)) - 0.004);
        let frost = fbm(surface * 40.0) * 0.08;
        let crack = smoothstep(0.06, 0.0, found.z) * smoothstep(0.0, 0.08, burst);
        let edge = smoothstep(0.08, 0.0, found.z) * late;
        var glass = vec3f(0.62, 0.72, 0.76) + frost + etched * 0.22;
        glass += vec3f(0.898, 0.89, 0.824) * (crack * (1.0 - late) * 0.8 + edge * 0.7);
        let light = 0.75 + 0.25 * sin(angle * 2.0 + surface.x * 3.0);
        color = mix(color, glass * light, 0.86 - 0.18 * late);
      }
    }
  }
  return vec4f(color, 1.0);
}`

export const shatter: Wonder<Shatter> = {
  wgsl,
  continuous: false,
  state: () => ({x: 0.5, y: 0.5, burst: 0, glow: 0}),
  bindings: (state, view) => ({
    params: {view: [view.width, view.height, 0, 0], blow: [state.x, state.y, state.burst, state.glow]},
  }),
  play({root, stage, state, nudge, say}) {
    let broken = false
    let moving: Timeline | undefined
    say("Whole")

    const strike = (x: number, y: number) => {
      moving?.cancel()
      broken = !broken
      if (broken) {
        Object.assign(state, {x, y})
        say("Shattered")
        moving = createTimeline({onUpdate: nudge})
          .add(state, {burst: [{to: 0.06, duration: 220, ease: "outQuad"}, {to: 1, duration: 1300, ease: "outExpo"}]})
          .add(state, {glow: 1, duration: 900, ease: "outQuad"}, 260)
      } else {
        say("Whole")
        moving = createTimeline({onUpdate: nudge})
          .add(state, {burst: 0, ease: spring({bounce: 0.35, duration: 1400})})
          .add(state, {glow: 0, duration: 700, ease: "inQuad"}, 0)
      }
    }

    return {
      release: all(
        listen(stage, "pointerdown", event => strike(...across(stage, event))),
        onAction(root, "strike", () => strike(0.5, 0.5)),
      ),
    }
  },
}
