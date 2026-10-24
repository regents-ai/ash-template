/**
 * Ink bloom: drops of colour spreading through slow, folding water. Tap the water
 * to drop the chosen ink; move across it to stir. Each drop blooms on an elastic
 * curve, then thins away.
 */
import {animate, createAnimatable, createTimeline, utils} from "animejs"

import {across, all, listen, noiseWgsl, onAction, type Wonder} from "./wonder"

type Drop = {x: number; y: number; size: number; strength: number; ink: number}
type Ink = {drops: Drop[]; stirX: number; stirY: number; swirl: number; ink: number}

const DROPS = 6

const INKS: readonly (readonly [number, number, number])[] = [
  [1.0, 0.357, 0.098],
  [0.36, 0.62, 0.95],
  [0.494, 0.847, 0.663],
]
const NAMES = ["Tangerine", "Powder blue", "Green"]

const wgsl = noiseWgsl + /* wgsl */ `
struct Params { view: vec4f, stir: vec4f, drops: array<vec4f, ${DROPS}>, inks: array<vec4f, ${DROPS}>, }
@group(0) @binding(0) var<uniform> params: Params;

fn turn(p: vec2f, angle: f32) -> vec2f {
  let c = cos(angle);
  let s = sin(angle);
  return vec2f(c * p.x - s * p.y, s * p.x + c * p.y);
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let aspect = params.view.x / max(params.view.y, 1.0);
  let time = params.view.z;
  var p = uv * vec2f(aspect, 1.0);
  // Stirring twists the water around the pointer, most of all close to it.
  let stir = params.stir.xy * vec2f(aspect, 1.0);
  let near = exp(-dot(p - stir, p - stir) * 9.0);
  p = stir + turn(p - stir, params.stir.z * near * 2.6);
  let warp = vec2f(fbm(p * 2.0 + vec2f(0.0, time * 0.05)), fbm(p * 2.0 + vec2f(5.2, 1.3 - time * 0.04)));
  let flow = p + (warp - 0.5) * 0.35;
  let grain = fbm(flow * 7.0 + time * 0.02);
  var color = mix(vec3f(0.07, 0.075, 0.08), vec3f(0.13, 0.14, 0.15), grain);
  for (var i = 0; i < ${DROPS}; i++) {
    let drop = params.drops[i];
    if (drop.w <= 0.001) { continue; }
    let centre = drop.xy * vec2f(aspect, 1.0);
    let reach = max(drop.z, 0.001);
    let edge = (fbm(flow * 5.0 + f32(i) * 3.1) - 0.5) * 0.55;
    let d = length(flow - centre) / reach + edge;
    let body = smoothstep(1.0, 0.25, d);
    let rim = smoothstep(0.7, 0.95, d) * smoothstep(1.1, 0.95, d);
    let tendrils = smoothstep(0.55, 0.85, fbm(flow * 11.0 - f32(i))) * smoothstep(1.6, 0.6, d);
    let ink = params.inks[i].rgb;
    let amount = clamp((body * 0.8 + tendrils * 0.45) * drop.w, 0.0, 0.92);
    color = mix(color, ink * (0.75 + 0.35 * grain), amount);
    color = mix(color, ink * 0.35, rim * drop.w * 0.5);
  }
  let sheen = pow(max(0.0, 1.0 - length(uv - vec2f(0.3, 0.2)) * 1.4), 3.0);
  return vec4f(color + sheen * 0.06, 1.0);
}`

export const ink: Wonder<Ink> = {
  wgsl,
  continuous: true,
  state: () => ({
    drops: Array.from({length: DROPS}, () => ({x: 0.5, y: 0.5, size: 0, strength: 0, ink: 0})),
    stirX: 0.5,
    stirY: 0.5,
    swirl: 0,
    ink: 0,
  }),
  bindings: (state, view) => ({
    params: {
      view: [view.width, view.height, view.time, 0],
      stir: [state.stirX, state.stirY, state.swirl, 0],
      drops: state.drops.map(drop => [drop.x, drop.y, drop.size, drop.strength]),
      inks: state.drops.map(drop => [...INKS[drop.ink]!, 1]),
    },
  }),
  play({root, stage, state, say}) {
    const follow = createAnimatable(state, {stirX: 500, stirY: 500, ease: "out(4)"})
    let next = 0
    let last: [number, number] | undefined
    say(NAMES[state.ink]!)

    const bloom = (x: number, y: number, ink = state.ink) => {
      const drop = state.drops[next]!
      next = (next + 1) % DROPS
      Object.assign(drop, {x, y, size: 0, strength: 1, ink})
      createTimeline()
        .add(drop, {size: utils.random(0.22, 0.36, 3), duration: 2200, ease: "outElastic(1, .55)"})
        .add(drop, {strength: 0, duration: 6500, ease: "inQuad"}, 2600)
    }

    return {
      // Three drops open the picture, one of each ink.
      ready: () => {
        const opening = createTimeline()
        INKS.forEach((_, index) => opening.call(() => bloom(0.28 + index * 0.22, 0.42 + (index % 2) * 0.16, index), index * 380))
      },
      release: all(
        listen(stage, "pointerdown", event => bloom(...across(stage, event))),
        listen(stage, "pointermove", event => {
          const [x, y] = across(stage, event)
          follow.stirX!(x)
          follow.stirY!(y)
          const moved = last ? Math.hypot(x - last[0], y - last[1]) : 0
          last = [x, y]
          animate(state, {
            swirl: [
              {to: Math.min(1.4, state.swirl + moved * 6), duration: 160, ease: "outQuad"},
              {to: 0, duration: 1600, ease: "outCubic"},
            ],
          })
        }),
        onAction(root, "ink", button => {
          state.ink = Number(button.dataset.ink)
          say(NAMES[state.ink]!)
          for (const choice of root.querySelectorAll<HTMLElement>("[data-ink]"))
            choice.setAttribute("aria-pressed", String(choice === button))
          bloom(utils.random(0.2, 0.8, 3), utils.random(0.25, 0.75, 3))
        }),
      ),
    }
  },
}
