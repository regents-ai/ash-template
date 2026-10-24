/**
 * Event horizon: a black hole bending the starlight behind it, with a burning disc
 * whose far side the hole lifts into view above it. Drag the hole across the sky and
 * let go to watch it spring home; feed it and it flares, then grows.
 */
import {createAnimatable, createTimeline, spring} from "animejs"

import {across, all, listen, noiseWgsl, onAction, type Wonder} from "./wonder"

type Horizon = {x: number; y: number; mass: number; flare: number}

const wgsl = noiseWgsl + /* wgsl */ `
struct Params { view: vec4f, hole: vec4f, }
@group(0) @binding(0) var<uniform> params: Params;

fn stars(sky: vec2f) -> vec3f {
  var light = vec3f(0.0);
  for (var layer = 0; layer < 3; layer++) {
    let scale = 34.0 + f32(layer) * 38.0;
    let p = sky * scale + f32(layer) * 17.0;
    let cell = floor(p);
    let place = hash22(cell) * 0.7 + 0.15;
    let chance = hash21(cell + 9.1);
    let glint = smoothstep(0.09 - f32(layer) * 0.02, 0.0, length(fract(p) - place)) * step(0.82, chance);
    let tint = mix(vec3f(0.682, 0.792, 0.804), vec3f(1.0, 0.86, 0.72), hash21(cell + 3.7));
    light += glint * tint * (1.6 - f32(layer) * 0.4);
  }
  let cloud = fbm(sky * 2.2);
  light += vec3f(0.05, 0.035, 0.09) * cloud + vec3f(0.16, 0.05, 0.01) * pow(fbm(sky * 3.1 + 7.0), 4.0);
  return light;
}

fn disc(q: vec2f, horizon: f32, time: f32, flare: f32) -> vec4f {
  let level = vec2f(q.x, q.y * 4.2);
  let d = length(level);
  let inner = horizon * 1.45;
  let outer = horizon * (4.2 + flare * 1.4);
  let band = smoothstep(inner, inner * 1.3, d) * (1.0 - smoothstep(outer * 0.55, outer, d));
  let turn = atan2(level.y, level.x);
  let swirl = fbm(vec2f(turn * 2.0 - time * 1.4 / (d * 7.0 + 0.25), d * 16.0));
  let towards = 0.55 + 0.55 * (-level.x / max(d, 0.0001));
  let heat = band * (0.3 + swirl) * towards * (1.0 + flare * 1.8);
  let color = mix(vec3f(1.0, 0.357, 0.098), vec3f(1.0, 0.93, 0.82), clamp(heat - 0.25, 0.0, 1.0));
  return vec4f(color * heat * 1.7, clamp(band * 1.4, 0.0, 1.0));
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let aspect = params.view.x / max(params.view.y, 1.0);
  let time = params.view.z;
  let flare = params.hole.w;
  let horizon = 0.055 + 0.07 * params.hole.z;
  let centre = params.hole.xy * vec2f(aspect, 1.0);
  let p = uv * vec2f(aspect, 1.0) - centre;
  let r = max(length(p), 0.0001);
  // Light passing the hole is bent around it: what lies behind shows up pushed
  // outwards, and a ring of it is folded right round.
  let einstein = horizon * 1.9;
  let lensed = p * (1.0 - einstein * einstein / (r * r));
  var color = stars(centre + lensed + vec2f(time * 0.004, 0.0));
  let far = disc(vec2f(lensed.x, -abs(lensed.y)), horizon, time, flare);
  color += far.rgb * 0.8;
  color *= smoothstep(horizon * 0.98, horizon * 1.04, r);
  let ring = exp(-pow((r - horizon * 1.1) / (horizon * 0.06), 2.0));
  color += vec3f(1.0, 0.78, 0.6) * ring * (0.7 + flare * 1.5);
  let near = disc(p, horizon, time, flare);
  let front = step(0.0, p.y) * near.a;
  color = mix(color, near.rgb, front * 0.85) + near.rgb * 0.25 * (1.0 - front);
  color = vec3f(1.0) - exp(-color * 1.25);
  let edge = smoothstep(1.25, 0.35, length((uv - 0.5) * vec2f(aspect, 1.0)));
  return vec4f(color * (0.55 + 0.45 * edge), 1.0);
}`

export const horizon: Wonder<Horizon> = {
  wgsl,
  continuous: true,
  state: () => ({x: 0.5, y: 0.5, mass: 0.35, flare: 0}),
  bindings: (state, view) => ({
    params: {view: [view.width, view.height, view.time, 0], hole: [state.x, state.y, state.mass, state.flare]},
  }),
  play({root, stage, state, say}) {
    const follow = createAnimatable(state, {x: 380, y: 380, ease: "out(3)"})
    let dragging = false
    const suns = () => say(`${Math.round(4 + state.mass * 36)} suns`)
    suns()

    // Let go and the hole springs home, overshooting and settling like a rubber band.
    const home = () => {
      dragging = false
      follow.x!(0.5, 1300, "outElastic(1, .4)")
      follow.y!(0.5, 1300, "outElastic(1, .4)")
    }
    const feed = () => {
      const heavier = state.mass > 0.92 ? 0.3 : Math.min(1, state.mass + 0.16)
      createTimeline()
        .add(state, {flare: [0, 1], duration: 420, ease: "outExpo"})
        .add(state, {flare: 0, duration: 2400, ease: "inOutSine"})
        .add(state, {mass: heavier, ease: spring({bounce: 0.45, duration: 1200}), onUpdate: suns}, 300)
    }

    return {
      release: all(
        listen(stage, "pointerdown", event => {
          dragging = true
          stage.setPointerCapture(event.pointerId)
          const [x, y] = across(stage, event)
          follow.x!(x)
          follow.y!(y)
        }),
        listen(stage, "pointermove", event => {
          if (!dragging) return
          const [x, y] = across(stage, event)
          follow.x!(Math.min(0.92, Math.max(0.08, x)))
          follow.y!(Math.min(0.9, Math.max(0.1, y)))
        }),
        listen(stage, "pointerup", home),
        listen(stage, "pointercancel", home),
        onAction(root, "feed", feed),
      ),
    }
  },
}
