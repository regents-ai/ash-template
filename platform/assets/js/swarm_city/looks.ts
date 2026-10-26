/**
 * The swarm city's looks. Each one paints the same city, streets and agents in
 * its own colours and its own way, as the WGSL functions shaders.ts asks for.
 * The page names the look in its address (`?look=`), and the first one is the
 * city's own.
 */

export type LookId = "neon" | "blueprint" | "porcelain" | "lamplight" | "sunset" | "hologram"

export type Look = {
  readonly id: LookId
  /** See-through buildings that glow where they overlap, instead of hiding what stands behind them. */
  readonly glass: boolean
  /** Whether the grid hangs over the downtowns, and whether the beacons are lit. */
  readonly sky: boolean
  readonly beacons: boolean
  readonly wgsl: string
}

/** Thin coloured outlines on the dark, a blue street plan, a red sky grid, and yellow agents. */
const neon: Look = {
  id: "neon",
  glass: false,
  sky: true,
  beacons: true,
  wgsl: /* wgsl */ `
const NIGHT: vec3f = vec3f(0.006, 0.007, 0.014);
const HAZE: vec3f = NIGHT;
const PLATE: vec3f = vec3f(0.012, 0.015, 0.026);
// The castle green, the forge cyan, the inn lime, and the low city between them lavender.
const CASTLE: vec3f = vec3f(0.26, 0.95, 0.52);
const FORGE: vec3f = vec3f(0.22, 0.82, 1.0);
const INN: vec3f = vec3f(0.78, 1.0, 0.3);
const BETWEEN: vec3f = vec3f(0.44, 0.46, 0.92);
const STREET: vec3f = vec3f(0.17, 0.32, 1.0);
const SIGNAL: vec3f = vec3f(1.0, 0.9, 0.04);
const SKY_RED: vec3f = vec3f(1.0, 0.13, 0.13);
const BEACON_SIZE: f32 = 1.4;

fn quarterColour(quarter: u32) -> vec3f {
  switch quarter {
    case 0u: { return CASTLE; }
    case 1u: { return FORGE; }
    case 2u: { return INN; }
    default: { return BETWEEN * 0.7; }
  }
}

fn sky(direction: vec3f) -> vec3f {
  return NIGHT;
}

// A faint wash of colour over a district that is lit.
fn groundColour(p: vec2f, onPlate: f32) -> vec3f {
  let light = districtLight(p);
  let colour = PLATE + (CASTLE * light.x + FORGE * light.y + INN * light.z) * 0.06;
  return mix(NIGHT, colour, onPlate);
}

fn faceColour(face: Face) -> vec4f {
  return vec4f(PLATE, 1.0);
}

// Each building keeps a brightness of its own, so the city is never one flat colour.
fn edgeColour(edge: Edge) -> vec3f {
  let tint = quarterColour(edge.quarter) * (0.55 + 0.45 * edge.shade);
  return mix(tint, vec3f(0.9, 1.0, 0.95), edge.lit * 0.2) * (1.0 + edge.lit * 0.6);
}

fn streetColour(kind: u32, p: vec3f) -> vec4f {
  let strength = array<f32, 3>(0.6, 0.95, 1.0);
  return vec4f(STREET * strength[kind], 1.0);
}

fn skyColour(down: f32, kind: u32) -> vec3f {
  return SKY_RED * select(0.85, 0.7 - 0.45 * down, kind == 1u);
}

fn beaconColour(glow: f32) -> vec3f {
  return SIGNAL * glow;
}

// The swarm is yellow; an agent's own disc is its colour, ringed in yellow.
fn discColour(agent: vec3f, lead: f32, ring: f32) -> vec3f {
  return mix(agent, SIGNAL, select(1.0, ring, lead > 0.5));
}

fn trailColour(glow: f32) -> vec4f {
  return vec4f(SIGNAL, glow);
}
`,
}

/** A drafting sheet: white linework on blueprint blue, hatched shadow sides, a fine grid, and agents in red pencil orange. */
const blueprint: Look = {
  id: "blueprint",
  glass: false,
  sky: true,
  beacons: true,
  wgsl: /* wgsl */ `
const SHEET: vec3f = vec3f(0.04, 0.17, 0.43);
const SHEET_EDGE: vec3f = vec3f(0.025, 0.1, 0.29);
const HAZE: vec3f = SHEET_EDGE;
const INK: vec3f = vec3f(0.88, 0.94, 1.0);
const PENCIL: vec3f = vec3f(1.0, 0.45, 0.12);
const BEACON_SIZE: f32 = 1.2;

fn quarterColour(quarter: u32) -> vec3f {
  switch quarter {
    case 0u: { return INK; }
    case 1u: { return vec3f(0.66, 0.9, 1.0); }
    case 2u: { return vec3f(1.0, 0.95, 0.74); }
    default: { return INK * 0.45; }
  }
}

fn sky(direction: vec3f) -> vec3f {
  return mix(SHEET_EDGE, SHEET_EDGE * 0.55, smoothstep(0.0, 0.6, direction.y));
}

// A fine grid on the sheet and a heavier one every five squares, running on past the plate.
fn groundColour(p: vec2f, onPlate: f32) -> vec3f {
  let light = districtLight(p);
  let fine = gridLine(p, 0.5, 1.0) * onPlate;
  let major = gridLine(p, 2.5, 1.2);
  return mix(SHEET_EDGE, SHEET, onPlate) + INK * (fine * 0.05 + major * 0.09 + (light.x + light.y + light.z) * 0.06);
}

// Sides turned from the light are hatched, the way a drawing shades them; the hatching
// thins out where its lines would crowd together.
fn faceColour(face: Face) -> vec4f {
  let shadow = clamp(step(0.5, face.normal.x) + step(0.5, face.normal.z), 0.0, 1.0);
  let t = (face.along + face.world.y) * 7.0;
  let width = max(fwidth(t), 1e-4);
  let hatch = 1.0 - min(abs(fract(t + 0.5) - 0.5) / width, 1.0);
  let detail = 1.0 - smoothstep(0.3, 0.6, width);
  return vec4f(SHEET * 0.94 + INK * 0.16 * hatch * shadow * detail, 1.0);
}

fn edgeColour(edge: Edge) -> vec3f {
  let ink = quarterColour(edge.quarter) * (0.62 + 0.38 * edge.shade);
  return mix(ink, PENCIL, edge.lit * 0.55);
}

// Streets are dashed centre lines; avenues and the plate's rim are drawn solid.
fn streetColour(kind: u32, p: vec3f) -> vec4f {
  let dash = step(0.45, fract((p.x + p.z) * 3.0));
  let strength = array<f32, 3>(0.42, 0.75, 1.0);
  return vec4f(INK * strength[kind], select(1.0, dash, kind == 0u));
}

fn skyColour(down: f32, kind: u32) -> vec3f {
  return INK * select(0.26, 0.3 - 0.22 * down, kind == 1u);
}

fn beaconColour(glow: f32) -> vec3f {
  return PENCIL * glow;
}

fn discColour(agent: vec3f, lead: f32, ring: f32) -> vec3f {
  return mix(agent, PENCIL, select(1.0, ring, lead > 0.5));
}

fn trailColour(glow: f32) -> vec4f {
  return vec4f(PENCIL, glow);
}
`,
}

/** An architect's model in daylight: pastel towers lit by a low sun, fine ink outlines, and ink-dark agents. */
const porcelain: Look = {
  id: "porcelain",
  glass: false,
  sky: false,
  beacons: false,
  wgsl: /* wgsl */ `
const PAPER: vec3f = vec3f(0.935, 0.915, 0.875);
const LAND: vec3f = vec3f(0.86, 0.845, 0.81);
const HAZE: vec3f = vec3f(0.9, 0.89, 0.87);
const INK: vec3f = vec3f(0.14, 0.13, 0.16);
const CLAY: vec3f = vec3f(0.82, 0.42, 0.3);
const SUN: vec3f = vec3f(-0.47, 0.8, 0.37);

fn quarterColour(quarter: u32) -> vec3f {
  switch quarter {
    case 0u: { return vec3f(0.78, 0.87, 0.8); }
    case 1u: { return vec3f(0.78, 0.86, 0.95); }
    case 2u: { return vec3f(0.98, 0.91, 0.74); }
    default: { return vec3f(0.96, 0.95, 0.93); }
  }
}

fn sky(direction: vec3f) -> vec3f {
  return mix(HAZE, vec3f(0.8, 0.85, 0.9), smoothstep(0.02, 0.8, direction.y));
}

// A lit district's ground takes on its colour.
fn groundColour(p: vec2f, onPlate: f32) -> vec3f {
  let light = districtLight(p);
  var colour = mix(LAND, PAPER, onPlate);
  for (var i = 0u; i < 3u; i++) {
    colour = mix(colour, quarterColour(i) * 0.92, light[i] * 0.7);
  }
  return colour;
}

// Lit by the sun and the sky, darker near the ground where the buildings crowd in, with a
// faint line at every floor.
fn faceColour(face: Face) -> vec4f {
  let base = quarterColour(face.quarter) * (0.93 + 0.07 * face.shade);
  let sun = 0.62 + 0.38 * max(dot(face.normal, normalize(SUN)), 0.0);
  let crowd = mix(0.74, 1.0, smoothstep(0.0, 1.3, face.world.y));
  let floors = face.world.y / 0.22;
  let line = (1.0 - min(abs(fract(floors + 0.5) - 0.5) / max(fwidth(floors), 1e-4), 1.0)) * (1.0 - face.normal.y);
  let detail = 1.0 - smoothstep(0.25, 0.5, fwidth(floors));
  let glow = 1.0 + 0.07 * face.lit;
  return vec4f(base * sun * crowd * glow * (1.0 - 0.07 * line * detail), 1.0);
}

fn edgeColour(edge: Edge) -> vec3f {
  let ink = mix(quarterColour(edge.quarter) * 0.55, INK, 0.5);
  return mix(ink, CLAY, edge.lit * 0.7);
}

fn streetColour(kind: u32, p: vec3f) -> vec4f {
  let colours = array<vec3f, 3>(mix(PAPER, CLAY, 0.4), CLAY, INK);
  return vec4f(colours[kind], 1.0);
}

// An agent is drawn in ink, and its own disc is its colour ringed in ink.
fn discColour(agent: vec3f, lead: f32, ring: f32) -> vec3f {
  return mix(agent, INK, select(1.0, ring, lead > 0.5));
}

fn trailColour(glow: f32) -> vec4f {
  return vec4f(INK, glow * 0.75);
}
`,
}

/** The city after dark: black towers with windows lit at random, amber street lamps, and teal agents. */
const lamplight: Look = {
  id: "lamplight",
  glass: false,
  sky: false,
  beacons: true,
  wgsl: /* wgsl */ `
const DARK: vec3f = vec3f(0.006, 0.008, 0.016);
const HAZE: vec3f = vec3f(0.07, 0.05, 0.055);
const ASPHALT: vec3f = vec3f(0.018, 0.017, 0.022);
const WALL: vec3f = vec3f(0.02, 0.02, 0.03);
const LAMP: vec3f = vec3f(1.0, 0.6, 0.2);
const WARM: vec3f = vec3f(1.0, 0.78, 0.46);
const COOL: vec3f = vec3f(0.66, 0.82, 1.0);
const TEAL: vec3f = vec3f(0.35, 1.0, 0.88);
const BEACON_SIZE: f32 = 1.5;

fn quarterColour(quarter: u32) -> vec3f {
  switch quarter {
    case 0u: { return vec3f(0.6, 0.78, 1.0); }
    case 1u: { return vec3f(1.0, 0.52, 0.26); }
    case 2u: { return vec3f(1.0, 0.84, 0.5); }
    default: { return WARM; }
  }
}

// The glow of the city low over the horizon, darkening overhead.
fn sky(direction: vec3f) -> vec3f {
  return mix(HAZE, DARK, smoothstep(0.0, 0.45, direction.y));
}

fn groundColour(p: vec2f, onPlate: f32) -> vec3f {
  let light = districtLight(p);
  return mix(DARK, ASPHALT, onPlate) + (quarterColour(0u) * light.x + quarterColour(1u) * light.y + quarterColour(2u) * light.z) * 0.035;
}

// Windows in bays across each side and floors up it, about a third of them lit, more in a
// lit district. Far away a window is smaller than a pixel, so the wall takes on the share of
// light its windows give instead.
fn faceColour(face: Face) -> vec4f {
  let side = 1.0 - face.normal.y;
  let cell = vec2f(face.along / 0.18, face.world.y / 0.22);
  let inside = fract(cell);
  let pane = step(0.22, inside.x) * step(inside.x, 0.78) * step(0.3, inside.y) * step(inside.y, 0.8);
  let size = fwidth(cell);
  let detail = 1.0 - smoothstep(0.35, 0.8, max(size.x, size.y));
  let id = floor(cell) + vec2f(face.shade * 517.0, dot(face.normal, vec3f(3.0, 0.0, 7.0)));
  let share = 0.35 + 0.35 * face.lit;
  let on = step(hash(id), share);
  let tint = mix(mix(WARM, COOL, step(0.82, hash(id + 9.1))), quarterColour(face.quarter), 0.3);
  let near = tint * pane * on * (0.7 + 0.5 * hash(id + 3.7));
  let far = mix(WARM, quarterColour(face.quarter), 0.3) * 0.9 * 0.28 * share * 1.6;
  let spill = LAMP * 0.07 * (1.0 - smoothstep(0.0, 0.5, face.world.y));
  return vec4f(WALL + side * (mix(far, near, detail) + spill), 1.0);
}

fn edgeColour(edge: Edge) -> vec3f {
  return quarterColour(edge.quarter) * (0.1 + 0.06 * edge.shade) * (1.0 + edge.lit * 2.5);
}

fn streetColour(kind: u32, p: vec3f) -> vec4f {
  let strength = array<f32, 3>(0.32, 0.8, 0.5);
  return vec4f(LAMP * strength[kind], 1.0);
}

// The beacons are street lamps, burning steadily.
fn beaconColour(glow: f32) -> vec3f {
  return LAMP * (0.85 + 0.15 * glow);
}

fn discColour(agent: vec3f, lead: f32, ring: f32) -> vec3f {
  return mix(agent, TEAL, select(1.0, ring, lead > 0.5));
}

fn trailColour(glow: f32) -> vec4f {
  return vec4f(TEAL, glow * 0.9);
}
`,
}

/** A neon dusk: violet towers edged in pink and cyan, a striped sun, a glowing grid floor, and gold agents. */
const sunset: Look = {
  id: "sunset",
  glass: false,
  sky: false,
  beacons: true,
  wgsl: /* wgsl */ `
const TOP: vec3f = vec3f(0.04, 0.01, 0.1);
const DUSK: vec3f = vec3f(0.36, 0.04, 0.34);
const HORIZON: vec3f = vec3f(1.0, 0.38, 0.3);
const HAZE: vec3f = vec3f(0.42, 0.07, 0.3);
const FLOOR: vec3f = vec3f(0.03, 0.005, 0.06);
const GRID: vec3f = vec3f(1.0, 0.16, 0.66);
const CYAN: vec3f = vec3f(0.12, 0.88, 1.0);
const GOLD: vec3f = vec3f(1.0, 0.74, 0.18);
const SUN_AT: vec3f = vec3f(0.0, 0.1, -0.995);
const BEACON_SIZE: f32 = 1.3;

fn quarterColour(quarter: u32) -> vec3f {
  switch quarter {
    case 0u: { return vec3f(1.0, 0.22, 0.74); }
    case 1u: { return CYAN; }
    case 2u: { return GOLD; }
    default: { return vec3f(0.56, 0.3, 1.0) * 0.6; }
  }
}

// Dusk over the horizon, and the sun sinking into it, cut by bands across its lower half.
fn sky(direction: vec3f) -> vec3f {
  let h = max(direction.y, 0.0);
  var colour = mix(mix(HORIZON, DUSK, smoothstep(0.0, 0.18, h)), TOP, smoothstep(0.18, 0.6, h));
  let towards = dot(direction, normalize(SUN_AT));
  let up = direction.y - SUN_AT.y;
  let cut = select(1.0, step(0.38, fract(up * 70.0)), up < 0.0);
  let sun = mix(vec3f(1.0, 0.24, 0.55), vec3f(1.0, 0.86, 0.32), smoothstep(-0.12, 0.12, up));
  colour = mix(colour, sun, smoothstep(0.9925, 0.9935, towards) * cut);
  return colour + HORIZON * 0.3 * pow(max(towards, 0.0), 40.0);
}

// A pink grid running out to the horizon, finer on the plate.
fn groundColour(p: vec2f, onPlate: f32) -> vec3f {
  let light = districtLight(p);
  let lines = max(gridLine(p, 1.0, 1.3), gridLine(p, 0.5, 0.8) * onPlate * 0.4);
  return FLOOR + GRID * lines * 0.55 + (quarterColour(0u) * light.x + quarterColour(1u) * light.y + quarterColour(2u) * light.z) * 0.07;
}

fn faceColour(face: Face) -> vec4f {
  let rise = clamp(face.world.y / 9.0, 0.0, 1.0);
  let wall = mix(vec3f(0.02, 0.0, 0.035), vec3f(0.17, 0.03, 0.23), rise);
  let roof = quarterColour(face.quarter) * 0.12 + vec3f(0.05, 0.0, 0.07);
  return vec4f(mix(wall, roof, face.normal.y) * (1.0 + face.lit * 0.6), 1.0);
}

// Each edge brightens toward the roof, from cyan at the foot to the quarter's colour on top.
fn edgeColour(edge: Edge) -> vec3f {
  let up = smoothstep(edge.base, edge.top, edge.world.y);
  let colour = mix(CYAN * 0.5, quarterColour(edge.quarter), up);
  return colour * (0.4 + 0.45 * edge.shade + 0.6 * up) * (1.0 + edge.lit * 0.7);
}

fn streetColour(kind: u32, p: vec3f) -> vec4f {
  let strength = array<f32, 3>(0.55, 1.0, 1.0);
  return vec4f(CYAN * strength[kind], 1.0);
}

fn beaconColour(glow: f32) -> vec3f {
  return GRID * glow;
}

fn discColour(agent: vec3f, lead: f32, ring: f32) -> vec3f {
  return mix(agent, GOLD, select(1.0, ring, lead > 0.5));
}

fn trailColour(glow: f32) -> vec4f {
  return vec4f(mix(GRID, GOLD, glow), glow);
}
`,
}

/** A city of light: see-through glass towers with rainbow edges and rising scan lines, a dot floor, and white agents. */
const hologram: Look = {
  id: "hologram",
  glass: true,
  sky: true,
  beacons: true,
  wgsl: /* wgsl */ `
const VOID: vec3f = vec3f(0.0, 0.012, 0.022);
const HAZE: vec3f = VOID;
const WHITE: vec3f = vec3f(0.88, 1.0, 1.0);
const BEACON_SIZE: f32 = 1.2;

fn quarterColour(quarter: u32) -> vec3f {
  switch quarter {
    case 0u: { return vec3f(0.3, 1.0, 0.84); }
    case 1u: { return vec3f(0.36, 0.64, 1.0); }
    case 2u: { return vec3f(0.86, 0.5, 1.0); }
    default: { return vec3f(0.26, 0.55, 0.76) * 0.55; }
  }
}

fn rainbow(t: f32) -> vec3f {
  return 0.5 + 0.5 * cos(6.2832 * (t + vec3f(0.0, 0.33, 0.67)));
}

fn sky(direction: vec3f) -> vec3f {
  return VOID + vec3f(0.0, 0.03, 0.05) * (1.0 - smoothstep(0.0, 0.6, direction.y));
}

// A floor of dots, one at every corner of the grid.
fn groundColour(p: vec2f, onPlate: f32) -> vec3f {
  let light = districtLight(p);
  let cell = p / 0.5;
  let gap = length(fract(cell + 0.5) - 0.5) / max(length(fwidth(cell)), 1e-4);
  let spot = 1.0 - min(gap / 1.6, 1.0);
  let base = VOID + vec3f(0.0, 0.025, 0.04) * onPlate;
  return base + vec3f(0.3, 0.9, 1.0) * spot * mix(0.08, 0.28, onPlate)
    + (quarterColour(0u) * light.x + quarterColour(1u) * light.y + quarterColour(2u) * light.z) * 0.08;
}

// Faint glass, brighter where it is seen edge-on, with scan lines rising up each tower.
fn faceColour(face: Face) -> vec4f {
  let view = normalize(city.eye - face.world);
  let rim = pow(1.0 - abs(dot(view, face.normal)), 2.0);
  let scan = smoothstep(0.9, 1.0, fract(face.world.y * 2.5 - city.time * 0.35));
  let colour = quarterColour(face.quarter) * (0.01 + 0.03 * rim + 0.07 * scan) * (1.0 + face.lit * 0.25);
  return vec4f(colour, 1.0);
}

fn edgeColour(edge: Edge) -> vec3f {
  let shimmer = rainbow(edge.world.y * 0.08 + edge.shade * 0.3 + city.time * 0.05);
  return mix(quarterColour(edge.quarter), shimmer, 0.5) * 0.2 * (1.0 + edge.lit * 0.2);
}

fn streetColour(kind: u32, p: vec3f) -> vec4f {
  let strength = array<f32, 3>(0.25, 0.5, 0.7);
  return vec4f(vec3f(0.3, 0.9, 1.0) * strength[kind], 1.0);
}

fn skyColour(down: f32, kind: u32) -> vec3f {
  return vec3f(0.62, 0.36, 1.0) * select(0.45, 0.4 - 0.32 * down, kind == 1u);
}

fn beaconColour(glow: f32) -> vec3f {
  return WHITE * glow;
}

fn discColour(agent: vec3f, lead: f32, ring: f32) -> vec3f {
  return mix(agent, WHITE, select(1.0, ring, lead > 0.5));
}

fn trailColour(glow: f32) -> vec4f {
  return vec4f(mix(vec3f(0.3, 0.9, 1.0), WHITE, glow), glow);
}
`,
}

export const LOOKS: Readonly<Record<LookId, Look>> = {neon, blueprint, porcelain, lamplight, sunset, hologram}
