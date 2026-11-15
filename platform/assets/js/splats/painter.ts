/**
 * Paints the splats page's island with WebGPU through vgpu, in three passes:
 *
 * 1. Splats. Every splat is one instance of a single draw: its 3D covariance is
 *    carried through the camera into an ellipse on a low picture of about 290 by 190
 *    pixels, drawn as a quad along the ellipse's axes with a gaussian falloff, in the
 *    order order.ts gives (farthest first), each laid over the ones behind it.
 * 2. Pixels. On that same low grid: where the splats cover a pixel past a dithered
 *    threshold it takes their colour, elsewhere the night sky's; the fire's glow is
 *    added; then every pixel takes the nearest colour of the night palette after a
 *    4 by 4 ordered dither. The pixel grid moves with the island's bob in whole
 *    pixels only, so bobbing never makes the picture shimmer.
 * 3. Picture. The low picture is scaled up by a whole number onto the canvas, each
 *    pixel a crisp square of device pixels, and soft motes drift over it: small ones
 *    behind the island, a few large blurred ones in front.
 *
 * The moon's light is worked out per splat as the island turns, so its cool edge
 * light stays on one side; the fire's light is baked into each splat (island.ts) and
 * flickers here. Shared by the renderer (renderer.ts) and the still picture's script
 * (`stills.mjs`), so it imports only vgpu and types.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {draw, effect, storage, target, type Frame, type Gpu, type Target} from "vgpu"

import type {Island} from "./island"

/** The camera: its pitch above the island, the angle it sees top to bottom, how far back it stands, the height it looks at. */
export const PITCH = (17 * Math.PI) / 180
const FIELD = (20 * Math.PI) / 180
const DISTANCE = 8
const LOOK_AT = 0.42
/** About how many rows of pixels the picture has, whatever the size of its box: the island's
 * pixels are the same size against it on a wide screen and a phone. */
export const ROWS = 192
/** The island's radius, as a share of the picture's height: what a drag turns 1:1. */
export const RADIUS_IN_HEIGHT = 1 / (2 * Math.tan(FIELD / 2) * DISTANCE)
/** The island's angle and clock in the still picture, the first frame and a still island. */
export const STILL_TURN = (-24 * Math.PI) / 180
export const STILL_SECONDS = 3.2
/** Motes behind the island, then in front of it. */
const BACK_MOTES = 26
const FRONT_MOTES = 7

export type PixelGrid = {
  /** Device pixels per picture pixel, a whole number. */
  readonly scale: number
  readonly columns: number
  readonly rows: number
  /** Where the grid's first pixel starts on the canvas, in device pixels (zero or less). */
  readonly offset: readonly [number, number]
}

/** The low picture for a canvas of this many device pixels: about `ROWS` high, scaled by a whole number to cover it. */
export function pixelGrid(width: number, height: number): PixelGrid {
  const scale = Math.max(1, Math.round(height / ROWS))
  const columns = Math.ceil(width / scale)
  const rows = Math.ceil(height / scale)
  return {scale, columns, rows, offset: [Math.floor((width - columns * scale) / 2), Math.floor((height - rows * scale) / 2)]}
}

/** One frame's moment: the island's turn, its bob in whole pixels, the fire's flicker, and the clock. */
export type Moment = {
  readonly turn: number
  readonly bob: number
  readonly flicker: number
  readonly seconds: number
}

/** The fire's flicker at a moment: a few slow waves, never quite repeating. */
export const flicker = (seconds: number) =>
  0.84 + 0.08 * Math.sin(seconds * 7.3) + 0.05 * Math.sin(seconds * 13.1 + 1.7) + 0.04 * Math.sin(seconds * 21.7 + 0.4)

/** The island's bob, in whole pixels of a low picture this many rows high. */
export const bob = (seconds: number, rows: number) => Math.round(rows * 0.0125 * Math.sin((seconds * Math.PI * 2) / 5.5))

const vec3 = (c: readonly number[]) => `vec3f(${c.map(v => v.toFixed(6)).join(", ")})`

// What both the splat pass and the pixel pass know of the camera.
const VIEW_WGSL = /* wgsl */ `
struct View {
  // The low picture's columns and rows, its focal length in pixels, and the clock in seconds.
  frame: vec4f,
  // The cosine and sine of the island's turn, its bob in whole pixels, and the fire's flicker.
  turn: vec4f,
  // The cosine and sine of the camera's pitch, its distance, and the height it looks at.
  camera: vec4f,
  // Where the fire's light comes from on the island (the fourth is padding).
  fire: vec4f,
}

@group(0) @binding(0) var<uniform> view: View;

fn turned(p: vec3f) -> vec3f {
  return vec3f(view.turn.x * p.x + view.turn.y * p.z, p.y, -view.turn.y * p.x + view.turn.x * p.z);
}

// A point on the turned island in the camera's own frame: x right, y up, z straight ahead.
fn seen(r: vec3f) -> vec3f {
  let cp = view.camera.x;
  let sp = view.camera.y;
  let q = r - vec3f(0.0, view.camera.w + view.camera.z * sp, view.camera.z * cp);
  return vec3f(q.x, q.y * cp - q.z * sp, -(q.y * sp + q.z * cp));
}

// Where a seen point lands on the low picture, in pixels from its bottom left.
fn onPicture(v: vec3f) -> vec2f {
  return vec2f(view.frame.x * 0.5, view.frame.y * 0.5 + view.turn.z) + view.frame.z * v.xy / v.z;
}
`

const SPLAT_WGSL = /* wgsl */ `
${VIEW_WGSL}

struct Splat {
  // Place, opacity.
  a: vec4f,
  // Covariance xx, xy, xz, yy.
  b: vec4f,
  // Covariance yz, zz, kind (0 lit, 1 flame, 2 spark), the fire's light.
  c: vec4f,
  // Colour, a phase for flames and sparks.
  d: vec4f,
  // The way it faces, how open it is to the sky.
  e: vec4f,
}

@group(0) @binding(1) var<storage, read> splats: array<Splat>;
@group(0) @binding(2) var<storage, read> order: array<u32>;

struct Out {
  @builtin(position) position: vec4f,
  @location(0) local: vec2f,
  @location(1) colour: vec3f,
  @location(2) opacity: f32,
}

// How many standard deviations each quad reaches: past it a splat adds nothing worth a pixel.
const EXTENT = 2.8;
// The moon, high on the left, in the world the camera sees.
const MOON = vec3f(-0.8, 0.55, -0.05);
const MOONLIGHT = vec3f(0.7, 0.76, 0.86);
const SKY = vec3f(0.36, 0.42, 0.56);
const BOUNCE = vec3f(0.16, 0.16, 0.2);
const EDGE = vec3f(0.68, 0.79, 0.8);
const FIRELIGHT = vec3f(1.0, 0.52, 0.2);

@vertex fn vs_main(@builtin(vertex_index) vertex: u32, @builtin(instance_index) instance: u32) -> Out {
  var out: Out;
  let s = splats[order[instance]];
  let kind = u32(s.c.z);
  var at = s.a.xyz;
  var opacity = s.a.w;
  var grow = 1.0;
  var colour = s.d.rgb;
  let seconds = view.frame.w;
  let phase = s.d.w;

  if (kind == 1u) {
    // A flame licks upward, shrinking and fading as it goes, and brightens with the flicker.
    let lick = fract(seconds * (1.1 + phase * 0.8) + phase);
    at.y += lick * 0.05 * (0.4 + at.y * 3.0);
    grow = 1.0 - lick * 0.45;
    opacity *= 1.0 - lick * lick;
    colour *= 0.82 + 0.3 * view.turn.w;
  } else if (kind == 2u) {
    // A spark rises from the fire on its own slow path, wavers, and goes out.
    let life = fract(seconds * (0.3 + phase * 0.25) + phase * 7.0);
    at += vec3f(sin(life * 5.0 + phase * 40.0) * 0.06 * life, life * (0.55 + phase * 0.45), cos(life * 4.0 + phase * 23.0) * 0.06 * life);
    opacity *= smoothstep(0.0, 0.06, life) * (1.0 - life);
    colour = mix(vec3f(1.0, 0.95, 0.75), colour, smoothstep(0.0, 0.4, life));
  } else {
    let facing = turned(s.e.xyz);
    let open = s.e.w;
    let moon = normalize(MOON);
    let toward = normalize(vec3f(0.0, view.camera.y, view.camera.x));
    let lit = max(dot(facing, moon), 0.0);
    let sky = mix(BOUNCE, SKY, facing.y * 0.5 + 0.5);
    // Light along the outline on the moon's side, so the island's shape reads as it turns.
    let edge = pow(1.0 - clamp(abs(dot(facing, toward)), 0.0, 1.0), 3.0) * smoothstep(0.0, 0.5, dot(facing, moon));
    colour = s.d.rgb * (sky * open + MOONLIGHT * lit * (0.45 + 0.55 * open)) + EDGE * edge * 0.5 * open + s.d.rgb * FIRELIGHT * s.c.w * view.turn.w * 2.2;
  }

  let middle = seen(turned(at));
  let f = view.frame.z;
  let z = middle.z;
  // The covariance, turned with the island and seen by the camera.
  let cov = mat3x3f(
    vec3f(s.b.x, s.b.y, s.b.z),
    vec3f(s.b.y, s.b.w, s.c.x),
    vec3f(s.b.z, s.c.x, s.c.y),
  ) * (grow * grow);
  let cp = view.camera.x;
  let sp = view.camera.y;
  let ct = view.turn.x;
  let st = view.turn.y;
  // The camera's rows times the island's turn: right, up, ahead.
  let right = vec3f(ct, 0.0, st);
  let up = vec3f(sp * st, cp, -sp * ct);
  let ahead = vec3f(cp * st, -sp, -cp * ct);
  // The projection's slope at this point, applied to each row.
  let t0 = right * (f / z) - ahead * (f * middle.x / (z * z));
  let t1 = up * (f / z) - ahead * (f * middle.y / (z * z));
  // Plus a third of a pixel either way, so the smallest splat still covers one.
  let a = dot(t0, cov * t0) + 0.3;
  let b = dot(t0, cov * t1);
  let d = dot(t1, cov * t1) + 0.3;
  let mid = 0.5 * (a + d);
  let spread = sqrt(max(mid * mid - (a * d - b * b), 0.0));
  let major = mid + spread;
  let minor = max(mid - spread, 0.1);
  var axis = vec2f(1.0, 0.0);
  if (abs(b) > 1e-6) {
    axis = normalize(vec2f(b, major - a));
  } else if (d > a) {
    axis = vec2f(0.0, 1.0);
  }
  var corners = array<vec2f, 4>(vec2f(-1.0, -1.0), vec2f(1.0, -1.0), vec2f(-1.0, 1.0), vec2f(1.0, 1.0));
  let k = corners[vertex] * EXTENT;
  let pixel = onPicture(middle) + axis * (k.x * sqrt(major)) + vec2f(-axis.y, axis.x) * (k.y * sqrt(minor));
  out.position = vec4f(pixel / view.frame.xy * 2.0 - 1.0, 0.0, 1.0);
  if (z < 0.5) {
    out.position = vec4f(2.0, 2.0, 2.0, 1.0);
  }
  out.local = k;
  out.colour = colour;
  out.opacity = opacity;
  return out;
}

@fragment fn fs_main(in: Out) -> @location(0) vec4f {
  let alpha = min(0.99, in.opacity * exp(-0.5 * dot(in.local, in.local)));
  if (alpha < 1.0 / 255.0) {
    discard;
  }
  return vec4f(in.colour * alpha, alpha);
}
`

const BAYER_WGSL = `const BAYER = array<f32, 16>(0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);`

function pixelWgsl(palette: readonly (readonly [number, number, number])[], lab: readonly (readonly [number, number, number])[]) {
  return /* wgsl */ `
${VIEW_WGSL}

@group(0) @binding(1) var splatsDrawn: texture_2d<f32>;

const COLOURS = ${palette.length}u;
const PALETTE = array<vec3f, ${palette.length}>(${palette.map(vec3).join(", ")});
const PALETTE_LAB = array<vec3f, ${lab.length}>(${lab.map(vec3).join(", ")});
${BAYER_WGSL}
// How far the dither nudges a colour before it is matched to the palette.
const SPREAD = 0.05;

fn threshold(p: vec2i) -> f32 {
  let x = ((p.x % 4) + 4) % 4;
  let y = ((p.y % 4) + 4) % 4;
  return (BAYER[y * 4 + x] + 0.5) / 16.0;
}

fn toLinear(c: vec3f) -> vec3f {
  return select(pow((c + 0.055) / 1.055, vec3f(2.4)), c / 12.92, c <= vec3f(0.04045));
}

fn oklab(c: vec3f) -> vec3f {
  let r = toLinear(clamp(c, vec3f(0.0), vec3f(1.0)));
  let l = pow(0.4122214708 * r.x + 0.5363325363 * r.y + 0.0514459929 * r.z, 1.0 / 3.0);
  let m = pow(0.2119034982 * r.x + 0.6806995451 * r.y + 0.1073969566 * r.z, 1.0 / 3.0);
  let s = pow(0.0883024619 * r.x + 0.2817188376 * r.y + 0.6299787005 * r.z, 1.0 / 3.0);
  return vec3f(
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  );
}

fn nearest(c: vec3f) -> vec3f {
  let want = oklab(c);
  var best = 0u;
  var bestDistance = 1e9;
  for (var i = 0u; i < COLOURS; i++) {
    let gap = PALETTE_LAB[i] - want;
    let distance = dot(gap, gap);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = i;
    }
  }
  return PALETTE[best];
}

fn hash(p: vec2f) -> f32 {
  return fract(sin(dot(p, vec2f(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2f) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2f(1.0, 0.0)), u.x), mix(hash(i + vec2f(0.0, 1.0)), hash(i + vec2f(1.0, 1.0)), u.x), u.y);
}

// The night sky at a pixel, y down: darkest at the top, with soft bands of cloud.
fn sky(p: vec2f) -> vec3f {
  let v = p.y / view.frame.y;
  var c = mix(vec3f(0.03, 0.05, 0.11), vec3f(0.1, 0.16, 0.34), smoothstep(0.0, 0.8, v));
  c = mix(c, vec3f(0.12, 0.19, 0.38), smoothstep(0.75, 1.0, v));
  let q = p / view.frame.y * vec2f(2.4, 7.0);
  let cloud = noise(q) * 0.6 + noise(q * 2.3 + vec2f(5.2, 1.3)) * 0.3 + noise(q * 5.1) * 0.1;
  c = mix(c, c * 1.45 + vec3f(0.01, 0.015, 0.03), smoothstep(0.55, 0.85, cloud) * 0.55);
  c = mix(c, c * 0.72, smoothstep(0.42, 0.18, cloud) * 0.4);
  return c;
}

@fragment fn fs_main(@builtin(position) at: vec4f) -> @location(0) vec4f {
  let pixel = vec2i(at.xy);
  let drawn = textureLoad(splatsDrawn, pixel, 0);
  // The cloud drifts a whole pixel at a time, and its dither drifts with it.
  let drift = vec2i(i32(floor(view.frame.w * 1.5)), 0);
  // The island's dither moves with its bob, so a step of the bob never reshuffles it.
  let lifted = vec2i(0, -i32(view.turn.z));
  let island = drawn.a > 0.2 + 0.6 * threshold(pixel + lifted);
  var colour = sky(vec2f(pixel + drift) + 0.5);
  var dither = threshold(pixel + drift);
  if (island) {
    colour = drawn.rgb / drawn.a;
    dither = threshold(pixel + lifted);
  }
  // The fire's glow, round where the fire is, brighter while it is on the near side.
  let fire = seen(turned(view.fire.xyz));
  let spot = onPicture(fire);
  let gap = (at.xy - vec2f(spot.x, view.frame.y - spot.y)) / view.frame.y;
  let near = mix(0.35, 1.0, smoothstep(0.4, -0.6, fire.z - view.camera.z));
  colour += vec3f(1.0, 0.42, 0.12) * exp(-dot(gap, gap) / 0.0045) * 0.32 * view.turn.w * near;
  return vec4f(nearest(colour + (dither - 0.5) * SPREAD), select(0.0, 1.0, island));
}
`
}

const PRESENT_WGSL = /* wgsl */ `
struct Present {
  // Device pixels per picture pixel, where the grid starts (device pixels), the motes' clock in seconds.
  grid: vec4f,
  // The canvas's width and height in device pixels (the last two are padding).
  canvas: vec4f,
}

@group(0) @binding(0) var<uniform> present: Present;
@group(0) @binding(1) var pixels: texture_2d<f32>;

fn gridPixel(at: vec2f) -> vec2i {
  let size = vec2i(textureDimensions(pixels));
  return clamp(vec2i(floor((at - present.grid.yz) / present.grid.x)), vec2i(0), size - 1);
}
`

const PICTURE_WGSL = /* wgsl */ `
${PRESENT_WGSL}

@fragment fn fs_main(@builtin(position) at: vec4f) -> @location(0) vec4f {
  return vec4f(textureLoad(pixels, gridPixel(at.xy), 0).rgb, 1.0);
}
`

const MOTES_WGSL = /* wgsl */ `
${PRESENT_WGSL}

const BACK = ${BACK_MOTES}u;

struct Out {
  @builtin(position) position: vec4f,
  @location(0) local: vec2f,
  @location(1) @interpolate(flat) look: vec4f,
}

fn hash(n: f32) -> f32 {
  return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

@vertex fn vs_main(@builtin(vertex_index) vertex: u32, @builtin(instance_index) instance: u32) -> Out {
  var out: Out;
  let k = f32(instance) * 1.618;
  let front = instance >= BACK;
  let size = present.canvas.xy;
  let seconds = present.grid.w;
  // Each mote rises slowly, sways a little, and comes round again from below.
  let rise = mix(0.004, 0.012, hash(k + 3.0)) * select(1.0, 1.7, front);
  let y = fract(hash(k + 1.0) - seconds * rise) * 1.2 - 0.1;
  let x = fract(hash(k + 2.0) + 0.015 * sin(seconds * mix(0.15, 0.4, hash(k + 4.0)) + k));
  let radius = select(mix(0.005, 0.012, hash(k + 5.0)), mix(0.022, 0.042, hash(k + 5.0)), front) * size.y;
  var corners = array<vec2f, 4>(vec2f(-1.0, -1.0), vec2f(1.0, -1.0), vec2f(-1.0, 1.0), vec2f(1.0, 1.0));
  let corner = corners[vertex];
  let pixel = vec2f(x * size.x, y * size.y) + corner * radius;
  out.position = vec4f(pixel.x / size.x * 2.0 - 1.0, 1.0 - pixel.y / size.y * 2.0, 0.0, 1.0);
  out.local = corner;
  let strength = select(mix(0.2, 0.5, hash(k + 6.0)), mix(0.1, 0.2, hash(k + 6.0)), front);
  out.look = vec4f(select(0.0, 1.0, front), strength, hash(k + 7.0), 0.0);
  return out;
}

@fragment fn fs_main(in: Out) -> @location(0) vec4f {
  let d = length(in.local);
  if (d > 1.0) {
    discard;
  }
  let front = in.look.x > 0.5;
  // A mote behind the island shows only against the sky.
  if (!front && textureLoad(pixels, gridPixel(in.position.xy), 0).a > 0.5) {
    discard;
  }
  let soft = select(1.0 - smoothstep(0.3, 1.0, d), exp(-d * d * 3.5) * (1.0 - d), front);
  let colour = mix(vec3f(0.68, 0.79, 0.8), vec3f(0.9, 0.89, 0.82), in.look.z);
  let alpha = in.look.y * soft;
  return vec4f(colour * alpha, alpha);
}
`

export type Painter = {
  /** Fits the low picture to a canvas of this many device pixels. */
  resize(width: number, height: number): PixelGrid
  /** The order to draw the splats in, farthest first. */
  order(indices: Uint32Array<ArrayBuffer>): void
  /** Encodes one moment: the splats and their pixels, and the scaled picture with motes on `picture` when given. */
  encode(f: Frame, moment: Moment, picture?: Target): void
  /** The low picture, one palette colour per pixel; alpha is 1 where the island is. */
  readonly pixels: Target
  /** Prepares every pipeline before the first frame. */
  compile(picture?: Target): Promise<void>
}

export function createPainter(
  gpu: Gpu,
  island: Island,
  palette: readonly (readonly [number, number, number])[],
  lab: readonly (readonly [number, number, number])[],
): Painter {
  let grid = pixelGrid(ROWS * 1.5, ROWS)
  const splatsDrawn = target(gpu, {size: [grid.columns, grid.rows], format: "rgba16float", label: "splats.drawn"})
  const pixels = target(gpu, {size: [grid.columns, grid.rows], format: "rgba8unorm", label: "splats.pixels"})
  const data = storage(gpu, island.data.byteLength, "read")
  data.write(island.data)
  const order = storage(gpu, island.count * 4, "read")

  const view = (moment: Moment) => ({
    frame: [grid.columns, grid.rows, grid.rows / (2 * Math.tan(FIELD / 2)), moment.seconds],
    turn: [Math.cos(moment.turn), Math.sin(moment.turn), moment.bob, moment.flicker],
    camera: [Math.cos(PITCH), Math.sin(PITCH), DISTANCE, LOOK_AT],
    fire: [island.fire[0], island.fire[1], island.fire[2], 0],
  })
  const first: Moment = {turn: 0, bob: 0, flicker: 1, seconds: 0}

  const splats = draw(gpu, {
    shader: prepareShader(SPLAT_WGSL, "splats.wgsl"),
    geometry: {topology: "triangle-strip"},
    vertices: 4,
    instances: island.count,
    blend: "premultiplied",
    depth: false,
    label: "splats.splats",
    set: {view: view(first), splats: data, order},
  })
  const pixelPass = effect(gpu, prepareShader(pixelWgsl(palette, lab), "splats_pixels.wgsl"), {
    label: "splats.pixels",
    set: {view: view(first), splatsDrawn},
  })
  const presentation = (seconds: number, size: readonly [number, number]) => ({
    grid: [grid.scale, grid.offset[0], grid.offset[1], seconds],
    canvas: [size[0], size[1], 0, 0],
  })
  const picture = effect(gpu, prepareShader(PICTURE_WGSL, "splats_picture.wgsl"), {
    label: "splats.picture",
    set: {present: presentation(0, [1, 1]), pixels},
  })
  const motes = draw(gpu, {
    shader: prepareShader(MOTES_WGSL, "splats_motes.wgsl"),
    geometry: {topology: "triangle-strip"},
    vertices: 4,
    instances: BACK_MOTES + FRONT_MOTES,
    blend: "premultiplied",
    depth: false,
    label: "splats.motes",
    set: {present: presentation(0, [1, 1]), pixels},
  })

  return {
    pixels,
    resize(width, height) {
      grid = pixelGrid(width, height)
      splatsDrawn.resize([grid.columns, grid.rows])
      pixels.resize([grid.columns, grid.rows])
      return grid
    },
    order(indices) {
      order.write(indices)
    },
    encode(f, moment, destination) {
      const looking = view(moment)
      splats.set({view: looking})
      pixelPass.set({view: looking})
      f.pass({target: splatsDrawn, clear: [0, 0, 0, 0]}, pass => pass.draw(splats))
      f.pass({target: pixels, clear: [0, 0, 0, 0]}, pixelPass)
      if (!destination) return
      const present = presentation(moment.seconds, destination.size)
      picture.set({present})
      motes.set({present})
      f.pass({target: destination, clear: [0, 0, 0, 1]}, pass => {
        pass.draw(picture)
        pass.draw(motes)
      })
    },
    async compile(destination) {
      await splats.compile(splatsDrawn)
      await pixelPass.compile(pixels)
      if (!destination) return
      await picture.compile(destination)
      await motes.compile(destination)
    },
  }
}
