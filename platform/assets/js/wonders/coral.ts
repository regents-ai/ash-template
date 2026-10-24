/**
 * Living coral: two chemicals feeding on and spreading through each other, a
 * pattern that grows by itself from whatever it was a moment before. Draw on it
 * with the pointer. Each pattern button slowly changes the feed, so the growth
 * turns from coral into a maze or into dividing cells as you watch.
 *
 * A brush follows a spiral on the first frame to plant the first growth.
 */
import {animate, createAnimatable, createTimeline, type Timeline} from "animejs"

import {across, all, listen, onAction, type Wonder} from "./wonder"

type Coral = {feed: number; kill: number; brushX: number; brushY: number; size: number; paint: number}

const PATTERNS: Record<string, {feed: number; kill: number; name: string}> = {
  coral: {feed: 0.0545, kill: 0.062, name: "Coral"},
  maze: {feed: 0.029, kill: 0.057, name: "Maze"},
  cells: {feed: 0.0367, kill: 0.0649, name: "Cells"},
}

const SIZE: [number, number] = [320, 200]

// One step of the growth. The texture keeps (1 - a, b), so a fresh, all-zero texture
// is the resting state: all of the first chemical and none of the second.
const steps = /* wgsl */ `
struct Steps { rates: vec4f, brush: vec4f, }
@group(0) @binding(0) var<uniform> steps: Steps;
@group(0) @binding(1) var src: texture_2d<f32>;

fn at(c: vec2i, size: vec2i) -> vec2f {
  let t = textureLoad(src, (c + size) % size, 0).xy;
  return vec2f(1.0 - t.x, t.y);
}

@fragment fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let size = vec2i(i32(steps.rates.z), i32(steps.rates.w));
  let c = vec2i(position.xy);
  let here = at(c, size);
  var spread = -here;
  spread += 0.2 * (at(c + vec2i(1, 0), size) + at(c - vec2i(1, 0), size) + at(c + vec2i(0, 1), size) + at(c - vec2i(0, 1), size));
  spread += 0.05 * (at(c + vec2i(1, 1), size) + at(c - vec2i(1, 1), size) + at(c + vec2i(1, -1), size) + at(c - vec2i(1, -1), size));
  let feed = steps.rates.x;
  let kill = steps.rates.y;
  let meet = here.x * here.y * here.y;
  var a = clamp(here.x + spread.x - meet + feed * (1.0 - here.x), 0.0, 1.0);
  var b = clamp(here.y + 0.5 * spread.y + meet - (feed + kill) * here.y, 0.0, 1.0);
  let place = (vec2f(c) + 0.5) / vec2f(size);
  let reach = length((place - steps.brush.xy) * vec2f(f32(size.x) / f32(size.y), 1.0));
  let touched = smoothstep(steps.brush.z, steps.brush.z * 0.6, reach) * steps.brush.w;
  b = max(b, touched * 0.9);
  a = min(a, 1.0 - touched * 0.5);
  return vec4f(1.0 - a, b, 0.0, 1.0);
}`

const wgsl = /* wgsl */ `
struct Params { view: vec4f, }
@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var field: texture_2d<f32>;

fn grown(p: vec2f) -> f32 {
  let size = vec2f(textureDimensions(field));
  let texel = p * size - 0.5;
  let base = floor(texel);
  let f = texel - base;
  let c = vec2i(base);
  let limit = vec2i(size) - 1;
  let a = textureLoad(field, clamp(c, vec2i(0), limit), 0).y;
  let b = textureLoad(field, clamp(c + vec2i(1, 0), vec2i(0), limit), 0).y;
  let d = textureLoad(field, clamp(c + vec2i(0, 1), vec2i(0), limit), 0).y;
  let e = textureLoad(field, clamp(c + vec2i(1, 1), vec2i(0), limit), 0).y;
  return mix(mix(a, b, f.x), mix(d, e, f.x), f.y);
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let pixel = 1.0 / vec2f(textureDimensions(field));
  let v = grown(uv);
  let slope = vec2f(grown(uv + vec2f(pixel.x, 0.0)) - grown(uv - vec2f(pixel.x, 0.0)),
                    grown(uv + vec2f(0.0, pixel.y)) - grown(uv - vec2f(0.0, pixel.y)));
  let light = clamp(0.5 + dot(slope, vec2f(-1.0, -1.2)) * 3.0, 0.0, 1.0);
  let body = smoothstep(0.12, 0.32, v);
  let ground = mix(vec3f(0.05, 0.08, 0.1), vec3f(0.08, 0.14, 0.17), uv.y);
  let flesh = mix(vec3f(1.0, 0.357, 0.098), vec3f(1.0, 0.608, 0.561), smoothstep(0.25, 0.45, v));
  var color = mix(ground, flesh * (0.55 + 0.7 * light), body);
  color += vec3f(0.898, 0.89, 0.824) * pow(light, 6.0) * body * 0.5;
  color += vec3f(0.682, 0.792, 0.804) * smoothstep(0.02, 0.1, v) * (1.0 - body) * 0.25;
  return vec4f(color, 1.0);
}`

export const coral: Wonder<Coral> = {
  wgsl,
  continuous: true,
  simulation: {
    wgsl: steps,
    size: SIZE,
    steps: 12,
    bindings: state => ({
      steps: {rates: [state.feed, state.kill, ...SIZE], brush: [state.brushX, state.brushY, state.size, state.paint]},
    }),
  },
  state: () => ({...PATTERNS.coral!, brushX: 0.5, brushY: 0.5, size: 0.03, paint: 0}),
  bindings: (_state, view) => ({params: {view: [view.width, view.height, view.time, 0]}}),
  play({root, stage, state, say}) {
    const brush = createAnimatable(state, {brushX: 120, brushY: 120, ease: "out(2)"})
    let painting = false
    let planting: Timeline | undefined
    say(PATTERNS.coral!.name)

    const stroke = (event: PointerEvent) => {
      const [x, y] = across(stage, event)
      brush.brushX!(x)
      brush.brushY!(y)
    }

    // The brush draws a spiral out from the middle, then lifts.
    const plant = () => {
      planting?.cancel()
      const turns = {t: 0}
      planting = createTimeline()
        .add(state, {paint: 1, duration: 1})
        .add(turns, {
          t: 1,
          duration: 2600,
          ease: "inOutSine",
          onUpdate: () => {
            const angle = turns.t * Math.PI * 7
            const out = 0.04 + turns.t * 0.3
            state.brushX = 0.5 + Math.cos(angle) * out * 0.62
            state.brushY = 0.5 + Math.sin(angle) * out
          },
        })
        .add(state, {paint: 0, duration: 1})
    }

    return {
      ready: plant,
      release: all(
        listen(stage, "pointerdown", event => {
          planting?.cancel()
          painting = true
          stage.setPointerCapture(event.pointerId)
          Object.assign(state, {paint: 1, size: 0.03})
          const [x, y] = across(stage, event)
          Object.assign(state, {brushX: x, brushY: y})
        }),
        listen(stage, "pointermove", event => {
          if (painting) stroke(event)
        }),
        listen(stage, "pointerup", () => {
          painting = false
          state.paint = 0
        }),
        onAction(root, "pattern", button => {
          const pattern = PATTERNS[button.dataset.pattern!]!
          say(pattern.name)
          for (const choice of root.querySelectorAll<HTMLElement>("[data-pattern]"))
            choice.setAttribute("aria-pressed", String(choice === button))
          animate(state, {feed: pattern.feed, kill: pattern.kill, duration: 2400, ease: "inOutSine"})
        }),
        onAction(root, "plant", plant),
      ),
    }
  },
}
