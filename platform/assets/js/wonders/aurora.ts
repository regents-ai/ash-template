/**
 * Northern lights: curtains of light over a still sea at night, mirrored in the
 * water. The pointer is the wind. A storm brightens the curtains one after another
 * and turns them from green to violet, then lets them fade back.
 */
import {createAnimatable, createTimeline, stagger, type Timeline} from "animejs"

import {across, all, listen, noiseWgsl, onAction, type Wonder} from "./wonder"

type Curtain = {strength: number}
type Aurora = {curtains: Curtain[]; storm: number; wind: number}

/** How bright each curtain is on a calm night. */
const REST = [1, 0.7, 0.5]

const wgsl = noiseWgsl + /* wgsl */ `
struct Params { view: vec4f, sky: vec4f, curtains: vec4f, }
@group(0) @binding(0) var<uniform> params: Params;

const HORIZON = 0.7;

fn curtain(x: f32, y: f32, k: f32, time: f32, storm: f32, wind: f32) -> vec3f {
  let drift = time * (0.035 + storm * 0.06) + wind * 0.4;
  let base = 0.38 + k * 0.07 + 0.09 * sin(x * (2.2 + k) + drift * 3.0 + k * 2.0) + 0.08 * (fbm(vec2f(x * 1.7 + k * 4.0, drift)) - 0.5);
  let above = base - y;
  if (above < -0.01) { return vec3f(0.0); }
  let rays = 0.35 + 0.65 * pow(noise(vec2f(x * (38.0 + k * 9.0) + drift * 9.0, k * 5.0 + time * 0.25)), 2.0);
  let fall = exp(-max(above, 0.0) * (5.0 - storm * 2.0)) * smoothstep(-0.01, 0.006, above);
  let green = vec3f(0.3, 1.0, 0.55);
  let violet = vec3f(0.62, 0.36, 1.0);
  let top = mix(vec3f(0.4, 0.3, 0.9), vec3f(1.0, 0.35, 0.6), storm);
  let low = mix(green, violet, storm * 0.7);
  return mix(low, top, smoothstep(0.0, 0.3, above)) * rays * fall;
}

fn sky(uv: vec2f, aspect: f32) -> vec3f {
  let time = params.view.z;
  let storm = params.sky.x;
  let wind = params.sky.y;
  let x = uv.x * aspect;
  var color = mix(vec3f(0.01, 0.02, 0.05), vec3f(0.03, 0.06, 0.1), uv.y / HORIZON);
  let cell = floor(uv * vec2f(aspect, 1.0) * 120.0);
  color += vec3f(0.9) * step(0.996, hash21(cell)) * (0.5 + 0.5 * sin(time * 2.0 + hash21(cell + 1.0) * 40.0));
  for (var k = 0; k < 3; k++) {
    color += curtain(x, uv.y, f32(k), time, storm, wind) * params.curtains[k] * 0.9;
  }
  let ridge = HORIZON - 0.05 * fbm(vec2f(x * 3.0, 2.0)) - 0.03 * smoothstep(0.3, 0.0, abs(uv.x - 0.72));
  return mix(color, vec3f(0.005, 0.008, 0.012), smoothstep(ridge - 0.002, ridge + 0.002, uv.y));
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let aspect = params.view.x / max(params.view.y, 1.0);
  let time = params.view.z;
  if (uv.y < HORIZON) { return vec4f(sky(uv, aspect), 1.0); }
  // The sea mirrors the sky, broken up by slow swell.
  let depth = uv.y - HORIZON;
  let swell = (fbm(vec2f(uv.x * aspect * 6.0, depth * 40.0 - time * 0.3)) - 0.5) * 0.04 * (depth * 4.0 + 0.2);
  let mirrored = vec2f(uv.x + swell, HORIZON - depth * 1.4 - 0.004);
  let water = sky(mirrored, aspect) * (0.55 - depth * 0.8);
  return vec4f(water + vec3f(0.005, 0.01, 0.018), 1.0);
}`

export const aurora: Wonder<Aurora> = {
  wgsl,
  continuous: true,
  state: () => ({curtains: REST.map(strength => ({strength})), storm: 0, wind: 0}),
  bindings: (state, view) => ({
    params: {
      view: [view.width, view.height, view.time, 0],
      sky: [state.storm, state.wind, 0, 0],
      curtains: [...state.curtains.map(curtain => curtain.strength), 0],
    },
  }),
  play({root, stage, state, say}) {
    const wind = createAnimatable(state, {wind: 2400, ease: "out(2)"})
    let storm: Timeline | undefined
    say("Calm")

    return {
      release: all(
        listen(stage, "pointermove", event => {
          wind.wind!(across(stage, event)[0] - 0.5)
        }),
        onAction(root, "storm", () => {
          storm?.cancel()
          say("Storm")
          storm = createTimeline()
            .add(state, {storm: 1, duration: 1800, ease: "outQuad"})
            .add(state.curtains, {strength: [{to: 2.4, duration: 700, ease: "outExpo"}, {to: 1.4, duration: 1400}], delay: stagger(260)}, 0)
            .add(state, {storm: 0, duration: 4200, ease: "inOutSine"}, "+=2200")
          REST.forEach((strength, i) => storm!.add(state.curtains[i]!, {strength, duration: 3600, ease: "inOutSine"}, "<<"))
          storm.call(() => say("Calm"))
        }),
      ),
    }
  },
}
