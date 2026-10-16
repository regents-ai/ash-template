/**
 * The harbour's WGSL. Each shader is prepared on its own, so the shared part is
 * written once here and placed at the head of the ones that light things.
 */

/** Keep in step with MAX_SHIPS in sim.ts and the five islands in ISLANDS. */
const shared = /* wgsl */ `
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
  var lit = 0.0;
  for (var y = -1; y <= 1; y++) {
    for (var x = -1; x <= 1; x++) {
      let offset = vec2f(f32(x), f32(y)) * SHADOW_TEXEL * 1.3;
      lit += textureSampleCompareLevel(shadowMap, shadowSampler, uv + offset, ndc.z - 0.0012);
    }
  }
  return lit / 9.0;
}

struct Surface {
  albedo: vec3f,
  specular: f32,
  shininess: f32,
  emission: vec3f,
}

fn shade(surface: Surface, n: vec3f, shadow: f32) -> vec3f {
  let l = scene.sunDirection;
  let ndl = max(dot(n, l), 0.0);
  let h = normalize(l + camera.toEye);
  let lobe = pow(max(dot(n, h), 0.0), surface.shininess) * surface.specular * ndl * shadow;
  let ground = scene.skyColor * 0.35 + vec3f(0.06, 0.05, 0.03) * (1.0 - scene.night);
  let ambient = mix(ground, scene.skyColor, n.y * 0.5 + 0.5);
  return surface.albedo * (scene.sunColor * ndl * shadow + ambient) + scene.sunColor * lobe + surface.emission;
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

@fragment
fn fs_main(input: PartVarying) -> @location(0) vec4f {
  let n = facetNormal(input.world);
  let shadow = sunShadow(input.world, n);
  return vec4f(finish(shade(surfaceFor(input), n, shadow)), 1.0);
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

@fragment
fn fs_main(input: WaterVarying) -> @location(0) vec4f {
  let p = input.world;
  let n = facetNormal(p);
  let night = scene.night;
  let t = scene.time;

  var shore = 100.0;
  for (var i = 0u; i < 5u; i++) {
    let island = scene.islands[i];
    shore = min(shore, length(p.xz - island.xy) - island.z);
  }
  let shallow = 1.0 - smoothstep(-0.3, 1.9, shore);
  let day = mix(linear(vec3f(0.16, 0.42, 0.6)), linear(vec3f(0.36, 0.7, 0.72)), shallow);
  let dark = mix(linear(vec3f(0.04, 0.1, 0.19)), linear(vec3f(0.08, 0.25, 0.31)), shallow);
  var albedo = mix(day, dark, night);

  // Rings of foam rolling in to each beach.
  let ripple = sin(shore * 11.0 + t * 1.6) * 0.5 + 0.5;
  let surf = (1.0 - smoothstep(0.0, 0.6, shore)) * smoothstep(0.6, 0.95, ripple) * 0.75
    + (1.0 - smoothstep(-0.25, 0.1, shore)) * 0.85;
  let foam = clamp(surf + wakes(p.xz), 0.0, 1.0);
  albedo = mix(albedo, mix(linear(vec3f(0.97, 0.98, 0.97)), linear(vec3f(0.5, 0.6, 0.72)), night), foam);

  let shadow = sunShadow(p, n);
  var surface = Surface(albedo, mix(0.55, 0.2, foam) * (1.0 - night * 0.6), 140.0, vec3f(0.0));
  // Lamplight from the shore and the ships' lanterns, by night only.
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
  surface.emission = linear(vec3f(1.0, 0.68, 0.35)) * warm * night * (1.0 - foam * 0.5);
  let lit = finish(shade(surface, n, shadow));

  // Far water melts into the page.
  let far = smoothstep(9.5, 16.0, length(p.xz));
  return vec4f(mix(lit, scene.haze, far), 1.0);
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

/** Resolves the scene onto the page with a soft vignette. */
export const presentWgsl = /* wgsl */ `
struct Present {
  resolution: vec2f,
  vignette: f32,
}

@group(0) @binding(0) var<uniform> present: Present;
@group(0) @binding(1) var sceneColor: texture_2d<f32>;
@group(0) @binding(2) var linearSampler: sampler;

@fragment
fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let uv = position.xy / present.resolution;
  let color = textureSampleLevel(sceneColor, linearSampler, uv, 0.0).rgb;
  let centred = (uv - 0.5) * vec2f(present.resolution.x / present.resolution.y, 1.0);
  let vignette = 1.0 - present.vignette * smoothstep(0.4, 1.2, length(centred));
  return vec4f(color * vignette, 1.0);
}
`
