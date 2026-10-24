/**
 * Warp drive: a field of stars that stretch into streaks as the ship gathers speed.
 * Hold the button and the drive builds to light speed, where the sky goes white;
 * let go and it eases back to a cruise. The pointer steers.
 */
import {animate, createAnimatable, createTimeline, spring, type Timeline} from "animejs"

import {across, all, listen, noiseWgsl, type Wonder} from "./wonder"

type Warp = {speed: number; flash: number; steerX: number; steerY: number; travel: number; at: number}

const CRUISE = 0.12

const wgsl = noiseWgsl + /* wgsl */ `
struct Params { view: vec4f, drive: vec4f, steer: vec4f, }
@group(0) @binding(0) var<uniform> params: Params;

fn streaks(p: vec2f, count: f32, travel: f32, speed: f32, seed: f32) -> f32 {
  let r = length(p);
  let sector = (atan2(p.y, p.x) / 6.2831853 + 0.5) * count;
  let cell = floor(sector);
  let across = abs(fract(sector) - 0.5) / count * 6.2831853 * r;
  let chance = hash21(vec2f(cell, seed));
  let lane = fract(chance * 7.13 + travel * (0.4 + chance));
  let place = lane * lane * 1.6;
  let tail = 0.01 + speed * speed * 0.55 * place;
  let along = smoothstep(place - tail, place, r) * smoothstep(place + 0.004, place, r);
  let width = 0.0018 + 0.003 * place;
  return along * smoothstep(width, 0.0, across) * step(0.35, chance) * smoothstep(0.0, 0.2, place);
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let aspect = params.view.x / max(params.view.y, 1.0);
  let speed = params.drive.x;
  let flash = params.drive.y;
  let travel = params.drive.z;
  // The stars stream from the point the ship is heading for, which leans towards the pointer.
  let centre = vec2f(0.5) + (params.steer.xy - vec2f(0.5)) * 0.35;
  let p = (uv - centre) * vec2f(aspect, 1.0);
  let light = streaks(p, 220.0, travel, speed, 1.0) + streaks(p, 140.0, travel * 0.7, speed, 2.0) * 0.8 + streaks(p, 90.0, travel * 0.45, speed, 3.0) * 0.6;
  let r = length(p);
  let blue = mix(vec3f(0.82, 0.86, 0.92), vec3f(0.55, 0.78, 1.0), speed);
  var color = vec3f(0.012, 0.014, 0.022) + blue * light * (1.0 + speed * 2.0);
  // The tunnel wall wraps once around the heading: two samples blended across the turn, so it has no seam.
  let turn = atan2(p.y, p.x) / 6.2831853 + 0.5;
  let depth = 1.0 / max(r, 0.05) - travel * 2.0;
  let tunnel = mix(fbm(vec2f(turn * 18.85, depth)), fbm(vec2f((turn - 1.0) * 18.85, depth)), turn);
  color += vec3f(0.06, 0.04, 0.12) * fbm(p * 2.2 + vec2f(travel * 0.04, 3.0)) * (1.0 - speed * 0.5);
  color += vec3f(0.12, 0.28, 0.6) * tunnel * smoothstep(0.3, 1.0, speed) * smoothstep(0.05, 0.6, r);
  color += vec3f(1.0, 0.55, 0.3) * exp(-r * 9.0) * (0.15 + speed * 0.6);
  color = mix(color, vec3f(1.0, 0.98, 0.95), flash);
  return vec4f(vec3f(1.0) - exp(-color * 1.4), 1.0);
}`

export const warp: Wonder<Warp> = {
  wgsl,
  continuous: true,
  state: () => ({speed: CRUISE, flash: 0, steerX: 0.5, steerY: 0.5, travel: 0, at: 0}),
  bindings(state, view) {
    // Distance travelled is speed summed over time, so a change of speed never jumps the stars.
    state.travel += state.speed * Math.min(0.05, Math.max(0, view.time - state.at)) * 1.6
    state.at = view.time
    return {
      params: {
        view: [view.width, view.height, view.time, 0],
        drive: [state.speed, state.flash, state.travel, 0],
        steer: [state.steerX, state.steerY, 0, 0],
      },
    }
  },
  play({root, stage, state, say}) {
    const steer = createAnimatable(state, {steerX: 700, steerY: 700, ease: "out(3)"})
    const button = root.querySelector<HTMLButtonElement>("[data-wonder-action='launch']")!
    const read = () => say(state.flash > 0.5 ? "Light speed" : `${Math.round(state.speed * 100)}% of light speed`)
    read()

    let launch: Timeline | undefined
    const hold = () => {
      launch?.cancel()
      launch = createTimeline({onUpdate: read})
        .add(state, {speed: 1, duration: 2600, ease: "inQuad"})
        .add(state, {flash: [{to: 1, duration: 140, ease: "outQuad"}, {to: 0, duration: 900, ease: "inOutSine"}]})
    }
    const letGo = () => {
      launch?.cancel()
      launch = undefined
      animate(state, {speed: CRUISE, flash: 0, ease: spring({bounce: 0.2, duration: 1600}), onUpdate: read})
    }
    const holding = (event: KeyboardEvent) => event.key === " " || event.key === "Enter"

    return {
      release: all(
        listen(button, "pointerdown", hold),
        listen(button, "pointerup", letGo),
        listen(button, "pointerleave", letGo),
        listen(button, "keydown", event => {
          if (holding(event) && !event.repeat) hold()
        }),
        listen(button, "keyup", event => {
          if (holding(event)) letGo()
        }),
        listen(stage, "pointermove", event => {
          const [x, y] = across(stage, event)
          steer.steerX!(x)
          steer.steerY!(y)
        }),
      ),
    }
  },
}
