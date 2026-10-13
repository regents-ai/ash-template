/**
 * The world cube, drawn by one fullscreen shader.
 *
 * Every pixel casts a ray at a cube. The face the ray enters is a window, and
 * behind each window is a room far larger than the cube that holds it: the ray
 * is carried into that face's own space and marched through the room there. So
 * turning the cube slides each room behind its frame, and flying the camera
 * through a window is the same picture with the frame left behind.
 *
 * Rooms are indexed by the face they sit behind: 0 +x, 1 -x, 2 +y, 3 -y, 4 +z,
 * 5 -z. In a room's own space the window is the square at z = 1, x runs right,
 * y runs up and the floor is y = -1.
 */
export const worldCubeWgsl = /* wgsl */ `
struct Params {
  resolution: vec2f,
  // Yaw and pitch of the visitor's head once inside a room.
  look: vec2f,
  time: f32,
  // Camera distance from the cube's centre; under 1 it is inside.
  distance: f32,
  // Cube orientation, object to world.
  rotation: vec4f,
  // Tangent of half the vertical field of view.
  lens: f32,
  // The room the camera is flying into or standing in.
  face: f32,
  // The face under a resting pointer, and how strongly it is lit for it.
  hover: f32,
  glow: f32,
}
@group(0) @binding(0) var<uniform> params: Params;

const PI = 3.14159265;
// The palette, in linear light.
const TANGERINE = vec3f(1.0, 0.105, 0.010);
const POWDER = vec3f(0.423, 0.591, 0.610);
const PLATINUM = vec3f(0.783, 0.767, 0.646);
const GOLD = vec3f(1.0, 0.62, 0.18);

// Light given off around the point the last map() call was asked about.
var<private> gEmit: vec3f;

fn rot(a: f32) -> mat2x2f {
  let c = cos(a);
  let s = sin(a);
  return mat2x2f(c, s, -s, c);
}

fn qrot(q: vec4f, v: vec3f) -> vec3f {
  let t = 2.0 * cross(q.xyz, v);
  return v + q.w * t + cross(q.xyz, t);
}

fn hash21(p: vec2f) -> f32 {
  var q = fract(p * vec2f(123.34, 456.21));
  q += dot(q, q + 45.32);
  return fract(q.x * q.y);
}

fn sdBox(p: vec3f, b: vec3f) -> f32 {
  let q = abs(p) - b;
  return length(max(q, vec3f(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdCyl(p: vec3f, r: f32, h: f32) -> f32 {
  let d = vec2f(length(p.xz) - r, abs(p.y) - h);
  return min(max(d.x, d.y), 0.0) + length(max(d, vec2f(0.0)));
}

fn sdCapsule(p: vec3f, a: vec3f, b: vec3f, r: f32) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - r;
}

// A cone with rounded ends standing on the origin: r1 below, r2 at height h.
fn sdRoundCone(p: vec3f, r1: f32, r2: f32, h: f32) -> f32 {
  let q = vec2f(length(p.xz), p.y);
  let b = (r1 - r2) / h;
  let a = sqrt(1.0 - b * b);
  let k = dot(q, vec2f(-b, a));
  if (k < 0.0) { return length(q) - r1; }
  if (k > a * h) { return length(q - vec2f(0.0, h)) - r2; }
  return dot(q, vec2f(a, b)) - r1;
}

fn pick(a: vec2f, d: f32, m: f32) -> vec2f {
  if (d < a.x) { return vec2f(d, m); }
  return a;
}

// A falling edge: 1 below low, 0 above high.
fn fade(high: f32, low: f32, x: f32) -> f32 {
  return 1.0 - smoothstep(low, high, x);
}

// How much of a lamp's light reaches a point d away from it.
fn lamp(d: f32, r: f32) -> f32 {
  let k = r / (r + max(d, 0.0));
  return k * k;
}

// ---------------------------------------------------------------- Autolaunch
// A launch silo: a rocket holding over its pad, and bid steps climbing the walls.

const LAUNCH_ROCKET = vec3f(0.0, -0.25, -1.0);
// Where the first bid step stands, and how far apart the steps are.
const LAUNCH_STEP = vec2f(0.3, 0.6);

fn launchLift() -> f32 {
  return 0.06 * sin(params.time * 0.9);
}

// Which bid step a depth belongs to, counted back from the window.
fn launchStep(z: f32) -> f32 {
  return clamp(round((LAUNCH_STEP.x - z) / LAUNCH_STEP.y), 0.0, 5.0);
}

fn mapLaunch(p: vec3f) -> vec2f {
  let t = params.time;
  var res = vec2f(min(min(2.3 - abs(p.x), p.y + 1.0), min(2.8 - p.y, p.z + 3.6)), 1.0);

  let q = p - LAUNCH_ROCKET - vec3f(0.0, launchLift(), 0.0);
  var body = sdCyl(q - vec3f(0.0, 0.05, 0.0), 0.2, 0.42);
  body = min(body, sdRoundCone(q - vec3f(0.0, 0.47, 0.0), 0.2, 0.03, 0.5));
  let f = vec3f(abs(q.x), q.y, abs(q.z));
  let fins = min(
    sdBox(f - vec3f(0.3, -0.3, 0.0), vec3f(0.12, 0.13, 0.015)),
    sdBox(f - vec3f(0.0, -0.3, 0.3), vec3f(0.015, 0.13, 0.12)));
  res = pick(res, min(body, fins), 2.0);
  res = pick(res, sdRoundCone(q - vec3f(0.0, -0.52, 0.0), 0.13, 0.08, 0.12), 3.0);

  // Bid steps: each one further back stands a little taller.
  let sx = abs(p.x) - 1.55;
  let id = launchStep(p.z);
  let hgt = 0.2 + 0.19 * id;
  res = pick(res, sdBox(vec3f(sx, p.y + 1.0 - hgt, p.z - LAUNCH_STEP.x + LAUNCH_STEP.y * id), vec3f(0.17, hgt, 0.17)), 4.0);

  // The gantry beside the rocket.
  let g = p - vec3f(-0.62, 0.0, LAUNCH_ROCKET.z);
  var gantry = sdBox(g - vec3f(0.0, -0.2, 0.0), vec3f(0.035, 0.8, 0.035));
  gantry = min(gantry, sdBox(g - vec3f(0.2, 0.25, 0.0), vec3f(0.2, 0.02, 0.02)));
  res = pick(res, gantry, 5.0);

  let flicker = 0.8 + 0.2 * sin(t * 23.0 + q.y * 31.0);
  let flame = sdCapsule(q, vec3f(0.0, -0.6, 0.0), vec3f(0.0, -0.82, 0.0), 0.02);
  gEmit += vec3f(1.0, 0.3, 0.04) * lamp(flame, 0.07) * 7.0 * flicker;
  let pad = length(vec2f(length(p.xz - LAUNCH_ROCKET.xz) - 0.62, p.y + 1.0));
  gEmit += TANGERINE * lamp(pad, 0.02) * 2.5;
  gEmit += vec3f(1.0, 0.05, 0.03) * lamp(length(g - vec3f(0.0, 0.64, 0.0)), 0.02) * 3.0 * step(0.0, sin(t * 3.0));
  return res;
}

// ------------------------------------------------------------------ Techtree
// A night greenhouse around one luminous tree that keeps branching.

const TREE_BASE = vec3f(0.0, -0.84, -1.5);

fn mapTree(p: vec3f) -> vec2f {
  let t = params.time;
  var res = vec2f(min(min(2.4 - abs(p.x), p.y + 1.0), min(2.8 - p.y, p.z + 3.6)), 1.0);
  res = pick(res, sdCyl(p - vec3f(TREE_BASE.x, -0.92, TREE_BASE.z), 0.55, 0.08), 2.0);

  var q = p - TREE_BASE;
  var s = 1.0;
  var wood = sdCapsule(q, vec3f(0.0), vec3f(0.0, 0.62, 0.0), 0.07);
  var nodes = 1e3;
  for (var i = 0; i < 5; i++) {
    q.y -= 0.62;
    nodes = min(nodes, (length(q) - 0.085) / s);
    q = vec3f(abs(q.x), q.y, abs(q.z));
    let sway = 0.03 * sin(t * 0.7 + f32(i) * 1.7);
    let xy = rot(0.6 + sway) * q.xy;
    let zy = rot(0.42 - sway) * vec2f(q.z, xy.y);
    q = vec3f(xy.x, zy.y, zy.x) * 1.38;
    s *= 1.38;
    wood = min(wood, sdCapsule(q, vec3f(0.0), vec3f(0.0, 0.62, 0.0), 0.055) / s);
  }
  res = pick(res, wood, 3.0);
  res = pick(res, nodes, 4.0);

  let leaves = (length(q - vec3f(0.0, 0.62, 0.0)) - 0.1) / s;
  gEmit += vec3f(0.5, 0.86, 1.0) * lamp(leaves, 0.025) * 2.2;
  gEmit += vec3f(0.5, 0.86, 1.0) * lamp(nodes, 0.03) * 0.8;
  return res;
}

// ------------------------------------------------------------------ Patchbay
// A switchboard room: a wall of sockets, and cables carrying signals between them.

const PATCH_PANEL = vec3f(0.0, 0.3, -1.7);
const PATCH_BULB = vec3f(0.0, 1.12, -0.7);

fn mapPatch(p: vec3f) -> vec2f {
  let t = params.time;
  var res = vec2f(min(min(2.3 - abs(p.x), p.y + 1.0), min(1.6 - p.y, p.z - PATCH_PANEL.z + 0.12)), 1.0);
  res = pick(res, sdBox(p - PATCH_PANEL, vec3f(1.8, 0.95, 0.07)) - 0.02, 2.0);
  res = pick(res, sdBox(p - vec3f(0.0, -0.82, -1.0), vec3f(1.4, 0.18, 0.3)) - 0.02, 4.0);

  // Each cable: its two sockets, then how far it sags and which colour it carries.
  var ends = array<vec4f, 6>(
    vec4f(-1.5, 0.95, -0.3, 0.6),
    vec4f(-1.2, 0.35, 0.6, 0.95),
    vec4f(-0.6, 0.95, 1.5, 0.35),
    vec4f(0.0, 0.3, 1.5, 0.95),
    vec4f(-1.5, 0.05, 0.9, -0.25),
    vec4f(0.3, 0.65, 1.2, -0.25));
  var sags = array<f32, 6>(0.4, 0.55, 0.65, 0.45, 0.35, 0.4);
  var cable = 1e3;
  for (var i = 0; i < 6; i++) {
    let e = ends[i];
    let x = clamp(p.x, e.x, e.z);
    let u = (x - e.x) / (e.z - e.x);
    let droop = 4.0 * u * (1.0 - u);
    let y = mix(e.y, e.w, u) - sags[i] * droop;
    let slope = (e.w - e.y - sags[i] * 4.0 * (1.0 - 2.0 * u)) / (e.z - e.x);
    let z = PATCH_PANEL.z + 0.12 + 0.22 * droop;
    let d = length(vec3f(p.x - x, (p.y - y) / sqrt(1.0 + slope * slope), p.z - z)) - 0.032;
    let hue = i % 3;
    var c = TANGERINE;
    if (hue == 1) { c = PLATINUM; }
    if (hue == 2) { c = vec3f(0.25, 0.62, 0.9); }
    cable = min(cable, d);
    let pulse = fract(t * 0.22 + f32(i) * 0.37);
    let near = (u - pulse) * 7.0;
    gEmit += c * lamp(d, 0.03) * exp(-near * near) * 6.0;
  }
  res = pick(res, cable, 3.0);

  let bulb = p - PATCH_BULB;
  res = pick(res, min(length(bulb) - 0.1, sdCapsule(bulb, vec3f(0.0, 0.1, 0.0), vec3f(0.0, 0.5, 0.0), 0.012)), 5.0);
  gEmit += vec3f(1.0, 0.78, 0.5) * lamp(length(bulb) - 0.1, 0.07) * 0.9;
  return res;
}

// The colour of the cable nearest a point on the switchboard.
fn patchTint(p: vec3f) -> vec3f {
  let band = floor((p.x + p.y * 0.7 + 2.3) * 1.3);
  let hue = i32(band) % 3;
  if (hue == 1) { return PLATINUM; }
  if (hue == 2) { return vec3f(0.25, 0.62, 0.9); }
  return TANGERINE;
}

// ----------------------------------------------------------------- Regents X
// A black observatory: two crossed beams sending rings out, and posts wheeling round them.

const SIGNAL_CENTRE = vec3f(0.0, 0.45, -1.5);

fn mapSignal(p: vec3f) -> vec2f {
  let t = params.time;
  var res = vec2f(p.y + 1.0, 1.0);
  let m = p - SIGNAL_CENTRE;
  let a = rot(PI * 0.25) * m.xy;
  let b = rot(-PI * 0.25) * m.xy;
  let bars = min(
    sdBox(vec3f(a, m.z), vec3f(0.09, 0.85, 0.08)),
    sdBox(vec3f(b, m.z), vec3f(0.09, 0.85, 0.08))) - 0.015;
  res = pick(res, bars, 2.0);
  res = pick(res, sdCyl(p - vec3f(SIGNAL_CENTRE.x, -0.93, SIGNAL_CENTRE.z), 0.55, 0.07), 3.0);

  // Seven posts wheeling slowly round the beams, each at its own depth.
  let sector = 2.0 * PI / 7.0;
  let angle = atan2(m.y, m.x) + t * 0.08;
  let id = round(angle / sector);
  let local = angle - sector * id;
  let radius = length(m.xy);
  let pane = vec3f(radius * cos(local) - 1.2, radius * sin(local), m.z - 0.5 * sin(id * 2.4));
  res = pick(res, sdBox(pane, vec3f(0.17, 0.25, 0.012)) - 0.01, 4.0);

  gEmit += vec3f(1.0) * lamp(bars, 0.05) * 0.7;
  for (var i = 0; i < 3; i++) {
    let grow = fract(t * 0.11 + f32(i) / 3.0);
    let ring = length(vec2f(length(m.xy) - grow * 2.8, m.z));
    gEmit += vec3f(1.0) * lamp(ring, 0.014) * (1.0 - grow) * 2.4;
  }
  return res;
}

// ------------------------------------------------------------- Regents stake
// A hall of columns leading to the crown, with staked blocks circling it.

const HALL_CROWN = vec3f(0.0, 0.3, -1.6);
const CROWN_PITCH = 0.245;
const CROWN_HALF = 0.11;
const CROWN_SCALE = 1.25;

// The Regents crown, block for block: three blocks over two rows of five.
fn sdCrown(p: vec3f) -> f32 {
  let c = p / CROWN_SCALE;
  let lower = vec3f(
    c.x - CROWN_PITCH * clamp(round(c.x / CROWN_PITCH), -2.0, 2.0),
    c.y - CROWN_PITCH * clamp(round(c.y / CROWN_PITCH), -1.0, 0.0),
    c.z);
  let upper = vec3f(
    c.x - 2.0 * CROWN_PITCH * clamp(round(c.x / (2.0 * CROWN_PITCH)), -1.0, 1.0),
    c.y - CROWN_PITCH,
    c.z);
  let block = vec3f(CROWN_HALF - 0.014);
  return (min(sdBox(lower, block), sdBox(upper, block)) - 0.014) * CROWN_SCALE;
}

fn crownSpace(p: vec3f) -> vec3f {
  let t = params.time;
  let c = p - HALL_CROWN - vec3f(0.0, 0.05 * sin(t * 0.8), 0.0);
  let xz = rot(0.32 * sin(t * 0.35)) * c.xz;
  return vec3f(xz.x, c.y, xz.y);
}

fn mapHall(p: vec3f) -> vec2f {
  let t = params.time;
  var res = vec2f(min(min(2.0 - abs(p.x), p.y + 1.0), min(3.2 - p.y, p.z + 4.6)), 1.0);

  let sx = abs(p.x) - 1.45;
  let bay = clamp(round((p.z + 0.3) / 1.1), -3.0, 0.0) * 1.1 - 0.3;
  var column = sdCyl(vec3f(sx, p.y - 1.1, p.z - bay), 0.15, 2.1);
  column = min(column, sdBox(vec3f(sx, p.y + 0.9, p.z - bay), vec3f(0.21, 0.1, 0.21)));
  res = pick(res, column, 2.0);

  var dais = sdBox(p - vec3f(0.0, -0.94, -1.8), vec3f(1.15, 0.06, 0.85));
  dais = min(dais, sdBox(p - vec3f(0.0, -0.82, -1.9), vec3f(0.9, 0.06, 0.66)));
  dais = min(dais, sdBox(p - vec3f(0.0, -0.7, -2.0), vec3f(0.65, 0.06, 0.48)));
  res = pick(res, dais, 3.0);

  let crown = sdCrown(crownSpace(p));
  res = pick(res, crown, 4.0);

  // Ten staked blocks in a ring around the crown.
  let o = p - HALL_CROWN;
  let sector = 2.0 * PI / 10.0;
  let angle = atan2(o.z, o.x) + t * 0.22;
  let id = round(angle / sector);
  let local = angle - sector * id;
  let radius = length(o.xz);
  let stake = vec3f(radius * cos(local) - 1.2, o.y + 0.45 - 0.07 * sin(id * 1.9 + t), radius * sin(local));
  let block = sdBox(stake, vec3f(0.06)) - 0.008;
  res = pick(res, block, 5.0);

  gEmit += PLATINUM * lamp(crown, 0.06) * 0.3;
  gEmit += TANGERINE * lamp(block, 0.03) * 1.6;
  // The shaft of light the crown hangs in.
  gEmit += vec3f(1.0, 0.9, 0.72) * lamp(length(o.xz) - 0.35, 0.3) * 0.05 * smoothstep(-1.0, 2.6, p.y);
  return res;
}

// ------------------------------------------------------------------ Keyfleet
// A harbour at night: a great key over the water, a lighthouse, lantern boats.

const HARBOUR_LIGHT = vec3f(1.0, -0.72, -2.6);
const HARBOUR_KEY = vec3f(-0.3, -0.05, -1.0);
// The middle berth of the fleet.
const HARBOUR_BERTH = -1.6;

fn mapHarbour(p: vec3f) -> vec2f {
  let t = params.time;
  var res = vec2f(p.y + 1.0, 1.0);

  let rock = (p - vec3f(HARBOUR_LIGHT.x, -1.0, HARBOUR_LIGHT.z)) / vec3f(0.85, 0.36, 0.65);
  res = pick(res, (length(rock) - 1.0) * 0.36, 2.0);

  let l = p - HARBOUR_LIGHT;
  var tower = sdRoundCone(l, 0.2, 0.13, 1.25);
  tower = min(tower, sdCyl(l - vec3f(0.0, 1.33, 0.0), 0.2, 0.025));
  tower = min(tower, sdRoundCone(l - vec3f(0.0, 1.56, 0.0), 0.13, 0.02, 0.12));
  res = pick(res, tower, 3.0);
  let beacon = l - vec3f(0.0, 1.45, 0.0);
  res = pick(res, length(beacon) - 0.1, 4.0);

  // The key: a ring for a bow, a shaft, two teeth.
  let k0 = p - HARBOUR_KEY - vec3f(0.0, 0.06 * sin(t * 0.7), 0.0);
  let kxz = rot(0.5 * sin(t * 0.3)) * k0.xz;
  let k = vec3f(kxz.x, k0.y, kxz.y);
  var key = length(vec2f(length(k.xy - vec2f(0.0, 0.42)) - 0.2, k.z)) - 0.055;
  key = min(key, sdCapsule(k, vec3f(0.0, 0.2, 0.0), vec3f(0.0, -0.55, 0.0), 0.05));
  key = min(key, sdBox(k - vec3f(0.11, -0.5, 0.0), vec3f(0.09, 0.035, 0.04)));
  key = min(key, sdBox(k - vec3f(0.09, -0.33, 0.0), vec3f(0.07, 0.035, 0.04)));
  res = pick(res, key, 5.0);

  // The fleet: one boat to a berth, each riding the swell on its own beat.
  let berth = vec2f(clamp(round(p.x / 1.3), -2.0, 2.0), clamp(round((p.z - HARBOUR_BERTH) / 1.5), -2.0, 0.0));
  let h = hash21(berth + 7.0);
  let drift = vec2f(h - 0.5, fract(h * 7.3) - 0.5) * 0.3;
  let b = vec3f(
    p.x - berth.x * 1.3 - drift.x,
    p.y + 0.95 - 0.02 * sin(t * 1.3 + h * 20.0),
    p.z - HARBOUR_BERTH - berth.y * 1.5 - drift.y);
  var boat = sdBox(b, vec3f(0.2, 0.045, 0.07)) - 0.03;
  boat = min(boat, sdBox(b - vec3f(-0.03, 0.2, 0.0), vec3f(0.09, 0.13, 0.006)));
  res = pick(res, boat, 6.0);
  let lantern = length(b - vec3f(0.17, 0.16, 0.0)) - 0.035;
  res = pick(res, lantern, 7.0);

  gEmit += GOLD * lamp(lantern, 0.035) * 1.3;
  gEmit += GOLD * lamp(key, 0.05) * 0.9;
  gEmit += vec3f(1.0, 0.9, 0.7) * lamp(length(beacon) - 0.1, 0.06) * 1.6;
  // The lighthouse beam, sweeping both ways.
  let sweep = t * 0.45;
  let aim = vec3f(cos(sweep), 0.0, sin(sweep));
  let along = dot(beacon, aim);
  let off = length(beacon - aim * along);
  let width = 0.05 + 0.11 * abs(along);
  gEmit += vec3f(1.0, 0.9, 0.7) * exp(-(off * off) / (width * width)) * 0.42 / (1.0 + abs(along) * 0.5);
  return res;
}

// ----------------------------------------------------------------- Every room

fn map(p: vec3f, room: i32) -> vec2f {
  gEmit = vec3f(0.0);
  switch room {
    case 0 { return mapLaunch(p); }
    case 1 { return mapTree(p); }
    case 2 { return mapPatch(p); }
    case 3 { return mapSignal(p); }
    case 4 { return mapHall(p); }
    default { return mapHarbour(p); }
  }
}

fn stars(rd: vec3f, density: f32) -> f32 {
  let g = vec2f(atan2(rd.x, -rd.z), rd.y) * 22.0;
  let id = floor(g);
  let h = hash21(id);
  let centre = vec2f(fract(h * 13.7), fract(h * 91.3)) * 0.7 + 0.15;
  let d = length(fract(g) - centre);
  return step(1.0 - density, h) * fade(0.07, 0.0, d) * (0.4 + 0.6 * fract(h * 51.0));
}

// What a ray sees when it leaves a room that has no walls.
fn sky(room: i32, rd: vec3f) -> vec3f {
  if (room == 3) {
    let lane = (rd.y - 0.35 - rd.x * 0.3) * 4.0;
    let band = exp(-lane * lane);
    return vec3f(0.004) + vec3f(0.03) * band + vec3f(1.0) * stars(rd, 0.3);
  }
  let up = clamp(rd.y, 0.0, 1.0);
  var col = mix(vec3f(0.02, 0.07, 0.11), vec3f(0.003, 0.007, 0.03), pow(up, 0.45));
  col += vec3f(0.9, 0.95, 1.0) * stars(rd, 0.16) * smoothstep(0.02, 0.2, rd.y);
  let moon = dot(rd, normalize(vec3f(-0.42, 0.44, -1.0)));
  col += vec3f(1.0, 0.96, 0.85) * (smoothstep(0.9985, 0.9992, moon) * 1.4 + pow(max(moon, 0.0), 60.0) * 0.12);
  return col;
}

struct Surface {
  albedo: vec3f,
  emit: vec3f,
  gloss: f32,
}

fn grid(p: vec2f, width: f32) -> f32 {
  let g = abs(fract(p) - 0.5);
  return smoothstep(0.5 - width, 0.5, max(g.x, g.y));
}

fn surface(room: i32, m: f32, p: vec3f, n: vec3f, rd: vec3f) -> Surface {
  let t = params.time;
  var s = Surface(vec3f(0.03), vec3f(0.0), 0.0);
  let mat = i32(m + 0.5);
  switch room {
    // Autolaunch
    case 0 {
      if (mat == 1) {
        s.albedo = vec3f(0.022, 0.022, 0.026);
        if (n.y > 0.5) {
          s.emit = TANGERINE * grid(p.xz * 2.0, 0.03) * 0.5 * exp(-length(p.xz - LAUNCH_ROCKET.xz) * 0.5);
          s.gloss = 0.5;
        } else if (n.z > 0.5) {
          // The hatch in the back wall, open on a dusk sky.
          let h = p.xy - vec2f(0.0, 0.7);
          let r = length(h);
          let dusk = mix(vec3f(1.0, 0.22, 0.03), vec3f(0.05, 0.03, 0.2), smoothstep(-0.9, 0.9, h.y));
          s.emit = dusk * 0.8 * fade(1.15, 1.1, r)
            + vec3f(1.0, 0.5, 0.15) * fade(0.05, 0.0, abs(r - 1.15)) * 1.2;
        } else {
          s.albedo *= 0.6 + 0.4 * smoothstep(0.42, 0.46, abs(fract(p.z * 1.6) - 0.5));
        }
      } else if (mat == 2) {
        let q = p - LAUNCH_ROCKET - vec3f(0.0, launchLift(), 0.0);
        s.albedo = PLATINUM;
        if ((q.y > 0.12 && q.y < 0.24) || q.y < -0.16 || q.y > 0.82) { s.albedo = TANGERINE; }
        s.gloss = 0.8;
      } else if (mat == 3) {
        s.albedo = vec3f(0.02);
        s.emit = vec3f(1.0, 0.25, 0.03) * 0.6;
      } else if (mat == 4) {
        let id = launchStep(p.z);
        let top = -1.0 + 2.0 * (0.2 + 0.19 * id);
        s.albedo = vec3f(0.035, 0.03, 0.03);
        s.emit = TANGERINE * (fade(0.05, 0.0, top - p.y) * 1.6
          + 0.25 * smoothstep(0.46, 0.5, abs(fract(p.y * 5.0) - 0.5)));
      } else {
        s.albedo = vec3f(0.09);
        s.gloss = 0.4;
      }
    }
    // Techtree
    case 1 {
      if (mat == 1) {
        s.albedo = vec3f(0.008, 0.02, 0.026);
        if (n.y > 0.5) {
          let r = length(p.xz - TREE_BASE.xz);
          let ring = smoothstep(0.42, 0.5, abs(fract(r * 2.2 - t * 0.25) - 0.5));
          s.emit = POWDER * ring * 0.35 * exp(-r * 0.7);
          s.gloss = 0.6;
        } else {
          // Greenhouse ribs.
          let ribs = max(
            smoothstep(0.47, 0.5, abs(fract(p.y * 1.2 + 0.2) - 0.5)),
            smoothstep(0.47, 0.5, abs(fract((p.x + p.z) * 1.1) - 0.5)));
          s.emit = POWDER * ribs * 0.09;
        }
      } else if (mat == 2) {
        s.albedo = vec3f(0.05, 0.07, 0.08);
        s.emit = POWDER * fade(0.04, 0.0, abs(length(p.xz - TREE_BASE.xz) - 0.5)) * 0.8;
        s.gloss = 0.5;
      } else if (mat == 3) {
        s.albedo = vec3f(0.2, 0.3, 0.32);
        s.emit = POWDER * 0.12;
      } else {
        s.albedo = vec3f(0.3);
        s.emit = mix(vec3f(0.6, 0.92, 1.0), TANGERINE * 1.6, step(0.3, p.y) * step(p.y, 0.75)) * 1.3;
      }
    }
    // Patchbay
    case 2 {
      if (mat == 1) {
        s.albedo = vec3f(0.5, 0.47, 0.37);
        if (n.y > 0.5) {
          let c = floor(p.xz * 1.6);
          s.albedo = mix(vec3f(0.06, 0.05, 0.045), vec3f(0.2, 0.18, 0.14), fract((c.x + c.y) * 0.5) * 2.0);
          s.gloss = 0.5;
        } else if (p.y < -0.35) {
          s.albedo = vec3f(0.16, 0.14, 0.11);
          s.emit = TANGERINE * fade(0.03, 0.0, -0.35 - p.y) * 0.5;
        } else if (n.y > -0.5) {
          // Panelled walls: a seam every so often, along whichever way the wall runs.
          let along = p.x * abs(n.z) + p.z * abs(n.x);
          s.albedo *= 0.55 + 0.45 * fade(0.5, 0.47, abs(fract(along * 1.25) - 0.5));
        }
      } else if (mat == 2) {
        // Sockets in rows, a signal lamp over each.
        let cell = (p.xy - PATCH_PANEL.xy) / 0.3;
        let f = fract(cell) - 0.5;
        let id = floor(cell);
        let ringD = abs(length(f + vec2f(0.0, 0.08)) - 0.2);
        s.albedo = mix(vec3f(0.012), PLATINUM * 0.7, fade(0.05, 0.02, ringD));
        s.albedo = mix(s.albedo, vec3f(0.0), fade(0.17, 0.14, length(f + vec2f(0.0, 0.08))));
        let h = hash21(id);
        let on = step(0.35, h) * (0.4 + 0.6 * step(0.0, sin(t * (1.0 + h * 3.0) + h * 40.0)));
        var led = TANGERINE;
        if (h > 0.6) { led = vec3f(0.25, 0.62, 0.9); }
        if (h > 0.82) { led = PLATINUM; }
        s.emit = led * on * fade(0.07, 0.03, length(f - vec2f(0.0, 0.33))) * 2.2 * step(0.5, n.z);
        s.gloss = 0.4;
      } else if (mat == 3) {
        s.albedo = patchTint(p) * 0.5;
        s.gloss = 0.5;
      } else if (mat == 4) {
        s.albedo = vec3f(0.03, 0.028, 0.026);
        if (n.y > 0.5) {
          let cell = p.xz * vec2f(7.0, 9.0);
          let f = fract(cell) - 0.5;
          let h = hash21(floor(cell));
          s.emit = mix(TANGERINE, PLATINUM, step(0.5, h)) * step(0.45, h)
            * fade(0.28, 0.2, length(f)) * 0.9;
        }
        s.gloss = 0.3;
      } else {
        s.albedo = vec3f(0.2);
        s.emit = vec3f(1.0, 0.78, 0.5) * 2.0 * step(p.y, 1.24);
      }
    }
    // Regents X
    case 3 {
      if (mat == 1) {
        let r = length(p.xz - SIGNAL_CENTRE.xz);
        let ring = smoothstep(0.46, 0.5, abs(fract(r * 1.4 - t * 0.11) - 0.5));
        s.albedo = vec3f(0.004);
        s.emit = vec3f(1.0) * ring * 0.3 * exp(-r * 0.45) + sky(3, reflect(rd, n)) * 0.5;
        s.gloss = 1.0;
      } else if (mat == 2) {
        s.albedo = vec3f(0.6);
        s.emit = vec3f(1.0) * 1.1;
      } else if (mat == 3) {
        s.albedo = vec3f(0.02);
        s.emit = vec3f(1.0) * fade(0.04, 0.0, abs(length(p.xz - SIGNAL_CENTRE.xz) - 0.5)) * 0.9;
        s.gloss = 0.8;
      } else {
        // A post: a few lines of writing on dark glass.
        let lines = smoothstep(0.3, 0.38, abs(fract(p.y * 9.0) - 0.5));
        let across = fract(p.x * 2.6 + floor(p.y * 9.0) * 0.37);
        s.albedo = vec3f(0.02);
        s.emit = vec3f(0.9) * lines * step(across, 0.72) * 0.55 + vec3f(0.05);
        s.gloss = 0.9;
      }
    }
    // Regents stake
    case 4 {
      if (mat == 1) {
        s.albedo = vec3f(0.03, 0.03, 0.032);
        if (n.y > 0.5) {
          s.albedo = mix(vec3f(0.018), PLATINUM * 0.5, grid(p.xz / 1.1 + vec2f(0.5, 0.27), 0.02));
          if (abs(p.x) < 0.42 && p.z > -0.95) { s.albedo = TANGERINE * 0.55; }
          s.gloss = 0.7;
        } else if (n.z > 0.5) {
          // The tall window behind the dais.
          let arch = max(abs(p.x) - 0.75, p.y - 2.3 + 0.6 * p.x * p.x);
          s.emit = vec3f(1.0, 0.84, 0.6) * fade(0.05, -0.05, arch) * 0.5;
        } else {
          s.albedo *= 0.6 + 0.4 * smoothstep(0.44, 0.47, abs(fract(p.z / 1.1 + 0.77) - 0.5));
        }
      } else if (mat == 2) {
        s.albedo = PLATINUM * 0.55;
        s.gloss = 0.3;
      } else if (mat == 3) {
        s.albedo = vec3f(0.07, 0.068, 0.062);
        s.gloss = 0.5;
      } else if (mat == 4) {
        s.albedo = PLATINUM;
        s.emit = PLATINUM * 0.1;
        s.gloss = 1.0;
      } else {
        s.albedo = TANGERINE;
        s.emit = TANGERINE * 1.4;
      }
    }
    // Keyfleet
    default {
      if (mat == 1) {
        let ripple = vec3f(
          sin(p.x * 9.0 + t * 1.1) + sin(p.z * 13.0 - t * 0.7),
          0.0,
          sin(p.z * 8.0 + t * 0.9) + sin(p.x * 11.0 + t * 0.6)) * 0.035;
        let wn = normalize(n + ripple);
        let fres = pow(1.0 - max(dot(-rd, wn), 0.0), 3.0);
        let mirror = reflect(rd, wn);
        s.albedo = vec3f(0.003, 0.012, 0.02);
        // The moon is too bright to mirror whole: the swell would scatter it in blots.
        s.emit = min(sky(5, vec3f(mirror.x, abs(mirror.y), mirror.z)), vec3f(0.3)) * (0.1 + 0.5 * fres);
        // The lighthouse lamp, drawn out across the water.
        let toLight = normalize(HARBOUR_LIGHT + vec3f(0.0, 1.45, 0.0) - p);
        s.emit += vec3f(1.0, 0.85, 0.6) * pow(max(dot(mirror, toLight), 0.0), 220.0) * 0.9;
        s.gloss = 1.0;
      } else if (mat == 2) {
        s.albedo = vec3f(0.02, 0.024, 0.03);
      } else if (mat == 3) {
        let band = step(0.5, fract((p.y - HARBOUR_LIGHT.y) * 2.4));
        s.albedo = mix(PLATINUM, TANGERINE, band);
        s.emit = s.albedo * 0.04;
      } else if (mat == 4) {
        s.emit = vec3f(1.0, 0.9, 0.7) * 3.0;
      } else if (mat == 5) {
        s.albedo = GOLD;
        s.emit = GOLD * 0.55;
        s.gloss = 1.0;
      } else if (mat == 6) {
        s.albedo = mix(vec3f(0.05, 0.035, 0.03), PLATINUM * 0.7, step(-0.86, p.y));
      } else {
        s.emit = GOLD * 3.0;
      }
    }
  }
  return s;
}

// How each room is lit, and how far and how hazily a ray may travel in it.
struct Rig {
  key: vec3f,
  keyColor: vec3f,
  fill: vec3f,
  fillColor: vec3f,
  ambient: vec3f,
  haze: vec3f,
  thickness: f32,
  reach: f32,
}

fn rig(room: i32) -> Rig {
  switch room {
    case 0 {
      return Rig(vec3f(0.0, -0.75, -1.0), vec3f(1.0, 0.3, 0.06) * 2.2, vec3f(0.2, 1.4, 0.2), vec3f(0.5, 0.55, 0.75) * 1.6,
        vec3f(0.03, 0.03, 0.04), vec3f(0.05, 0.015, 0.008), 0.07, 9.0);
    }
    case 1 {
      return Rig(vec3f(0.0, 1.5, -1.2), vec3f(0.55, 0.85, 1.0) * 2.4, vec3f(-1.6, -0.5, -0.2), TANGERINE * 1.1,
        vec3f(0.015, 0.03, 0.035), vec3f(0.006, 0.024, 0.03), 0.08, 9.0);
    }
    case 2 {
      return Rig(vec3f(0.0, 1.1, -0.7), vec3f(1.0, 0.8, 0.55) * 2.2, vec3f(0.0, 0.3, 0.8), vec3f(0.6, 0.66, 0.7) * 1.4,
        vec3f(0.1, 0.09, 0.07), vec3f(0.1, 0.085, 0.06), 0.04, 7.0);
    }
    case 3 {
      return Rig(vec3f(-1.5, 2.2, -0.8), vec3f(1.0) * 2.4, SIGNAL_CENTRE, vec3f(1.0) * 0.9,
        vec3f(0.012), vec3f(0.004), 0.03, 16.0);
    }
    case 4 {
      return Rig(vec3f(0.0, 2.3, -0.2), vec3f(1.0, 0.9, 0.74) * 2.8, vec3f(0.0, -0.3, -1.6), TANGERINE * 1.6,
        vec3f(0.035, 0.035, 0.04), vec3f(0.03, 0.022, 0.016), 0.06, 11.0);
    }
    default {
      return Rig(vec3f(-2.6, 2.6, -5.0), vec3f(0.55, 0.7, 1.0) * 5.0, vec3f(-0.3, 0.0, -0.4), GOLD * 0.9,
        vec3f(0.01, 0.018, 0.03), vec3f(0.012, 0.035, 0.055), 0.035, 18.0);
    }
  }
}

fn normalAt(p: vec3f, room: i32) -> vec3f {
  let e = vec2f(0.0015, -0.0015);
  return normalize(
    e.xyy * map(p + e.xyy, room).x + e.yyx * map(p + e.yyx, room).x
    + e.yxy * map(p + e.yxy, room).x + e.xxx * map(p + e.xxx, room).x);
}

fn renderRoom(ro: vec3f, rd: vec3f, room: i32) -> vec3f {
  let g = rig(room);
  var t = 0.02;
  var m = 0.0;
  var glow = vec3f(0.0);
  for (var i = 0; i < 72; i++) {
    let r = map(ro + rd * t, room);
    let stride = clamp(r.x, 0.004, 0.4);
    glow += gEmit * stride * exp(-t * g.thickness);
    if (r.x < 0.0015 * (1.0 + t)) {
      m = r.y;
      break;
    }
    t += stride * 0.92;
    if (t > g.reach) { break; }
  }

  var col: vec3f;
  if (m < 0.5) {
    col = mix(sky(room, rd), g.haze, select(1.0, 0.0, room == 3 || room == 5));
  } else {
    let p = ro + rd * t;
    let n = normalAt(p, room);
    let s = surface(room, m, p, n, rd);
    let open = clamp(map(p + n * 0.12, room).x / 0.12, 0.0, 1.0) * 0.75 + 0.25;
    let toKey = g.key - p;
    let keyD = length(toKey);
    let keyL = toKey / keyD;
    let toFill = g.fill - p;
    let fillD = length(toFill);
    let key = g.keyColor / (1.0 + 0.16 * keyD * keyD);
    let fill = g.fillColor / (1.0 + 0.16 * fillD * fillD);
    let lit = g.ambient + key * max(dot(n, keyL), 0.0) + fill * max(dot(n, toFill / fillD), 0.0);
    let shine = pow(max(dot(n, normalize(keyL - rd)), 0.0), 48.0) * s.gloss;
    col = s.albedo * lit * open + s.emit + key * shine * 0.6;
    col = mix(g.haze, col, exp(-t * g.thickness));
  }
  return col + glow;
}

// ------------------------------------------------------------------ The cube

fn toRoom(face: i32, v: vec3f) -> vec3f {
  switch face {
    case 0 { return vec3f(-v.z, v.y, v.x); }
    case 1 { return vec3f(v.z, v.y, -v.x); }
    case 2 { return vec3f(v.x, -v.z, v.y); }
    case 3 { return vec3f(v.x, v.z, -v.y); }
    case 4 { return v; }
    default { return vec3f(-v.x, v.y, -v.z); }
  }
}

fn raySegment(ro: vec3f, rd: vec3f, a: vec3f, b: vec3f) -> f32 {
  let ab = b - a;
  let ao = ro - a;
  let rdab = dot(rd, ab);
  let denom = dot(ab, ab) - rdab * rdab;
  var s = 0.5;
  if (denom > 1e-5) { s = clamp((dot(ao, ab) - dot(ao, rd) * rdab) / denom, 0.0, 1.0); }
  let on = a + ab * s;
  let t = max(dot(on - ro, rd), 0.0);
  return length(ro + rd * t - on);
}

// How close a ray passes to the nearest of the cube's twelve edges.
fn edgeDistance(ro: vec3f, rd: vec3f) -> f32 {
  var d = 1e3;
  for (var i = 0; i < 4; i++) {
    let u = f32(i & 1) * 2.0 - 1.0;
    let v = f32(i >> 1u) * 2.0 - 1.0;
    d = min(d, raySegment(ro, rd, vec3f(-1.0, u, v), vec3f(1.0, u, v)));
    d = min(d, raySegment(ro, rd, vec3f(u, -1.0, v), vec3f(u, 1.0, v)));
    d = min(d, raySegment(ro, rd, vec3f(u, v, -1.0), vec3f(u, v, 1.0)));
  }
  return d;
}

fn backdrop(sp: vec2f) -> vec3f {
  let r = length(sp);
  var col = mix(vec3f(0.018, 0.02, 0.034), vec3f(0.004, 0.004, 0.007), smoothstep(0.0, 1.9, r));
  let g = sp * 15.0;
  let id = floor(g);
  let h = hash21(id);
  let centre = vec2f(fract(h * 13.7), fract(h * 91.3)) * 0.7 + 0.15;
  let twinkle = 0.65 + 0.35 * sin(params.time * (0.6 + h * 1.6) + h * 50.0);
  col += vec3f(0.8, 0.85, 1.0) * step(0.86, h) * fade(0.05, 0.0, length(fract(g) - centre)) * fract(h * 51.0) * twinkle;
  return col;
}

fn aces(x: vec3f) -> vec3f {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3f(0.0), vec3f(1.0));
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let res = max(params.resolution, vec2f(1.0));
  let sp = vec2f((uv.x - 0.5) * 2.0 * res.x / res.y, (0.5 - uv.y) * 2.0);

  var rd = normalize(vec3f(sp * params.lens, -1.0));
  let yz = rot(params.look.y) * rd.yz;
  let xz = rot(params.look.x) * vec2f(rd.x, yz.y);
  rd = vec3f(xz.x, yz.x, xz.y);
  let eye = vec3f(params.look.x * 0.5, params.look.y * 0.35, params.distance);

  let inverse = vec4f(-params.rotation.xyz, params.rotation.w);
  let ro = qrot(inverse, eye);
  let dir = qrot(inverse, rd);

  let safe = select(dir, vec3f(1e-6), abs(dir) < vec3f(1e-6));
  let t1 = (vec3f(-1.0) - ro) / safe;
  let t2 = (vec3f(1.0) - ro) / safe;
  let near = min(t1, t2);
  let far = max(t1, t2);
  let enter = max(near.x, max(near.y, near.z));
  let leave = min(far.x, min(far.y, far.z));
  let within = all(abs(ro) < vec3f(1.0));

  var col = backdrop(sp);
  if (within) {
    let face = i32(params.face + 0.5);
    col = renderRoom(toRoom(face, ro), toRoom(face, dir), face);
  } else if (enter < leave && enter > 0.0) {
    var face = 4;
    if (near.x >= near.y && near.x >= near.z) {
      face = select(0, 1, dir.x > 0.0);
    } else if (near.y >= near.z) {
      face = select(2, 3, dir.y > 0.0);
    } else {
      face = select(4, 5, dir.z > 0.0);
    }
    let start = toRoom(face, ro + dir * enter);
    let local = toRoom(face, dir);
    col = renderRoom(start, local, face);

    let lit = params.glow * select(0.0, 1.0, i32(params.hover + 0.5) == face && params.hover > -0.5);
    col *= 1.0 + 0.18 * lit;
    // The pane: a little of the night outside rides on the glass at a slant.
    let slant = pow(1.0 - max(-local.z, 0.0), 4.0);
    col = mix(col, vec3f(0.07, 0.085, 0.12), slant * 0.3);
    // The frame, and the light it spills onto the pane beside it.
    let edge = max(abs(start.x), abs(start.y));
    let pixel = 2.0 * params.lens * params.distance / res.y;
    let frame = smoothstep(0.962 - pixel, 0.962 + pixel, edge);
    col += PLATINUM * exp(-(1.0 - edge) * 16.0) * (0.22 + 0.3 * lit);
    col = mix(col, vec3f(1.0, 0.97, 0.84) * (1.5 + 0.8 * lit), frame);
  } else {
    let d = edgeDistance(ro, dir);
    let halo = 0.03 / (d + 0.03);
    col += vec3f(1.0, 0.95, 0.8) * halo * halo * (0.85 + 0.4 * params.glow);
  }

  col = pow(aces(col), vec3f(1.0 / 2.2));
  col += (hash21(uv * res) - 0.5) / 255.0;
  return vec4f(col, 1.0);
}
`
