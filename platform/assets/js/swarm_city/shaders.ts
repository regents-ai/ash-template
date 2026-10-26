/**
 * The swarm city's WGSL. Each shader is prepared on its own, so the part every
 * scene shader shares is written once here and placed at the head of each.
 *
 * The city is drawn as thin lines on the dark: each building is a dark box
 * outlined in its quarter's colour, streets are blue, the sky grid is red, and
 * the agents are flat yellow discs trailing thin yellow tails.
 */
import {CITY_REACH, DISTRICTS} from "./city"

const f = (value: number) => value.toFixed(3)

/** The lens, top to bottom, in degrees. */
export const FOV = 38

const shared = /* wgsl */ `
struct City {
  viewProjection: mat4x4f,
  // Where the camera is, and the time the city is drawn at.
  eye: vec3f,
  time: f32,
  // The camera's right and up, for things that always face it.
  right: vec3f,
  // Device pixels in one CSS pixel, so marks keep their size on the page.
  pixel: f32,
  up: vec3f,
  // How lit each district is: castle, forge, inn, from 0 to 1.
  lit: vec4f,
  resolution: vec2f,
}

@group(0) @binding(0) var<uniform> city: City;

// How far the lens reaches: 1 / tan(half the field of view).
const FOCAL: f32 = ${f(1 / Math.tan((FOV * Math.PI) / 360))};

// The dark the city stands in, and the plate it is built on.
const NIGHT: vec3f = vec3f(0.006, 0.007, 0.014);
const PLATE: vec3f = vec3f(0.012, 0.015, 0.026);
// Each quarter's line colour: the castle green, the forge cyan, the inn lime, and the low city between them lavender.
const CASTLE: vec3f = vec3f(0.26, 0.95, 0.52);
const FORGE: vec3f = vec3f(0.22, 0.82, 1.0);
const INN: vec3f = vec3f(0.78, 1.0, 0.3);
const BETWEEN: vec3f = vec3f(0.44, 0.46, 0.92);
const STREET: vec3f = vec3f(0.17, 0.32, 1.0);
const SIGNAL: vec3f = vec3f(1.0, 0.9, 0.04);
const SKY_RED: vec3f = vec3f(1.0, 0.13, 0.13);

fn quarterColour(quarter: u32) -> vec3f {
  switch quarter {
    case 0u: { return CASTLE; }
    case 1u: { return FORGE; }
    case 2u: { return INN; }
    default: { return BETWEEN * 0.7; }
  }
}

fn quarterLit(quarter: u32) -> f32 {
  switch quarter {
    case 0u: { return city.lit.x; }
    case 1u: { return city.lit.y; }
    case 2u: { return city.lit.z; }
    default: { return 0.0; }
  }
}

// Far things sink into the dark, so the city has depth.
fn distanceFade(p: vec3f) -> f32 {
  return 1.0 - smoothstep(30.0, 60.0, length(p - city.eye));
}

// A quad of six corners round a point, for things drawn as flat cards: x and y from -1 to 1.
fn corner(index: u32) -> vec2f {
  let corners = array<vec2f, 6>(
    vec2f(-1.0, -1.0), vec2f(1.0, -1.0), vec2f(1.0, 1.0),
    vec2f(-1.0, -1.0), vec2f(1.0, 1.0), vec2f(-1.0, 1.0),
  );
  return corners[index];
}
`

/** A building's record, as each of its two draws reads it. */
const buildingInput = /* wgsl */ `
struct Building {
  // Middle x and z, then width and depth.
  @location(0) footprint: vec4f,
  // Base and roof.
  @location(1) span: vec2f,
  @location(2) quarter: f32,
  @location(3) shade: f32,
}

// A corner of the building's box, from a corner of the unit box: x, y and z from 0 to 1, pulled in by 'inset'.
fn boxPoint(building: Building, unit: vec3f, inset: f32) -> vec3f {
  let half = building.footprint.zw * 0.5 - vec2f(inset);
  let low = building.footprint.xy - half;
  let ground = low + unit.xz * half * 2.0;
  return vec3f(ground.x, mix(building.span.x, building.span.y - inset, unit.y), ground.y);
}
`

/**
 * The buildings' sides and roofs: dark, and pulled in a hair from the
 * outline, so each building hides what stands behind it but never its own edges.
 */
export const towerFaceWgsl = /* wgsl */ `${shared}
${buildingInput}

// Five faces of the unit box, two triangles each: four sides and the roof.
const FACES = array<vec3f, 30>(
  vec3f(0.0, 0.0, 0.0), vec3f(1.0, 0.0, 0.0), vec3f(1.0, 1.0, 0.0), vec3f(0.0, 0.0, 0.0), vec3f(1.0, 1.0, 0.0), vec3f(0.0, 1.0, 0.0),
  vec3f(1.0, 0.0, 0.0), vec3f(1.0, 0.0, 1.0), vec3f(1.0, 1.0, 1.0), vec3f(1.0, 0.0, 0.0), vec3f(1.0, 1.0, 1.0), vec3f(1.0, 1.0, 0.0),
  vec3f(1.0, 0.0, 1.0), vec3f(0.0, 0.0, 1.0), vec3f(0.0, 1.0, 1.0), vec3f(1.0, 0.0, 1.0), vec3f(0.0, 1.0, 1.0), vec3f(1.0, 1.0, 1.0),
  vec3f(0.0, 0.0, 1.0), vec3f(0.0, 0.0, 0.0), vec3f(0.0, 1.0, 0.0), vec3f(0.0, 0.0, 1.0), vec3f(0.0, 1.0, 0.0), vec3f(0.0, 1.0, 1.0),
  vec3f(0.0, 1.0, 0.0), vec3f(1.0, 1.0, 0.0), vec3f(1.0, 1.0, 1.0), vec3f(0.0, 1.0, 0.0), vec3f(1.0, 1.0, 1.0), vec3f(0.0, 1.0, 1.0),
);

struct FaceVarying {
  @builtin(position) clip: vec4f,
  @location(0) world: vec3f,
}

@vertex
fn vs_main(@builtin(vertex_index) vertex: u32, building: Building) -> FaceVarying {
  var output: FaceVarying;
  output.world = boxPoint(building, FACES[vertex], 0.004);
  output.clip = city.viewProjection * vec4f(output.world, 1.0);
  return output;
}

@fragment
fn fs_main(input: FaceVarying) -> @location(0) vec4f {
  return vec4f(mix(NIGHT, PLATE, distanceFade(input.world)), 1.0);
}
`

/** The buildings' outlines: the twelve edges of each box, a hair-thin line in its quarter's colour. */
export const towerEdgeWgsl = /* wgsl */ `${shared}
${buildingInput}

// The twelve edges of the unit box, two ends each.
const EDGES = array<vec3f, 24>(
  vec3f(0.0, 0.0, 0.0), vec3f(1.0, 0.0, 0.0), vec3f(1.0, 0.0, 0.0), vec3f(1.0, 0.0, 1.0),
  vec3f(1.0, 0.0, 1.0), vec3f(0.0, 0.0, 1.0), vec3f(0.0, 0.0, 1.0), vec3f(0.0, 0.0, 0.0),
  vec3f(0.0, 1.0, 0.0), vec3f(1.0, 1.0, 0.0), vec3f(1.0, 1.0, 0.0), vec3f(1.0, 1.0, 1.0),
  vec3f(1.0, 1.0, 1.0), vec3f(0.0, 1.0, 1.0), vec3f(0.0, 1.0, 1.0), vec3f(0.0, 1.0, 0.0),
  vec3f(0.0, 0.0, 0.0), vec3f(0.0, 1.0, 0.0), vec3f(1.0, 0.0, 0.0), vec3f(1.0, 1.0, 0.0),
  vec3f(1.0, 0.0, 1.0), vec3f(1.0, 1.0, 1.0), vec3f(0.0, 0.0, 1.0), vec3f(0.0, 1.0, 1.0),
);

struct EdgeVarying {
  @builtin(position) clip: vec4f,
  @location(0) colour: vec3f,
}

@vertex
fn vs_main(@builtin(vertex_index) vertex: u32, building: Building) -> EdgeVarying {
  var output: EdgeVarying;
  let world = boxPoint(building, EDGES[vertex], 0.0);
  let quarter = u32(building.quarter + 0.5);
  let lit = quarterLit(quarter);
  // Each building keeps a brightness of its own, so the city is never one flat colour.
  let tint = quarterColour(quarter) * (0.55 + 0.45 * building.shade);
  output.colour = mix(tint, vec3f(0.9, 1.0, 0.95), lit * 0.2) * (1.0 + lit * 0.6) * distanceFade(world);
  output.clip = city.viewProjection * vec4f(world, 1.0);
  return output;
}

@fragment
fn fs_main(input: EdgeVarying) -> @location(0) vec4f {
  return vec4f(input.colour, 1.0);
}
`

/** The plate the city stands on: dark, with a faint wash of colour over a district that is lit. */
export const groundWgsl = /* wgsl */ `${shared}
struct GroundVarying {
  @builtin(position) clip: vec4f,
  @location(0) world: vec3f,
}

const DISTRICT_AT = array<vec3f, 3>(
  vec3f(${f(DISTRICTS.castle.x)}, ${f(DISTRICTS.castle.z)}, ${f(DISTRICTS.castle.radius)}),
  vec3f(${f(DISTRICTS.forge.x)}, ${f(DISTRICTS.forge.z)}, ${f(DISTRICTS.forge.radius)}),
  vec3f(${f(DISTRICTS.inn.x)}, ${f(DISTRICTS.inn.z)}, ${f(DISTRICTS.inn.radius)}),
);
const REACH: f32 = ${f(CITY_REACH + 0.06)};

@vertex
fn vs_main(@location(0) position: vec3f) -> GroundVarying {
  var output: GroundVarying;
  output.world = position;
  output.clip = city.viewProjection * vec4f(position, 1.0);
  return output;
}

@fragment
fn fs_main(input: GroundVarying) -> @location(0) vec4f {
  let p = input.world.xz;
  var colour = PLATE;
  for (var i = 0u; i < 3u; i++) {
    let reach = length(p - DISTRICT_AT[i].xy) / DISTRICT_AT[i].z;
    colour += quarterColour(i) * 0.06 * city.lit[i] * (1.0 - smoothstep(0.4, 1.1, reach));
  }
  let onPlate = step(max(abs(p.x), abs(p.y)), REACH);
  return vec4f(mix(NIGHT, colour, onPlate * distanceFade(input.world)), 1.0);
}
`

/** The streets: thin blue lines on the plate, brighter along the avenues and round the rim. */
export const streetWgsl = /* wgsl */ `${shared}
struct StreetVarying {
  @builtin(position) clip: vec4f,
  @location(0) colour: vec3f,
}

@vertex
fn vs_main(@location(0) position: vec3f, @location(1) kind: f32) -> StreetVarying {
  var output: StreetVarying;
  let strength = array<f32, 3>(0.6, 0.95, 1.0);
  output.colour = STREET * strength[u32(kind + 0.5)] * distanceFade(position);
  output.clip = city.viewProjection * vec4f(position, 1.0);
  return output;
}

@fragment
fn fs_main(input: StreetVarying) -> @location(0) vec4f {
  return vec4f(input.colour, 1.0);
}
`

/** The red sky grid and the lines it drops, fading as they fall. */
export const skyWgsl = /* wgsl */ `${shared}
struct SkyVarying {
  @builtin(position) clip: vec4f,
  @location(0) colour: vec3f,
}

@vertex
fn vs_main(@location(0) position: vec3f, @location(1) down: f32, @location(2) kind: f32) -> SkyVarying {
  var output: SkyVarying;
  let strength = select(0.85, 0.7 - 0.45 * down, kind > 0.5);
  output.colour = SKY_RED * strength * distanceFade(position);
  output.clip = city.viewProjection * vec4f(position, 1.0);
  return output;
}

@fragment
fn fs_main(input: SkyVarying) -> @location(0) vec4f {
  return vec4f(input.colour, 1.0);
}
`

/** The beacons: small yellow squares round the rim, at street corners and along the avenues. */
export const beaconWgsl = /* wgsl */ `${shared}
struct BeaconVarying {
  @builtin(position) clip: vec4f,
  @location(0) glow: f32,
}

@vertex
fn vs_main(@builtin(vertex_index) vertex: u32, @location(0) position: vec3f, @location(1) phase: f32) -> BeaconVarying {
  var output: BeaconVarying;
  let clip = city.viewProjection * vec4f(position, 1.0);
  let half = 1.4 * city.pixel / city.resolution * 2.0;
  output.clip = clip + vec4f(corner(vertex) * half * clip.w, 0.0, 0.0);
  output.glow = (0.8 + 0.2 * sin(city.time * 1.6 + phase)) * distanceFade(position);
  return output;
}

@fragment
fn fs_main(input: BeaconVarying) -> @location(0) vec4f {
  return vec4f(SIGNAL * input.glow, 1.0);
}
`

/**
 * The agents and their swarms: flat yellow discs that always face the camera.
 * An agent's own disc is larger and ringed in its own colour.
 */
export const nodeWgsl = /* wgsl */ `${shared}
struct NodeVarying {
  @builtin(position) clip: vec4f,
  @location(0) at: vec2f,
  @location(1) colour: vec3f,
  @location(2) glow: f32,
  // 1 for an agent's own disc, 0 for one of its swarm.
  @location(3) lead: f32,
  // The disc's radius on the page, in device pixels.
  @location(4) radius: f32,
}

@vertex
fn vs_main(
  @builtin(vertex_index) vertex: u32,
  @location(0) position: vec3f,
  @location(1) size: f32,
  @location(2) colour: vec3f,
  @location(3) glow: f32,
) -> NodeVarying {
  var output: NodeVarying;
  let at = corner(vertex);
  // Never smaller than a share of the picture's height, so a far agent still reads as a disc
  // and keeps the same size beside the city on a phone as on a wide screen.
  let centre = city.viewProjection * vec4f(position, 1.0);
  let perPixel = centre.w * 2.0 / (city.resolution.y * FOCAL);
  let lead = select(0.0, 1.0, size > 0.15);
  let least = mix(0.006, 0.016, lead) * city.resolution.y * perPixel;
  let radius = max(size, least);
  let world = position + (city.right * at.x + city.up * at.y) * radius;
  output.clip = city.viewProjection * vec4f(world, 1.0);
  output.at = at;
  output.colour = colour;
  output.glow = glow * distanceFade(position);
  output.lead = lead;
  output.radius = radius / perPixel;
  return output;
}

@fragment
fn fs_main(input: NodeVarying) -> @location(0) vec4f {
  let d = length(input.at) * input.radius;
  let edge = 1.0 - smoothstep(input.radius - 1.0, input.radius, d);
  let ring = (1.0 - smoothstep(input.radius - 2.6 * city.pixel, input.radius - 1.6 * city.pixel, d)) * input.lead;
  let colour = mix(input.colour, SIGNAL, select(1.0, ring, input.lead > 0.5));
  return vec4f(colour, edge * input.glow);
}
`

/** The tails: hair-thin yellow lines that always face the camera, fading toward their ends. */
export const trailWgsl = /* wgsl */ `${shared}
struct TrailVarying {
  @builtin(position) clip: vec4f,
  @location(0) side: f32,
  @location(1) glow: f32,
}

@vertex
fn vs_main(
  @builtin(vertex_index) vertex: u32,
  @location(0) from_: vec3f,
  @location(1) to: vec3f,
  @location(2) glows: vec2f,
) -> TrailVarying {
  var output: TrailVarying;
  let at = corner(vertex);
  let ends = array<vec4f, 2>(city.viewProjection * vec4f(from_, 1.0), city.viewProjection * vec4f(to, 1.0));
  let end = select(0u, 1u, at.x > 0.0);
  let screen0 = ends[0].xy / ends[0].w * city.resolution;
  let screen1 = ends[1].xy / ends[1].w * city.resolution;
  var direction = screen1 - screen0;
  direction = select(vec2f(1.0, 0.0), normalize(direction), length(direction) > 1e-4);
  let across = vec2f(-direction.y, direction.x);
  let glow = select(glows.x, glows.y, at.x > 0.0);
  let width = (1.1 + 0.9 * glow) * city.pixel;
  let clip = ends[end];
  output.clip = clip + vec4f(across * at.y * width / city.resolution * clip.w, 0.0, 0.0);
  output.side = at.y;
  output.glow = glow * distanceFade(select(from_, to, at.x > 0.0));
  return output;
}

@fragment
fn fs_main(input: TrailVarying) -> @location(0) vec4f {
  let soft = 1.0 - input.side * input.side;
  return vec4f(SIGNAL, soft * input.glow);
}
`
