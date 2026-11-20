/* Paints a baked scene with WebGPU as pixel art: a coarse grid of art pixels, each one of the scene's palette colours, with every
   splat posed in the vertex shader by its part's matrix and its kind of motion. Each frame lays the solid splats (depth-tested),
   their crisp edges and then the blended splats far to near (order.js) onto the grid, and finishes it with glass, contact shade,
   outline, dither and the nearest palette colour. The finished picture goes onto the canvas, each art pixel a square of pixels. */
import { prepareShader } from '@vgpu/wgsl/prepare';
import { draw, effect, storage, target } from 'vgpu';

import { gridFor, viewFrom } from './camera.js';
import { frameAt } from './motion.js';
import { createOrder } from './order.js';
import { CHUNK_SIZE, GLASS, NO_DEPTH, NO_FOG } from './scene.js';

const float = x => `${x}f`;

// the scene's own numbers, as constants of every shader that reads it
const sceneWgsl = ({ header: h, at }) => /* wgsl */ `
const PALETTE = ${at.palette}u;
const STYLE_DENSITY = ${at.styleDensity}u;
const STYLE_CODE = ${at.styleCode}u;
const STYLE_PART = ${at.stylePart}u;
const MOTION_RANGE = ${at.motionRange}u;
const MOTION_EXTRA = ${at.motionExtra}u;
const CHUNK_BOUNDS = ${at.chunkBounds}u;
const POSITION = ${at.position}u;
const ROTATION = ${at.rotation}u;
const SCALE = ${at.scale}u;
const COLOUR = ${at.colour}u;
const STYLE = ${at.style}u;
const CYCLES = ${at.cycles}u;
const PHASE = ${at.phase}u;
const MOTION = ${at.motion}u;
const TRACK = ${at.track}u;

const MOVING = ${h.moving}u;
const PARTS = ${h.parts}u;
const CHUNK = ${CHUNK_SIZE}u;
const COLOURS = ${h.colours}u;
const FOG_INDEX = ${h.fogIndex}u;
const OUTLINE_INDEX = ${h.outlineIndex}u;

const LOG_SCALE_MIN = ${float(h.logScaleMin)};
const LOG_SCALE_SPAN = ${float(h.logScaleMax - h.logScaleMin)};
const RADIUS = ${float(h.radius)};
const FOG_START = ${float(h.fogStart)};
const FOG_MAX = ${float(h.fogMax)};
const OUTLINE_EDGE = ${float(h.outlineEdge)};
const SHADE_STRENGTH = ${float(h.shadeStrength)};
const SHADE_RANGE = ${float(h.shadeRange)};
const DITHER = ${float(h.dither)};
const GLASS_BEND = ${float(h.glassBend)};

const NO_DEPTH = ${NO_DEPTH}u;
const NO_FOG = ${NO_FOG}u;
const GLASS = ${GLASS}u;

@group(0) @binding(1) var<storage, read> words: array<u32>;

// the k-th byte, 16-bit number, signed byte and 32-bit float of a block
fn u8At(block: u32, k: u32) -> u32 {
  return (words[block + (k >> 2u)] >> ((k & 3u) * 8u)) & 255u;
}
fn u16At(block: u32, k: u32) -> u32 {
  return (words[block + (k >> 1u)] >> ((k & 1u) * 16u)) & 65535u;
}
fn i8At(block: u32, k: u32) -> i32 {
  return (i32(u8At(block, k)) << 24u) >> 24u;
}
fn f32At(block: u32, k: u32) -> f32 {
  return bitcast<f32>(words[block + k]);
}

fn paletteColour(index: u32) -> vec3f {
  let value = words[PALETTE + index];
  return vec3f(f32((value >> 16u) & 255u), f32((value >> 8u) & 255u), f32(value & 255u)) / 255.0;
}
`;

const SPLATS_WGSL = /* wgsl */ `
struct View {
  // the camera's right axis and its focal length in art pixels; its up axis and the nearest a splat may be; its back axis and one
  // over the farthest a splat can be; the eye and its distance from the target
  right: vec4f,
  up: vec4f,
  back: vec4f,
  eye: vec4f,
  // the grid's columns and rows, and how far off the middle a splat's slope is taken
  grid: vec4f,
  // the time into the loop over the loop, and the stored frame shown
  clock: vec4f,
}

@group(0) @binding(0) var<uniform> view: View;
@group(0) @binding(2) var<storage, read> ids: array<u32>;

const TAU = 6.283185307179586;
const FLICKER = 1u;
const FALL = 2u;
const RISE = 3u;
const BLINK = 4u;
const ORBIT = 5u;
const BOB = 6u;
const PULSE = 7u;
const SWAY = 11u;

// a splat drawn nowhere: its corners all outside what the graphics card draws
const NOWHERE = vec4f(2.0, 2.0, 2.0, 1.0);

struct Dab {
  @builtin(position) position: vec4f,
  // its centre on the grid, in art pixels from the bottom left, and its density
  @location(0) @interpolate(flat) centre: vec3f,
  // its footprint on the grid: the covariance a, b, c
  @location(1) @interpolate(flat) shape: vec3f,
  // its colour, and its depth from the front of the scene (0) to the back (1)
  @location(2) @interpolate(flat) colour: vec4f,
  @location(3) @interpolate(flat) code: u32,
}

fn restCentre(n: u32) -> vec3f {
  let box = CHUNK_BOUNDS + (n / CHUNK) * 6u;
  let lo = vec3f(bitcast<f32>(words[box]), bitcast<f32>(words[box + 1u]), bitcast<f32>(words[box + 2u]));
  let hi = vec3f(bitcast<f32>(words[box + 3u]), bitcast<f32>(words[box + 4u]), bitcast<f32>(words[box + 5u]));
  let at = vec3f(f32(u16At(POSITION, 3u * n)), f32(u16At(POSITION, 3u * n + 1u)), f32(u16At(POSITION, 3u * n + 2u)));
  return lo + (hi - lo) * at / 65535.0;
}

fn restShape(n: u32) -> mat3x3f {
  let packed = words[ROTATION + n];
  let left = packed >> 30u;
  var q = vec4f(0.0);
  var kept = 0u;
  for (var place = 0u; place < 4u; place++) {
    if (place == left) {
      continue;
    }
    let v = f32((packed >> (20u - 10u * kept)) & 1023u);
    q[place] = (2.0 * v / 1023.0 - 1.0) * 0.7071067811865476;
    kept++;
  }
  q[left] = sqrt(max(0.0, 1.0 - dot(q, q)));
  let x = q.x;
  let y = q.y;
  let z = q.z;
  let w = q.w;
  let turn = mat3x3f(
    vec3f(1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y + z * w), 2.0 * (x * z - y * w)),
    vec3f(2.0 * (x * y - z * w), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z + x * w)),
    vec3f(2.0 * (x * z + y * w), 2.0 * (y * z - x * w), 1.0 - 2.0 * (x * x + y * y)),
  );
  let size = exp(LOG_SCALE_MIN + LOG_SCALE_SPAN * vec3f(
    f32(u16At(SCALE, 3u * n)), f32(u16At(SCALE, 3u * n + 1u)), f32(u16At(SCALE, 3u * n + 2u))) / 65535.0);
  let m = mat3x3f(turn[0] * size.x, turn[1] * size.y, turn[2] * size.z);
  return m * transpose(m);
}

@vertex fn vs_main(@builtin(vertex_index) corner: u32, @builtin(instance_index) instance: u32) -> Dab {
  var out: Dab;
  out.position = NOWHERE;
  let n = ids[instance];
  let style = u8At(STYLE, n);
  let code = u8At(STYLE_CODE, style);
  let frame = u32(view.clock.y);
  var alpha = f32At(STYLE_DENSITY, style);
  var p = restCentre(n);
  var sigma = restShape(n);

  // carried by its part
  let track = TRACK + (frame * PARTS + u8At(STYLE_PART, style)) * 12u;
  let carry = transpose(mat3x3f(
    vec3f(f32At(track, 0u), f32At(track, 1u), f32At(track, 2u)),
    vec3f(f32At(track, 3u), f32At(track, 4u), f32At(track, 5u)),
    vec3f(f32At(track, 6u), f32At(track, 7u), f32At(track, 8u)),
  ));
  p = carry * p + vec3f(f32At(track, 9u), f32At(track, 10u), f32At(track, 11u));
  sigma = carry * sigma * transpose(carry);

  // moved by its kind; every kind makes a whole number of cycles a loop
  let kind = select(0u, code & 15u, n < MOVING);
  var grow = 1.0;
  var glow = 0.0;
  if (kind != 0u) {
    let m = u8At(MOTION, n);
    let range = f32At(MOTION_RANGE, m);
    let extra = f32At(MOTION_EXTRA, m);
    let cycles = f32(i8At(CYCLES, n));
    let phase = f32(u16At(PHASE, n)) / 65536.0;
    let turns = fract(cycles * view.clock.x);
    let angle = TAU * (turns + phase);
    switch kind {
      case FLICKER: {
        alpha *= 0.62 + 0.38 * sin(angle);
      }
      case FALL: {
        let u = fract(turns + phase);
        p.y -= u * range;
        alpha *= 1.0 - u * u;
        grow = 1.0 + u * extra;
      }
      case RISE: {
        let u = fract(turns + phase);
        p += vec3f(0.25 * u * sin(7.0 * u + 50.0 * phase), u * range, 0.0);
        alpha *= (1.0 - u) * smoothstep(0.0, 0.1, u);
        grow = 0.6 + u * extra;
      }
      case BLINK: {
        glow = 0.3 * smoothstep(0.75, 1.0, sin(angle));
      }
      case ORBIT: {
        let turn = TAU * turns;
        p = vec3f(p.x * cos(turn) + p.z * sin(turn), p.y, p.z * cos(turn) - p.x * sin(turn));
      }
      case BOB: {
        p.y += range * sin(angle);
      }
      case PULSE: {
        alpha *= 0.82 + 0.18 * sin(angle);
      }
      case SWAY: {
        let before = p;
        p.x += range * sin(angle + 1.3 * before.y + 0.9 * before.z);
        p.y += 0.6 * range * sin(TAU * (fract(1.3 * cycles * view.clock.x) + phase) + 1.1 * before.x);
      }
      default: {}
    }
  }
  if (alpha <= 0.0) {
    return out;
  }

  // seen by the camera
  let seen = p - view.eye.xyz;
  let c = vec3f(dot(view.right.xyz, seen), dot(view.up.xyz, seen), dot(view.back.xyz, seen));
  if (c.z > -view.up.w) {
    return out;
  }
  let focal = view.right.w;
  let iota = -1.0 / c.z;
  var centre = view.grid.xy * 0.5 + focal * c.xy * iota;
  if (kind == FLICKER) {
    centre = floor(centre) + 0.5;
  }
  let slope = clamp(c.xy * iota, -view.grid.zw, view.grid.zw);
  let across = focal * iota * (view.right.xyz + slope.x * view.back.xyz);
  let upward = focal * iota * (view.up.xyz + slope.y * view.back.xyz);
  let s = sigma * (grow * grow);
  let shape = vec3f(dot(across, s * across) + 0.15, dot(across, s * upward), dot(upward, s * upward) + 0.15);
  if (shape.x * shape.z - shape.y * shape.y <= 0.0) {
    return out;
  }
  let reach = min(3.0 * sqrt(shape.xz), vec2f(2048.0));
  var corners = array<vec2f, 4>(vec2f(-1.0, -1.0), vec2f(1.0, -1.0), vec2f(-1.0, 1.0), vec2f(1.0, 1.0));
  let at = centre + corners[corner] * reach;

  // its colour, its depth and the haze
  let depth = clamp((-c.z - (view.eye.w - RADIUS)) / (2.0 * RADIUS), 0.0, 1.0);
  var colour = paletteColour(u8At(COLOUR, n)) + glow;
  if ((code & NO_FOG) == 0u) {
    colour = mix(colour, paletteColour(FOG_INDEX), smoothstep(FOG_START, 1.0, depth) * FOG_MAX);
  }

  out.position = vec4f(at / view.grid.xy * 2.0 - 1.0, -c.z * view.back.w, 1.0);
  out.centre = vec3f(centre, alpha);
  out.shape = shape;
  out.colour = vec4f(min(colour, vec3f(1.0)), depth);
  out.code = code;
  return out;
}

// a splat's cover of this art pixel: crisp for a solid splat, soft for the rest
fn weight(dab: Dab) -> f32 {
  let d = vec2f(dab.position.x, view.grid.y - dab.position.y) - dab.centre.xy;
  let s = dab.shape;
  let power = -(s.z * d.x * d.x - 2.0 * s.y * d.x * d.y + s.x * d.y * d.y) / (2.0 * (s.x * s.z - s.y * s.y));
  if (power < -4.5) {
    return 0.0;
  }
  return dab.centre.z * exp(power);
}

fn cover(dab: Dab, w: f32) -> f32 {
  if (dab.centre.z >= 1.0) {
    return 0.99 * smoothstep(0.38, 0.62, w);
  }
  return min(0.99, w);
}

// colour and depth are kept less a half, where a 16-bit float holds them most finely
struct Layers {
  @location(0) colour: vec4f,
  @location(1) depth: vec4f,
  @location(2) glass: vec4f,
}

@fragment fn fs_solid(dab: Dab) -> Layers {
  if (weight(dab) < 0.62) {
    discard;
  }
  return Layers(vec4f(dab.colour.rgb - 0.5, 1.0), vec4f(dab.colour.a - 0.5, 1.0, 0.0, 1.0), vec4f(0.0));
}

@fragment fn fs_edge(dab: Dab) -> Layers {
  let w = weight(dab);
  if (w >= 0.62 || w <= 0.38) {
    discard;
  }
  return over(dab, cover(dab, w));
}

@fragment fn fs_sorted(dab: Dab) -> Layers {
  return over(dab, cover(dab, weight(dab)));
}

fn over(dab: Dab, a: f32) -> Layers {
  if (a < 0.004) {
    discard;
  }
  let solid = dab.centre.z >= 1.0 && (dab.code & NO_DEPTH) == 0u;
  let glass = !solid && (dab.code & GLASS) != 0u;
  var out = Layers(vec4f(a * (dab.colour.rgb - 0.5), a), vec4f(0.0), vec4f(0.0));
  if (solid) {
    out.depth = vec4f(a * (dab.colour.a - 0.5), a, 0.0, a);
    out.glass = vec4f(0.0, 0.0, 0.0, a);
  } else if (glass) {
    out.glass = vec4f(0.5 * a, 0.0, 0.0, 0.0);
  }
  return out;
}
`;

const FINISH_WGSL = /* wgsl */ `
@group(0) @binding(2) var colourLayer: texture_2d<f32>;
@group(0) @binding(3) var depthLayer: texture_2d<f32>;
@group(0) @binding(4) var glassLayer: texture_2d<f32>;

// art pixel (x, y), counted from the bottom left, as a texel; reads off the grid take the nearest edge
fn texel(x: i32, y: i32) -> vec2i {
  let size = vec2i(textureDimensions(colourLayer));
  return vec2i(clamp(x, 0, size.x - 1), size.y - 1 - clamp(y, 0, size.y - 1));
}

// the layers laid over the backdrop (palette colour 0): depth 1 and no glass where nothing covers
fn colourAt(x: i32, y: i32) -> vec3f {
  let c = textureLoad(colourLayer, texel(x, y), 0);
  return c.rgb + 0.5 * c.a + (1.0 - c.a) * paletteColour(0u);
}
fn depthAt(x: i32, y: i32) -> f32 {
  let d = textureLoad(depthLayer, texel(x, y), 0);
  return d.r + 0.5 * d.g + (1.0 - d.g);
}
fn glassAt(x: i32, y: i32) -> f32 {
  return textureLoad(glassLayer, texel(x, y), 0).r;
}

// the nearest palette colour, by 0.3 red, 0.55 green and 0.15 blue; the first of a tie
fn nearest(c: vec3f) -> vec3f {
  var best = vec3f(0.0);
  var bestGap = 1e9;
  for (var i = 0u; i < COLOURS; i++) {
    let candidate = paletteColour(i);
    let d = candidate - c;
    let gap = dot(vec3f(0.3, 0.55, 0.15), d * d);
    if (gap < bestGap) {
      best = candidate;
      bestGap = gap;
    }
  }
  return best;
}

@fragment fn fs_main(@builtin(position) at: vec4f) -> @location(0) vec4f {
  let x = i32(at.x);
  let y = i32(textureDimensions(colourLayer).y) - 1 - i32(at.y);

  var colour = colourAt(x, y);
  let gx = glassAt(x + 1, y) - glassAt(x - 1, y);
  let gy = glassAt(x, y + 1) - glassAt(x, y - 1);
  if (glassAt(x, y) + abs(gx) + abs(gy) > 0.0) {
    colour = colourAt(x + i32(floor(GLASS_BEND * gx + 0.5)), y + i32(floor(GLASS_BEND * gy + 0.5)));
  }

  let depth = depthAt(x, y);
  var around = array<vec2i, 8>(
    vec2i(2, 0), vec2i(-2, 0), vec2i(0, 2), vec2i(0, -2), vec2i(1, 1), vec2i(1, -1), vec2i(-1, 1), vec2i(-1, -1));
  var shut = 0.0;
  for (var i = 0u; i < 8u; i++) {
    let gap = (depth - depthAt(x + around[i].x, y + around[i].y)) / (SHADE_RANGE / (2.0 * RADIUS));
    if (gap > 0.08 && gap < 3.0) {
      shut += min(1.0, gap);
    }
  }
  colour *= 1.0 - SHADE_STRENGTH * min(1.0, shut / 4.0);

  let step = max(2.0 * depth - depthAt(x - 1, y) - depthAt(x + 1, y), 2.0 * depth - depthAt(x, y - 1) - depthAt(x, y + 1));
  if (step > OUTLINE_EDGE / (2.0 * RADIUS)) {
    return vec4f(paletteColour(OUTLINE_INDEX), 1.0);
  }

  var bayer = array<f32, 16>(0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
  let b = bayer[u32(y & 3) * 4u + u32(x & 3)];
  return vec4f(nearest(clamp(colour + ((b + 0.5) / 16.0 - 0.5) * 0.105 * DITHER, vec3f(0.0), vec3f(1.0))), 1.0);
}
`;

const PRESENT_WGSL = /* wgsl */ `
struct Present {
  // screen pixels to a side of an art pixel (the last three are padding)
  scale: vec4f,
}

@group(0) @binding(0) var<uniform> present: Present;
@group(0) @binding(1) var picture: texture_2d<f32>;

@fragment fn fs_main(@builtin(position) at: vec4f) -> @location(0) vec4f {
  let size = vec2i(textureDimensions(picture));
  return vec4f(textureLoad(picture, clamp(vec2i(floor(at.xy / present.scale.x)), vec2i(0), size - 1), 0).rgb, 1.0);
}
`;

/* A painter for one scene: resize(width, height) fits the grid to a stage of that many screen pixels and returns it; encode(f,
   { yaw, pitch, seconds }, stage) draws one moment onto the stage; compile(stage) prepares every pipeline before the first frame. */
export function createPainter(gpu, scene) {
  const { header } = scene;
  let grid = gridFor(header, 3, 2);
  const layers = target(gpu, {
      size: [grid.columns, grid.rows],
      colors: [{ format: 'rgba16float' }, { format: 'rg16float' }, { format: 'r8unorm' }],
      depth: 'depth32float',
      label: 'splats.layers'
    }),
    picture = target(gpu, { size: [grid.columns, grid.rows], format: 'rgba8unorm', label: 'splats.picture' }),
    words = storage(gpu, scene.words.byteLength, 'read'),
    order = createOrder(scene),
    solidIds = storage(gpu, Math.max(4, order.solid.byteLength), 'read'),
    sortedIds = storage(gpu, Math.max(4, (header.splats - order.solid.length) * 4), 'read');
  words.write(scene.words);
  solidIds.write(order.solid);

  // how far from the world's middle any splat reaches at rest, so the depth test can take each depth as a share of the farthest a
  // splat can be from the eye, with room for the moving parts
  const extent = Math.sqrt(3) * scene.blocks.chunkBounds.reduce((most, v) => Math.max(most, Math.abs(v)), 0);
  const viewOf = ({ right, up, back, eye, distance }, seconds) => {
    const limit = 1.3 / (2 * grid.focal);
    return {
      right: [...right, grid.focal],
      up: [...up, Math.max(0.4, 0.15 * distance)],
      back: [...back, 1 / (2 * (distance + Math.hypot(...header.camTarget) + extent))],
      eye: [...eye, distance],
      grid: [grid.columns, grid.rows, limit * grid.columns, limit * grid.rows],
      clock: [seconds / header.loop, frameAt(header, seconds), 0, 0]
    };
  };
  const first = viewOf(viewFrom(header, header.camYaw, header.camPitch, grid.zoom), 0),
    shader = prepareShader(sceneWgsl(scene) + SPLATS_WGSL, 'splats.wgsl'),
    splats = { shader, geometry: { topology: 'triangle-strip' }, vertices: 4, label: 'splats.splats' },
    solid = draw(gpu, {
      ...splats,
      instances: order.solid.length,
      depth: { write: true, compare: 'less-equal' },
      entry: { vertex: 'vs_main', fragment: 'fs_solid' },
      set: { view: first, words, ids: solidIds }
    }),
    edges = draw(gpu, {
      ...splats,
      instances: order.solid.length,
      blend: 'premultiplied',
      depth: { write: false, compare: 'less' },
      entry: { vertex: 'vs_main', fragment: 'fs_edge' },
      set: { view: first, words, ids: solidIds }
    }),
    blended = draw(gpu, {
      ...splats,
      blend: 'premultiplied',
      depth: { write: false, compare: 'less' },
      entry: { vertex: 'vs_main', fragment: 'fs_sorted' },
      set: { view: first, words, ids: sortedIds }
    }),
    finish = effect(gpu, prepareShader(sceneWgsl(scene) + FINISH_WGSL, 'splats_finish.wgsl'), { label: 'splats.finish' }),
    show = effect(gpu, prepareShader(PRESENT_WGSL, 'splats_present.wgsl'), { label: 'splats.present' });
  const bind = () => {
    finish.set({ words, colourLayer: layers.colors[0], depthLayer: layers.colors[1], glassLayer: layers.colors[2] });
    show.set({ present: { scale: [grid.scale, 0, 0, 0] }, picture: picture.color });
  };
  bind();

  return {
    resize(width, height) {
      const next = gridFor(header, width, height),
        same = next.columns === grid.columns && next.rows === grid.rows && next.scale === grid.scale;
      grid = next;
      if (!same) {
        layers.resize([grid.columns, grid.rows]);
        picture.resize([grid.columns, grid.rows]);
        bind();
      }
      return grid;
    },
    encode(f, { yaw, pitch, seconds }, stage) {
      const camera = viewFrom(header, yaw, pitch, grid.zoom),
        view = viewOf(camera, seconds),
        ids = order.farToNear(camera.back, seconds);
      sortedIds.write(ids);
      solid.set({ view });
      edges.set({ view });
      blended.set({ view });
      f.pass({ target: layers, clear: [0, 0, 0, 0] }, pass => {
        pass.draw(solid);
        pass.draw(edges);
        pass.draw(blended, { instances: ids.length });
      });
      f.pass({ target: picture }, finish);
      f.pass({ target: stage }, show);
    },
    async compile(stage) {
      await solid.compile(layers);
      await edges.compile(layers);
      await blended.compile(layers);
      await finish.compile(picture);
      await show.compile(stage);
    }
  };
}
