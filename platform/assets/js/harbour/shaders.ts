/**
 * The harbour's WGSL. Each shader is prepared on its own, so the shared part is
 * written once here and placed at the head of the ones that light things.
 *
 * The harbour has six looks (`scene.style`): toy, studio, cartoon, paper,
 * blueprint and pixel. The scene shaders give each look its light, colours and
 * water; the present pass adds outlines, paper grain or big pixels on top.
 */

/** The order of HARBOUR_STYLES in renderer.ts. */
const styles = /* wgsl */ `
const STUDIO: u32 = 1u;
const CARTOON: u32 = 2u;
const PAPER: u32 = 3u;
const BLUEPRINT: u32 = 4u;
const PIXEL: u32 = 5u;
`

/** Keep in step with MAX_SHIPS in sim.ts and the five islands in ISLANDS. */
const shared = /* wgsl */ `${styles}
struct Camera {
  viewProjection: mat4x4f,
  // Unit vector from the scene toward the camera; the view is orthographic.
  toEye: vec3f,
}

struct Scene {
  lightViewProjection: mat4x4f,
  sunDirection: vec3f,
  time: f32,
  sunColor: vec3f,
  // 0 by day, 1 by night, eased between.
  night: f32,
  skyColor: vec3f,
  shipCount: u32,
  // The page colour the sea fades into at its edges, display-encoded.
  haze: vec3f,
  exposure: f32,
  style: u32,
  // x, z, radius, unused.
  islands: array<vec4f, 5>,
  // x, z, heading, speed from 0 to 1.
  ships: array<vec4f, 16>,
}

@group(0) @binding(0) var<uniform> camera: Camera;
@group(0) @binding(1) var<uniform> scene: Scene;
@group(0) @binding(2) var shadowMap: texture_depth_2d;
@group(0) @binding(3) var shadowSampler: sampler_comparison;

const SHADOW_TEXEL: f32 = 1.0 / 2048.0;

// The blueprint's paper and ink, by day and by night (display colours).
const DRAFT_PAPER_DAY: vec3f = vec3f(0.95, 0.96, 0.97);
const DRAFT_PAPER_NIGHT: vec3f = vec3f(0.07, 0.15, 0.3);
const DRAFT_INK_DAY: vec3f = vec3f(0.12, 0.3, 0.62);
const DRAFT_INK_NIGHT: vec3f = vec3f(0.66, 0.84, 1.0);

fn linear(c: vec3f) -> vec3f {
  return pow(c, vec3f(2.2));
}

// Every face is flat: its slope comes from the screen, turned to face the camera.
fn facetNormal(p: vec3f) -> vec3f {
  let n = normalize(cross(dpdx(p), dpdy(p)));
  return select(-n, n, dot(n, camera.toEye) > 0.0);
}

fn sunShadow(p: vec3f, n: vec3f) -> f32 {
  let clip = scene.lightViewProjection * vec4f(p + n * 0.02, 1.0);
  let ndc = clip.xyz / clip.w;
  let uv = vec2f(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
  if (any(uv < vec2f(0.0)) || any(uv > vec2f(1.0)) || ndc.z > 1.0) {
    return 1.0;
  }
  let depth = ndc.z - 0.0012;
  // Cartoon and blueprint shadows have hard edges; the studio's are wide and soft.
  if (scene.style == CARTOON || scene.style == BLUEPRINT) {
    return textureSampleCompareLevel(shadowMap, shadowSampler, uv, depth);
  }
  let reach = select(1, 2, scene.style == STUDIO);
  let spread = select(1.3, 4.5, scene.style == STUDIO) * SHADOW_TEXEL;
  var lit = 0.0;
  var taps = 0.0;
  for (var y = -reach; y <= reach; y++) {
    for (var x = -reach; x <= reach; x++) {
      lit += textureSampleCompareLevel(shadowMap, shadowSampler, uv + vec2f(f32(x), f32(y)) * spread, depth);
      taps += 1.0;
    }
  }
  return lit / taps;
}

struct Surface {
  albedo: vec3f,
  specular: f32,
  shininess: f32,
  emission: vec3f,
}

// A look's palette: the studio's is quieter, the cartoon's louder, paper's pale.
fn styled(albedo: vec3f) -> vec3f {
  let grey = vec3f(dot(albedo, vec3f(0.2126, 0.7152, 0.0722)));
  if (scene.style == STUDIO) {
    return mix(grey, albedo, 0.7) * 1.06;
  }
  if (scene.style == CARTOON) {
    return clamp(mix(grey, albedo, 1.35), vec3f(0.0), vec3f(1.0));
  }
  if (scene.style == PAPER) {
    return mix(albedo, linear(vec3f(0.93, 0.89, 0.8)), 0.25);
  }
  return albedo;
}

fn shade(surface: Surface, n: vec3f, shadow: f32) -> vec3f {
  let l = scene.sunDirection;
  var direct = max(dot(n, l), 0.0) * shadow;
  let h = normalize(l + camera.toEye);
  var lobe = pow(max(dot(n, h), 0.0), surface.shininess) * surface.specular * direct;
  let ground = scene.skyColor * 0.35 + vec3f(0.06, 0.05, 0.03) * (1.0 - scene.night);
  var ambient = mix(ground, scene.skyColor, n.y * 0.5 + 0.5);
  if (scene.style == STUDIO) {
    // A soft studio fill: light from the whole sky, little from the ground.
    ambient = mix(scene.skyColor * 0.5, scene.skyColor * 1.2, n.y * 0.5 + 0.5);
  } else if (scene.style == CARTOON) {
    // Two tones, lit or in shade, and one hard highlight.
    direct = smoothstep(0.3, 0.36, direct) * 0.95;
    lobe = smoothstep(0.45, 0.5, lobe) * 0.5;
    ambient *= 1.15;
  } else if (scene.style == PAPER) {
    direct = smoothstep(0.0, 0.7, direct);
    lobe = 0.0;
    ambient *= 1.25;
  }
  return surface.albedo * (scene.sunColor * direct + ambient) + scene.sunColor * lobe + surface.emission;
}

fn tonemap(x: vec3f) -> vec3f {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3f(0.0), vec3f(1.0));
}

fn encode(c: vec3f) -> vec3f {
  return select(1.055 * pow(c, vec3f(1.0 / 2.4)) - 0.055, c * 12.92, c <= vec3f(0.0031308));
}

// The scene target holds display-ready colour.
fn finish(radiance: vec3f) -> vec3f {
  return encode(tonemap(radiance * scene.exposure));
}

// What the present pass draws its outlines from: a value that changes across
// every edge worth inking, kept in the scene target's alpha.
fn edgeKey(n: vec3f, material: u32, height: f32) -> f32 {
  return 0.15 + 0.3 * (dot(n, vec3f(0.31, 0.83, 0.47)) * 0.5 + 0.5) + 0.05 * f32(material % 8u)
    + 0.04 * clamp(height, 0.0, 3.0);
}

// The sea's own key: no outline inside the water, only where it meets land.
const WATER_KEY: f32 = 0.05;

// Diagonal ink strokes in screen space, for the blueprint's shade.
fn hatch(pixel: vec2f) -> f32 {
  return step(0.62, fract((pixel.x + pixel.y) / 7.0));
}

fn grainAt(p: vec2f) -> f32 {
  return fract(sin(dot(floor(p), vec2f(127.1, 311.7))) * 43758.5453);
}

// Same sum as waveHeight in sim.ts.
fn waveHeight(p: vec2f, t: f32) -> f32 {
  return 0.045 * sin(0.9 * p.x + 0.6 * p.y + 1.1 * t)
    + 0.03 * sin(-0.5 * p.x + 1.3 * p.y + 1.7 * t + 1.3)
    + 0.018 * sin(1.9 * p.x - 1.1 * p.y + 2.3 * t);
}

// Sails belly forward and flags ripple along their length.
fn swayed(position: vec3f, material: u32, sway: f32, phase: f32) -> vec3f {
  var p = position;
  let t = scene.time;
  if (material == 10u) {
    p.x += sway * (0.075 + 0.02 * sin(t * 1.7 + phase));
  }
  if (material == 11u) {
    p.z += sway * 0.07 * sin(t * 5.0 - p.x * 9.0 + phase);
  }
  return p;
}
`

/** Islands, buildings, ships and smoke: every mesh vertex names its material. */
export const partsWgsl = /* wgsl */ `${shared}
struct PartInput {
  @location(0) position: vec3f,
  @location(1) material: f32,
  @location(2) sway: f32,
  @location(3) world0: vec4f,
  @location(4) world1: vec4f,
  @location(5) world2: vec4f,
  @location(6) world3: vec4f,
  // rgb: the agent's colour (linear), w: a phase so no two ships move alike.
  @location(7) style: vec4f,
}

struct PartVarying {
  @builtin(position) clip: vec4f,
  @location(0) world: vec3f,
  @location(1) @interpolate(flat, either) material: u32,
  @location(2) @interpolate(flat, either) style: vec4f,
}

@vertex
fn vs_main(input: PartInput) -> PartVarying {
  let model = mat4x4f(input.world0, input.world1, input.world2, input.world3);
  let material = u32(input.material + 0.5);
  let local = swayed(input.position, material, input.sway, input.style.w);
  var output: PartVarying;
  output.world = (model * vec4f(local, 1.0)).xyz;
  output.material = material;
  output.style = input.style;
  output.clip = camera.viewProjection * vec4f(output.world, 1.0);
  return output;
}

fn grain(p: vec3f) -> f32 {
  return fract(sin(dot(floor(p * 7.0), vec3f(12.9898, 78.233, 37.719))) * 43758.5453);
}

fn surfaceFor(input: PartVarying) -> Surface {
  var surface = Surface(vec3f(0.5), 0.04, 24.0, vec3f(0.0));
  let speck = grain(input.world);
  let night = scene.night;
  let t = scene.time;
  switch input.material {
    case 0u: { surface.albedo = linear(vec3f(0.91, 0.83, 0.63)) * (0.94 + 0.1 * speck); }
    case 1u: { surface.albedo = mix(linear(vec3f(0.46, 0.66, 0.38)), linear(vec3f(0.55, 0.72, 0.42)), speck); }
    case 2u: { surface.albedo = linear(vec3f(0.56, 0.55, 0.52)) * (0.9 + 0.15 * speck); }
    case 3u: { surface.albedo = linear(vec3f(0.63, 0.44, 0.26)); }
    case 4u: { surface.albedo = linear(vec3f(0.95, 0.91, 0.83)); }
    case 5u: { surface.albedo = linear(vec3f(0.78, 0.34, 0.24)); surface.shininess = 18.0; }
    case 6u: { surface.albedo = linear(vec3f(0.74, 0.72, 0.67)) * (0.92 + 0.12 * speck); }
    case 7u: {
      // Dark glass by day; lamplight by night.
      let flicker = 0.92 + 0.08 * sin(t * 6.0 + input.world.x * 13.0);
      surface.albedo = linear(vec3f(0.24, 0.3, 0.36));
      surface.specular = 0.4;
      surface.shininess = 80.0;
      surface.emission = linear(vec3f(1.0, 0.72, 0.38)) * 3.2 * night * flicker;
    }
    case 8u: {
      let glow = 2.2 + 0.6 * sin(t * 3.1) + 0.3 * sin(t * 7.3 + 1.0);
      surface.albedo = linear(vec3f(0.3, 0.08, 0.02));
      surface.emission = linear(vec3f(1.0, 0.45, 0.12)) * glow * (1.0 + night);
    }
    case 9u: { surface.albedo = linear(vec3f(0.38, 0.24, 0.15)); }
    case 10u: {
      surface.albedo = mix(linear(vec3f(0.96, 0.94, 0.89)), input.style.rgb, 0.8);
      surface.shininess = 10.0;
      // By night the lantern lights the sail, so each agent keeps its colour.
      surface.emission = surface.albedo * 0.35 * night;
    }
    case 11u: { surface.albedo = input.style.rgb; }
    case 12u: { surface.albedo = linear(vec3f(0.29, 0.31, 0.34)); surface.specular = 0.6; surface.shininess = 60.0; }
    case 13u: { surface.albedo = linear(vec3f(0.3, 0.55, 0.29)) * (0.88 + 0.16 * speck); }
    case 14u: { surface.albedo = mix(linear(vec3f(0.88, 0.86, 0.84)), linear(vec3f(0.42, 0.45, 0.52)), night); }
    case 15u: { surface.albedo = linear(vec3f(0.42, 0.29, 0.18)); }
    case 16u: { surface.albedo = linear(vec3f(0.34, 0.38, 0.43)); surface.shininess = 30.0; }
    default: {}
  }
  return surface;
}

// The studio rounds the islands' slopes, so only the buildings show their faces.
fn roundedGround(p: vec3f, n: vec3f) -> vec3f {
  var middle = vec2f(0.0);
  var nearest = 1e9;
  for (var i = 0u; i < 5u; i++) {
    let island = scene.islands[i];
    let d = length(p.xz - island.xy) - island.z;
    if (d < nearest) {
      nearest = d;
      middle = island.xy;
    }
  }
  let out = normalize(p.xz - middle + vec2f(1e-4));
  let slope = length(n.xz);
  return normalize(vec3f(out.x * slope, n.y, out.y * slope));
}

// A technical drawing: plain paper with the shade hatched in ink. The present
// pass inks every edge. Sails and pennants keep their agent's colour, and lit
// windows glow at night.
fn drafted(input: PartVarying, n: vec3f, shadow: f32) -> vec3f {
  let night = scene.night;
  let paper = mix(DRAFT_PAPER_DAY, DRAFT_PAPER_NIGHT, night);
  let ink = mix(DRAFT_INK_DAY, DRAFT_INK_NIGHT, night);
  let facing = max(dot(n, scene.sunDirection), 0.0) * shadow;
  var colour = mix(paper, ink, hatch(input.clip.xy) * (1.0 - smoothstep(0.15, 0.35, facing)) * 0.55);
  if (input.material == 10u || input.material == 11u) {
    colour = mix(encode(input.style.rgb), paper, 0.15);
  }
  if (input.material == 7u || input.material == 8u) {
    colour = mix(colour, vec3f(1.0, 0.76, 0.42), night);
  }
  return colour;
}

@fragment
fn fs_main(input: PartVarying) -> @location(0) vec4f {
  var n = facetNormal(input.world);
  if (scene.style == STUDIO && input.material <= 1u) {
    n = roundedGround(input.world, n);
  }
  let key = edgeKey(n, input.material, input.world.y);
  let shadow = sunShadow(input.world, n);
  if (scene.style == BLUEPRINT) {
    return vec4f(drafted(input, n, shadow), key);
  }
  var surface = surfaceFor(input);
  surface.albedo = styled(surface.albedo);
  if (scene.style == PAPER) {
    // Paper fibres in every face.
    surface.albedo *= 0.95 + 0.06 * grainAt(input.world.xz * 60.0 + input.world.y * 37.0);
  }
  return vec4f(finish(shade(surface, n, shadow)), key);
}
`

/** The sea: a grid lifted by the waves, coloured by its depth, foam and wakes. */
export const waterWgsl = /* wgsl */ `${shared}
struct WaterVarying {
  @builtin(position) clip: vec4f,
  @location(0) world: vec3f,
}

@vertex
fn vs_main(@location(0) position: vec3f) -> WaterVarying {
  var output: WaterVarying;
  output.world = vec3f(position.x, waveHeight(position.xz, scene.time), position.z);
  output.clip = camera.viewProjection * vec4f(output.world, 1.0);
  return output;
}

// The short V a moving hull leaves behind it.
fn wakes(p: vec2f) -> f32 {
  var foam = 0.0;
  for (var i = 0u; i < min(scene.shipCount, 16u); i++) {
    let ship = scene.ships[i];
    let forward = vec2f(cos(ship.z), sin(ship.z));
    let offset = p - ship.xy;
    let behind = -dot(offset, forward);
    let side = dot(offset, vec2f(-forward.y, forward.x));
    if (behind < -0.4 || behind > 1.6 || abs(side) > 0.8) {
      continue;
    }
    let fade = (1.0 - smoothstep(0.0, 1.6, behind)) * smoothstep(-0.4, -0.05, behind) * ship.w;
    let arm = abs(abs(side) - (0.08 + max(behind, 0.0) * 0.38));
    let edge = 1.0 - smoothstep(0.01, 0.05 + behind * 0.04, arm);
    let hull = 1.0 - smoothstep(0.1, 0.26, length(offset));
    foam += edge * fade * 0.7 + hull * 0.3 * ship.w;
  }
  return foam;
}

// Lamplight from the shore and the ships' lanterns, by night only.
fn nightGlow(p: vec3f, foam: f32) -> vec3f {
  var warm = 0.0;
  for (var i = 0u; i < 3u; i++) {
    let island = scene.islands[i];
    let d = length(p.xz - island.xy) - island.z;
    warm += exp(-d * d * 7.0) * 0.12;
  }
  for (var i = 0u; i < min(scene.shipCount, 16u); i++) {
    let d = length(p.xz - scene.ships[i].xy);
    warm += exp(-d * d * 14.0) * 0.18;
  }
  return linear(vec3f(1.0, 0.68, 0.35)) * warm * scene.night * (1.0 - foam * 0.5);
}

fn foamColour() -> vec3f {
  return mix(linear(vec3f(0.97, 0.98, 0.97)), linear(vec3f(0.5, 0.6, 0.72)), scene.night);
}

// Low-poly water: faceted swell, rings of surf and a glossy sheen.
fn toySea(p: vec3f, n: vec3f, shore: f32) -> vec3f {
  let night = scene.night;
  let shallow = 1.0 - smoothstep(-0.3, 1.9, shore);
  let day = mix(linear(vec3f(0.16, 0.42, 0.6)), linear(vec3f(0.36, 0.7, 0.72)), shallow);
  let dark = mix(linear(vec3f(0.04, 0.1, 0.19)), linear(vec3f(0.08, 0.25, 0.31)), shallow);
  var albedo = mix(day, dark, night);

  // Rings of foam rolling in to each beach.
  let ripple = sin(shore * 11.0 + scene.time * 1.6) * 0.5 + 0.5;
  let surf = (1.0 - smoothstep(0.0, 0.6, shore)) * smoothstep(0.6, 0.95, ripple) * 0.75
    + (1.0 - smoothstep(-0.25, 0.1, shore)) * 0.85;
  let foam = clamp(surf + wakes(p.xz), 0.0, 1.0);
  albedo = mix(albedo, foamColour(), foam);

  var surface = Surface(albedo, mix(0.55, 0.2, foam) * (1.0 - night * 0.6), 140.0, nightGlow(p, foam));
  return finish(shade(surface, n, sunShadow(p, n)));
}

// The swell's slope, from the same sum as waveHeight.
fn swellSlope(p: vec2f, t: f32) -> vec2f {
  let a = 0.045 * cos(0.9 * p.x + 0.6 * p.y + 1.1 * t);
  let b = 0.03 * cos(-0.5 * p.x + 1.3 * p.y + 1.7 * t + 1.3);
  let c = 0.018 * cos(1.9 * p.x - 1.1 * p.y + 2.3 * t);
  return a * vec2f(0.9, 0.6) + b * vec2f(-0.5, 1.3) + c * vec2f(1.9, -1.1);
}

// Small ripples running across the swell, for the studio's sparkle.
fn rippleSlope(p: vec2f, t: f32) -> vec2f {
  var waves = array<vec3f, 4>(vec3f(3.1, 1.7, 2.9), vec3f(-2.3, 3.7, 3.4), vec3f(4.3, -2.9, 4.1), vec3f(-5.1, -4.4, 5.3));
  var slope = vec2f(0.0);
  for (var i = 0u; i < 4u; i++) {
    let wave = waves[i];
    let phase = dot(wave.xy, p) + wave.z * t + f32(i) * 1.7;
    slope += (0.008 / (1.0 + f32(i) * 0.5)) * cos(phase) * wave.xy;
  }
  return slope;
}

// Real-looking water: smooth and glossy, sand and moving light in the
// shallows, the sky reflected where the surface tilts away.
fn studioSea(p: vec3f, shore: f32) -> vec3f {
  let t = scene.time;
  let night = scene.night;
  let slope = swellSlope(p.xz, t) + rippleSlope(p.xz, t);
  let n = normalize(vec3f(-slope.x, 1.0, -slope.y));
  let shallow = 1.0 - smoothstep(-0.2, 1.6, shore);
  var albedo = mix(linear(vec3f(0.17, 0.3, 0.35)), linear(vec3f(0.45, 0.62, 0.6)), shallow);
  let sand = 1.0 - smoothstep(-0.25, 0.35, shore);
  albedo = mix(albedo, linear(vec3f(0.78, 0.74, 0.6)), sand * 0.55);
  let a = 0.5 + 0.5 * sin(p.x * 6.0 + sin(p.z * 5.0 + t * 1.3) * 1.4 + t);
  let b = 0.5 + 0.5 * sin(p.z * 6.5 + sin(p.x * 4.0 - t * 1.1) * 1.2 - t * 0.8);
  let caustic = pow(a * b, 4.0);
  albedo += linear(vec3f(0.9, 0.95, 0.85)) * caustic * shallow * 0.12 * (1.0 - night);
  albedo = mix(albedo, albedo * vec3f(0.2, 0.26, 0.45), night);

  let ripple = sin(shore * 9.0 + t * 1.4) * 0.5 + 0.5;
  let surf = (1.0 - smoothstep(0.0, 0.45, shore)) * smoothstep(0.75, 0.98, ripple) * 0.5
    + (1.0 - smoothstep(-0.2, 0.05, shore)) * 0.6;
  let foam = clamp(surf + wakes(p.xz) * 0.6, 0.0, 1.0);
  albedo = mix(albedo, foamColour(), foam);

  let fresnel = 0.03 + 0.5 * pow(1.0 - max(dot(n, camera.toEye), 0.0), 4.0);
  var surface = Surface(albedo, (1.0 - foam) * 0.7 * (1.0 - night * 0.5), 400.0, vec3f(0.0));
  surface.emission = scene.skyColor * fresnel * 0.6 + nightGlow(p, foam);
  return finish(shade(surface, n, sunShadow(p, n)));
}

// Flat bands of colour, curling white strokes, and a ring of surf rolling out.
fn cartoonSea(p: vec3f, shore: f32) -> vec3f {
  let t = scene.time;
  let wobble = shore + 0.06 * sin(p.x * 3.0 + t * 1.2) * sin(p.z * 2.6 - t);
  var albedo = linear(vec3f(0.1, 0.45, 0.78));
  albedo = select(albedo, linear(vec3f(0.2, 0.66, 0.86)), wobble < 1.3);
  albedo = select(albedo, linear(vec3f(0.48, 0.86, 0.9)), wobble < 0.45);
  let swirl = sin(p.x * 1.1 + sin(p.z * 0.8 + t * 0.35) * 1.8) * sin(p.z * 1.3 + sin(p.x * 0.6 - t * 0.3) * 2.0);
  let stroke = (1.0 - smoothstep(0.02, 0.05, abs(swirl - 0.55))) * smoothstep(0.9, 1.6, shore);
  let ring = fract(t * 0.22);
  let band = (1.0 - smoothstep(0.12, 0.16, wobble))
    + (1.0 - smoothstep(0.03, 0.05, abs(wobble - 0.25 - ring * 0.9))) * (1.0 - ring);
  let foam = clamp(max(max(stroke, band), step(0.35, wakes(p.xz))), 0.0, 1.0);
  albedo = mix(albedo, linear(vec3f(0.98)), foam);
  albedo = mix(albedo, albedo * vec3f(0.17, 0.21, 0.38), scene.night);
  let up = vec3f(0.0, 1.0, 0.0);
  let surface = Surface(albedo, 0.0, 1.0, nightGlow(p, foam));
  return finish(shade(surface, up, sunShadow(p, up)));
}

// Layers of cut paper stepping down from each beach; their edges breathe.
fn paperSea(p: vec3f, shore: f32) -> vec3f {
  let t = scene.time;
  let level = max(shore, 0.0) * 1.8 + 0.12 * sin(t * 0.7 - shore * 1.3);
  let layer = min(floor(level), 5.0);
  var albedo = mix(linear(vec3f(0.62, 0.86, 0.84)), linear(vec3f(0.2, 0.47, 0.62)), layer / 5.0);
  // Each layer casts a thin shadow onto the one below it.
  let below = select(0.0, 1.0, layer >= 1.0 && layer < 5.0);
  albedo *= 1.0 - 0.22 * below * (1.0 - smoothstep(0.0, 0.1, fract(level)));
  let beach = 1.0 - smoothstep(0.08, 0.12, shore);
  let foam = max(beach, step(0.4, wakes(p.xz)));
  albedo = mix(albedo, linear(vec3f(0.97, 0.95, 0.9)), foam);
  albedo *= 0.95 + 0.06 * grainAt(p.xz * 60.0);
  albedo = mix(albedo, albedo * vec3f(0.22, 0.27, 0.45), scene.night);
  let up = vec3f(0.0, 1.0, 0.0);
  let surface = Surface(albedo, 0.0, 1.0, nightGlow(p, foam) * 0.6);
  return finish(shade(surface, up, sunShadow(p, up)));
}

// A chart: a grid riding the swell, soundings rolling out from each beach,
// wakes in ink, and shadows hatched.
fn draftedSea(p: vec3f, pixel: vec2f, shore: f32, grid: vec2f, gridStep: vec2f, shoreStep: f32) -> vec3f {
  let night = scene.night;
  let paper = mix(DRAFT_PAPER_DAY, DRAFT_PAPER_NIGHT, night);
  let ink = mix(DRAFT_INK_DAY, DRAFT_INK_NIGHT, night);
  let cell = abs(fract(grid - 0.5) - 0.5) / max(gridStep, vec2f(1e-4));
  let gridLine = 1.0 - min(min(cell.x, cell.y), 1.0);
  let sounding = max(shore, 0.0) / 0.45 - scene.time * 0.25;
  let ring = abs(fract(sounding - 0.5) - 0.5) / max(shoreStep / 0.45, 1e-4);
  let ringLine = (1.0 - min(ring, 1.0)) * (1.0 - smoothstep(1.5, 4.0, shore)) * step(0.0, shore);
  let coast = 1.0 - min(abs(shore) / max(shoreStep, 1e-4), 1.0);
  let wake = smoothstep(0.3, 0.5, wakes(p.xz));
  let hatched = hatch(pixel) * (1.0 - sunShadow(p, vec3f(0.0, 1.0, 0.0))) * 0.55;
  return mix(paper, ink, max(max(gridLine * 0.3, ringLine * 0.8), max(max(coast, wake), hatched)));
}

// The toy sea with points of light winking on it, for the pixel look.
fn pixelSea(p: vec3f, n: vec3f, shore: f32) -> vec3f {
  let cell = floor(p.xz * 2.5);
  let seed = grainAt(cell);
  let middle = (cell + 0.5) / 2.5;
  let blink = step(0.93, fract(seed * 13.0 + scene.time * 0.35 * (0.5 + seed)));
  let sparkle = blink * (1.0 - smoothstep(0.06, 0.12, length(p.xz - middle))) * smoothstep(1.0, 2.0, shore);
  return toySea(p, n, shore) + vec3f(sparkle * (0.7 - scene.night * 0.3));
}

@fragment
fn fs_main(input: WaterVarying) -> @location(0) vec4f {
  let p = input.world;
  // Everything measured across the screen is taken before anything branches.
  let n = facetNormal(p);
  var shore = 100.0;
  for (var i = 0u; i < 5u; i++) {
    let island = scene.islands[i];
    shore = min(shore, length(p.xz - island.xy) - island.z);
  }
  let grid = p.xz / 0.7;
  let gridStep = fwidth(grid);
  let shoreStep = fwidth(shore);

  var lit: vec3f;
  if (scene.style == STUDIO) {
    lit = studioSea(p, shore);
  } else if (scene.style == CARTOON) {
    lit = cartoonSea(p, shore);
  } else if (scene.style == PAPER) {
    lit = paperSea(p, shore);
  } else if (scene.style == BLUEPRINT) {
    lit = draftedSea(p, input.clip.xy, shore, grid, gridStep, shoreStep);
  } else if (scene.style == PIXEL) {
    lit = pixelSea(p, n, shore);
  } else {
    lit = toySea(p, n, shore);
  }

  // Far water melts into the page.
  let far = smoothstep(9.5, 16.0, length(p.xz));
  return vec4f(mix(lit, scene.haze, far), WATER_KEY);
}
`

/** Depth from the sun, for every mesh that casts a shadow. */
export const shadowWgsl = /* wgsl */ `
struct Scene {
  lightViewProjection: mat4x4f,
  sunDirection: vec3f,
  time: f32,
  sunColor: vec3f,
  night: f32,
  skyColor: vec3f,
  shipCount: u32,
  haze: vec3f,
  exposure: f32,
  style: u32,
  islands: array<vec4f, 5>,
  ships: array<vec4f, 16>,
}

@group(0) @binding(1) var<uniform> scene: Scene;

struct ShadowInput {
  @location(0) position: vec3f,
  @location(1) material: f32,
  @location(2) sway: f32,
  @location(3) world0: vec4f,
  @location(4) world1: vec4f,
  @location(5) world2: vec4f,
  @location(6) world3: vec4f,
  @location(7) style: vec4f,
}

@vertex
fn vs_main(input: ShadowInput) -> @builtin(position) vec4f {
  let model = mat4x4f(input.world0, input.world1, input.world2, input.world3);
  var p = input.position;
  let material = u32(input.material + 0.5);
  if (material == 10u) {
    p.x += input.sway * (0.075 + 0.02 * sin(scene.time * 1.7 + input.style.w));
  }
  return scene.lightViewProjection * model * vec4f(p, 1.0);
}

@fragment
fn fs_main() -> @location(0) vec4f {
  return vec4f(0.0);
}
`

/**
 * Lays the scene on the page: outlines where a look inks them, paper grain,
 * big dithered pixels for the pixel look, and a soft vignette.
 */
export const presentWgsl = /* wgsl */ `${styles}
struct Present {
  resolution: vec2f,
  vignette: f32,
  style: u32,
  // The outline colour (display), and how strongly it is laid down; 0 draws none.
  ink: vec3f,
  inkStrength: f32,
  // Outline width in pixels, and the step in the scene's edge key that counts as an edge.
  line: f32,
  edge: f32,
  // The pixel look's block size, in pixels.
  pixel: f32,
}

@group(0) @binding(0) var<uniform> present: Present;
@group(0) @binding(1) var sceneColor: texture_2d<f32>;
@group(0) @binding(2) var linearSampler: sampler;

fn keyAt(uv: vec2f) -> f32 {
  return textureSampleLevel(sceneColor, linearSampler, uv, 0.0).a;
}

// A 4 by 4 ordered dither, from 0 to 1.
fn bayer(cell: vec2f) -> f32 {
  var matrix = array<f32, 16>(0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
  let x = u32(cell.x) % 4u;
  let y = u32(cell.y) % 4u;
  return (matrix[y * 4u + x] + 0.5) / 16.0;
}

@fragment
fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let uv = position.xy / present.resolution;
  var color: vec3f;
  if (present.style == PIXEL) {
    let cell = floor(position.xy / present.pixel);
    let middle = (cell + 0.5) * present.pixel / present.resolution;
    let levels = 8.0;
    color = textureSampleLevel(sceneColor, linearSampler, middle, 0.0).rgb;
    color = floor(color * (levels - 1.0) + 0.5 + (bayer(cell) - 0.5) * 0.6) / (levels - 1.0);
  } else {
    color = textureSampleLevel(sceneColor, linearSampler, uv, 0.0).rgb;
  }
  if (present.inkStrength > 0.0) {
    let offset = present.line / present.resolution;
    let across = abs(keyAt(uv + vec2f(offset.x, 0.0)) - keyAt(uv - vec2f(offset.x, 0.0)));
    let down = abs(keyAt(uv + vec2f(0.0, offset.y)) - keyAt(uv - vec2f(0.0, offset.y)));
    let edge = smoothstep(present.edge, present.edge * 2.0, max(across, down));
    color = mix(color, present.ink, edge * present.inkStrength);
  }
  if (present.style == PAPER) {
    let fibre = fract(sin(dot(floor(position.xy / 1.5), vec2f(127.1, 311.7))) * 43758.5453);
    color *= 0.975 + 0.04 * fibre;
  }
  let centred = (uv - 0.5) * vec2f(present.resolution.x / present.resolution.y, 1.0);
  let vignette = 1.0 - present.vignette * smoothstep(0.4, 1.2, length(centred));
  return vec4f(color * vignette, 1.0);
}
`
