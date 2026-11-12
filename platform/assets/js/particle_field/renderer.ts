/**
 * Draws the particle field with WebGPU through vgpu: 80,000 grains, each with a
 * home in the current shape (particle_field/shapes.ts).
 *
 * One compute pass moves every grain. A new shape tears the old one loose: the
 * release sweeps across it from the left, so one end streams away while the
 * rest still stands. Each grain flies from where it let go to its new home
 * while one slow field of wind bends the whole stream at once, and the new
 * shape swings round to face the page as it forms, so the stream twists like a
 * ribbon. Grains bound for the new shape's rim land first, its middle fills
 * after, and a few strays blow loose as dust and land last. A grain keeps its
 * colour and its light until it lands. A new shape mid-flight starts from
 * wherever the grains are, at the speed they are going. A value change only
 * moves the homes, so the grains follow on a stiff spring without flying again.
 *
 * The grains are drawn as soft points added together into a float picture. On a
 * dark page they give light, lit more on the side the light falls on, and the
 * lit ones glow, from a blurred quarter-size copy of their light; on a light page
 * they are ink, denser on the side turned from the light, and nothing glows.
 * Nothing glows outside the canvas.
 *
 * Loaded only once the picture is really going to be drawn; the hook
 * (hooks/particle_field.ts) keeps the shape, the value and the colours.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {compute, draw, effect, frame, init, sampler, storage, surface, target} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import type {Rgb} from "../token_colour"
import {GRAINS, HOME_FLOATS, type Knob} from "./shapes"

/** What the field shows this frame, read afresh as each frame is drawn. */
export type FieldScene = {
  /** The canvas's CSS size; it reaches past the box by the same amount on every side. */
  width: number
  height: number
  /** CSS pixels per shape unit. */
  scale: number
  /** Half the shape's width in CSS pixels: what the release sweeps across when the next shape comes. */
  half: number
  value: number
  /** Square units the shape covers, so the grains on a small shape can each be fainter. */
  area: number
  knob: Knob | undefined
  turns: boolean
  light: boolean
  colours: {muted: Rgb; lit: Rgb; far: Rgb}
}

export type ParticleFieldRenderer = IslandRenderer & {
  /** Where each frame's scene comes from. */
  show(read: () => FieldScene): void
  /** A new shape: every grain's home, in flying order (`inFlightOrder`). */
  place(homes: Float32Array<ArrayBuffer>): void
}

const WORKGROUP = 64
const GRAIN_FLOATS = 20
const SCENE_FORMAT = "rgba16float"
/** Seconds the release takes to sweep across the shape the grains are leaving, and how unevenly grains let go about it. */
const SWEEP = 0.55
const SPREAD = 0.08
/** Seconds a grain flies: to the new shape's rim, to its flat middle, and as a stray, at least and how much longer at most. */
const RIM_FLIGHT = 0.55
const MIDDLE_FLIGHT = 0.9
const STRAY_FLIGHT = 1.45
const STRAY_SPREAD = 0.5
/** The share of grains that blow loose as strays. */
const STRAYS = 0.04
/** Seconds from a new shape until the last stray has landed and come to rest. */
const SHAPE_SETTLES = SWEEP + SPREAD + STRAY_FLIGHT + STRAY_SPREAD + 0.4
/** Seconds from a value or size change until the grains have followed it. */
const VALUE_SETTLES = 1.2
/** How far, in units, the wind bends the stream, and blows a stray out. */
const BEND = 0.12
const STRAY_BEND = 0.3
/** How far a stray drifts as dust, in units across, down and in depth, and how far it rises like smoke. */
const DUST = [1.2, 0.8, 0.6] as const
const RISE = 0.25
/**
 * How much more a grain gives at the middle of its flight, where the stream has
 * thinned, so the stream stays as bright as the shape it tore from; a stray, on
 * its own out in the dark, gives more again.
 */
const FLIGHT_GLOW = 0.6
const STRAY_GLOW = 3
/** How far round the new shape has swung, in radians, as a grain lets go for it. */
const SWING = 0.7
/** The stiff spring a grain rests on at home (per second), and its damping. */
const STIFF = 26
const DAMPING = 0.95
/** The longest step the grains take between two frames, so a pause never throws them. */
const LONGEST_STEP = 1 / 30
/** A spinner's arc: one turn in this many seconds. */
const TURN_SECONDS = 1.1
/** How bright one square device pixel of the shape's flat top is, all its grains together. */
const DARK_GLOW = 0.9
const LIGHT_INK = 1.1
/** How far the viewer is from the page, in units, as the forming shape swings in depth. */
const VIEWER = 7
/** On a dark page: how far the glow round lit grains reaches, as a share of a unit, and how strong it is. */
const HALO = 0.12
const HALO_STRENGTH = 1.2
/** How wide the blur's nine taps spread it, in taps, over its two rounds. */
const BLUR_REACH = 2.4

const homeWgsl = /* wgsl */ `
// Where the grain lives in units: at value 0 (xy) and 1 (zw).
// face: the sideways part of the way the surface faces (xy); the stretch of value it travels over (zw).
// light: the stretch of value it lights over (xy), its tone, its flags (1 behind the knob, 2 turns).
struct Home {
  place: vec4f,
  face: vec4f,
  light: vec4f,
}

// pos: where it is (xyz, CSS px from the box's centre, z away from the page); when it lets go (s after the change).
// vel: how fast it moves (px/s); the number of the shape it last noted.
// look: how lit it is, its tone, the facing it shows (zw).
// start: where it let go (xyz); how much of it shows, 0 behind the knob.
// kick: how fast it was going as it let go (xyz); how much light or ink it gives.
struct Grain {
  pos: vec4f,
  vel: vec4f,
  look: vec4f,
  start: vec4f,
  kick: vec4f,
}
`

export const simulateWgsl = /* wgsl */ `${homeWgsl}
struct Sim {
  // CSS px per unit, half the width in CSS px of the shape the grains are leaving, this frame's seconds, the clock in seconds.
  frame: vec4f,
  // The value shown, how far a turning part has turned (radians), seconds since the shape changed, the shape's number.
  state: vec4f,
  // 1 to put every grain home at once, the side the forming shape swings in from, the viewer's distance in CSS px, unused.
  flight: vec4f,
  // The knob's centre at value 0 (xy) and at 1 (zw), in CSS px from the box's centre.
  knob: vec4f,
  // The knob's radius in CSS px (0 for none), unused, unused, unused.
  ball: vec4f,
  // How much one grain gives at home, and on or from the shape before, so a shape's flat top is as bright whatever its size; unused, unused.
  energy: vec4f,
}

@group(0) @binding(0) var<uniform> sim: Sim;
@group(0) @binding(1) var<storage, read> homes: array<Home>;
@group(0) @binding(2) var<storage, read_write> grains: array<Grain>;

const PI = 3.14159265;

fn hash(n: u32) -> f32 {
  var x = n * 747796405u + 2891336453u;
  x = ((x >> ((x >> 28u) + 4u)) ^ x) * 277803737u;
  x = (x >> 22u) ^ x;
  return f32(x) / 4294967295.0;
}

fn through(v: f32, stretch: vec2f) -> f32 {
  return clamp((v - stretch.x) / max(stretch.y - stretch.x, 1e-5), 0.0, 1.0);
}

// Wind: one slow, smooth field in units, nearly the same for neighbours, so it bends the whole stream at once.
fn wind(p: vec3f, t: f32) -> vec3f {
  return vec3f(
    sin(p.y * 2.3 + t * 1.1) + sin(p.z * 1.7 - t * 0.7),
    sin(p.x * 1.9 - t * 0.9) + sin(p.z * 2.1 + t * 0.6),
    sin(p.x * 1.4 + t * 0.8) + sin(p.y * 2.6 - t * 1.2),
  );
}

// How much of a grain at p shows: a track grain is hidden behind the knob, as seen from the viewer.
fn showing(p: vec3f, behind: bool) -> f32 {
  if (!behind || sim.ball.x <= 0.0) {
    return 1.0;
  }
  let eye = sim.flight.z;
  let at = p.xy * eye / max(eye + p.z, 1.0);
  let centre = mix(sim.knob.xy, sim.knob.zw, sim.state.x);
  return smoothstep(sim.ball.x - 1.5, sim.ball.x + 1.0, distance(at, centre));
}

@compute @workgroup_size(${WORKGROUP})
fn cs_main(@builtin(global_invocation_id) id: vec3u) {
  let i = id.x;
  if (i >= arrayLength(&grains)) {
    return;
  }
  let h = homes[i];
  let scale = sim.frame.x;
  let value = sim.state.x;
  var spot = mix(h.place.xy, h.place.zw, through(value, h.face.zw));
  if ((u32(h.light.w) & 2u) != 0u) {
    let c = cos(sim.state.y);
    let s = sin(sim.state.y);
    spot = vec2f(c * spot.x - s * spot.y, s * spot.x + c * spot.y);
  }
  let home = vec3f(spot * scale, 0.0);
  let look = vec4f(through(value, h.light.xy), h.light.z, h.face.xy);
  let behind = (u32(h.light.w) & 1u) != 0u;

  if (sim.flight.x > 0.5) {
    let shown = showing(home, behind);
    grains[i] = Grain(vec4f(home, -100.0), vec4f(0.0, 0.0, 0.0, sim.state.w), look, vec4f(home, shown), vec4f(0.0, 0.0, 0.0, sim.energy.x * shown));
    return;
  }

  var g = grains[i];
  let dt = sim.frame.z;
  if (g.vel.w != sim.state.w) {
    // A new shape. The grain lets go in its turn as the release sweeps across the
    // shape it is leaving from the left, so one end streams away while the rest stands.
    let across = clamp(g.pos.x / (2.0 * sim.frame.y) + 0.5, 0.0, 1.0);
    g.pos.w = across * ${SWEEP} + hash(i) * ${SPREAD};
    g.vel.w = sim.state.w;
    g.start = vec4f(g.pos.xyz, g.start.w);
    g.kick = vec4f(g.vel.xyz, g.kick.w);
  }
  let age = sim.state.z - g.pos.w;
  if (age < 0.0) {
    // Still holding on: it keeps its look and its light and, if it was moving, drifts to a stop where it is.
    let drift = g.vel.xyz * exp(-3.0 * dt);
    let p = g.pos.xyz + drift * dt;
    grains[i] = Grain(vec4f(p, g.pos.w), vec4f(drift, g.vel.w), g.look, vec4f(p, g.start.w), vec4f(drift, sim.energy.y * g.start.w));
    return;
  }

  let stray = hash(i * 5u + 1u) < ${STRAYS};
  // A grain bound for the rim lands first, so the new outline shows before its middle fills.
  let rim = smoothstep(0.3, 0.9, length(h.face.xy));
  var flight = mix(${MIDDLE_FLIGHT}, ${RIM_FLIGHT}, rim) * (0.9 + 0.2 * hash(i * 5u + 2u));
  if (stray) {
    flight = ${STRAY_FLIGHT} + ${STRAY_SPREAD} * hash(i * 5u + 3u);
  }
  let u = age / flight;
  if (u >= 1.0) {
    // Home, on a stiff spring, so a dragged knob keeps up with the finger. Damping
    // taken implicitly, so a long frame can never make the spring ring.
    let vel = (g.vel.xyz + (home - g.pos.xyz) * ${STIFF * STIFF} * dt) / (1.0 + ${2 * DAMPING * STIFF} * dt);
    let p = g.pos.xyz + vel * dt;
    let shown = showing(p, behind);
    grains[i] = Grain(vec4f(p, g.pos.w), vec4f(vel, g.vel.w), look, vec4f(g.start.xyz, shown), vec4f(g.kick.xyz, sim.energy.x * shown));
    return;
  }

  // The new shape swings round to face the page as each grain reaches it, so the stream between twists.
  let turn = sim.flight.y * ${SWING} * (1.0 - u) * (1.0 - u);
  let goal = vec3f(home.x * cos(turn), home.y, home.x * sin(turn));
  let u2 = u * u;
  let u3 = u2 * u;
  let eased = 3.0 * u2 - 2.0 * u3;
  // From where it let go, at the speed it was going, to rest at its new home.
  let path = g.start.xyz * (1.0 - eased) + g.kick.xyz * min(flight, 0.5) * (u3 - 2.0 * u2 + u) + goal * eased;
  let lift = sin(PI * u);
  let along = mix(g.start.xyz, goal, eased) / scale;
  var bend = wind(along, sim.frame.w) * ${BEND} * lift * lift;
  if (stray) {
    // A stray blows loose beyond the shape as dust and rises a little, like smoke.
    let dust = vec3f(hash(i * 5u + 4u), hash(i * 7u + 5u), hash(i * 11u + 6u)) - 0.5;
    bend = (wind(along, sim.frame.w) * ${STRAY_BEND} + dust * vec3f(${DUST.join(", ")}) - vec3f(0.0, ${RISE}, 0.0)) * lift;
  }
  let p = path + bend * scale;
  let vel = select(g.vel.xyz, (p - g.pos.xyz) / max(dt, 1e-4), dt > 0.0);
  // It keeps its colour and its light while it flies, and takes the new shape's as it
  // lands. Mid-flight it gives more, where the stream has thinned, so it does not fade.
  let landing = smoothstep(0.6, 0.95, u);
  let follow = 1.0 - exp(-30.0 * landing * dt);
  let shown = mix(g.start.w, mix(1.0, showing(p, behind), landing), 1.0 - exp(-12.0 * dt));
  let glow = 1.0 + select(f32(${FLIGHT_GLOW}), f32(${STRAY_GLOW}), stray) * lift;
  let gives = mix(sim.energy.y, sim.energy.x, landing) * shown * glow;
  grains[i] = Grain(vec4f(p, g.pos.w), vec4f(vel, g.vel.w), mix(g.look, look, follow), vec4f(g.start.xyz, shown), vec4f(g.kick.xyz, gives));
}
`

export const paintWgsl = /* wgsl */ `${homeWgsl}
struct View {
  // The canvas's CSS width and height, device px per CSS px, a grain's radius in device px.
  canvas: vec4f,
  // 1 on a light page, unused, unused, the viewer's distance in CSS px.
  look: vec4f,
  muted: vec4f,
  lit: vec4f,
  far: vec4f,
}

@group(0) @binding(0) var<uniform> view: View;
@group(0) @binding(1) var<storage, read> grains: array<Grain>;

struct Out {
  @builtin(position) position: vec4f,
  // Where in the point this corner is, in grain radii.
  @location(0) offset: vec2f,
  // Light or ink, premultiplied, and how much of it.
  @location(1) colour: vec4f,
}

@vertex fn vs_main(@builtin(vertex_index) vertex: u32, @builtin(instance_index) i: u32) -> Out {
  var corners = array<vec2f, 4>(vec2f(-1.0, -1.0), vec2f(1.0, -1.0), vec2f(-1.0, 1.0), vec2f(1.0, 1.0));
  let g = grains[i];
  let eye = view.look.w;
  let at = g.pos.xy * eye / max(eye + g.pos.z, 1.0);

  let facing = g.look.zw;
  let normal = vec3f(facing, sqrt(max(1.0 - dot(facing, facing), 0.0)));
  let light = max(dot(normal, normalize(vec3f(-0.5, -0.62, 0.6))), 0.0);
  let colour = mix(view.muted.rgb, mix(view.lit.rgb, view.far.rgb, g.look.y), g.look.x);

  let radius = view.canvas.w;
  let corner = corners[vertex] * radius * 2.0;
  let pixel = at * view.canvas.z + corner;
  let half = view.canvas.xy * 0.5 * view.canvas.z;
  var out: Out;
  out.position = vec4f(pixel.x / half.x, -pixel.y / half.y, 0.0, 1.0);
  out.offset = corners[vertex] * 2.0;
  // What the grain gives, as the simulation worked it out; lit grains give more, so the lit part reads at a glance.
  let amount = g.kick.w * mix(0.7, 1.3, g.look.x);
  if (view.look.x < 0.5) {
    // A dark page: grains give light, more on the side the light falls on. The lit
    // ones also give glow (alpha), which the composite spreads round them.
    out.colour = vec4f(colour * (0.28 + 0.9 * light) * amount, amount * g.look.x);
  } else {
    // A light page: grains are ink, denser on the side turned from the light.
    let ink = amount * (1.2 - 0.55 * light);
    out.colour = vec4f(colour * ink, ink);
  }
  return out;
}

@fragment fn fs_main(in: Out) -> @location(0) vec4f {
  let w = exp(-2.0 * dot(in.offset, in.offset));
  if (w < 0.02) {
    discard;
  }
  return in.colour * w;
}
`

export const downWgsl = /* wgsl */ `
struct Down {
  // One source texel (xy).
  texel: vec4f,
}

@group(0) @binding(0) var source: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> down: Down;

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let t = down.texel.xy;
  return 0.25 * (
    textureSampleLevel(source, samp, uv + vec2f(-t.x, -t.y), 0.0) +
    textureSampleLevel(source, samp, uv + vec2f(t.x, -t.y), 0.0) +
    textureSampleLevel(source, samp, uv + vec2f(-t.x, t.y), 0.0) +
    textureSampleLevel(source, samp, uv + vec2f(t.x, t.y), 0.0)
  );
}
`

export const blurWgsl = /* wgsl */ `
struct Blur {
  // How far apart the taps are along the way the blur runs (xy), in texture coordinates.
  step: vec4f,
}

@group(0) @binding(0) var source: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> blur: Blur;

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let weights = array<f32, 5>(0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
  var sum = textureSampleLevel(source, samp, uv, 0.0) * weights[0];
  for (var k = 1; k < 5; k++) {
    let offset = blur.step.xy * f32(k);
    sum += (textureSampleLevel(source, samp, uv + offset, 0.0) + textureSampleLevel(source, samp, uv - offset, 0.0)) * weights[k];
  }
  return sum;
}
`

export const compositeWgsl = /* wgsl */ `
struct Page {
  // 1 on a light page, how strong the glow round lit grains is, unused, unused.
  look: vec4f,
  // The colour lit grains glow in.
  lit: vec4f,
}

@group(0) @binding(0) var scene: texture_2d<f32>;
@group(0) @binding(1) var halo: texture_2d<f32>;
@group(0) @binding(2) var samp: sampler;
@group(0) @binding(3) var<uniform> page: Page;

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let grains = textureSampleLevel(scene, samp, uv, 0.0);
  if (page.look.x < 0.5) {
    // Light added up, with the lit grains' glow round them, and a soft shoulder so
    // a dense rim brightens instead of clipping flat.
    let glow = textureSampleLevel(halo, samp, uv, 0.0).a * page.look.y;
    let light = vec3f(1.0) - exp(-(grains.rgb + page.lit.rgb * glow));
    return vec4f(light, max(light.r, max(light.g, light.b)));
  }
  // Ink: each pixel takes the grains' own colour, as much as they cover it.
  let cover = 1.0 - exp(-grains.a);
  return vec4f(grains.rgb / max(grains.a, 1e-4) * cover, cover);
}
`

const rgba = (colour: Rgb): [number, number, number, number] => [colour[0], colour[1], colour[2], 1]

const quarter = (size: readonly [number, number]): [number, number] => [
  Math.max(1, Math.round(size[0] / 4)),
  Math.max(1, Math.round(size[1] / 4)),
]

export async function createParticleFieldRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<ParticleFieldRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a picture still in use reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  try {
    const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "premultiplied", label: "particle-field"})
    stage.resize([size[0], size[1]])
    const homes = storage(gpu, GRAINS * HOME_FLOATS * 4, "read")
    const grains = storage(gpu, GRAINS * GRAIN_FLOATS * 4, "read-write")
    const scene = target(gpu, {size: [size[0], size[1]], format: SCENE_FORMAT, label: "particle-field.scene"})
    const haloA = target(gpu, {size: quarter(size), format: SCENE_FORMAT, label: "particle-field.halo-a"})
    const haloB = target(gpu, {size: quarter(size), format: SCENE_FORMAT, label: "particle-field.halo-b"})
    const linear = sampler(gpu, {minFilter: "linear", magFilter: "linear", addressModeU: "clamp-to-edge", addressModeV: "clamp-to-edge"})

    const simulate = compute(gpu, prepareShader(simulateWgsl, "particle_simulate.wgsl"), {
      label: "particle-field.simulate",
      set: {
        sim: {frame: [1, 1, 0, 0], state: [0, 0, 0, 0], flight: [1, 1, 1, 0], knob: [0, 0, 0, 0], ball: [0, 0, 0, 0], energy: [0, 0, 0, 0]},
        homes,
        grains,
      },
    })
    const paint = draw(gpu, {
      shader: prepareShader(paintWgsl, "particle_paint.wgsl"),
      geometry: {topology: "triangle-strip"},
      vertices: 4,
      instances: GRAINS,
      blend: "additive",
      depth: false,
      label: "particle-field.paint",
      set: {
        view: {canvas: [1, 1, 1, 1], look: [0, 0, 0, 1], muted: [1, 1, 1, 1], lit: [1, 1, 1, 1], far: [1, 1, 1, 1]},
        grains,
      },
    })
    const down = effect(gpu, prepareShader(downWgsl, "particle_down.wgsl"), {
      label: "particle-field.down",
      set: {source: scene, samp: linear, down: {texel: [...scene.texelSize, 0, 0]}},
    })
    const blurAcross = effect(gpu, prepareShader(blurWgsl, "particle_blur.wgsl"), {
      label: "particle-field.blur-across",
      set: {source: haloA, samp: linear, blur: {step: [haloA.texelSize[0], 0, 0, 0]}},
    })
    const blurDown = effect(gpu, prepareShader(blurWgsl, "particle_blur.wgsl"), {
      label: "particle-field.blur-down",
      set: {source: haloB, samp: linear, blur: {step: [0, haloB.texelSize[1], 0, 0]}},
    })
    const composite = effect(gpu, prepareShader(compositeWgsl, "particle_composite.wgsl"), {
      label: "particle-field.composite",
      set: {scene, halo: haloA, samp: linear, page: {look: [0, 0, 0, 0], lit: [1, 1, 1, 1]}},
    })
    await Promise.all([
      simulate.compile(),
      paint.compile(scene),
      down.compile(haloA),
      blurAcross.compile(haloB),
      blurDown.compile(haloA),
      composite.compile(stage),
    ])

    let read: (() => FieldScene) | undefined
    let current: FieldScene | undefined
    let fresh = true
    let pending: Float32Array<ArrayBuffer> | undefined
    let shapeNumber = 0
    let swing = 1
    let clock = 0
    let since = 0
    let quietUntil = 0
    let turn = 0
    let dt = 0
    let energy = 0
    let energyBefore = 0
    let sweep = 1
    let lastHalf = 1
    let last: number | undefined
    let shown: {value: number; scale: number; width: number; height: number; light: boolean} | undefined

    const bind = () => {
      down.set({source: scene, down: {texel: [...scene.texelSize, 0, 0]}})
      blurAcross.set({source: haloA})
      blurDown.set({source: haloB})
      composite.set({scene, halo: haloA})
    }

    /** How much one grain gives so the shape's flat top is as bright, or as inked, whatever its size. */
    const energyFor = (view: FieldScene, ratio: number, radius: number) => {
      const pixels = view.area * view.scale * view.scale * ratio * ratio
      const footprint = (Math.PI / 2) * radius * radius
      return Math.min(2, Math.max(0.01, ((view.light ? LIGHT_INK : DARK_GLOW) * pixels) / (GRAINS * footprint)))
    }

    return {
      show(next) {
        read = next
      },
      place(next) {
        pending = next
        quietUntil = clock + SHAPE_SETTLES
      },
      resize(width, height) {
        stage.resize([width, height])
        scene.resize([width, height])
        haloA.resize(quarter([width, height]))
        haloB.resize(quarter([width, height]))
        bind()
        quietUntil = Math.max(quietUntil, clock + VALUE_SETTLES)
      },
      step() {
        if (!read) return false
        const now = performance.now() / 1000
        dt = last === undefined ? 0 : Math.min(now - last, LONGEST_STEP)
        last = now
        clock += dt
        since += dt
        current = read()
        const changed =
          !shown ||
          shown.value !== current.value ||
          shown.scale !== current.scale ||
          shown.width !== current.width ||
          shown.height !== current.height ||
          shown.light !== current.light
        if (changed) quietUntil = Math.max(quietUntil, clock + VALUE_SETTLES)
        shown = {value: current.value, scale: current.scale, width: current.width, height: current.height, light: current.light}
        if (current.turns) turn = (turn + (dt * 2 * Math.PI) / TURN_SECONDS) % (2 * Math.PI)
        const moving = clock < quietUntil || current.turns || pending !== undefined
        // Resting: the next frame that comes starts its clock afresh instead of counting the rest.
        if (!moving) last = undefined
        return moving
      },
      present() {
        const view = current ?? read?.()
        if (!view) return
        const ratio = stage.size[0] / view.width
        // Big enough that neighbouring grains overlap into a fine, even sand rather than salt and pepper.
        const radius = Math.max(1.1, 0.85 * ratio)
        const goal = energyFor(view, ratio, radius)
        energy = fresh ? goal : energy + (goal - energy) * (1 - Math.exp(-5 * dt))
        if (fresh) energyBefore = energy
        if (pending) {
          homes.write(pending)
          pending = undefined
          shapeNumber += 1
          since = 0
          swing = -swing
          sweep = lastHalf
          energyBefore = energy
        }
        lastHalf = view.half
        const eye = VIEWER * view.scale
        const knob = view.knob
        simulate.set({
          sim: {
            frame: [view.scale, sweep, dt, clock],
            state: [view.value, turn, since, shapeNumber],
            flight: [fresh ? 1 : 0, swing, eye, 0],
            knob: knob ? [knob.x0 * view.scale, knob.y0 * view.scale, knob.x1 * view.scale, knob.y1 * view.scale] : [0, 0, 0, 0],
            ball: [knob ? knob.r * view.scale : 0, 0, 0, 0],
            energy: [energy, energyBefore, 0, 0],
          },
        })
        paint.set({
          view: {
            canvas: [view.width, view.height, ratio, radius],
            look: [view.light ? 1 : 0, 0, 0, eye],
            muted: rgba(view.colours.muted),
            lit: rgba(view.colours.lit),
            far: rgba(view.colours.far),
          },
        })
        // The glow reaches the same share of a unit whatever the size: taps spaced in quarter-size texels.
        const spacing = Math.max(1, (HALO * view.scale * ratio) / 4 / BLUR_REACH)
        blurAcross.set({blur: {step: [haloA.texelSize[0] * spacing, 0, 0, 0]}})
        blurDown.set({blur: {step: [0, haloB.texelSize[1] * spacing, 0, 0]}})
        composite.set({page: {look: [view.light ? 1 : 0, view.light ? 0 : HALO_STRENGTH, 0, 0], lit: rgba(view.colours.lit)}})
        fresh = false
        frame(gpu, f => {
          f.computePass(pass => pass.dispatch(simulate, Math.ceil(GRAINS / WORKGROUP)))
          f.pass({target: scene, clear: [0, 0, 0, 0]}, pass => pass.draw(paint, {instances: GRAINS}))
          if (!view.light) {
            f.pass({target: haloA, clear: [0, 0, 0, 0]}, down)
            // Two rounds, so the glow is smooth however far apart the taps are.
            for (let round = 0; round < 2; round++) {
              f.pass({target: haloB, clear: [0, 0, 0, 0]}, blurAcross)
              f.pass({target: haloA, clear: [0, 0, 0, 0]}, blurDown)
            }
          }
          f.pass({target: stage, clear: [0, 0, 0, 0]}, composite)
        })
      },
      settled() {
        return gpu.settled()
      },
      dispose() {
        if (disposed) return
        disposed = true
        stage.dispose()
        gpu.dispose()
      },
    }
  } catch (error) {
    gpu.dispose()
    throw error
  }
}
