/**
 * The frosted glass picture, in four shaders.
 *
 * `plant` draws what is behind the glass: one giant tree seen from under its
 * crown with the sky behind it, from close among its boughs out to the whole
 * tree, and on back until it stands in a forest of its own kind. It keeps how
 * far behind the glass each pixel is in the alpha channel. `blur` softens that
 * picture twice over. `wipe` keeps the fog on the pane: wiped away under the
 * visitor's hand, creeping back over a few seconds. `glass` is the pane itself,
 * leaning away from the visitor: its relief bends the view, things far behind
 * it come from the softer pictures, the wire sits inside it and the lamp in
 * front of it clouds and glitters on the surface.
 */

const noise = /* wgsl */ `
fn hash21(p: vec2f) -> f32 {
  var q = fract(p * vec2f(123.34, 456.21));
  q += dot(q, q + 45.32);
  return fract(q.x * q.y);
}

fn hash22(p: vec2f) -> vec2f {
  let n = hash21(p);
  return vec2f(n, hash21(p + vec2f(n * 37.1, 11.7)));
}

fn vnoise(p: vec2f) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  let a = hash21(i);
  let b = hash21(i + vec2f(1.0, 0.0));
  let c = hash21(i + vec2f(0.0, 1.0));
  let d = hash21(i + vec2f(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
`

export const plant = /* wgsl */ `
struct Plant {
  resolution: vec2f,
  shift: vec2f,
  time: f32,
  wind: f32,
  journey: f32,
  zoom: f32,
  leafDark: vec3f,
  leafLight: vec3f,
  leafGlow: vec3f,
  sky: vec3f,
  shade: vec3f,
  bark: vec3f,
  glow: vec3f,
  glowing: f32,
}
@group(0) @binding(0) var<uniform> plant: Plant;

${noise}

/** The height of the trunk, half its thickness, and how far its foot spreads. */
const TRUNK = 1.25;
const TRUNK_GIRTH = 0.17;
const FOOT = 0.3;
/** How many times a bough forks, and the fork its leaves begin at. */
const FORKS = 9;
const LEAFING = 3;
/** Leaves to one unit of height. */
const LEAVES = 36.0;
/** How far from the trunk the visitor starts and ends. */
const CLOSE = 0.9;
const BACK = 3.1;
/** The nearest a bough comes to the visitor, as a share of their distance from the trunk. */
const NEAREST = 0.55;
/** How much of the scene one unit of distance shows. */
const FIELD = 0.9;
/** Where the visitor ends up, among the trees of the forest. */
const FOREST_EYE = vec3f(0.0, 1.35, -9.5);
const NARROW_FOREST_EYE = vec3f(0.0, 1.5, -11.0);
/**
 * The forest's rows of trees, from the farthest to the nearest: how far
 * behind the great tree, how far apart the trees stand, and where the row's
 * first tree stands as a share of that. The last row is in front of the great
 * tree, so it frames it from the sides.
 */
const ROWS = array<vec3f, 4>(
  vec3f(15.0, 4.2, 0.31),
  vec3f(9.0, 4.6, 0.77),
  vec3f(4.5, 5.0, 0.5),
  vec3f(-4.6, 7.4, 0.5),
);

/**
 * The tree's boughs, each leaving the trunk on its own: how high up the trunk,
 * which way (in radians to the right of upright), how long, and half how thick.
 * The first three are in the trunk's own layer; the rest go two to a layer,
 * from the layer farthest behind the trunk to the one nearest the visitor.
 */
const BOUGHS = array<vec4f, 17>(
  vec4f(1.25, -0.62, 1.0, 0.078),
  vec4f(1.25, 0.34, 0.78, 0.066),
  vec4f(0.78, 1.08, 0.72, 0.047),
  vec4f(1.2, 0.8, 0.92, 0.062),
  vec4f(1.25, -0.95, 0.85, 0.058),
  vec4f(1.25, -0.14, 1.05, 0.07),
  vec4f(0.95, -1.1, 0.66, 0.043),
  vec4f(1.2, -0.34, 0.86, 0.062),
  vec4f(1.05, 0.9, 0.7, 0.047),
  vec4f(1.25, 0.16, 0.92, 0.062),
  vec4f(1.1, -0.8, 0.8, 0.051),
  vec4f(1.25, 0.52, 0.76, 0.055),
  vec4f(1.15, -0.46, 0.7, 0.047),
  vec4f(1.2, 1.15, 0.8, 0.035),
  vec4f(1.25, -0.6, 0.9, 0.039),
  vec4f(1.1, 0.7, 0.85, 0.027),
  vec4f(1.2, -1.2, 0.75, 0.023),
);

/**
 * Twenty kinds of leaf.
 * Shape: where it is widest (below 1 towards the stem, above 1 towards the tip),
 * how pointed, how wide for its length, and how long.
 * Edge: how many lobes and how deep, how toothed, and how much it curls to one side.
 * Tone: how light, how warm (below 0 is blue-green, above 0 is yellow-green), and how many side veins.
 */
const SHAPES = array<vec4f, 20>(
  vec4f(0.72, 0.85, 0.3, 0.92), vec4f(0.9, 1.3, 0.11, 1.35), vec4f(1.1, 0.7, 0.34, 1.05), vec4f(0.55, 0.6, 0.5, 0.88),
  vec4f(0.6, 0.5, 0.46, 0.7), vec4f(0.95, 1.0, 0.2, 1.15), vec4f(0.8, 0.9, 0.3, 0.88), vec4f(0.8, 1.2, 0.15, 1.3),
  vec4f(0.5, 0.7, 0.44, 0.75), vec4f(1.5, 0.75, 0.3, 1.2), vec4f(0.6, 1.0, 0.34, 0.6), vec4f(0.9, 0.8, 0.3, 0.85),
  vec4f(1.0, 1.1, 0.14, 0.85), vec4f(0.45, 0.8, 0.48, 0.85), vec4f(0.9, 0.6, 0.5, 1.1), vec4f(0.8, 1.0, 0.24, 0.5),
  vec4f(1.2, 1.0, 0.2, 1.35), vec4f(2.2, 0.45, 0.5, 0.75), vec4f(0.7, 0.55, 0.4, 0.8), vec4f(0.75, 1.1, 0.26, 1.35),
);
const EDGES = array<vec4f, 20>(
  vec4f(0.0, 0.0, 0.0, 0.0), vec4f(0.0, 0.0, 0.0, 0.25), vec4f(4.0, 0.42, 0.0, 0.0), vec4f(2.5, 0.6, 0.15, 0.0),
  vec4f(0.0, 0.0, 0.12, 0.0), vec4f(0.0, 0.0, 0.0, 0.1), vec4f(0.0, 0.0, 0.3, 0.08), vec4f(0.0, 0.0, 0.0, 0.6),
  vec4f(1.5, 0.5, 0.0, 0.0), vec4f(0.0, 0.0, 0.0, 0.0), vec4f(0.0, 0.0, 0.25, 0.0), vec4f(5.0, 0.3, 0.2, 0.0),
  vec4f(0.0, 0.0, 0.0, 0.0), vec4f(0.0, 0.0, 0.1, 0.0), vec4f(2.0, 0.5, 0.0, 0.0), vec4f(0.0, 0.0, 0.0, 0.0),
  vec4f(0.0, 0.0, 0.3, 0.0), vec4f(1.0, 0.25, 0.0, 0.0), vec4f(0.0, 0.0, 0.0, 0.0), vec4f(9.0, 0.55, 0.0, 0.15),
);
const TONES = array<vec3f, 20>(
  vec3f(0.55, 0.1, 9.0), vec3f(0.7, 0.3, 0.0), vec3f(0.3, 0.2, 5.0), vec3f(0.6, 0.5, 4.0),
  vec3f(0.75, 0.35, 7.0), vec3f(0.1, -0.2, 0.0), vec3f(0.4, 0.0, 12.0), vec3f(0.5, -0.6, 0.0),
  vec3f(0.15, -0.1, 4.0), vec3f(0.35, -0.15, 8.0), vec3f(0.8, 0.45, 9.0), vec3f(0.05, -0.3, 0.0),
  vec3f(0.45, -0.7, 0.0), vec3f(0.65, 0.2, 6.0), vec3f(0.25, 0.05, 3.0), vec3f(0.95, 0.8, 0.0),
  vec3f(0.3, 0.1, 14.0), vec3f(0.85, 0.7, 16.0), vec3f(0.08, -0.1, 5.0), vec3f(0.45, 0.25, 0.0),
);

struct Tree {
  /** How far to the surface of the wood, and how leafy this place is. */
  wood: f32,
  leafy: f32,
  /** Where on the nearest limb this is: how far across from its middle, half how thick it is there, and how far along from the foot of the tree. */
  across: f32,
  girth: f32,
  along: f32,
}

struct Foliage {
  colour: vec3f,
  alpha: f32,
}

fn turned(q: vec2f, angle: f32) -> vec2f {
  let cs = cos(angle);
  let sn = sin(angle);
  return vec2f(q.x * cs - q.y * sn, q.x * sn + q.y * cs);
}

/** Four chance numbers for one limb, told apart by the turns taken to reach it. */
fn chance(path: f32, seed: f32) -> vec4f {
  return fract(hash21(vec2f(path, seed)) * vec4f(1.0, 37.7, 291.3, 1733.1));
}

fn joined(a: Tree, b: Tree) -> Tree {
  var both: Tree;
  let nearer = a.wood < b.wood;
  both.wood = min(a.wood, b.wood);
  both.leafy = max(a.leafy, b.leafy);
  both.across = select(b.across, a.across, nearer);
  both.girth = select(b.girth, a.girth, nearer);
  both.along = select(b.along, a.along, nearer);
  return both;
}

/**
 * One bough and everything that grows from it. Every fork folds the picture in
 * half, so one limb drawn a few times over is the whole bough, but the two
 * sides of each fork open by their own angles and grow to their own lengths,
 * so no two limbs match. Each limb is a little thinner than the one it grew
 * from, down to twigs as fine as a hair, and it bends twice along its length.
 * The last two forks are too fine to draw, and only carry leaves.
 */
fn bough(at: vec2f, base: vec2f, angle: f32, len: f32, girth: f32, seed: f32, start: f32) -> Tree {
  var q = turned(at - base, angle) / len;
  var unit = len;
  var path = 1.0;
  var run = start;
  var slim = girth / len;
  var twig = 1000.0;
  var grown: Tree;
  grown.wood = 1000.0;
  grown.across = 0.0;
  grown.girth = 1.0;
  grown.along = 0.0;
  var r = chance(path, seed);
  for (var i = 0; i < FORKS; i++) {
    let level = f32(i);
    let h = clamp(q.y, 0.0, 1.0);
    // A long bow one way, and a shorter kink on top of it.
    let bend = sin(h * 3.14159265) * (r.x - 0.5) * 0.3
      + sin(h * 3.14159265) * sin(h * 8.0 + r.w * 20.0) * 0.045;
    let across = q.x - bend;
    let thick = slim * (1.0 - 0.35 * h);
    let d = (length(vec2f(across, q.y - h)) - thick) * unit;
    if (i < FORKS - 2 && d < grown.wood) {
      grown.wood = d;
      grown.across = across * unit;
      grown.girth = thick * unit;
      grown.along = run + h * unit;
    }
    if (i >= LEAFING) { twig = min(twig, d); }
    q.y -= 1.0;
    run += unit;
    // The fork leans to one side as a whole and sways as a whole. Then each side
    // opens by its own angle and grows to its own length.
    let lean = (r.y - 0.5) * 0.5
      + sin(plant.time * 0.5 + seed * 9.0 + level * 1.7) * 0.01 * level * plant.wind;
    q = turned(q, lean);
    path = path * 2.0 + step(0.0, q.x);
    r = chance(path, seed);
    let shrink = 0.62 + 0.2 * r.w;
    q.x = abs(q.x);
    q = turned(q, 0.3 + 0.5 * r.z) / shrink;
    unit *= shrink;
    // A limb starts nine tenths as thick as the end of the one it grew from.
    slim *= 0.585 / shrink;
  }
  grown.leafy = 1.0 - smoothstep(0.05, 0.25, min(twig, length(q) * unit));
  return grown;
}

/** Where the middle of the trunk is at each height: it does not grow straight. */
fn spine(y: f32) -> f32 {
  return 0.1 * sin(y * 2.4 + 0.5) - 0.048;
}

/** The trunk. Its foot spreads more to one side than the other, and goes on down out of sight. */
fn trunk(at: vec2f) -> Tree {
  let y = min(at.y, TRUNK);
  let across = at.x - spine(y);
  let girth = TRUNK_GIRTH * (1.0 - 0.3 * max(y, 0.0) / TRUNK)
    + FOOT * exp(-max(y, 0.0) * 7.0) * (1.0 + 0.4 * sign(across));
  var stem: Tree;
  stem.wood = length(vec2f(across, at.y - y)) - girth;
  stem.leafy = 0.0;
  stem.across = across;
  stem.girth = girth;
  stem.along = y;
  return stem;
}

/** Distance to a leaf of one kind lying along x from its stem at 0 to its tip at len. */
fn leafShape(q: vec2f, len: f32, shape: vec4f, edge: vec4f) -> f32 {
  let u = clamp(q.x / len, 0.0, 1.0);
  let curl = edge.w * len * 0.35 * sin(u * 3.14159265);
  // At the very tip the sine can round to just under nothing, which no power can take.
  var profile = shape.z * len * pow(max(sin(3.14159265 * pow(u, shape.x)), 0.0), shape.y);
  profile *= 1.0 - edge.y * (0.5 - 0.5 * cos(6.2831853 * edge.x * u));
  profile *= 1.0 - edge.z * abs(fract(u * 14.0) - 0.5);
  return max(abs(q.y - curl) - profile, max(-q.x, q.x - len));
}

/** A leaf's colour: its kind sets how light and how warm it is, and each leaf differs a little from the next. */
fn leafColour(tone: vec3f, luck: f32) -> vec3f {
  var c = mix(plant.leafDark, plant.leafLight, clamp(tone.x + (luck - 0.5) * 0.3, 0.0, 1.0));
  c = mix(c, vec3f(0.74, 0.7, 0.2), max(tone.y, 0.0) * 0.5);
  return mix(c, vec3f(0.1, 0.4, 0.34), max(-tone.y, 0.0) * 0.6);
}

/**
 * The leaves of one layer: more of them come out the leafier the place is,
 * but never so many that no sky shows between them. Kinds grow in patches,
 * with strays of other kinds among them.
 */
fn foliage(p: vec2f, index: f32, soft: f32, leafy: f32) -> Foliage {
  let offset = vec2f(index * 7.31, index * 3.17);
  let g = p * LEAVES + offset;
  let cell = floor(g);
  var leaves: Foliage;
  leaves.colour = vec3f(0.0);
  leaves.alpha = 0.0;
  for (var j = -1; j <= 1; j++) {
    for (var i = -1; i <= 1; i++) {
      let id = cell + vec2f(f32(i), f32(j));
      let r = hash22(id + index * 17.3);
      let s = hash22(id * 1.7 + index * 5.1 + 3.3);
      let out = smoothstep(s.y * 1.25, s.y * 1.25 + 0.06, leafy);
      if (out <= 0.0) { continue; }
      let place = (id + 0.5 - offset) / LEAVES;
      let kind = u32(fract(vnoise(place * 1.6 + index * 4.1) * 3.0 + r.y * 0.3) * 20.0) % 20u;
      let shape = SHAPES[kind];
      let edge = EDGES[kind];
      let tone = TONES[kind];
      let centre = id + 0.5 + (r - 0.5) * 0.9;
      let sway = (sin(plant.time * (0.5 + r.x * 0.9) + r.y * 6.2831853) * 0.17
        + sin(plant.time * 0.27 + place.x * 3.0 + place.y * 2.0) * 0.11) * plant.wind;
      let angle = (vnoise(place * 2.4 + index) * 2.0 - 1.0) * 2.6 + (s.x - 0.5) * 1.7 + sway;
      let len = shape.w * (0.9 + 0.35 * r.x);
      let d = g - centre;
      let cs = cos(angle);
      let sn = sin(angle);
      let q = vec2f(cs * d.x + sn * d.y, -sn * d.x + cs * d.y) + vec2f(len * 0.5, 0.0);
      let dist = leafShape(q, len, shape, edge);
      let m = (1.0 - smoothstep(-soft, soft, dist)) * out;
      let wid = shape.z * len;
      let across = q.y / wid;
      let along = q.x / len;
      let rib = 1.0 - smoothstep(0.0, 0.03 + soft, abs(q.y));
      let vein = (1.0 - smoothstep(0.0, 0.2 + soft, abs(fract((along + abs(across) * 0.45) * tone.z) - 0.5))) * step(0.5, tone.z);
      var c = leafColour(tone, s.x) * (0.9 + 0.2 * along);
      c *= 0.82 + 0.26 * across;
      c = mix(c, c * 1.4 + 0.02, max(rib * 0.45, vein * 0.16));
      leaves.colour = leaves.colour * (1.0 - m) + c * m;
      leaves.alpha = leaves.alpha * (1.0 - m) + m;
    }
  }
  return leaves;
}

/**
 * Vines hanging in the crown: a thin stem that wanders as it drops and swings
 * in the wind, with small heart-shaped leaves down both sides.
 */
fn vines(at: vec2f, index: f32, soft: f32) -> Foliage {
  let gap = 0.17;
  let pitch = 0.04;
  let column = floor(at.x / gap);
  var hung: Foliage;
  hung.colour = vec3f(0.0);
  hung.alpha = 0.0;
  for (var i = -1; i <= 1; i++) {
    let id = column + f32(i);
    let r = hash22(vec2f(id, index * 7.7 + 1.3));
    let s = hash22(vec2f(id * 1.3 + 2.0, index * 3.1));
    let x0 = (id + 0.5 + (r.x - 0.5) * 0.7) * gap;
    // A vine starts somewhere inside the crown, which is lower towards its sides. Some places have none.
    let top = 1.75 + 1.6 * s.x - 0.16 * x0 * x0;
    let len = 0.35 + 0.8 * s.y;
    let t = top - at.y;
    if (r.y > 0.7 || abs(x0) > 2.3 || t < 0.0 || t > len) { continue; }
    let swing = sin(plant.time * 0.7 + id * 2.1) * 0.05 * plant.wind * t;
    let x = x0 + 0.025 * sin(t * 11.0 + r.x * 20.0) + swing;
    let thin = 0.005 * (1.0 - 0.5 * t / len);
    let stem = 1.0 - smoothstep(thin - soft, thin + soft, abs(at.x - x));
    let green = leafColour(vec3f(0.12 + 0.3 * s.x, -0.15, 0.0), r.x);
    hung.colour = mix(hung.colour, green * 0.7, stem);
    hung.alpha = max(hung.alpha, stem);
    // The two leaves nearest this height, on alternate sides of the stem.
    let rung = floor(t / pitch);
    for (var j = 0; j <= 1; j++) {
      let n = rung + f32(j);
      let down = (n + 0.5) * pitch;
      if (down > len) { continue; }
      let side = 1.0 - 2.0 * (n % 2.0);
      let stemX = x0 + 0.025 * sin(down * 11.0 + r.x * 20.0) + sin(plant.time * 0.7 + id * 2.1) * 0.05 * plant.wind * down;
      let off = at - vec2f(stemX, top - down);
      // Each leaf points out and down from the stem.
      let q = turned(vec2f(off.x * side, off.y), -0.55 - 0.3 * hash21(vec2f(n, id)));
      let size = 0.024 * (1.0 - 0.4 * down / len);
      let dist = leafShape(q, size, SHAPES[13], EDGES[13]);
      let m = 1.0 - smoothstep(-soft, soft, dist);
      hung.colour = mix(hung.colour, green * (0.8 + 0.5 * q.x / size), m);
      hung.alpha = max(hung.alpha, m);
    }
  }
  return hung;
}

/**
 * A leaf with the sky behind it glows yellow-green as the light comes through
 * it; one with other leaves or wood behind it shows its own darker green.
 */
fn lit(leaf: vec3f, light: f32) -> vec3f {
  return mix(leaf * 0.45, mix(leaf, plant.leafGlow, 0.5) * 1.3, light);
}

/** A spray of leaves seen as one mass, darker or lighter by how thick it is, and flecked with the wood's light where it glows. */
fn leafMass(clump: f32) -> vec3f {
  let green = mix(plant.leafDark, plant.leafLight, smoothstep(0.3, 0.75, clump));
  return green + plant.glow * plant.glowing * 0.22 * smoothstep(0.6, 0.85, clump);
}

/**
 * Wood against the sky is nearly black. A thick limb shows its bark: rough
 * furrows along its length, mossy in patches, and caught here and there by
 * the sun. A thin one is too fine to show any. Where the wood glows, the light
 * runs brightest down the middle of each limb.
 */
fn barkColour(limbs: Tree, at: vec2f, pixel: f32, index: f32, out: f32) -> vec3f {
  let side = limbs.across / limbs.girth;
  let rough = smoothstep(2.0, 10.0, limbs.girth / pixel);
  let furrow = abs(vnoise(vec2f(side * 6.0 + index, limbs.along * 9.0)) * 2.0 - 1.0) * 0.7
    + vnoise(vec2f(side * 15.0, limbs.along * 34.0 + index)) * 0.3;
  let ridge = mix(0.4, furrow, rough);
  var timber = plant.bark * (0.3 + 1.5 * ridge) * (0.75 + 0.35 * (1.0 - side * side));
  // From far off the trunk reads paler: more of it is moss and lichen.
  timber = mix(timber, vec3f(0.2, 0.24, 0.1) * (0.4 + ridge), mix(0.5, 0.9, out) * rough * smoothstep(mix(0.45, 0.2, out), 0.75, vnoise(at * 4.0 + index * 7.0)));
  timber += vec3f(0.45, 0.38, 0.15) * ridge * ridge * rough * smoothstep(0.55, 0.8, vnoise(at * 3.1 + index * 2.0 + 11.0)) * 0.5;
  // A twig glows across its whole width; a bough only along a thin core, with a dim body round it.
  let core = exp(-side * side * mix(1.0, 18.0, rough));
  let vein = plant.glow * (0.1 + 0.85 * core) * (0.8 + 0.4 * (1.0 - ridge));
  return mix(timber, vein, plant.glowing);
}

/** How much of a limb a pixel covers. Glowing wood spreads its light a little past its edge, so the finest twigs still show. */
fn woodCover(wood: f32, pixel: f32) -> f32 {
  return 1.0 - smoothstep(-pixel, pixel * (1.0 + 1.5 * plant.glowing), wood);
}

/**
 * The whole tree in one layer, as a tree of the forest is seen from far off:
 * the same trunk and boughs as the great tree, every bough at the trunk's
 * distance. A bough too far from this place to reach it is passed over.
 */
fn grove(at: vec2f) -> Tree {
  var whole = trunk(at);
  if (abs(at.x) > 4.0 || at.y > 4.8) { return whole; }
  for (var b = 0; b < 17; b++) {
    let limb = BOUGHS[b];
    let base = vec2f(spine(limb.x), limb.x);
    if (length(at - base) > limb.z * 3.8) { continue; }
    let narrow = select(0.8, 1.0, b < 3);
    let place = vec2f((at.x - base.x) / narrow, at.y - base.y);
    whole = joined(whole, bough(place, vec2f(0.0), limb.y, limb.z, limb.w, f32(b) * 0.37 + 0.11, limb.x));
  }
  return whole;
}

/**
 * One tree of a forest row, its own size and facing its own way, standing a
 * little off the middle of its place in the row. A row never puts a tree
 * where the great tree stands.
 */
fn rowTree(at: vec2f, k: f32, row: vec3f, index: f32, pixel: f32, light: f32) -> Foliage {
  var seen: Foliage;
  seen.colour = vec3f(0.0);
  seen.alpha = 0.0;
  let centre = (k + row.z) * row.y;
  if (abs(centre) < 1.5 && row.x < 0.0) { return seen; }
  let luck = hash22(vec2f(k, index * 13.1 + 2.0));
  let size = 0.78 + 0.4 * luck.x;
  let facing = select(-1.0, 1.0, luck.y > 0.5);
  let local = vec2f((at.x - centre - 0.3 * (luck.y - 0.5) * row.y) * facing, at.y) / size;
  let limbs = grove(local);
  let fine = pixel / size;
  if (limbs.leafy > 0.0) {
    let clump = 0.55 * vnoise(local * 5.0 + index * 3.3) + 0.45 * vnoise(local * 27.0 + index * 1.7);
    seen.alpha = smoothstep(0.34, 0.5, limbs.leafy * (0.15 + 1.1 * clump));
    seen.colour = lit(leafMass(clump), light);
  }
  let wood = woodCover(limbs.wood, fine);
  seen.colour = mix(seen.colour, barkColour(limbs, local, fine, index, 1.0), wood);
  seen.alpha = max(seen.alpha, wood);
  return seen;
}

/**
 * One row of the forest: the two trees of the row either side of this place,
 * since a crown reaches past the middle of the gap to the next, and the ground
 * the row stands on.
 */
fn forestRow(eye: vec3f, ray: vec2f, row: vec3f, index: f32, light: f32) -> Foliage {
  var seen: Foliage;
  seen.colour = vec3f(0.0);
  seen.alpha = 0.0;
  let away = row.x - eye.z;
  if (away < 1.0) { return seen; }
  let at = eye.xy + ray * away;
  let pixel = away * FIELD / (plant.resolution.y * plant.zoom);
  let left = floor(at.x / row.y - row.z);
  for (var side = 0; side < 2; side++) {
    let tree = rowTree(at, left + f32(side), row, index, pixel, light);
    // The second tree over the first.
    let alpha = tree.alpha + seen.alpha * (1.0 - tree.alpha);
    seen.colour = (tree.colour * tree.alpha + seen.colour * seen.alpha * (1.0 - tree.alpha)) / max(alpha, 1e-4);
    seen.alpha = alpha;
  }
  // The ground the row stands on hides the feet of every row behind it.
  let ground = smoothstep(pixel, -pixel, at.y);
  let soil = mix(plant.shade, plant.leafDark, 0.5) * (0.7 + 0.6 * vnoise(at * vec2f(2.0, 9.0) + index));
  seen.colour = mix(seen.colour, soil, ground);
  seen.alpha = max(seen.alpha, ground);
  // Farther rows fade into the air between them and the visitor.
  seen.colour = mix(plant.sky * 0.92, seen.colour, exp(-away * 0.035));
  return seen;
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let aspect = plant.resolution.x / plant.resolution.y;
  // The window sees the middle of this picture, so the scene is framed for that part.
  let view = (uv - 0.5) / plant.zoom;
  // The journey: from close among the boughs at the top of the trunk, outwards
  // and downwards to the foot of the tree, looking up into the whole crown, and
  // then on back through the trees round it until it is one of a forest.
  // Looking about moves the eye a little.
  let toTree = clamp(plant.journey * 2.0, 0.0, 1.0);
  let toForest = clamp(plant.journey * 2.0 - 1.0, 0.0, 1.0);
  let out = toTree * toTree * (3.0 - 2.0 * toTree);
  let wide = toForest * toForest * (3.0 - 2.0 * toForest);
  let tree = vec3f(mix(0.5, 0.0, out), mix(1.5, 0.6, out), -mix(CLOSE, BACK, out));
  // A tall, narrow window stands a little farther back in a closer-set forest, so it still sees trees on either side.
  let slender = clamp((1.1 - aspect) / 0.65, 0.0, 1.0);
  let forest = mix(FOREST_EYE, NARROW_FOREST_EYE, slender);
  let closer = vec3f(1.0, mix(1.0, 0.6, slender), 1.0);
  let eye = mix(tree, forest, wide) + vec3f(plant.shift.x * 0.05, -plant.shift.y * 0.03, 0.0);
  // The lower the visitor stands, the more they look up; among the trees they look ahead again.
  let lift = mix(mix(0.0, 0.45, out), mix(0.16, 0.12, slender), wide);
  // How far across and up the scene this pixel looks, for each unit of distance.
  let ray = vec2f(view.x * aspect, lift - view.y) * FIELD;

  // A bright sky behind everything, brightest where the sun stands, and the
  // shade of the undergrowth low down beside the trunk.
  let cloud = 0.92 + 0.12 * vnoise(vec2f(view.x * aspect, view.y) * 1.3 + vec2f(plant.time * 0.02, 0.0));
  let sun = exp(-dot(ray - vec2f(0.35, 0.55), ray - vec2f(0.35, 0.55)) * 2.5);
  let sky = plant.sky * cloud * (1.0 + 0.14 * sun) * (1.0 - 0.12 * wide);
  let low = eye.y - ray.y * eye.z;
  var colour = mix(sky, mix(plant.shade, plant.leafDark, 0.5), smoothstep(0.5, -0.4, low));
  var depth = 1.0;
  // How much of the sky's light still comes through from behind.
  // Less of it reaches the foot of the tree than its crown.
  // Seen from outside the crown, among other trees, the leaves are lit from the sky in front of them too.
  var light = mix(smoothstep(-0.4, 0.5, low) * mix(1.0, 0.7, out), 0.9, wide);
  let shading = 1.0 - 0.75 * wide;
  // Stepping back, the glass's sharpness reaches farther, so the forest is more than a blur.
  let focus = mix(40.0, 90.0, wide);

  // The forest behind the great tree comes out of the air as the visitor steps back.
  if (wide > 0.0) {
    for (var r = 0; r < 3; r++) {
      let row = forestRow(eye, ray, ROWS[r] * closer, f32(r) + 8.0, 0.6);
      let shown = row.alpha * smoothstep(0.0, 0.7, wide);
      colour = mix(colour, row.colour, shown);
      depth = mix(depth, clamp((ROWS[r].x - eye.z - 0.7) / focus, 0.0, 1.0), shown);
    }
  }

  // The tree in eight layers, from the farthest to the nearest: boughs reaching
  // away from the visitor, the trunk in the middle, and boughs reaching towards
  // them. However close the visitor stands, a bough is never much nearer to
  // them than the trunk is, so none is ever behind them.
  var layers = array<f32, 8>(1.8, 1.1, 0.55, 0.0, -0.5, -1.0, -1.6, -2.2);
  for (var k = 0; k < 8; k++) {
    let away = max(layers[k] - eye.z, NEAREST * -eye.z);
    let index = f32(k);
    let at = eye.xy + ray * away;
    let pixel = away * FIELD / (plant.resolution.y * plant.zoom);
    let near = exp(-away * 0.03);
    let behind = clamp((away - 0.7) / focus, 0.0, 1.0);
    // Nothing in a tree grows straight: the whole layer is pulled a little out of true.
    let gnarl = (vec2f(vnoise(at * 2.3 + index * 5.0), vnoise(at * 2.3 + index * 5.0 + 31.7)) - 0.5) * 0.1;
    let grown = at + gnarl;
    // A bough is as far away as its layer, but it leaves the trunk where the
    // trunk is seen to be: nearer boughs are larger, not somewhere else.
    let scale = away / -eye.z;
    // Reaching towards or away from the visitor, a bough looks shorter across.
    let narrow = select(0.66 + 0.05 * index, 1.0, k == 3);
    var limbs: Tree;
    var first = 0;
    var count = 3;
    if (k == 3) {
      limbs = trunk(grown);
    } else {
      first = select(2 * k + 3, 2 * k + 1, k > 3);
      count = 2;
      limbs.wood = 1000.0;
      limbs.leafy = 0.0;
      limbs.across = 0.0;
      limbs.girth = 1.0;
      limbs.along = 0.0;
    }
    for (var b = first; b < first + count; b++) {
      let limb = BOUGHS[b];
      let base = eye.xy + (vec2f(spine(limb.x), limb.x) - eye.xy) * scale;
      let place = vec2f((grown.x - base.x) / narrow, grown.y - base.y);
      limbs = joined(limbs, bough(place, vec2f(0.0), limb.y, limb.z, limb.w, f32(b) * 0.37 + 0.11, limb.x));
    }

    let soft = max(0.05, pixel * LEAVES * 1.5);
    // From far off single leaves are too small to tell apart, and each spray of
    // them is one mass with gaps the sky shows through.
    let far = smoothstep(0.03, 0.2, pixel * LEAVES);
    if (limbs.leafy > 0.0) {
      let clump = 0.55 * vnoise(at * 5.0 + index * 3.3) + 0.45 * vnoise(at * 27.0 + index * 1.7);
      let mass = smoothstep(0.34, 0.5, limbs.leafy * (0.15 + 1.1 * clump)) * far;
      colour = mix(colour, mix(sky, lit(leafMass(clump), light), near), mass);
      depth = mix(depth, behind, mass);
      light *= 1.0 - 0.4 * mass * shading;

      // Seen from under the crown, the leaves are above the limbs that carry them.
      let back = foliage(at, index * 2.0, soft, limbs.leafy);
      var shown = back.alpha;
      colour = mix(colour, mix(sky, lit(back.colour, light), near), shown);
      depth = mix(depth, behind, shown);
      light *= 1.0 - 0.45 * shown * shading;

      let front = foliage(at, index * 2.0 + 1.0, soft, limbs.leafy * 0.6);
      shown = front.alpha;
      colour = mix(colour, mix(sky, lit(front.colour, light), near), shown);
      depth = mix(depth, behind, shown);
      light *= 1.0 - 0.45 * shown * shading;
    }

    let wood = woodCover(limbs.wood, pixel);
    colour = mix(colour, mix(sky, barkColour(limbs, at, pixel, index, out), near), wood);
    depth = mix(depth, behind, wood);
    light *= 1.0 - wood * shading;

    // Vines are too fine to see from far off.
    if (far < 1.0) {
      let hung = vines(at, index, pixel * 1.5);
      let shown = hung.alpha * (1.0 - far) * (1.0 - plant.glowing);
      colour = mix(colour, mix(sky, lit(hung.colour, light), near), shown);
      depth = mix(depth, behind, shown);
    }
  }

  // The nearest row of the forest stands between the visitor and the great tree, to either side of it.
  if (wide > 0.0) {
    let row = forestRow(eye, ray, ROWS[3] * closer, 11.0, 0.45);
    let shown = row.alpha * smoothstep(0.35, 1.0, wide);
    colour = mix(colour, row.colour, shown);
    depth = mix(depth, clamp((ROWS[3].x - eye.z - 0.7) / focus, 0.0, 1.0), shown);
  }
  return vec4f(colour, depth);
}
`

/**
 * The fog on the pane, one value to a pixel of the window: 1 where it is
 * thick, 0 where it was wiped. Each frame it creeps back a little, and the
 * stretch the hand crossed since the last frame is wiped clean again.
 */
export const wipe = /* wgsl */ `
struct Wipe {
  startAt: vec2f,
  endAt: vec2f,
  aspect: f32,
  radius: f32,
  creep: f32,
  fresh: f32,
}
@group(0) @binding(0) var<uniform> wipe: Wipe;
@group(0) @binding(1) var fog: texture_2d<f32>;
@group(0) @binding(2) var fogSampler: sampler;

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let before = select(textureSampleLevel(fog, fogSampler, uv, 0.0).r, 1.0, wipe.fresh > 0.5);
  let scale = vec2f(wipe.aspect, 1.0);
  let p = uv * scale;
  let a = wipe.startAt * scale;
  let b = wipe.endAt * scale;
  let line = b - a;
  let along = clamp(dot(p - a, line) / max(dot(line, line), 1e-6), 0.0, 1.0);
  let gap = length(p - a - line * along);
  let left = min(min(before + wipe.creep, 1.0), smoothstep(wipe.radius * 0.45, wipe.radius, gap));
  return vec4f(left, left, left, 1.0);
}
`

export const blur = /* wgsl */ `
struct Blur {
  stride: vec2f,
}
@group(0) @binding(0) var<uniform> blur: Blur;
@group(0) @binding(1) var src: texture_2d<f32>;
@group(0) @binding(2) var srcSampler: sampler;

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  var sum = textureSampleLevel(src, srcSampler, uv, 0.0) * 0.2270270270;
  sum += (textureSampleLevel(src, srcSampler, uv + blur.stride * 1.3846153846, 0.0)
    + textureSampleLevel(src, srcSampler, uv - blur.stride * 1.3846153846, 0.0)) * 0.3162162162;
  sum += (textureSampleLevel(src, srcSampler, uv + blur.stride * 3.2307692308, 0.0)
    + textureSampleLevel(src, srcSampler, uv - blur.stride * 3.2307692308, 0.0)) * 0.0702702703;
  return sum;
}
`

export const glass = /* wgsl */ `
struct Glass {
  resolution: vec2f,
  light: vec2f,
  across: vec3f,
  down: vec3f,
  facing: vec3f,
  eye: f32,
  zoom: f32,
  time: f32,
  lightHeight: f32,
  lightPower: f32,
  pebble: f32,
  bump: f32,
  bend: f32,
  frost: f32,
  cells: f32,
  wire: f32,
  wireWidth: f32,
  wireTone: f32,
  wireWander: f32,
  veil: f32,
  sparkle: f32,
  grain: f32,
  room: f32,
  scatter: f32,
  surface: f32,
  mist: f32,
  bloom: f32,
  milk: vec3f,
}
@group(0) @binding(0) var<uniform> glass: Glass;
@group(0) @binding(1) var sharp: texture_2d<f32>;
@group(0) @binding(2) var soft: texture_2d<f32>;
@group(0) @binding(3) var softer: texture_2d<f32>;
@group(0) @binding(4) var fog: texture_2d<f32>;
@group(0) @binding(5) var glassSampler: sampler;

${noise}

/** Rounded bumps: a soft hill round one scattered point in every cell. */
fn pebbles(p: vec2f) -> f32 {
  let cell = floor(p);
  let f = fract(p);
  var sum = 0.0;
  for (var j = -1; j <= 1; j++) {
    for (var i = -1; i <= 1; i++) {
      let b = vec2f(f32(i), f32(j));
      let r = b - f + hash22(cell + b);
      sum += exp(-5.5 * dot(r, r));
    }
  }
  return sum;
}

fn relief(p: vec2f) -> f32 {
  return pebbles(p) * 0.7 + pebbles(p * 2.3 + 7.7) * 0.12 + vnoise(p * 0.3) * 0.5;
}

/** The tilt of pebbled glass at a place on the pane. */
fn pebbled(p: vec2f) -> vec2f {
  let pp = p * glass.pebble;
  let e = 0.07;
  let h = relief(pp);
  return -vec2f(relief(pp + vec2f(e, 0.0)) - h, relief(pp + vec2f(0.0, e)) - h) / e * glass.bump;
}

/**
 * The tilt of the surface. Reeds are narrow upright lenses, each rounded from
 * edge to edge, so each squeezes its own strip of what is behind. Bricks are
 * flat in the middle and round off towards their joints, so each one shows
 * its own piece of the view, pulled in from its edges.
 */
fn surfaceTilt(p: vec2f) -> vec2f {
  if (glass.surface < 0.5) {
    return pebbled(p);
  }
  if (glass.surface < 1.5) {
    let across = fract(p.x * glass.cells) - 0.5;
    let wobble = (vnoise(vec2f(p.x * glass.cells, p.y * 3.0)) - 0.5) * 0.25;
    return vec2f(-across * 2.0 * glass.bump + wobble, 0.0) + pebbled(p) * 0.08;
  }
  let local = fract(p * glass.cells) - 0.5;
  let rim = smoothstep(vec2f(0.22), vec2f(0.5), abs(local));
  return -local * 2.0 * glass.bump * (0.35 + 0.65 * rim) + pebbled(p) * 0.1;
}

/** The tree at one place, from the sharper or the softer pictures of it. */
fn behind(at: vec2f, blurred: f32) -> vec3f {
  let close = mix(
    textureSampleLevel(sharp, glassSampler, at, 0.0).rgb,
    textureSampleLevel(soft, glassSampler, at, 0.0).rgb,
    smoothstep(0.0, 0.45, blurred),
  );
  return mix(close, textureSampleLevel(softer, glassSampler, at, 0.0).rgb, smoothstep(0.4, 1.0, blurred));
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let aspect = glass.resolution.x / glass.resolution.y;
  // The pane leans away from the visitor. Where this pixel of the window meets
  // it, in window heights from the pane's middle, and as a share of the picture behind.
  let ray = vec3f((uv.x - 0.5) * aspect, uv.y - 0.5, glass.eye);
  let hit = vec3f(0.0, 0.0, -glass.eye) + ray * (glass.facing.z * glass.eye / dot(glass.facing, ray));
  let p = vec2f(dot(hit, glass.across), dot(hit, glass.down));
  let st = vec2f(p.x / aspect, p.y) * glass.zoom + 0.5;
  // How much of the pane one pixel covers here: more where the pane is farther off.
  let pixel = length(fwidth(p)) * 0.7;

  // The surface: pebbles, reeds or bricks.
  let tilt = surfaceTilt(p);
  let n = normalize(vec3f(tilt, 1.0));

  // Fog on the pane, where it has not been wiped away.
  let fogged = glass.mist * textureSampleLevel(fog, glassSampler, uv, 0.0).r;

  // Behind the glass. The surface bends the view more the farther back it
  // reaches, and far things come from the softer pictures. Fog softens all of it.
  let before = textureSampleLevel(soft, glassSampler, st, 0.0).a;
  let reach = glass.bend * (0.3 + 0.7 * before) * glass.zoom;
  let at = st + vec2f(n.x / aspect, n.y) * reach;
  let depth = textureSampleLevel(soft, glassSampler, at, 0.0).a;
  let clear = clamp(depth * 1.1 + glass.frost, 0.0, 1.0);
  let blurred = mix(mix(clear, depth * 0.5, glass.mist), 0.8, fogged);
  // Frost scatters each ray a little: three more looks round the first, turned differently at every pixel.
  let spin = hash21(uv * glass.resolution) * 6.2831853;
  let spread = glass.scatter * glass.zoom * (0.35 + 0.65 * depth) * (1.0 + 1.5 * fogged);
  var colour = behind(at, blurred) * 0.4;
  for (var k = 0; k < 3; k++) {
    let turn = spin + f32(k) * 2.0943951;
    colour += behind(at + vec2f(cos(turn) / aspect, sin(turn)) * spread, blurred) * 0.2;
  }
  // Glowing wood haloes through the glass.
  colour += textureSampleLevel(softer, glassSampler, at, 0.0).rgb * glass.bloom;

  // The lamp, in front of the glass.
  let here = vec3f(p, 0.0);
  let lamp = vec3f((glass.light.x - 0.5) * aspect, glass.light.y - 0.5, glass.lightHeight);
  let toLamp = lamp - here;
  let fall = glass.lightHeight * glass.lightHeight / dot(toLamp, toLamp);
  let halfway = normalize(normalize(toLamp) + vec3f(0.0, 0.0, 1.0));
  let facing = max(dot(n, halfway), 0.0);
  let power = glass.lightPower;
  colour *= glass.room + (1.25 - glass.room) * clamp(fall, 0.0, 1.0) * power;

  // The wire inside the glass: never quite straight, and nudged by the pebbles over it.
  let wander = (vec2f(vnoise(p * 6.0 + 3.1), vnoise(p * 6.0 + 17.9)) - 0.5) * glass.wireWander;
  let wp = (p + wander + tilt * 0.0012) * glass.cells;
  let w = abs(fract(wp) - 0.5);
  let toLine = 0.5 - max(w.x, w.y);
  let line = 1.0 - smoothstep(glass.wireWidth, glass.wireWidth + pixel * glass.cells * 1.5, toLine);
  let wireColour = (colour * 0.55 + glass.milk * 0.45) * glass.wireTone * (0.4 + 1.2 * clamp(fall, 0.0, 1.0) * power);
  colour = mix(colour, wireColour, line * glass.wire);

  // Light scattered in the frosted surface, and its glitter.
  let veil = clamp(pow(fall, 1.15) * glass.veil * power * (0.72 + 0.4 * pow(facing, 6.0)), 0.0, 1.0);
  colour = mix(colour, glass.milk, veil);
  colour = mix(colour, glass.milk * 0.4, glass.frost * 0.14);
  // Fog is a pale sheet of its own, lit a little more near the lamp.
  colour = mix(colour, glass.milk * (0.5 + 0.25 * clamp(fall, 0.0, 1.0) * power), fogged * 0.32);
  // Reeds catch a thin line of shadow where each one meets the next.
  let seam = smoothstep(0.4, 0.5, abs(fract(p.x * glass.cells) - 0.5)) * step(0.5, glass.surface) * step(glass.surface, 1.5);
  colour *= 1.0 - 0.3 * seam;
  colour += glass.milk * pow(facing, 260.0) * glass.sparkle * power * (0.06 + fall);

  colour += (hash21(uv * glass.resolution + fract(glass.time) * 91.7) - 0.5) * glass.grain;
  return vec4f(colour, 1.0);
}
`
