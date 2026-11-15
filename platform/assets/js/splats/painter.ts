/**
 * Paints a splats-page scene (build.ts) with WebGPU through vgpu, in three passes:
 *
 * 1. Splats, as Gaussian splatting draws them (Kerbl et al., 2023). Every splat is one
 *    instance of a single draw, in the order order.ts gives (farthest first). Its
 *    covariance Σ = R S Sᵀ Rᵀ comes from its quaternion and scales; it is carried into
 *    the camera (W) and through the perspective projection's Jacobian (J) at its centre,
 *    J W Σ Wᵀ Jᵀ, plus 0.3 of a pixel either way (the low-pass term); the quad spans
 *    three standard deviations along the ellipse's axes, and each pixel takes
 *    opacity · exp(-½ dᵀ Σ'⁻¹ d), at most 0.99, laid over what is behind it. Its colour
 *    is its spherical harmonics of degrees 0 and 1 seen along the real view direction.
 * 2. Pixels. On a low grid of about 450 columns: where the splats cover a pixel past a
 *    dithered threshold it takes their colour, elsewhere the sky's; the outline's edge
 *    toward the rim light brightens and glows are added; then every pixel takes the
 *    nearest colour of the scene's palette after a 4 by 4 ordered dither. The grid moves
 *    with the bob in whole pixels only, so bobbing never makes the picture shimmer.
 * 3. Picture. The low picture is scaled up by a whole number onto the canvas, each
 *    pixel a crisp square of device pixels, and soft motes drift over it.
 *
 * The camera orbits the scene: a turn round its upright axis and a tilt to nearly
 * straight above or below (`TILT_LIMIT`). Shared by the renderer (renderer.ts) and the
 * scripts beside it, so it imports only vgpu and types.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {draw, effect, storage, target, type Frame, type Gpu, type Target} from "vgpu"

import type {Camera, Glow, Scene, Vec3} from "./build.ts"

/** About how many columns of pixels the picture has on its longer side. */
export const COLUMNS = 450
/** The tilt reaches this close to straight above or below, so the view never flips. */
export const TILT_LIMIT = (86 * Math.PI) / 180
/** Motes are drawn at the canvas's own resolution, this many at most. */
const MOTES_LIMIT = 64

export type PixelGrid = {
  /** Device pixels per picture pixel, a whole number. */
  readonly scale: number
  readonly columns: number
  readonly rows: number
  /** Where the grid's first pixel starts on the canvas, in device pixels (zero or less). */
  readonly offset: readonly [number, number]
}

/** The low picture for a canvas of this many device pixels: at most `COLUMNS` on its longer side, scaled by a whole number to cover it. */
export function pixelGrid(width: number, height: number): PixelGrid {
  const scale = Math.max(1, Math.ceil(Math.max(width, height) / COLUMNS))
  const columns = Math.ceil(width / scale)
  const rows = Math.ceil(height / scale)
  return {scale, columns, rows, offset: [Math.floor((width - columns * scale) / 2), Math.floor((height - rows * scale) / 2)]}
}

/** The focal length in picture pixels: the field fits the picture's height, or the scene's width (`Camera.width`) its width, whichever is smaller. */
export const focal = (camera: Camera, grid: {columns: number; rows: number}) =>
  Math.min(grid.rows, grid.columns / camera.width) / (2 * Math.tan(camera.field / 2))

/** The camera stands back a little further as it tilts toward straight above or below, so the whole scene fits. */
const standBack = (camera: Camera, pitch: number) =>
  camera.distance * (1 + 0.32 * Math.pow(Math.max(0, (Math.abs(pitch) - camera.pitch) / (Math.PI / 2 - camera.pitch)), 1.5))

/** The camera, in the scene's own frame, at a turn and tilt: its right, up and forward, and where it stands. */
export function viewFrom(camera: Camera, turn: number, pitch: number) {
  const ct = Math.cos(turn)
  const st = Math.sin(turn)
  const cp = Math.cos(pitch)
  const sp = Math.sin(pitch)
  const right: Vec3 = [ct, 0, st]
  const up: Vec3 = [sp * st, cp, -sp * ct]
  const ahead: Vec3 = [cp * st, -sp, -cp * ct]
  const back = standBack(camera, pitch)
  const eye: Vec3 = [-ahead[0] * back, camera.lookAt - ahead[1] * back, -ahead[2] * back]
  return {right, up, ahead, eye}
}

/** One frame's moment: the view, the bob in whole pixels, the flicker of any fire, and the clock. */
export type Moment = {
  readonly turn: number
  readonly pitch: number
  readonly bob: number
  readonly flicker: number
  readonly seconds: number
}

/** A fire's flicker at a moment: a few slow waves, never quite repeating. */
export const flicker = (seconds: number) =>
  0.84 + 0.08 * Math.sin(seconds * 7.3) + 0.05 * Math.sin(seconds * 13.1 + 1.7) + 0.04 * Math.sin(seconds * 21.7 + 0.4)

/** The bob, in whole pixels of a low picture this many rows high. */
export const bob = (seconds: number, rows: number) => Math.round(rows * 0.01 * Math.sin((seconds * Math.PI * 2) / 5.5))

const vec3 = (c: readonly number[]) => `vec3f(${c.map(v => v.toFixed(6)).join(", ")})`

// What every pass that looks at the scene knows of the camera.
const VIEW_WGSL = /* wgsl */ `
struct View {
  // The low picture's columns and rows, its focal length in pixels, and the clock in seconds.
  frame: vec4f,
  // The camera's right in the scene's frame, and the bob in whole pixels.
  right: vec4f,
  // The camera's up, and the flicker of any fire.
  up: vec4f,
  // The camera's forward, and the camera's tilt.
  ahead: vec4f,
  // Where the camera stands, and how strongly the outline's lit edge shows.
  eye: vec4f,
  // How far off the middle a splat's centre may sit before the projection's slope is
  // taken at the edge instead (1.3 times the view's half width and half height, as in
  // the original renderer), then the step in pixels toward the rim light on the picture.
  limits: vec4f,
}

@group(0) @binding(0) var<uniform> view: View;

// A point of the scene in the camera's own frame: x right, y up, z straight ahead.
fn seen(p: vec3f) -> vec3f {
  let v = p - view.eye.xyz;
  return vec3f(dot(v, view.right.xyz), dot(v, view.up.xyz), dot(v, view.ahead.xyz));
}

// Where a seen point lands on the low picture, in pixels from its bottom left.
fn onPicture(v: vec3f) -> vec2f {
  return vec2f(view.frame.x * 0.5, view.frame.y * 0.5 + view.right.w) + view.frame.z * v.xy / v.z;
}
`

const SPLAT_WGSL = /* wgsl */ `
${VIEW_WGSL}

// One splat in the standard layout, then how it moves.
struct Splat {
  // Place, and opacity before the sigmoid.
  place: vec4f,
  // Rotation as a unit quaternion, real part first.
  rotation: vec4f,
  // The log of its scale on each axis, and its kind.
  scale: vec4f,
  // Colour, degree 0 (f_dc), and a phase for anything that moves by itself.
  dc: vec4f,
  // Colour, degree 1 (f_rest) for red, green and blue, each followed by: the moving
  // part it belongs to; the share of its colour a flickering fire gives; how often it blinks.
  red: vec4f,
  green: vec4f,
  blue: vec4f,
}

// Where a moving part is: three axes, a shift, and an opacity.
struct Part {
  x: vec4f,
  y: vec4f,
  z: vec4f,
  shift: vec4f,
}

@group(0) @binding(1) var<storage, read> splats: array<Splat>;
@group(0) @binding(2) var<storage, read> order: array<u32>;
@group(0) @binding(3) var<storage, read> parts: array<Part>;

struct Out {
  @builtin(position) position: vec4f,
  @location(0) local: vec2f,
  @location(1) colour: vec3f,
  @location(2) opacity: f32,
}

const SH_C0 = 0.28209479177387814;
const SH_C1 = 0.4886025119029199;
// How many standard deviations each quad reaches, as in the original renderer.
const EXTENT = 3.0;

fn rotation(q: vec4f) -> mat3x3f {
  let r = q.x;
  let x = q.y;
  let y = q.z;
  let z = q.w;
  return mat3x3f(
    vec3f(1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y + r * z), 2.0 * (x * z - r * y)),
    vec3f(2.0 * (x * y - r * z), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z + r * x)),
    vec3f(2.0 * (x * z + r * y), 2.0 * (y * z - r * x), 1.0 - 2.0 * (x * x + y * y)),
  );
}

@vertex fn vs_main(@builtin(vertex_index) vertex: u32, @builtin(instance_index) instance: u32) -> Out {
  var out: Out;
  let s = splats[order[instance]];
  let part = parts[u32(s.red.w)];
  let moved = mat3x3f(part.x.xyz, part.y.xyz, part.z.xyz);
  let kind = u32(s.scale.w);
  let phase = s.dc.w;
  let seconds = view.frame.w;
  var at = moved * s.place.xyz + part.shift.xyz;
  var opacity = part.shift.w / (1.0 + exp(-s.place.w));
  var grow = 1.0;

  // Its colour seen from the camera, in the splat's own frame (a moving part turns its look with it).
  let d = transpose(moved) * normalize(at - view.eye.xyz);
  let lobe = vec3f(-d.y, d.z, -d.x);
  var colour = max(vec3f(0.0), 0.5 + SH_C0 * s.dc.rgb + SH_C1 * vec3f(dot(lobe, s.red.xyz), dot(lobe, s.green.xyz), dot(lobe, s.blue.xyz)));
  colour *= 1.0 + s.green.w * (view.up.w - 1.0);
  if (s.blue.w > 0.0) {
    colour *= mix(0.2, 1.0, step(0.45, fract(seconds * s.blue.w + phase)));
  }

  if (kind == 1u) {
    // A flame licks upward, shrinking and fading as it goes, and brightens with the flicker.
    let lick = fract(seconds * (1.1 + phase * 0.8) + phase);
    at.y += lick * 0.05 * (0.4 + (s.place.y + 0.1) * 2.0);
    grow = 1.0 - lick * 0.45;
    opacity *= 1.0 - lick * lick;
    colour *= 0.82 + 0.3 * view.up.w;
  } else if (kind == 2u) {
    // A spark rises from the fire on its own slow path, wavers, and goes out.
    let life = fract(seconds * (0.3 + phase * 0.25) + phase * 7.0);
    at += vec3f(sin(life * 5.0 + phase * 40.0) * 0.06 * life, life * (0.55 + phase * 0.45), cos(life * 4.0 + phase * 23.0) * 0.06 * life);
    opacity *= smoothstep(0.0, 0.06, life) * (1.0 - life);
    colour = mix(vec3f(1.0, 0.95, 0.75), colour, smoothstep(0.0, 0.4, life));
  } else if (kind == 3u) {
    // Steam leaves the chimney as a faint wisp, then rises, spreads, swells and thins,
    // leaning with a light breeze. Each puff drifts out its own way, so the plume widens
    // as it goes rather than rising as one rope.
    let life = fract(seconds * 0.16 + phase);
    let away = fract(phase * 97.0) * 6.2831853;
    let spread = 0.1 * life * sqrt(fract(phase * 57.0));
    at += vec3f(
      0.16 * life * life + 0.025 * sin(seconds * 0.7 + phase * 9.0 + life * 4.0) + spread * cos(away),
      0.36 * life,
      0.05 * life * life + 0.02 * cos(seconds * 0.5 + phase * 13.0 + life * 3.0) + spread * sin(away),
    );
    grow = 1.0 + 2.5 * life;
    opacity *= smoothstep(0.0, 0.15, life) * pow(1.0 - life, 1.5);
  } else if (kind == 4u) {
    // A firefly drifts round where it lives and glows on and off.
    let t = seconds * (0.25 + phase * 0.2);
    at += vec3f(sin(t * 1.3 + phase * 17.0), 0.5 * sin(t * 1.9 + phase * 5.0), cos(t * 1.1 + phase * 11.0)) * 0.05;
    opacity *= smoothstep(0.2, 0.8, 0.5 + 0.5 * sin(seconds * (1.2 + phase) + phase * 31.0));
  } else if (kind == 5u) {
    // Water: small ripples run across it and catch the light.
    let ripple = sin(at.x * 61.0 + seconds * 1.7 + sin(at.z * 23.0)) * sin(at.z * 53.0 - seconds * 1.3 + phase * 6.0);
    colour += vec3f(0.7, 0.85, 0.9) * pow(max(ripple, 0.0), 12.0) * 1.4;
  }

  let middle = seen(at);
  let z = middle.z;
  let f = view.frame.z;
  let scale = exp(s.scale.xyz) * grow;
  let m = moved * rotation(s.rotation);
  let shape = mat3x3f(m[0] * scale.x, m[1] * scale.y, m[2] * scale.z);
  let cov = shape * transpose(shape);
  // The projection's slope at the centre, J W, row by row; past 1.3 times the edge of
  // the view it is taken at the edge, so splats far off to the side do not blow up.
  let tx = clamp(middle.x / z, -view.limits.x, view.limits.x) * z;
  let ty = clamp(middle.y / z, -view.limits.y, view.limits.y) * z;
  let t0 = view.right.xyz * (f / z) - view.ahead.xyz * (f * tx / (z * z));
  let t1 = view.up.xyz * (f / z) - view.ahead.xyz * (f * ty / (z * z));
  // The low-pass term: every splat covers at least about a pixel.
  let a = dot(t0, cov * t0) + 0.3;
  let b = dot(t0, cov * t1);
  let c = dot(t1, cov * t1) + 0.3;
  let mid = 0.5 * (a + c);
  let spread = sqrt(max(mid * mid - (a * c - b * b), 0.0));
  let major = mid + spread;
  let minor = max(mid - spread, 0.1);
  var axis = vec2f(1.0, 0.0);
  if (abs(b) > 1e-6) {
    axis = normalize(vec2f(b, major - a));
  } else if (c > a) {
    axis = vec2f(0.0, 1.0);
  }
  var corners = array<vec2f, 4>(vec2f(-1.0, -1.0), vec2f(1.0, -1.0), vec2f(-1.0, 1.0), vec2f(1.0, 1.0));
  let k = corners[vertex] * EXTENT;
  let pixel = onPicture(middle) + axis * (k.x * sqrt(major)) + vec2f(-axis.y, axis.x) * (k.y * sqrt(minor));
  out.position = vec4f(pixel / view.frame.xy * 2.0 - 1.0, 0.0, 1.0);
  // Behind or right at the camera: nothing to draw (the original renderer's near plane).
  if (z < 0.2) {
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

function glowsWgsl(glows: readonly Glow[]) {
  const rows = glows.map(g => `Glow(${vec3(g.at)}, ${vec3(g.colour)}, ${vec3(g.facing ?? [0, 0, 0])}, ${g.radius.toFixed(4)}, ${g.strength.toFixed(4)})`)
  return `
struct Glow { at: vec3f, colour: vec3f, facing: vec3f, radius: f32, strength: f32 }
const GLOWS = ${glows.length}u;
const GLOW = array<Glow, ${Math.max(1, glows.length)}>(${rows.length ? rows.join(", ") : "Glow(vec3f(0.0), vec3f(0.0), vec3f(0.0), 1.0, 0.0)"});`
}

function pixelWgsl(scene: Scene, palette: readonly (readonly [number, number, number])[], lab: readonly (readonly [number, number, number])[]) {
  const sky = scene.sky
  return /* wgsl */ `
${VIEW_WGSL}

@group(0) @binding(1) var splatsDrawn: texture_2d<f32>;

const COLOURS = ${palette.length}u;
const PALETTE = array<vec3f, ${palette.length}>(${palette.map(vec3).join(", ")});
const PALETTE_LAB = array<vec3f, ${lab.length}>(${lab.map(vec3).join(", ")});
${BAYER_WGSL}
// How far the dither nudges a colour before it is matched to the palette.
const SPREAD = 0.05;
const EDGE = ${vec3(scene.edge)};
const ZENITH = ${vec3(sky.zenith)};
const HIGH = ${vec3(sky.high)};
const HORIZON = ${vec3(sky.horizon)};
const BELOW = ${vec3(sky.below)};
const SKY_GLOW = ${vec3(sky.glow)};
const GLOW_AT = ${sky.glowAt.toFixed(6)};
const CLOUD = ${vec3(sky.cloud)};
const STARS = ${sky.stars.toFixed(4)};
${glowsWgsl(scene.glows)}

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

// The sky along the ray through a pixel (y down). The sky stays still while the scene
// turns; tilting the camera moves the horizon up and down the picture.
fn sky(p: vec2f) -> vec3f {
  let tilt = view.ahead.w;
  let x = p.x - view.frame.x * 0.5;
  let y = view.frame.y * 0.5 - p.y;
  let f = view.frame.z;
  let ray = normalize(vec3f(x, y * cos(tilt) - f * sin(tilt), -(y * sin(tilt) + f * cos(tilt))));
  let height = ray.y;
  let round = atan2(ray.x, -ray.z);
  var c = mix(HORIZON, HIGH, smoothstep(0.0, 0.3, height));
  c = mix(c, ZENITH, smoothstep(0.3, 0.95, height));
  c = mix(c, BELOW, smoothstep(0.0, -0.45, height));
  let side = round - GLOW_AT;
  let toward = exp(-side * side / 0.5);
  c += SKY_GLOW * toward * exp(-abs(height - 0.01) / 0.09);
  let q = vec2f(round * 3.0 + view.frame.w * 0.01, height * 14.0);
  let cloud = noise(q) * 0.6 + noise(q * 2.3 + vec2f(5.2, 1.3)) * 0.3 + noise(q * 5.1) * 0.1;
  let band = smoothstep(-0.25, 0.02, height) * smoothstep(0.45, 0.08, height);
  c = mix(c, CLOUD + SKY_GLOW * toward * 0.35, smoothstep(0.5, 0.82, cloud) * band * 0.6);
  // Stars: cells about a pixel across on a grid of directions, so they stay points all
  // the way up to straight overhead.
  let cell = floor(ray * f);
  let star = hash(cell.xy + cell.z * vec2f(17.31, 43.17));
  c += vec3f(0.85, 0.88, 0.95) * step(1.0 - STARS, star) * smoothstep(0.08, 0.3, height) * (0.6 + 0.4 * sin(view.frame.w * 2.0 + star * 90.0));
  return c;
}

fn covered(pixel: vec2i, lifted: vec2i) -> bool {
  return textureLoad(splatsDrawn, pixel, 0).a > 0.2 + 0.6 * threshold(pixel + lifted);
}

@fragment fn fs_main(@builtin(position) at: vec4f) -> @location(0) vec4f {
  let pixel = vec2i(at.xy);
  let size = vec2i(textureDimensions(splatsDrawn));
  let drawn = textureLoad(splatsDrawn, pixel, 0);
  // The scene's dither moves with its bob, so a step of the bob never reshuffles it.
  let lifted = vec2i(0, -i32(view.right.w));
  let inside = covered(pixel, lifted);
  var colour = sky(vec2f(pixel) + 0.5);
  var dither = threshold(pixel);
  if (inside) {
    colour = drawn.rgb / drawn.a;
    dither = threshold(pixel + lifted);
    // The outline's edge toward the rim light catches it: a line of bright pixels along
    // solid shapes, not along strands a pixel thin (hanging grass, roots, steam).
    let step = vec2i(view.limits.zw);
    let toward = clamp(pixel + step, vec2i(0), size - 1);
    let behind = clamp(pixel - step, vec2i(0), size - 1);
    if (!covered(toward, lifted) && covered(behind, lifted)) {
      colour = mix(colour, EDGE, view.eye.w);
    }
  }
  for (var g = 0u; g < GLOWS; g++) {
    let light = GLOW[g];
    let seenAt = seen(light.at);
    if (seenAt.z < 0.2) {
      continue;
    }
    let spot = onPicture(seenAt);
    let reach = light.radius * view.frame.z / seenAt.z;
    let gap = at.xy - vec2f(spot.x, view.frame.y - spot.y);
    // Every light sits on the island's top, so seen from below the island it is hidden.
    let toEye = normalize(view.eye.xyz - light.at);
    var facing = smoothstep(-0.12, 0.02, toEye.y);
    if (dot(light.facing, light.facing) > 0.0) {
      facing *= smoothstep(-0.2, 0.3, dot(light.facing, toEye));
    }
    colour += light.colour * light.strength * facing * exp(-dot(gap, gap) / (reach * reach)) * mix(1.0, view.up.w, 0.6);
  }
  return vec4f(nearest(colour + (dither - 0.5) * SPREAD), select(0.0, 1.0, inside));
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

function motesWgsl(scene: Scene) {
  const {back, colours, size} = scene.motes
  return /* wgsl */ `
${PRESENT_WGSL}

const BACK = ${back}u;
const NEAR_COLOUR = ${vec3(colours[0])};
const FAR_COLOUR = ${vec3(colours[1])};
const SIZE = ${size.toFixed(4)};

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
  let radius = select(mix(0.4, 1.0, hash(k + 5.0)), mix(1.6, 3.0, hash(k + 5.0)), front) * SIZE * size.y;
  var corners = array<vec2f, 4>(vec2f(-1.0, -1.0), vec2f(1.0, -1.0), vec2f(-1.0, 1.0), vec2f(1.0, 1.0));
  let corner = corners[vertex];
  let pixel = vec2f(x * size.x, y * size.y) + corner * radius;
  out.position = vec4f(pixel.x / size.x * 2.0 - 1.0, 1.0 - pixel.y / size.y * 2.0, 0.0, 1.0);
  out.local = corner;
  let strength = select(mix(0.14, 0.34, hash(k + 6.0)), mix(0.07, 0.15, hash(k + 6.0)), front);
  out.look = vec4f(select(0.0, 1.0, front), strength, hash(k + 7.0), 0.0);
  return out;
}

@fragment fn fs_main(in: Out) -> @location(0) vec4f {
  let d = length(in.local);
  if (d > 1.0) {
    discard;
  }
  let front = in.look.x > 0.5;
  // A mote behind the scene shows only against the sky.
  if (!front && textureLoad(pixels, gridPixel(in.position.xy), 0).a > 0.5) {
    discard;
  }
  // Behind, a soft-edged disc, the way a light far off blurs; in front, a wide haze.
  let soft = select(1.0 - smoothstep(0.55, 1.0, d), exp(-d * d * 3.5) * (1.0 - d), front);
  let colour = mix(NEAR_COLOUR, FAR_COLOUR, in.look.z);
  let alpha = in.look.y * soft;
  return vec4f(colour * alpha, alpha);
}
`
}

export type Painter = {
  /** Fits the low picture to a canvas of this many device pixels. */
  resize(width: number, height: number): PixelGrid
  /** The order to draw the splats in, farthest first. */
  order(indices: Uint32Array<ArrayBuffer>): void
  /** Where the moving parts are now (`Scene.pose`). */
  pose(parts: Float32Array<ArrayBuffer>): void
  /** Encodes one moment: the splats and their pixels, and the scaled picture with motes on `picture` when given. */
  encode(f: Frame, moment: Moment, picture?: Target): void
  /** The low picture, one palette colour per pixel; alpha is 1 where the scene is. */
  readonly pixels: Target
  /** Prepares every pipeline before the first frame. */
  compile(picture?: Target): Promise<void>
}

export function createPainter(
  gpu: Gpu,
  scene: Scene,
  palette: readonly (readonly [number, number, number])[],
  lab: readonly (readonly [number, number, number])[],
): Painter {
  let grid = pixelGrid(COLUMNS, Math.round(COLUMNS / 1.5))
  const splatsDrawn = target(gpu, {size: [grid.columns, grid.rows], format: "rgba16float", label: "splats.drawn"})
  const pixels = target(gpu, {size: [grid.columns, grid.rows], format: "rgba8unorm", label: "splats.pixels"})
  const data = storage(gpu, scene.data.byteLength, "read")
  data.write(scene.data)
  const order = storage(gpu, scene.count * 4, "read")
  const parts = storage(gpu, Math.max(1, scene.parts) * 64, "read")

  const view = (moment: Moment) => {
    const f = focal(scene.camera, grid)
    const {right, up, ahead, eye} = viewFrom(scene.camera, moment.turn, moment.pitch)
    // The rim light's way across the picture, as a step to the next pixel (y down).
    const across = scene.rim[0] * right[0] + scene.rim[1] * right[1] + scene.rim[2] * right[2]
    const upward = scene.rim[0] * up[0] + scene.rim[1] * up[1] + scene.rim[2] * up[2]
    const span = Math.hypot(across, upward)
    const step = span > 1e-3 ? [Math.round(across / span), -Math.round(upward / span)] : [0, -1]
    return {
      frame: [grid.columns, grid.rows, f, moment.seconds],
      right: [right[0], right[1], right[2], moment.bob],
      up: [up[0], up[1], up[2], moment.flicker],
      ahead: [ahead[0], ahead[1], ahead[2], moment.pitch],
      eye: [eye[0], eye[1], eye[2], 0.55 * Math.min(1, span * 1.6)],
      limits: [(1.3 * grid.columns) / (2 * f), (1.3 * grid.rows) / (2 * f), step[0]!, step[1]!],
    }
  }
  const first: Moment = {turn: 0, pitch: scene.camera.pitch, bob: 0, flicker: 1, seconds: 0}

  const splats = draw(gpu, {
    shader: prepareShader(SPLAT_WGSL, "splats.wgsl"),
    geometry: {topology: "triangle-strip"},
    vertices: 4,
    instances: scene.count,
    blend: "premultiplied",
    depth: false,
    label: "splats.splats",
    set: {view: view(first), splats: data, order, parts},
  })
  const pixelPass = effect(gpu, prepareShader(pixelWgsl(scene, palette, lab), "splats_pixels.wgsl"), {
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
    shader: prepareShader(motesWgsl(scene), "splats_motes.wgsl"),
    geometry: {topology: "triangle-strip"},
    vertices: 4,
    instances: Math.min(MOTES_LIMIT, scene.motes.back + scene.motes.front),
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
    pose(where) {
      parts.write(where)
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
