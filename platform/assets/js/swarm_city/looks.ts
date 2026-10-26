/**
 * The swarm city's looks. Each one paints the same city, streets and agents in
 * its own colours and its own way, as the WGSL functions shaders.ts asks for.
 * The page names the look in its address (`?look=`), and the first one is the
 * city's own. A few looks paint the city one way while the page is light and
 * another while it is dark.
 */

export type LookId =
  | "neon"
  | "blueprint"
  | "porcelain"
  | "lamplight"
  | "sunset"
  | "hologram"
  | "afterglow"
  | "showroom"
  | "glasshouse"
  | "opal"
  | "obsidian"
  | "regent"
  | "tangerine"
  | "powder"
  | "smoke"
  | "cobalt"

export type Look = {
  readonly id: LookId
  /**
   * See-through buildings instead of ones that hide what stands behind them: glass that
   * glows brighter where it overlaps, for a dark look, or glass that tints deeper, for a
   * light one, where a colour of white leaves what is behind it as it is.
   */
  readonly glass: "glow" | "tint" | null
  /** Whether the grid hangs over the downtowns, and whether the beacons are lit. */
  readonly sky: boolean
  readonly beacons: boolean
  readonly wgsl: string
}

/** Thin coloured outlines on the dark, a blue street plan, a red sky grid, and yellow agents. */
const neon: Look = {
  id: "neon",
  glass: null,
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
  glass: null,
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
  glass: null,
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
  glass: null,
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
  glass: null,
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
  glass: "glow",
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

/** Neon's colours in hologram glass: green, cyan and lime glass towers with rising scan lines, the red sky grid, and yellow agents. */
const afterglow: Look = {
  id: "afterglow",
  glass: "glow",
  sky: true,
  beacons: true,
  wgsl: /* wgsl */ `
const NIGHT: vec3f = vec3f(0.006, 0.007, 0.014);
const HAZE: vec3f = NIGHT;
const PLATE: vec3f = vec3f(0.012, 0.015, 0.026);
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
    default: { return BETWEEN * 0.6; }
  }
}

fn sky(direction: vec3f) -> vec3f {
  return NIGHT + vec3f(0.0, 0.01, 0.03) * (1.0 - smoothstep(0.0, 0.5, direction.y));
}

// A floor of lavender dots, one at every corner of the grid.
fn groundColour(p: vec2f, onPlate: f32) -> vec3f {
  let light = districtLight(p);
  let cell = p / 0.5;
  let gap = length(fract(cell + 0.5) - 0.5) / max(length(fwidth(cell)), 1e-4);
  let spot = 1.0 - min(gap / 1.6, 1.0);
  return mix(NIGHT, PLATE, onPlate) + BETWEEN * spot * mix(0.05, 0.22, onPlate)
    + (CASTLE * light.x + FORGE * light.y + INN * light.z) * 0.06;
}

// Faint glass in the quarter's colour, brighter edge-on, with scan lines rising up each tower.
fn faceColour(face: Face) -> vec4f {
  let view = normalize(city.eye - face.world);
  let rim = pow(1.0 - abs(dot(view, face.normal)), 2.0);
  let scan = smoothstep(0.92, 1.0, fract(face.world.y * 2.0 - city.time * 0.3));
  return vec4f(quarterColour(face.quarter) * (0.008 + 0.03 * rim + 0.06 * scan) * (1.0 + face.lit * 0.3), 1.0);
}

fn edgeColour(edge: Edge) -> vec3f {
  return quarterColour(edge.quarter) * (0.55 + 0.45 * edge.shade) * 0.2 * (1.0 + edge.lit * 0.3);
}

fn streetColour(kind: u32, p: vec3f) -> vec4f {
  let strength = array<f32, 3>(0.5, 0.85, 1.0);
  return vec4f(STREET * strength[kind], 1.0);
}

fn skyColour(down: f32, kind: u32) -> vec3f {
  return SKY_RED * select(0.7, 0.6 - 0.4 * down, kind == 1u);
}

fn beaconColour(glow: f32) -> vec3f {
  return SIGNAL * glow;
}

fn discColour(agent: vec3f, lead: f32, ring: f32) -> vec3f {
  return mix(agent, SIGNAL, select(1.0, ring, lead > 0.5));
}

fn trailColour(glow: f32) -> vec4f {
  return vec4f(SIGNAL, glow);
}
`,
}

/** Porcelain models at night with neon outlines: pale solid towers caught by one light, edged in neon colours, under the red sky grid. */
const showroom: Look = {
  id: "showroom",
  glass: null,
  sky: true,
  beacons: true,
  wgsl: /* wgsl */ `
const NIGHT: vec3f = vec3f(0.006, 0.007, 0.014);
const HAZE: vec3f = vec3f(0.02, 0.022, 0.04);
const PLATE: vec3f = vec3f(0.014, 0.017, 0.03);
const CASTLE: vec3f = vec3f(0.26, 0.95, 0.52);
const FORGE: vec3f = vec3f(0.22, 0.82, 1.0);
const INN: vec3f = vec3f(0.78, 1.0, 0.3);
const BETWEEN: vec3f = vec3f(0.44, 0.46, 0.92);
const STREET: vec3f = vec3f(0.17, 0.32, 1.0);
const SIGNAL: vec3f = vec3f(1.0, 0.9, 0.04);
const SKY_RED: vec3f = vec3f(1.0, 0.13, 0.13);
const SUN: vec3f = vec3f(-0.47, 0.8, 0.37);
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
  return mix(HAZE, NIGHT, smoothstep(0.0, 0.5, direction.y));
}

fn groundColour(p: vec2f, onPlate: f32) -> vec3f {
  let light = districtLight(p);
  return mix(NIGHT, PLATE, onPlate) + (CASTLE * light.x + FORGE * light.y + INN * light.z) * 0.07;
}

// A pale model lit by one light from above, darker low down where the towers crowd in,
// with a hint of the quarter's colour.
fn faceColour(face: Face) -> vec4f {
  let tint = mix(vec3f(0.62, 0.64, 0.72), quarterColour(face.quarter), 0.3);
  let sun = 0.3 + 0.7 * max(dot(face.normal, normalize(SUN)), 0.0);
  let crowd = mix(0.4, 1.0, smoothstep(0.0, 1.3, face.world.y));
  return vec4f(tint * sun * crowd * (0.46 + 0.12 * face.shade) * (1.0 + face.lit * 0.35), 1.0);
}

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

fn discColour(agent: vec3f, lead: f32, ring: f32) -> vec3f {
  return mix(agent, SIGNAL, select(1.0, ring, lead > 0.5));
}

fn trailColour(glow: f32) -> vec4f {
  return vec4f(SIGNAL, glow);
}
`,
}

/** Porcelain's paper in hologram glass: towers of tinted film that deepen edge-on, rainbow ink outlines, and ink agents. */
const glasshouse: Look = {
  id: "glasshouse",
  glass: "tint",
  sky: false,
  beacons: false,
  wgsl: /* wgsl */ `
const PAPER: vec3f = vec3f(0.945, 0.93, 0.895);
const LAND: vec3f = vec3f(0.87, 0.855, 0.82);
const HAZE: vec3f = vec3f(0.91, 0.9, 0.88);
const INK: vec3f = vec3f(0.14, 0.13, 0.16);
const CLAY: vec3f = vec3f(0.82, 0.42, 0.3);

fn quarterColour(quarter: u32) -> vec3f {
  switch quarter {
    case 0u: { return vec3f(0.5, 0.82, 0.62); }
    case 1u: { return vec3f(0.5, 0.72, 0.97); }
    case 2u: { return vec3f(0.98, 0.8, 0.45); }
    default: { return vec3f(0.84, 0.84, 0.9); }
  }
}

fn sky(direction: vec3f) -> vec3f {
  return mix(HAZE, vec3f(0.82, 0.87, 0.92), smoothstep(0.02, 0.8, direction.y));
}

// Paper with a dot of ink at every corner of the grid; a lit district's ground takes on its colour.
fn groundColour(p: vec2f, onPlate: f32) -> vec3f {
  let light = districtLight(p);
  let cell = p / 0.5;
  let gap = length(fract(cell + 0.5) - 0.5) / max(length(fwidth(cell)), 1e-4);
  let spot = 1.0 - min(gap / 1.4, 1.0);
  var colour = mix(LAND, PAPER, onPlate) * (1.0 - 0.22 * spot * onPlate);
  for (var i = 0u; i < 3u; i++) {
    colour = mix(colour, quarterColour(i), light[i] * 0.4);
  }
  return colour;
}

// Tinted film, deeper where it is seen edge-on, with faint bands rising up each tower.
fn faceColour(face: Face) -> vec4f {
  let view = normalize(city.eye - face.world);
  let rim = pow(1.0 - abs(dot(view, face.normal)), 2.0);
  let scan = smoothstep(0.9, 1.0, fract(face.world.y * 2.5 - city.time * 0.35));
  let depth = clamp((0.05 + 0.16 * rim + 0.1 * scan) * (1.0 + face.lit * 0.5), 0.0, 1.0);
  return vec4f(mix(vec3f(1.0), quarterColour(face.quarter), depth), 1.0);
}

// Ink with a rainbow sheen along it.
fn edgeColour(edge: Edge) -> vec3f {
  let sheen = rainbow((edge.world.x + edge.world.z) * 0.06 + edge.world.y * 0.1 + city.time * 0.05);
  let ink = mix(quarterColour(edge.quarter) * 0.45, sheen * 0.7, 0.5);
  let strength = select(0.26, 0.28, edge.quarter == 3u);
  return mix(vec3f(1.0), ink, strength + 0.1 * edge.lit);
}

fn streetColour(kind: u32, p: vec3f) -> vec4f {
  let colours = array<vec3f, 3>(mix(PAPER, CLAY, 0.4), CLAY, INK);
  return vec4f(colours[kind], 1.0);
}

fn discColour(agent: vec3f, lead: f32, ring: f32) -> vec3f {
  return mix(agent, INK, select(1.0, ring, lead > 0.5));
}

// Tails shift through the rainbow toward the agent.
fn trailColour(glow: f32) -> vec4f {
  return vec4f(mix(INK, rainbow(glow * 0.8 + 0.1) * 0.75, glow), glow * 0.8);
}
`,
}

/** Mother of pearl: white porcelain towers with a rainbow sheen that shifts as the city turns, neon outlines downtown, and gold agents. */
const opal: Look = {
  id: "opal",
  glass: null,
  sky: true,
  beacons: false,
  wgsl: /* wgsl */ `
const PEARL: vec3f = vec3f(0.935, 0.935, 0.95);
const LAND: vec3f = vec3f(0.855, 0.86, 0.885);
const HAZE: vec3f = vec3f(0.9, 0.905, 0.93);
const INK: vec3f = vec3f(0.14, 0.13, 0.18);
const STREET: vec3f = vec3f(0.17, 0.32, 1.0);
const SKY_RED: vec3f = vec3f(0.95, 0.3, 0.32);
const GOLD: vec3f = vec3f(0.93, 0.62, 0.0);
const SUN: vec3f = vec3f(-0.47, 0.8, 0.37);

// Neon's colours, deepened so they read on white.
fn quarterColour(quarter: u32) -> vec3f {
  switch quarter {
    case 0u: { return vec3f(0.08, 0.62, 0.32); }
    case 1u: { return vec3f(0.0, 0.5, 0.8); }
    case 2u: { return vec3f(0.44, 0.62, 0.0); }
    default: { return vec3f(0.58, 0.58, 0.7); }
  }
}

fn sky(direction: vec3f) -> vec3f {
  return mix(HAZE, vec3f(0.84, 0.86, 0.94), smoothstep(0.02, 0.8, direction.y));
}

fn groundColour(p: vec2f, onPlate: f32) -> vec3f {
  let light = districtLight(p);
  var colour = mix(LAND, PEARL, onPlate);
  for (var i = 0u; i < 3u; i++) {
    colour = mix(colour, mix(PEARL, quarterColour(i), 0.35), light[i] * 0.6);
  }
  return colour;
}

// White porcelain lit by the sun, with a pearly sheen that runs through the rainbow as the
// angle it is seen at changes, and a faint line at every floor.
fn faceColour(face: Face) -> vec4f {
  let view = normalize(city.eye - face.world);
  let facing = abs(dot(view, face.normal));
  let sheen = rainbow(facing * 1.3 + face.world.y * 0.05 + face.shade * 0.25);
  let base = mix(vec3f(0.95, 0.945, 0.94), quarterColour(face.quarter), 0.1 + 0.12 * face.lit);
  let sun = 0.64 + 0.36 * max(dot(face.normal, normalize(SUN)), 0.0);
  let crowd = mix(0.76, 1.0, smoothstep(0.0, 1.3, face.world.y));
  let floors = face.world.y / 0.22;
  let line = (1.0 - min(abs(fract(floors + 0.5) - 0.5) / max(fwidth(floors), 1e-4), 1.0)) * (1.0 - face.normal.y);
  let detail = 1.0 - smoothstep(0.25, 0.5, fwidth(floors));
  return vec4f(base * (0.87 + 0.14 * sheen) * sun * crowd * (1.0 - 0.06 * line * detail), 1.0);
}

fn edgeColour(edge: Edge) -> vec3f {
  return quarterColour(edge.quarter) * (0.75 + 0.25 * edge.shade) * (1.0 - 0.3 * edge.lit);
}

fn streetColour(kind: u32, p: vec3f) -> vec4f {
  let strength = array<f32, 3>(0.4, 0.75, 1.0);
  return vec4f(mix(PEARL, STREET, strength[kind]), 1.0);
}

fn skyColour(down: f32, kind: u32) -> vec3f {
  return mix(PEARL, SKY_RED, select(0.5, 0.55 - 0.4 * down, kind == 1u));
}

fn discColour(agent: vec3f, lead: f32, ring: f32) -> vec3f {
  return mix(agent, GOLD, select(1.0, ring, lead > 0.5));
}

fn trailColour(glow: f32) -> vec4f {
  return vec4f(GOLD, glow * 0.85);
}
`,
}

/** Black porcelain: glossy dark towers lit by one light, rimmed in neon where seen edge-on, with scan lines, the red sky grid, and white agents. */
const obsidian: Look = {
  id: "obsidian",
  glass: null,
  sky: true,
  beacons: true,
  wgsl: /* wgsl */ `
const NIGHT: vec3f = vec3f(0.004, 0.004, 0.008);
const HAZE: vec3f = vec3f(0.018, 0.016, 0.028);
const STONE: vec3f = vec3f(0.05, 0.05, 0.066);
const CASTLE: vec3f = vec3f(0.26, 0.95, 0.52);
const FORGE: vec3f = vec3f(0.22, 0.82, 1.0);
const INN: vec3f = vec3f(0.78, 1.0, 0.3);
const BETWEEN: vec3f = vec3f(0.44, 0.46, 0.92);
const STREET: vec3f = vec3f(0.17, 0.32, 1.0);
const SIGNAL: vec3f = vec3f(1.0, 0.9, 0.04);
const SKY_RED: vec3f = vec3f(1.0, 0.13, 0.13);
const WHITE: vec3f = vec3f(0.9, 0.98, 1.0);
const SUN: vec3f = vec3f(-0.47, 0.8, 0.37);
const BEACON_SIZE: f32 = 1.3;

fn quarterColour(quarter: u32) -> vec3f {
  switch quarter {
    case 0u: { return CASTLE; }
    case 1u: { return FORGE; }
    case 2u: { return INN; }
    default: { return BETWEEN * 0.6; }
  }
}

fn sky(direction: vec3f) -> vec3f {
  return mix(HAZE, NIGHT, smoothstep(0.0, 0.5, direction.y));
}

// Dark stone with a dot at every corner of the grid.
fn groundColour(p: vec2f, onPlate: f32) -> vec3f {
  let light = districtLight(p);
  let cell = p / 0.5;
  let gap = length(fract(cell + 0.5) - 0.5) / max(length(fwidth(cell)), 1e-4);
  let spot = 1.0 - min(gap / 1.6, 1.0);
  return mix(NIGHT, STONE * 0.6, onPlate) + BETWEEN * spot * 0.12 * onPlate
    + (CASTLE * light.x + FORGE * light.y + INN * light.z) * 0.06;
}

// Glazed black: lit by one light, darker low down, and catching the quarter's colour where
// it is seen edge-on and along the scan lines that rise up it.
fn faceColour(face: Face) -> vec4f {
  let view = normalize(city.eye - face.world);
  let sun = max(dot(face.normal, normalize(SUN)), 0.0);
  let glint = pow(max(dot(reflect(-normalize(SUN), face.normal), view), 0.0), 24.0);
  let crowd = mix(0.4, 1.0, smoothstep(0.0, 1.3, face.world.y));
  let rim = pow(1.0 - abs(dot(view, face.normal)), 2.0);
  let scan = smoothstep(0.93, 1.0, fract(face.world.y * 2.0 - city.time * 0.3));
  let glaze = STONE * (1.0 + 2.4 * sun + 0.8 * face.normal.y) * crowd + WHITE * glint * 0.25;
  return vec4f(glaze + quarterColour(face.quarter) * (rim * 0.4 + scan * 0.16) * (1.0 + face.lit * 0.8), 1.0);
}

fn edgeColour(edge: Edge) -> vec3f {
  return quarterColour(edge.quarter) * (0.2 + 0.15 * edge.shade) * (1.0 + edge.lit * 1.2);
}

fn streetColour(kind: u32, p: vec3f) -> vec4f {
  let strength = array<f32, 3>(0.5, 0.85, 1.0);
  return vec4f(STREET * strength[kind], 1.0);
}

fn skyColour(down: f32, kind: u32) -> vec3f {
  return SKY_RED * select(0.75, 0.6 - 0.4 * down, kind == 1u);
}

fn beaconColour(glow: f32) -> vec3f {
  return SIGNAL * glow;
}

fn discColour(agent: vec3f, lead: f32, ring: f32) -> vec3f {
  return mix(agent, WHITE, select(1.0, ring, lead > 0.5));
}

fn trailColour(glow: f32) -> vec4f {
  return vec4f(mix(FORGE, WHITE, glow), glow);
}
`,
}

/** Light or dark, as the page's theme switch shows it. */
export type Theme = "light" | "dark"

/** A look as each theme paints it. */
export type ThemedLook = Readonly<Record<Theme, Look>>

/** A look that paints the same whichever theme the page shows. */
const always = (look: Look): ThemedLook => ({light: look, dark: look})

/** A colour from 0 to 1 in each channel. */
type Colour = readonly [number, number, number]

/** A design-system colour, written as `#FF5B19`. */
const hex = (code: string): Colour => {
  const channel = (at: number) => parseInt(code.slice(at, at + 2), 16) / 255
  return [channel(1), channel(3), channel(5)]
}

/** A mix of exactly two colours, `share` of the way from the first to the second. */
const blend = ([r, g, b]: Colour, [r2, g2, b2]: Colour, share: number): Colour => [
  r + (r2 - r) * share,
  g + (g2 - g) * share,
  b + (b2 - b) * share,
]

const wgsl = ([r, g, b]: Colour) => `vec3f(${r.toFixed(3)}, ${g.toFixed(3)}, ${b.toFixed(3)})`

// The design system's four colours, and the page under them in each theme.
const TANGERINE = hex("#FF5B19")
const CHARCOAL = hex("#161616")
const PLATINUM = hex("#E5E3D2")
const POWDER = hex("#AECACD")
const PAGE_LIGHT = hex("#F6F4EA")
const PAGE_DARK = hex("#0B0B0B")

/** One glass look's colours in one theme. */
type GlassColours = {
  /** The city's plate, the land beyond its edge, and the dots at every corner of the grid. */
  readonly plate: Colour
  readonly land: Colour
  readonly dots: Colour
  /** Each quarter's glass: castle, forge, inn, and the low city between them. */
  readonly quarters: readonly [Colour, Colour, Colour, Colour]
  /** The two colours that take turns along the outlines. */
  readonly sheen: readonly [Colour, Colour]
  /** Back streets, avenues and main roads. */
  readonly streets: readonly [Colour, Colour, Colour]
  /** An agent's disc and the swarm around it, the rim round the agent's own disc, and the tail behind it. */
  readonly body: Colour
  readonly rim: Colour
  readonly tail: Colour
}

/** The colours every glass look's functions read, and the sheen that runs along its outlines. */
const glassColours = (colours: GlassColours) => /* wgsl */ `
const PLATE: vec3f = ${wgsl(colours.plate)};
const LAND: vec3f = ${wgsl(colours.land)};
const HAZE: vec3f = (PLATE + LAND) * 0.5;
const DOTS: vec3f = ${wgsl(colours.dots)};
const SHEEN_A: vec3f = ${wgsl(colours.sheen[0])};
const SHEEN_B: vec3f = ${wgsl(colours.sheen[1])};
const BODY: vec3f = ${wgsl(colours.body)};
const RIM: vec3f = ${wgsl(colours.rim)};
const TAIL: vec3f = ${wgsl(colours.tail)};

fn quarterColour(quarter: u32) -> vec3f {
  switch quarter {
    case 0u: { return ${wgsl(colours.quarters[0])}; }
    case 1u: { return ${wgsl(colours.quarters[1])}; }
    case 2u: { return ${wgsl(colours.quarters[2])}; }
    default: { return ${wgsl(colours.quarters[3])}; }
  }
}

// The two colours of the sheen in turn, a little further along each outline.
fn sheen(edge: Edge) -> vec3f {
  let along = (edge.world.x + edge.world.z) * 0.06 + edge.world.y * 0.1 + city.time * 0.05;
  return mix(SHEEN_A, SHEEN_B, 0.5 + 0.5 * cos(6.2832 * along));
}

fn streetColour(kind: u32, p: vec3f) -> vec4f {
  let colours = array<vec3f, 3>(${colours.streets.map(wgsl).join(", ")});
  return vec4f(colours[kind], 1.0);
}

fn discColour(agent: vec3f, lead: f32, ring: f32) -> vec3f {
  return mix(RIM, BODY, select(1.0, ring, lead > 0.5));
}
`

/** Glasshouse for the light theme: tinted film on the page's paper, deeper edge-on, with outlines in the sheen. */
const paperGlass = (id: LookId, colours: GlassColours): Look => ({
  id,
  glass: "tint",
  sky: false,
  beacons: false,
  wgsl: /* wgsl */ `${glassColours(colours)}
fn sky(direction: vec3f) -> vec3f {
  return mix(HAZE, PLATE, smoothstep(0.02, 0.8, direction.y));
}

// Paper with a dot at every corner of the grid; a lit district's ground takes on its colour.
fn groundColour(p: vec2f, onPlate: f32) -> vec3f {
  let light = districtLight(p);
  let cell = p / 0.5;
  let gap = length(fract(cell + 0.5) - 0.5) / max(length(fwidth(cell)), 1e-4);
  let spot = 1.0 - min(gap / 1.4, 1.0);
  var colour = mix(mix(LAND, PLATE, onPlate), DOTS, 0.22 * spot * onPlate);
  for (var i = 0u; i < 3u; i++) {
    colour = mix(colour, quarterColour(i), light[i] * 0.3);
  }
  return colour;
}

fn faceColour(face: Face) -> vec4f {
  let view = normalize(city.eye - face.world);
  let rim = pow(1.0 - abs(dot(view, face.normal)), 2.0);
  let scan = smoothstep(0.9, 1.0, fract(face.world.y * 2.5 - city.time * 0.35));
  let depth = clamp((0.05 + 0.16 * rim + 0.1 * scan) * (1.0 + face.lit * 0.5), 0.0, 1.0);
  return vec4f(mix(vec3f(1.0), quarterColour(face.quarter), depth), 1.0);
}

fn edgeColour(edge: Edge) -> vec3f {
  let ink = mix(quarterColour(edge.quarter), sheen(edge), 0.5) * 0.6;
  return mix(vec3f(1.0), ink, select(0.3, 0.32, edge.quarter == 3u) + 0.12 * edge.lit);
}

fn trailColour(glow: f32) -> vec4f {
  return vec4f(mix(BODY, TAIL, glow), glow * 0.8);
}
`,
})

/** Glasshouse for the dark theme: faint glass that glows brighter edge-on and where it overlaps, outlined in the sheen. */
const nightGlass = (id: LookId, colours: GlassColours): Look => ({
  id,
  glass: "glow",
  sky: false,
  beacons: false,
  wgsl: /* wgsl */ `${glassColours(colours)}
fn sky(direction: vec3f) -> vec3f {
  return mix(HAZE, LAND, smoothstep(0.0, 0.5, direction.y));
}

// The plate with a faint dot at every corner of the grid; a lit district's ground takes on its colour.
fn groundColour(p: vec2f, onPlate: f32) -> vec3f {
  let light = districtLight(p);
  let cell = p / 0.5;
  let gap = length(fract(cell + 0.5) - 0.5) / max(length(fwidth(cell)), 1e-4);
  let spot = 1.0 - min(gap / 1.6, 1.0);
  return mix(LAND, PLATE, onPlate) + DOTS * spot * mix(0.04, 0.16, onPlate)
    + (quarterColour(0u) * light.x + quarterColour(1u) * light.y + quarterColour(2u) * light.z) * 0.06;
}

fn faceColour(face: Face) -> vec4f {
  let view = normalize(city.eye - face.world);
  let rim = pow(1.0 - abs(dot(view, face.normal)), 2.0);
  let scan = smoothstep(0.92, 1.0, fract(face.world.y * 2.0 - city.time * 0.3));
  return vec4f(quarterColour(face.quarter) * (0.01 + 0.035 * rim + 0.06 * scan) * (1.0 + face.lit * 0.4), 1.0);
}

fn edgeColour(edge: Edge) -> vec3f {
  let colour = mix(quarterColour(edge.quarter), sheen(edge), 0.5);
  return colour * (0.55 + 0.45 * edge.shade) * 0.2 * (1.0 + edge.lit * 0.4);
}

fn trailColour(glow: f32) -> vec4f {
  return vec4f(mix(BODY, TAIL, glow), glow);
}
`,
})

/** All four colours: tangerine, powder blue and smoked glass, with tangerine agents. */
const regent: ThemedLook = {
  light: paperGlass("regent", {
    plate: PAGE_LIGHT,
    land: PLATINUM,
    dots: CHARCOAL,
    quarters: [TANGERINE, POWDER, blend(CHARCOAL, PLATINUM, 0.45), PLATINUM],
    sheen: [TANGERINE, blend(POWDER, CHARCOAL, 0.35)],
    streets: [blend(PLATINUM, CHARCOAL, 0.15), POWDER, TANGERINE],
    body: TANGERINE,
    rim: CHARCOAL,
    tail: TANGERINE,
  }),
  dark: nightGlass("regent", {
    plate: CHARCOAL,
    land: PAGE_DARK,
    dots: PLATINUM,
    quarters: [TANGERINE, POWDER, PLATINUM, blend(PLATINUM, CHARCOAL, 0.5)],
    sheen: [TANGERINE, POWDER],
    streets: [blend(CHARCOAL, PLATINUM, 0.12), blend(POWDER, CHARCOAL, 0.45), TANGERINE],
    body: TANGERINE,
    rim: PLATINUM,
    tail: TANGERINE,
  }),
}

/** Tangerine glass in three strengths, with charcoal or platinum agents ringed in tangerine. */
const tangerine: ThemedLook = {
  light: paperGlass("tangerine", {
    plate: PAGE_LIGHT,
    land: PLATINUM,
    dots: CHARCOAL,
    quarters: [TANGERINE, blend(TANGERINE, PLATINUM, 0.5), blend(TANGERINE, CHARCOAL, 0.35), PLATINUM],
    sheen: [TANGERINE, CHARCOAL],
    streets: [blend(PLATINUM, CHARCOAL, 0.15), blend(TANGERINE, PLATINUM, 0.5), TANGERINE],
    body: CHARCOAL,
    rim: TANGERINE,
    tail: TANGERINE,
  }),
  dark: nightGlass("tangerine", {
    plate: CHARCOAL,
    land: PAGE_DARK,
    dots: PLATINUM,
    quarters: [TANGERINE, blend(TANGERINE, PLATINUM, 0.45), blend(TANGERINE, CHARCOAL, 0.3), blend(PLATINUM, CHARCOAL, 0.55)],
    sheen: [TANGERINE, PLATINUM],
    streets: [blend(CHARCOAL, PLATINUM, 0.1), blend(TANGERINE, CHARCOAL, 0.55), TANGERINE],
    body: PLATINUM,
    rim: TANGERINE,
    tail: TANGERINE,
  }),
}

/** Powder blue glass in three strengths, with tangerine agents. */
const powder: ThemedLook = {
  light: paperGlass("powder", {
    plate: PAGE_LIGHT,
    land: PLATINUM,
    dots: CHARCOAL,
    quarters: [POWDER, blend(POWDER, PLATINUM, 0.4), blend(POWDER, CHARCOAL, 0.2), PLATINUM],
    sheen: [blend(POWDER, CHARCOAL, 0.4), POWDER],
    streets: [blend(PLATINUM, CHARCOAL, 0.15), POWDER, blend(POWDER, CHARCOAL, 0.45)],
    body: TANGERINE,
    rim: CHARCOAL,
    tail: TANGERINE,
  }),
  dark: nightGlass("powder", {
    plate: CHARCOAL,
    land: PAGE_DARK,
    dots: PLATINUM,
    quarters: [POWDER, blend(POWDER, PLATINUM, 0.5), blend(POWDER, CHARCOAL, 0.3), blend(PLATINUM, CHARCOAL, 0.55)],
    sheen: [POWDER, PLATINUM],
    streets: [blend(CHARCOAL, PLATINUM, 0.1), blend(POWDER, CHARCOAL, 0.5), POWDER],
    body: TANGERINE,
    rim: POWDER,
    tail: TANGERINE,
  }),
}

/** Smoked glass in charcoal and platinum only, and tangerine agents the one colour in it. */
const smoke: ThemedLook = {
  light: paperGlass("smoke", {
    plate: PAGE_LIGHT,
    land: PLATINUM,
    dots: CHARCOAL,
    quarters: [blend(CHARCOAL, PLATINUM, 0.25), blend(CHARCOAL, PLATINUM, 0.5), blend(CHARCOAL, PLATINUM, 0.7), PLATINUM],
    sheen: [CHARCOAL, blend(CHARCOAL, PLATINUM, 0.5)],
    streets: [blend(PLATINUM, CHARCOAL, 0.12), blend(PLATINUM, CHARCOAL, 0.3), CHARCOAL],
    body: TANGERINE,
    rim: CHARCOAL,
    tail: TANGERINE,
  }),
  dark: nightGlass("smoke", {
    plate: CHARCOAL,
    land: PAGE_DARK,
    dots: PLATINUM,
    quarters: [PLATINUM, blend(PLATINUM, CHARCOAL, 0.3), blend(PLATINUM, CHARCOAL, 0.5), blend(PLATINUM, CHARCOAL, 0.65)],
    sheen: [PLATINUM, blend(PLATINUM, CHARCOAL, 0.4)],
    streets: [blend(CHARCOAL, PLATINUM, 0.1), blend(CHARCOAL, PLATINUM, 0.25), PLATINUM],
    body: TANGERINE,
    rim: PLATINUM,
    tail: TANGERINE,
  }),
}

/** Patchbay's porcelain and cobalt: cobalt glass on cool white, or pale cobalt glass on midnight. */
const cobalt: ThemedLook = {
  light: paperGlass("cobalt", {
    plate: hex("#F6F7FA"),
    land: hex("#EAEDF4"),
    dots: hex("#192239"),
    quarters: [hex("#294EC3"), hex("#9BB4FF"), hex("#192239"), hex("#ABB8D1")],
    sheen: [hex("#294EC3"), hex("#9BB4FF")],
    streets: [blend(hex("#F6F7FA"), hex("#7B869B"), 0.4), hex("#9BB4FF"), hex("#294EC3")],
    body: hex("#294EC3"),
    rim: hex("#192239"),
    tail: hex("#294EC3"),
  }),
  dark: nightGlass("cobalt", {
    plate: hex("#1B2335"),
    land: hex("#111726"),
    dots: hex("#ABB8D1"),
    quarters: [hex("#9BB4FF"), hex("#294EC3"), hex("#EEF2FF"), hex("#6D7D99")],
    sheen: [hex("#9BB4FF"), hex("#EEF2FF")],
    streets: [hex("#252F45"), hex("#6D7D99"), hex("#9BB4FF")],
    body: hex("#9BB4FF"),
    rim: hex("#EEF2FF"),
    tail: hex("#9BB4FF"),
  }),
}

export const LOOKS: Readonly<Record<LookId, ThemedLook>> = {
  neon: always(neon),
  blueprint: always(blueprint),
  porcelain: always(porcelain),
  lamplight: always(lamplight),
  sunset: always(sunset),
  hologram: always(hologram),
  afterglow: always(afterglow),
  showroom: always(showroom),
  glasshouse: always(glasshouse),
  opal: always(opal),
  obsidian: always(obsidian),
  regent,
  tangerine,
  powder,
  smoke,
  cobalt,
}
