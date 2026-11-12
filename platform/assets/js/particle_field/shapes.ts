/**
 * Where the particle field's grains live: every shape as 80,000 homes, worked
 * out from geometry alone, with no page and no GPU, so it is the same anywhere.
 *
 * A shape is drawn in units one tall and `aspect` wide, centred on 0, with y
 * growing downwards as on the page. Each home says where its grain sits when the
 * value is 0 and when it is 1, over which stretch of the value it travels
 * between the two, over which stretch it lights, the tone of its light, which
 * way the surface under it faces, and its flags. A value change only moves
 * grains between their two places and lights them; it never asks for new homes.
 *
 * Grains lie on the surface of a solid seen from above: each part is a flat
 * shape whose edge rounds over (its bevel), and a grain is as likely anywhere on
 * that surface. Seen from above the rounded edge is foreshortened, so grains
 * crowd towards the silhouette as they would on a real rounded object, and that
 * crowding is the bright rim. A bevel as wide as the part makes a ball or a tube.
 */

export const GRAINS = 80_000
/** Floats in one home: three vec4f, as the shaders read them. */
export const HOME_FLOATS = 12
/** More grain numbers than there are grains, a power of two. */
const NUMBERS = 2 ** 17
/** A track grain the knob hides when it passes over it. */
export const BEHIND_KNOB = 1
/** A grain that turns round the centre with the clock, as a spinner's arc. */
export const TURNS = 2

/** A stretch of the value: below `from` nothing has happened, past `to` all of it. */
type Stretch = readonly [from: number, to: number]

const NEVER: Stretch = [2, 3]
const ALWAYS: Stretch = [-2, -1]
const WHOLE: Stretch = [0, 1]
/** How much of the value one grain takes to light, so a lit edge is soft, not stepped. */
const LIT_EDGE = 0.04
/**
 * The steepest surface counted at its true slope. A silhouette seen exactly edge
 * on would take every grain there is; past this it takes no more than five times
 * its share.
 */
const STEEPEST = 0.2
/** Cells across a part's longer side when it is drawn to be sampled. */
const CELLS = 400

/** Where one part's knob is, in units, when the value is 0 and when it is 1. */
export type Knob = {x0: number; y0: number; x1: number; y1: number; r: number}

export type Shape = {
  /** GRAINS homes of HOME_FLOATS floats each, in the order grains fly between shapes. */
  homes: Float32Array<ArrayBuffer>
  /** The ball that hides the track behind it, for a switch or a slider. */
  knob: Knob | undefined
  /** Part of it turns by itself, so the picture never rests while it shows. */
  turns: boolean
  /** How much of the box it covers, in square units, so grains on a small shape can be fainter. */
  area: number
}

/** A raster of the server's drawing, already fitted into the box: 1 where it is drawn. */
export type Picture = {
  mask: Uint8Array
  width: number
  height: number
  /** Units per cell. */
  cell: number
  /** The unit position of the first cell's top left corner. */
  left: number
  top: number
}

/** A seeded random stream (mulberry32), so a shape lands the same way every time. */
export function random(seed: number): () => number {
  let state = seed >>> 0
  return () => {
    state = (state + 0x6d2b79f5) >>> 0
    let t = state
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const seedOf = (name: string) => [...name].reduce((hash, char) => Math.imul(hash ^ char.charCodeAt(0), 16777619), 2166136261)

const clamp = (x: number, low: number, high: number) => Math.min(high, Math.max(low, x))

/** How far the value has come through a stretch, from 0 to 1. */
export const through = (value: number, [from, to]: Stretch) => clamp((value - from) / Math.max(to - from, 1e-5), 0, 1)

/** The stretch over which a grain at `s` along a fill lights: at value 0 none is lit, at 1 all are. */
const litFrom = (s: number): Stretch => {
  const from = clamp(s, 0, 1) * (1 - LIT_EDGE)
  return [from, from + LIT_EDGE]
}

type Distance = (x: number, y: number) => number

/**
 * A part drawn into cells: how far each cell's centre lies inside it, in units;
 * 0 outside. A part given as a distance keeps it, so its grains keep to its true
 * edge rather than to the steps of its cells.
 */
type Solid = {width: number; height: number; cell: number; left: number; top: number; depth: Float32Array; distance?: Distance}

/** A part given as a signed distance (negative inside), drawn into cells over its bounds. */
function solidOf(distance: Distance, left: number, top: number, right: number, bottom: number): Solid {
  const cell = Math.max(right - left, bottom - top) / CELLS
  // A cell of nothing all round, so every solid cell has neighbours to take a slope from.
  const x0 = left - 2 * cell
  const y0 = top - 2 * cell
  const width = Math.ceil((right - left) / cell) + 4
  const height = Math.ceil((bottom - top) / cell) + 4
  const depth = new Float32Array(width * height)
  for (let j = 0; j < height; j++) {
    const y = y0 + (j + 0.5) * cell
    for (let i = 0; i < width; i++) {
      const d = distance(x0 + (i + 0.5) * cell, y)
      if (d < 0) depth[j * width + i] = -d
    }
  }
  return {width, height, cell, left: x0, top: y0, depth, distance}
}

/** Squared distance along one row or column to the nearest zero (Felzenszwalb and Huttenlocher). */
function squaredDistance1d(f: Float64Array, n: number, out: Float64Array, v: Int32Array, z: Float64Array) {
  let k = 0
  v[0] = 0
  z[0] = -Infinity
  z[1] = Infinity
  for (let q = 1; q < n; q++) {
    let s = (f[q]! + q * q - (f[v[k]!]! + v[k]! * v[k]!)) / (2 * q - 2 * v[k]!)
    while (s <= z[k]!) {
      k--
      s = (f[q]! + q * q - (f[v[k]!]! + v[k]! * v[k]!)) / (2 * q - 2 * v[k]!)
    }
    k++
    v[k] = q
    z[k] = s
    z[k + 1] = Infinity
  }
  k = 0
  for (let q = 0; q < n; q++) {
    while (z[k + 1]! < q) k++
    out[q] = (q - v[k]!) * (q - v[k]!) + f[v[k]!]!
  }
}

/** A drawn picture as a solid: each drawn cell's distance in from the drawing's edge. */
export function solidOfPicture(picture: Picture): Solid {
  // Two empty cells all round, so the edge of the raster always counts as outside.
  const width = picture.width + 4
  const height = picture.height + 4
  const far = 1e20
  const field = new Float64Array(width * height)
  for (let j = 0; j < height; j++) {
    for (let i = 0; i < width; i++) {
      const pi = i - 2
      const pj = j - 2
      const drawn = pi >= 0 && pj >= 0 && pi < picture.width && pj < picture.height && picture.mask[pj * picture.width + pi] === 1
      field[j * width + i] = drawn ? far : 0
    }
  }
  const longest = Math.max(width, height)
  const f = new Float64Array(longest)
  const out = new Float64Array(longest)
  const v = new Int32Array(longest)
  const z = new Float64Array(longest + 1)
  for (let i = 0; i < width; i++) {
    for (let j = 0; j < height; j++) f[j] = field[j * width + i]!
    squaredDistance1d(f, height, out, v, z)
    for (let j = 0; j < height; j++) field[j * width + i] = out[j]!
  }
  for (let j = 0; j < height; j++) {
    for (let i = 0; i < width; i++) f[i] = field[j * width + i]!
    squaredDistance1d(f, width, out, v, z)
    for (let i = 0; i < width; i++) field[j * width + i] = out[i]!
  }
  const depth = new Float32Array(width * height)
  for (let c = 0; c < depth.length; c++) {
    // The nearest empty cell's centre is half a cell past the edge.
    if (field[c]! > 0) depth[c] = Math.max(Math.sqrt(field[c]!) - 0.5, 0.25) * picture.cell
  }
  return {width, height, cell: picture.cell, left: picture.left - 2 * picture.cell, top: picture.top - 2 * picture.cell, depth}
}

/** A solid's surface, ready to be sampled with each cell as likely as its share of the surface. */
type Surface = {solid: Solid; bevel: number; cells: Int32Array; running: Float64Array; area: number}

function surfaceOf(solid: Solid, bevel: number): Surface {
  const inside: number[] = []
  for (let c = 0; c < solid.depth.length; c++) if (solid.depth[c]! > 0) inside.push(c)
  const cells = Int32Array.from(inside)
  const running = new Float64Array(cells.length)
  let sum = 0
  cells.forEach((c, k) => {
    const flat = Math.min(solid.depth[c]! / bevel, 1)
    const tilt = 1 - flat
    sum += 1 / Math.max(Math.sqrt(1 - tilt * tilt), STEEPEST)
    running[k] = sum
  })
  return {solid, bevel, cells, running, area: cells.length * solid.cell * solid.cell}
}

/** One point on a surface: where it is, and the sideways part of the way the surface faces there. */
type Point = {x: number; y: number; nx: number; ny: number}

function sample(surface: Surface, rand: () => number, point: Point) {
  const {solid, running, cells} = surface
  const pick = rand() * running[running.length - 1]!
  let low = 0
  let high = running.length - 1
  while (low < high) {
    const mid = (low + high) >> 1
    if (running[mid]! < pick) low = mid + 1
    else high = mid
  }
  const c = cells[low]!
  const i = c % solid.width
  const j = (c - i) / solid.width
  const d = solid.depth
  const gx = d[c + 1]! - d[c - 1]!
  const gy = d[c + solid.width]! - d[c - solid.width]!
  const slope = Math.hypot(gx, gy)
  // The surface faces out over the edge as much as it has rounded over.
  const tilt = 1 - Math.min(d[c]! / surface.bevel, 1)
  // The cell's centre is inside, so a point drawn again until it is inside soon is.
  do {
    point.x = solid.left + (i + rand()) * solid.cell
    point.y = solid.top + (j + rand()) * solid.cell
  } while (solid.distance && solid.distance(point.x, point.y) > 0)
  point.nx = slope > 0 ? (-gx / slope) * tilt : 0
  point.ny = slope > 0 ? (-gy / slope) * tilt : 0
}

type Home = {
  x0: number
  y0: number
  x1: number
  y1: number
  move: Stretch
  lit: Stretch
  tone: number
  flags: number
}

type Part = {
  surface: Surface
  /** How many grains it takes against the other parts: its surface, unless it says otherwise. */
  share?: number
  home(point: Point, rand: () => number): Home
}

const shareOf = (part: Part) => part.share ?? part.surface.running[part.surface.running.length - 1]! * part.surface.solid.cell ** 2

function assemble(name: string, parts: readonly Part[], value: number): Float32Array<ArrayBuffer> {
  const rand = random(seedOf(name))
  const homes = new Float32Array(GRAINS * HOME_FLOATS)
  const total = parts.reduce((sum, part) => sum + shareOf(part), 0)
  const point: Point = {x: 0, y: 0, nx: 0, ny: 0}
  let at = 0
  parts.forEach((part, index) => {
    const count = index === parts.length - 1 ? GRAINS - at : Math.round((GRAINS * shareOf(part)) / total)
    for (let k = 0; k < count; k++) {
      sample(part.surface, rand, point)
      const home = part.home(point, rand)
      homes.set(
        [home.x0, home.y0, home.x1, home.y1, point.nx, point.ny, home.move[0], home.move[1], home.lit[0], home.lit[1], home.tone, home.flags],
        (at + k) * HOME_FLOATS,
      )
    }
    at += count
  })
  return inFlightOrder(homes, value)
}

/**
 * Grains in the order they sit across the shape from left to right, where they
 * are at this value. A grain keeps its number from shape to shape, so the
 * leftmost grain of one shape flies to the leftmost place of the next and the
 * cloud moves across as a whole instead of crossing itself.
 */
function inFlightOrder(homes: Float32Array, value: number): Float32Array<ArrayBuffer> {
  const keys = new Float64Array(GRAINS)
  let low = Infinity
  let high = -Infinity
  for (let g = 0; g < GRAINS; g++) {
    const at = g * HOME_FLOATS
    const m = through(value, [homes[at + 6]!, homes[at + 7]!])
    keys[g] = homes[at]! + (homes[at + 2]! - homes[at]!) * m
    low = Math.min(low, keys[g]!)
    high = Math.max(high, keys[g]!)
  }
  // Each grain's place across (in 2^35 steps) and its number (under 2^17) packed
  // into one exact double, so a plain numeric sort orders them: a sort that calls
  // back for every comparison is most of a shape change's cost on a phone.
  const steps = 2 ** 35 / Math.max(high - low, 1e-9)
  for (let g = 0; g < GRAINS; g++) keys[g] = Math.floor((keys[g]! - low) * steps) * NUMBERS + g
  keys.sort()
  const sorted = new Float32Array(homes.length)
  keys.forEach((key, slot) => {
    const g = key % NUMBERS
    sorted.set(homes.subarray(g * HOME_FLOATS, (g + 1) * HOME_FLOATS), slot * HOME_FLOATS)
  })
  return sorted
}

const areaOf = (parts: readonly Part[]) => parts.reduce((sum, part) => sum + part.surface.area, 0)

// Signed distances, negative inside.
const circle =
  (r: number): Distance =>
  (x, y) =>
    Math.hypot(x, y) - r

/** A horizontal stadium round the segment from (a, 0) to (b, 0). */
const stadium =
  (a: number, b: number, r: number): Distance =>
  (x, y) =>
    Math.hypot(x - clamp(x, a, b), y) - r

const band =
  (radius: number, half: number): Distance =>
  (x, y) =>
    Math.abs(Math.hypot(x, y) - radius) - half

const roundedSquare = (x: number, y: number, half: number, corner: number) => {
  const qx = Math.abs(x) - half + corner
  const qy = Math.abs(y) - half + corner
  return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - corner
}

/** Clockwise turns from twelve o'clock, from 0 to 1. */
const turnOf = (x: number, y: number) => (Math.atan2(x, -y) / (2 * Math.PI) + 1) % 1

const still = (point: Point, lit: Stretch, tone: number, flags = 0): Home => ({
  x0: point.x,
  y0: point.y,
  x1: point.x,
  y1: point.y,
  move: WHOLE,
  lit,
  tone,
  flags,
})

/** A track with a ball that rolls along it, lighting the track behind it (switch and slider). */
function rollingKnob(name: string, aspect: number, value: number, track: number, knob: number, trackBevel: number): Shape {
  const ends = aspect / 2 - 0.5
  const across = (x: number) => (x + ends) / (2 * ends)
  const parts: Part[] = [
    {
      surface: surfaceOf(solidOf(stadium(-ends, ends, track), -aspect / 2, -0.5, aspect / 2, 0.5), trackBevel),
      home: point => still(point, litFrom(across(point.x)), clamp(across(point.x), 0, 1), BEHIND_KNOB),
    },
    {
      surface: surfaceOf(solidOf(circle(knob), -knob, -knob, knob, knob), knob),
      home: point => ({x0: point.x - ends, y0: point.y, x1: point.x + ends, y1: point.y, move: WHOLE, lit: NEVER, tone: 0, flags: 0}),
    },
  ]
  return {homes: assemble(name, parts, value), knob: {x0: -ends, y0: 0, x1: ends, y1: 0, r: knob}, turns: false, area: areaOf(parts)}
}

const switchShape = (aspect: number, value: number) => rollingKnob("switch", aspect, value, 0.5, 0.39, 0.2)

const sliderShape = (aspect: number, value: number) => rollingKnob("slider", aspect, value, 0.1, 0.46, 0.1)

function barShape(aspect: number, value: number): Shape {
  const ends = aspect / 2 - 0.5
  const parts: Part[] = [
    {
      surface: surfaceOf(solidOf(stadium(-ends, ends, 0.5), -aspect / 2, -0.5, aspect / 2, 0.5), 0.32),
      home: point => {
        const s = clamp((point.x + aspect / 2) / aspect, 0, 1)
        return still(point, litFrom(s), s)
      },
    },
  ]
  return {homes: assemble("bar", parts, value), knob: undefined, turns: false, area: areaOf(parts)}
}

function ringShape(value: number): Shape {
  const parts: Part[] = [
    {
      surface: surfaceOf(solidOf(band(0.37, 0.1), -0.5, -0.5, 0.5, 0.5), 0.08),
      home: point => {
        const s = turnOf(point.x, point.y)
        return still(point, litFrom(s), s)
      },
    },
  ]
  return {homes: assemble("ring", parts, value), knob: undefined, turns: false, area: areaOf(parts)}
}

/** Three quarters of a ring with round ends, turning clockwise, brightest at its leading end. */
function spinnerShape(value: number): Shape {
  const radius = 0.36
  const half = 0.085
  const span = 0.75
  const arc: Distance = (x, y) => {
    const turn = turnOf(x, y)
    if (turn <= span) return Math.abs(Math.hypot(x, y) - radius) - half
    const end = (t: number) => [Math.sin(2 * Math.PI * t) * radius, -Math.cos(2 * Math.PI * t) * radius] as const
    const [ax, ay] = end(0)
    const [bx, by] = end(span)
    return Math.min(Math.hypot(x - ax, y - ay), Math.hypot(x - bx, y - by)) - half
  }
  const parts: Part[] = [
    {
      surface: surfaceOf(solidOf(arc, -0.5, -0.5, 0.5, 0.5), half),
      home: point => still(point, ALWAYS, 1 - clamp(turnOf(point.x, point.y) / span, 0, 1), TURNS),
    },
  ]
  return {homes: assemble("spinner", parts, value), knob: undefined, turns: true, area: areaOf(parts)}
}

/** Where along the tick a point lies, from where the pen starts (0) to where it lifts (1). */
function alongTick(points: readonly (readonly [number, number])[], x: number, y: number) {
  const lengths = points.slice(1).map((p, k) => Math.hypot(p[0] - points[k]![0], p[1] - points[k]![1]))
  const total = lengths.reduce((sum, length) => sum + length, 0)
  let best = Infinity
  let along = 0
  let before = 0
  lengths.forEach((length, k) => {
    const [ax, ay] = points[k]!
    const [bx, by] = points[k + 1]!
    const t = clamp(((x - ax) * (bx - ax) + (y - ay) * (by - ay)) / (length * length), 0, 1)
    const d = Math.hypot(x - (ax + (bx - ax) * t), y - (ay + (by - ay) * t))
    if (d < best) {
      best = d
      along = (before + t * length) / total
    }
    before += length
  })
  return {distance: best, along}
}

/** A box, and a tick its grains fly in to draw as the value rises, from the pen's start to its lift. */
function checkboxShape(value: number): Shape {
  const frameHalf = 0.055
  const tick = [[-0.2, 0.01], [-0.06, 0.15], [0.22, -0.15]] as const
  const tickHalf = 0.07
  const frame = surfaceOf(solidOf((x, y) => Math.abs(roundedSquare(x, y, 0.36, 0.12)) - frameHalf, -0.5, -0.5, 0.5, 0.5), frameHalf)
  const resting: Point = {x: 0, y: 0, nx: 0, ny: 0}
  const parts: Part[] = [
    {
      surface: frame,
      home: point => still(point, [0.55, 0.95], clamp(point.x + 0.5, 0, 1)),
    },
    {
      surface: surfaceOf(solidOf((x, y) => alongTick(tick, x, y).distance - tickHalf, -0.35, -0.3, 0.35, 0.3), tickHalf),
      home: (point, rand) => {
        // Unticked, the grain waits on the box; it flies in as the pen reaches its place.
        sample(frame, rand, resting)
        const s = alongTick(tick, point.x, point.y).along
        const stretch: Stretch = [s * 0.7, s * 0.7 + 0.3]
        return {x0: resting.x, y0: resting.y, x1: point.x, y1: point.y, move: stretch, lit: stretch, tone: s, flags: 0}
      },
    },
  ]
  return {homes: assemble("checkbox", parts, value), knob: undefined, turns: false, area: areaOf(parts)}
}

/** Three rings in a row and one lit ball that rolls to the chosen one: 0, a half or 1. */
function radioShape(aspect: number, value: number): Shape {
  const gap = aspect / 3
  const ring = surfaceOf(solidOf(band(0.34, 0.06), -0.5, -0.5, 0.5, 0.5), 0.06)
  const dot = 0.19
  const parts: Part[] = [-1, 0, 1].map(k => ({
    surface: ring,
    home: point => still({...point, x: point.x + k * gap}, NEVER, 0),
  }))
  parts.push({
    surface: surfaceOf(solidOf(circle(dot), -dot, -dot, dot, dot), dot),
    home: point => ({x0: point.x - gap, y0: point.y, x1: point.x + gap, y1: point.y, move: WHOLE, lit: ALWAYS, tone: 0.5, flags: 0}),
  })
  return {homes: assemble("radio", parts, value), knob: undefined, turns: false, area: areaOf(parts)}
}

/** A row of `count` balls; the first n light when the value is n of `count`. */
function stepsShape(count: number, aspect: number, value: number): Shape {
  const gap = aspect / count
  const r = Math.min(0.3, gap * 0.3)
  const ball = surfaceOf(solidOf(circle(r), -r, -r, r, r), r)
  const parts: Part[] = Array.from({length: count}, (_, k) => ({
    surface: ball,
    home: (point: Point) =>
      still({...point, x: point.x + (k - (count - 1) / 2) * gap}, [(k + 0.55) / count, (k + 0.95) / count], k / Math.max(count - 1, 1)),
  }))
  return {homes: assemble(`steps:${count}`, parts, value), knob: undefined, turns: false, area: areaOf(parts)}
}

/**
 * The shape a control's name asks for, drawn to fill a box `aspect` wide and one
 * tall. Icons and marks are pictures the server drew; see `pictureShape`.
 */
export function controlShape(name: string, aspect: number, value: number): Shape {
  const steps = /^steps:([2-8])$/.exec(name)
  if (steps) return stepsShape(Number(steps[1]), aspect, value)
  switch (name) {
    case "switch":
      return switchShape(aspect, value)
    case "slider":
      return sliderShape(aspect, value)
    case "bar":
      return barShape(aspect, value)
    case "ring":
      return ringShape(value)
    case "spinner":
      return spinnerShape(value)
    case "checkbox":
      return checkboxShape(value)
    case "radio":
      return radioShape(aspect, value)
    default:
      throw new Error(`The particle field has no shape called ${name}`)
  }
}

/** Icons and marks are drawn by the server; the field samples its drawing. */
export const isPicture = (name: string) => name.startsWith("icon:") || name.startsWith("mark:")

/**
 * A picture the server drew, as grains on its surface: a stroke becomes a tube
 * and a filled block a tile with rounded edges. The value lights it from left to right.
 */
export function pictureShape(name: string, picture: Picture, value: number): Shape {
  const solid = solidOfPicture(picture)
  let thickest = 0
  let leftmost = Infinity
  let rightmost = -Infinity
  for (let c = 0; c < solid.depth.length; c++) {
    if (solid.depth[c]! <= 0) continue
    thickest = Math.max(thickest, solid.depth[c]!)
    const x = solid.left + ((c % solid.width) + 0.5) * solid.cell
    leftmost = Math.min(leftmost, x)
    rightmost = Math.max(rightmost, x)
  }
  if (thickest === 0) throw new Error(`The drawing for ${name} is empty`)
  const span = Math.max(rightmost - leftmost, solid.cell)
  const parts: Part[] = [
    {
      surface: surfaceOf(solid, thickest * 0.7),
      home: point => {
        const s = clamp((point.x - leftmost) / span, 0, 1)
        return still(point, litFrom(s), s)
      },
    },
  ]
  return {homes: assemble(name, parts, value), knob: undefined, turns: false, area: areaOf(parts)}
}
