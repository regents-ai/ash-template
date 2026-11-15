/**
 * The solarpunk robot factory on the splats page (`AshTemplateWeb.SplatsLabLive`): a
 * plaster hall with a planted sawtooth roof, the Regents crown lit over its open bay
 * door and again in its back windows, a glass hall glowing with plants, solar panels,
 * two wind turbines, a water tower wrapped in vines, a chimney letting off steam, and a
 * conveyor carrying half-built robots out of the door past a swinging arm. Finished
 * robots water the beds and carry seedlings round the pond. Dusk, on a floating island.
 *
 * Grown from one fixed seed into a few hundred thousand splats (build.ts); the turbine
 * blades, belt, robots and arm are moving parts (`Scene.pose`). Units: the grass disc
 * is about one unit from its middle, the hall's floor at height 0, y up, the bay door
 * facing +z.
 */
import {
  add, after, clamp01, createBuilder, CROWN_BLOCKS, CROWN_PITCH, cross, FIREFLY, growUnderside, hex, length, mix, restPose, setPart, smoothstep,
  STEAM, STILL, sub, times, turning, unit, UP, WATER,
  type Glow, type Lighting, type Placed, type Pose, type Scene, type Vec3,
} from "./build.ts"
import {DUSK} from "./palette.ts"

const SEED = 20_261_116

const C = {
  plaster: hex("#f2e4cc"),
  plasterShade: hex("#dccab0"),
  brick: hex("#b4553a"),
  brickDark: hex("#8f3f2c"),
  mortar: hex("#d8c0a2"),
  timber: hex("#4a2e28"),
  timberLight: hex("#8a5634"),
  steel: hex("#5a6074"),
  steelLight: hex("#a3a9ba"),
  steelDark: hex("#2f3040"),
  frame: hex("#e5e3d2"),
  glass: hex("#aecacd"),
  lamp: hex("#ffd97a"),
  lampHot: hex("#fff3c8"),
  amber: hex("#ffb04a"),
  panel: hex("#16204a"),
  panelLine: hex("#6f93c6"),
  tangerine: hex("#ff5b19"),
  platinum: hex("#e5e3d2"),
  powder: hex("#aecacd"),
  charcoal: hex("#161616"),
  eye: hex("#7ff0e8"),
  rubber: hex("#2c2b36"),
  water: hex("#1f4664"),
  soil: hex("#3a2622"),
  copper: hex("#c9703e"),
  patina: hex("#79b0a2"),
  slate: hex("#3e3a5c"),
  stone: hex("#c9b49a"),
  firefly: hex("#e8ff9a"),
}
const GRASS = ["#3f7e3e", "#4b8c42", "#5c9a47", "#357039"].map(hex)
const GRASS_BRIGHT = ["#7cae52", "#9cc25c"].map(hex)
const LEAF = ["#25563a", "#2f683d", "#3f7c42", "#559249", "#77aa52", "#9ec45c"].map(hex)
const BARK = ["#6a4330", "#7d5238", "#553526", "#8d5f3d"].map(hex)
const EARTH = ["#7a5034", "#62402c", "#8c5d3a", "#4c3022"].map(hex)
const STONES = ["#8d8596", "#a39a9e", "#6f6a80", "#b9ab9c"].map(hex)
const FLOWERS = ["#e46a9a", "#a47be0", "#ffd97a", "#e5e3d2", "#ff8a3d"].map(hex)

/** The low sun on the left and in front, a cool rim light from behind on the right. */
const SUN: Vec3 = unit([-0.72, 0.42, 0.55])
const RIM: Vec3 = unit([0.6, 0.42, -0.68])

/** Where everything stands (x right, z toward the bay door's front). */
const HALL = {x0: -0.5, x1: 0.2, z0: -0.6, z1: -0.1, wall: 0.32, thick: 0.02, rise: 0.1, teeth: 4}
const DOOR = {x: -0.15, half: 0.1, top: 0.19}
const GLASSHOUSE = {x0: 0.2, x1: 0.7, z: -0.36, radius: 0.16, plinth: 0.045}
const CHIMNEY = {x: -0.42, z: -0.67, half: 0.04, top: 0.72}
const BELT = {x: -0.15, z0: -0.42, z1: 0.34, top: 0.065, half: 0.05, speed: 0.04, slat: 0.02}
const CRATE = {x: -0.15, z0: 0.36, z1: 0.5, half: 0.07, top: 0.055}
const ARM = {base: [-0.02, 0, 0.12] as Vec3, shoulder: [-0.02, 0.06, 0.12] as Vec3, elbow: [-0.02, 0.24, 0.12] as Vec3, wrist: [-0.13, 0.23, 0.12] as Vec3}
const POND = {x: 0.42, z: 0.44, a: 0.16, b: 0.11}
const LOOP = {x: 0.42, z: 0.44, a: 0.28, b: 0.21, period: 30}
const TOWER = {x: 0.8, z: 0.06, legs: 0.28, radius: 0.075, tank: 0.12}
const TURBINES = [
  {x: -0.8, z: -0.42, height: 0.8, blade: 0.2, part: 12, speed: 0.9},
  {x: 0.52, z: -0.78, height: 0.66, blade: 0.17, part: 13, speed: 0.75},
] as const
const SOLAR = {x0: -0.84, x1: -0.54, rows: [0.12, 0.27, 0.42], depth: 0.11, tilt: (30 * Math.PI) / 180}
const BEDS = [{x0: -0.5, x1: -0.33, z0: -0.04, z1: 0.05}, {x0: -0.5, x1: -0.33, z0: 0.12, z1: 0.21}]
const TROUGH = {x0: 0.26, x1: 0.66, z0: -0.17, z1: -0.12}
const LAMPS: readonly Vec3[] = [[0.06, 0, 0.28], [0.66, 0, 0.16], [-0.38, 0, 0.34]]
const TREES: readonly Vec3[] = [[0.08, 0, 0.68], [-0.3, 0, 0.66]]
const TENDER = {foot: [-0.28, 0, 0.13] as Vec3, yaw: -Math.PI / 2}

/** Moving parts; 0 stands still. */
const PART = {belt: 1, carried: [2, 3, 4], turret: 5, upperArm: 6, forearm: 7, walker: 8, legs: [9, 10], watering: 11}
const PARTS = 14

const rim = (angle: number) =>
  1.02 + 0.035 * Math.sin(3 * angle + 0.4) + 0.025 * Math.sin(7 * angle + 1.9) + 0.015 * Math.sin(13 * angle + 0.8)

/** The grass's height: nearly flat round the buildings, falling a little to the edge. */
const ground = (x: number, z: number) =>
  0.012 * (1 - Math.min(1, x * x + z * z)) + 0.003 * Math.sin(4.1 * x + 0.3) * Math.cos(3.3 * z - 0.2)

type Rect = {readonly x0: number; readonly x1: number; readonly z0: number; readonly z1: number}
const outside = (x: number, z: number, r: Rect) => Math.hypot(Math.max(r.x0 - x, 0, x - r.x1), Math.max(r.z0 - z, 0, z - r.z1))
const GLASS_RECT: Rect = {x0: GLASSHOUSE.x0, x1: GLASSHOUSE.x1, z0: GLASSHOUSE.z - GLASSHOUSE.radius, z1: GLASSHOUSE.z + GLASSHOUSE.radius}
const CRATE_RECT: Rect = {x0: CRATE.x - CRATE.half, x1: CRATE.x + CRATE.half, z0: CRATE.z0, z1: CRATE.z1}
const FOOTPRINTS: readonly Rect[] = [HALL, GLASS_RECT, CRATE_RECT, TROUGH, ...BEDS]
const inPond = (x: number, z: number, grow = 0) => ((x - POND.x) / (POND.a + grow)) ** 2 + ((z - POND.z) / (POND.b + grow)) ** 2 < 1

/** Where the walking robot is on its loop round the pond at a moment, and the way it faces. */
const onLoop = (seconds: number) => {
  const angle = (seconds / LOOP.period) * Math.PI * 2
  const x = LOOP.x + LOOP.a * Math.cos(angle)
  const z = LOOP.z + LOOP.b * Math.sin(angle)
  return {at: [x, ground(x, z), z] as Vec3, yaw: Math.atan2(-LOOP.a * Math.sin(angle), LOOP.b * Math.cos(angle))}
}

/** How a patch of surface looks: its colour, and any light it gives, gleam, blink or own openness. */
type Look = {readonly colour: Vec3} & Partial<Pick<Placed, "glow" | "shine" | "open" | "opacity" | "blink">>
type Paint = (s: number, t: number) => Look | undefined

export function buildFactory(): Scene {
  const b = createBuilder(SEED)
  const {random, between, pick, jitter, onSphere, place, flat, long, ball} = b

  /** A flat patch from `corner` along `u` and `v` (it faces u × v), a splat about every `step`. */
  const face = (corner: Vec3, u: Vec3, v: Vec3, step: number, paint: Paint, open: number, extra: Partial<Placed> = {}) => {
    const n = unit(cross(u, v))
    const nu = Math.max(1, Math.round(length(u) / step))
    const nv = Math.max(1, Math.round(length(v) / step))
    const du = unit(u)
    const dv = unit(v)
    const reach: Vec3 = [(length(u) / nu) * 0.62, (length(v) / nv) * 0.62, 0.0012]
    for (let i = 0; i < nu; i++) {
      for (let j = 0; j < nv; j++) {
        const s = (i + 0.5) / nu
        const t = (j + 0.5) / nv
        const look = paint(s, t)
        if (!look) continue
        const at = add(add(corner, times(u, s + (random() - 0.5) * 0.3 / nu)), times(v, t + (random() - 0.5) * 0.3 / nv))
        place({at, axes: [du, dv, n], reach, opacity: 0.985, facing: n, open, ...extra, ...look})
      }
    }
  }

  /** A box: its middle, right-handed axes, half its size along each, and each face's look
   * (0 +a, 1 −a, 2 +b, 3 −b, 4 +c, 5 −c). */
  const box = (centre: Vec3, axes: readonly [Vec3, Vec3, Vec3], half: Vec3, step: number, paint: (side: number, s: number, t: number) => Look | undefined, open: number, extra: Partial<Placed> = {}) => {
    for (let k = 0; k < 3; k++) {
      for (const sign of [1, -1]) {
        const a = times(axes[(k + 1) % 3]!, 2 * half[(k + 1) % 3]!)
        const c = times(axes[(k + 2) % 3]!, 2 * half[(k + 2) % 3]!)
        const [u, v] = sign > 0 ? [a, c] : [c, a]
        const corner = sub(sub(add(centre, times(axes[k]!, sign * half[k]!)), times(u, 0.5)), times(v, 0.5))
        const side = k * 2 + (sign > 0 ? 0 : 1)
        face(corner, u, v, step, (s, t) => paint(side, s, t), open, extra)
      }
    }
  }
  const AXES: readonly [Vec3, Vec3, Vec3] = [[1, 0, 0], UP, [0, 0, 1]]
  const plain = (colour: Vec3, vary = 0.06) => () => ({colour: jitter(colour, vary)})

  /** An upright drum: base, radius at foot and top, height, and its look by the angle round (0 to 1) and height (0 to 1). */
  const drum = (base: Vec3, radius: readonly [number, number], height: number, step: number, paint: Paint, open: number, extra: Partial<Placed> = {}) => {
    const around = Math.max(6, Math.round((Math.PI * 2 * Math.max(radius[0], radius[1])) / step))
    const up = Math.max(1, Math.round(height / step))
    const slope = (radius[0] - radius[1]) / height
    for (let i = 0; i < around; i++) {
      const a = ((i + 0.5) / around) * Math.PI * 2
      const out: Vec3 = [Math.cos(a), 0, Math.sin(a)]
      const tangent: Vec3 = [-Math.sin(a), 0, Math.cos(a)]
      const n = unit([out[0], slope, out[2]])
      for (let j = 0; j < up; j++) {
        const h = (j + 0.5) / up
        const look = paint((i + 0.5) / around, h)
        if (!look) continue
        const r = radius[0] + (radius[1] - radius[0]) * h
        const at = add(base, [out[0] * r, h * height, out[2] * r])
        const wide = (Math.PI * 2 * r) / around
        place({at, axes: [tangent, unit(cross(n, tangent)), n], reach: [wide * 0.62, (height / up) * 0.62, 0.0012], opacity: 0.985, facing: n, open, ...extra, ...look})
      }
    }
  }

  /** A thin round bar from one point to another. */
  const rod = (from: Vec3, to: Vec3, radius: number, colour: Vec3, open: number, extra: Partial<Placed> = {}) => {
    const span = sub(to, from)
    const d = unit(span)
    const n = Math.max(1, Math.ceil(length(span) / (radius * 1.5)))
    const lit = Math.abs(d[1]) > 0.95 ? unit([SUN[0], 0, SUN[2]]) : unit(sub(UP, times(d, d[1])))
    for (let i = 0; i < n; i++) {
      const at = add(from, times(span, (i + 0.5) / n))
      place({at, axes: [d, unit(cross(lit, d)), lit], reach: [(length(span) / n) * 0.7, radius, radius], colour: jitter(colour, 0.06), opacity: 0.98, facing: lit, open, ...extra})
    }
  }

  /** How far apart the splats of walls and roofs sit: a little under a picture pixel. */
  const STEP = 0.0055

  const groundOpen = (x: number, z: number) => {
    let open = 1
    for (const r of FOOTPRINTS) open *= 0.5 + 0.5 * smoothstep(0, 0.1, outside(x, z, r))
    for (const tree of TREES) open *= 0.6 + 0.4 * smoothstep(0.04, 0.16, Math.hypot(x - tree[0], z - tree[2]))
    return open
  }
  const onGrass = (x: number, z: number): Vec3 => [x, ground(x, z), z]

  // ----- Plaster, brick and windows -----
  const plaster = (run: number, y: number): Look => {
    // Courses of dressed plaster blocks, one splat wide at each joint, with soft stains.
    const course = Math.floor(y / 0.045)
    const across = (((run + (course % 2) * 0.045) % 0.09) + 0.09) % 0.09
    const joint = y - course * 0.045 < STEP || across < STEP
    const stain = 0.5 + 0.5 * Math.sin(run * 23 + Math.sin(y * 17) * 2)
    const base = mix(C.plaster, C.plasterShade, 0.25 + 0.35 * stain + 0.2 * random())
    if (y > HALL.wall - 0.02 && y < HALL.wall) return {colour: jitter(C.plasterShade, 0.05)}
    return {colour: joint ? times(base, 0.86) : jitter(base, 0.04)}
  }
  const brick = (run: number, y: number): Look => {
    const course = Math.floor((y + 0.02) / 0.012)
    const across = (((run + (course % 2) * 0.015) % 0.03) + 0.03) % 0.03
    const mortar = (y + 0.02) - course * 0.012 < STEP * 0.9 || across < STEP * 0.9
    return {colour: mortar ? jitter(C.mortar, 0.08) : jitter(random() < 0.3 ? C.brickDark : C.brick, 0.12)}
  }
  /** An arched window: its middle, sill, where the arch starts, half its width. */
  type Window = {readonly at: number; readonly sill: number; readonly spring: number; readonly half: number}
  const pane = (): Look => {
    const bright = random()
    return {colour: bright < 0.15 ? C.amber : bright < 0.85 ? jitter(C.lamp, 0.08) : C.lampHot, glow: 1.2}
  }
  const inWindow = (w: Window, run: number, y: number): Look | null => {
    const dx = run - w.at
    const inside = Math.abs(dx) < w.half && y > w.sill && (y < w.spring || dx * dx + (y - w.spring) ** 2 < w.half * w.half)
    if (!inside) return null
    const edge = Math.abs(dx) > w.half - STEP || y < w.sill + STEP || (y > w.spring && dx * dx + (y - w.spring) ** 2 > (w.half - STEP) ** 2)
    const third = (w.spring - w.sill) / 3
    const bar = Math.abs(dx) < STEP / 2 || Math.abs(y - (w.sill + third)) < STEP / 2 || Math.abs(y - (w.sill + 2 * third)) < STEP / 2 || Math.abs(y - w.spring) < STEP / 2
    return edge || bar ? {colour: jitter(C.timber, 0.1)} : pane()
  }
  const wallLook = (windows: readonly Window[], run: number, y: number, extra?: (run: number, y: number) => Look | null | undefined): Look | undefined => {
    const special = extra?.(run, y)
    if (special !== null && special !== undefined) return special
    if (special === null) return undefined
    for (const w of windows) {
      const look = inWindow(w, run, y)
      if (look) return look
    }
    return y < 0.04 ? brick(run, y) : plaster(run, y)
  }
  const interior = (): Look => ({colour: jitter(mix(C.plasterShade, C.amber, 0.25), 0.06), glow: 0.32, open: 0.1})

  /**
   * A wall of the hall from `start` along `along`, its outside facing along × up: the
   * outside with its windows and openings, and the inside a wall's thickness in. `extra`
   * paints anything special by the distance along and the height, or makes a hole (null).
   */
  const wall = (start: Vec3, along: Vec3, windows: readonly Window[], extra?: (run: number, y: number) => Look | null | undefined) => {
    const top: Vec3 = [0, HALL.wall + 0.01, 0]
    const span = length(along)
    const corner = add(start, [0, -0.01, 0])
    face(corner, along, top, STEP, (s, t) => wallLook(windows, s * span, t * top[1] - 0.01, extra), 0.95)
    const hole = (run: number, y: number) => extra?.(run, y) === null || windows.some(w => inWindow(w, run, y) !== null)
    const inner = add(add(corner, times(unit(cross(along, top)), -HALL.thick)), along)
    face(inner, times(along, -1), top, STEP * 1.3, (s, t) => (hole((1 - s) * span, t * top[1] - 0.01) ? undefined : interior()), 0.1)
  }

  // ----- The hall -----
  const width = HALL.x1 - HALL.x0
  const depth = HALL.z1 - HALL.z0
  const arched = (at: number, sill = 0.08, spring = 0.2, half = 0.03): Window => ({at, sill, spring, half})

  // The front: the bay door, the crown sign over it, two windows either side.
  const doorRun = DOOR.x - HALL.x0
  wall([HALL.x0, 0, HALL.z1], [width, 0, 0], [arched(0.07), arched(0.16), arched(0.54), arched(0.63)], (run, y) => {
    const dx = Math.abs(run - doorRun)
    if (dx < DOOR.half && y < DOOR.top) return null
    if (dx < DOOR.half + 2 * STEP && y < DOOR.top + 2 * STEP) return {colour: jitter(C.steelDark, 0.1)}
    return undefined
  })
  // The left side: three windows and a pipe running up it.
  wall([HALL.x0, 0, HALL.z0], [0, 0, depth], [arched(0.1), arched(0.25), arched(0.4)])
  // The right side, above the glass hall: a round window.
  wall([HALL.x1, 0, HALL.z1], [0, 0, -depth], [], (run, y) => {
    const d = Math.hypot(run - (HALL.z1 - GLASSHOUSE.z), y - 0.255)
    if (d < 0.034) return d > 0.034 - STEP || Math.abs(run - (HALL.z1 - GLASSHOUSE.z)) < STEP / 2 || Math.abs(y - 0.255) < STEP / 2 ? {colour: C.timber} : pane()
    return undefined
  })
  // The back: the crown as thirteen lit windows, with a window either side.
  const CROWN_WINDOW = 0.05
  const crownWindow = (run: number, y: number): Look | undefined => {
    const middle = DOOR.x - HALL.x0
    for (const [column, row] of CROWN_BLOCKS) {
      const cx = middle - column * CROWN_WINDOW * CROWN_PITCH
      const cy = 0.175 + row * CROWN_WINDOW * CROWN_PITCH
      if (Math.abs(run - cx) < CROWN_WINDOW / 2 && Math.abs(y - cy) < CROWN_WINDOW / 2) {
        const edge = Math.abs(run - cx) > CROWN_WINDOW / 2 - STEP * 0.6 || Math.abs(y - cy) > CROWN_WINDOW / 2 - STEP * 0.6
        return edge ? {colour: jitter(C.timber, 0.1)} : pane()
      }
    }
    return undefined
  }
  wall([HALL.x1, 0, HALL.z0], [-width, 0, 0], [arched(0.08), arched(0.62)], (run, y) => crownWindow(width - run, y))

  // The sawtooth roof: four teeth, each a planted slope rising to the right and a lit
  // glass face looking right; the gables are plaster with a timber edge.
  const tooth = width / HALL.teeth
  const H = HALL.wall
  for (let k = 0; k < HALL.teeth; k++) {
    const a = HALL.x0 + k * tooth
    const eave = 0.02
    face([a, H, HALL.z0 - eave], [0, 0, depth + 2 * eave], [tooth, HALL.rise, 0], STEP, (s, t) => {
      const edge = t > 1 - 1 / (tooth / STEP) || s < 0.012 || s > 0.988
      if (edge) return {colour: jitter(C.timber, 0.1)}
      const patch = 0.5 + 0.5 * Math.sin(s * 31 + k * 2) * Math.cos(t * 9 + s * 5)
      const colour = random() < 0.04 ? pick(FLOWERS) : random() < 0.15 ? pick(GRASS_BRIGHT) : jitter(mix(GRASS[3]!, GRASS[2]!, patch), 0.2)
      return {colour, open: 0.75 + 0.25 * t}
    }, 0.9)
    face([a + tooth, H, HALL.z1], [0, 0, -depth], [0, HALL.rise, 0], STEP, (s, t) => {
      const run = s * depth
      const bar = (run % 0.05) < STEP || Math.abs(t - 0.5) < STEP / HALL.rise / 2 || t > 1 - STEP / HALL.rise || t < STEP / HALL.rise
      return bar ? {colour: jitter(C.timber, 0.1)} : {colour: jitter(mix(C.lamp, C.amber, 0.4 * random()), 0.05), glow: 1.05}
    }, 0.9)
    const gable = (s: number, t: number): Look | undefined =>
      t > s ? undefined : t > s - STEP / tooth * 1.5 ? {colour: jitter(C.timber, 0.1)} : plaster(s * tooth + k * 0.03, H + t * HALL.rise)
    face([a, H, HALL.z1], [tooth, 0, 0], [0, HALL.rise, 0], STEP, gable, 0.95)
    face([a + tooth, H, HALL.z0], [-tooth, 0, 0], [0, HALL.rise, 0], STEP, (s, t) => gable(1 - s, t), 0.95)
    // Little clumps of planting along each slope.
    for (let i = 0; i < 26; i++) {
      const s = random()
      const z = HALL.z0 + 0.02 + random() * (depth - 0.04)
      const centre: Vec3 = [a + s * tooth, H + s * HALL.rise + 0.008, z]
      const radius = between(0.008, 0.016)
      for (let j = 0; j < 30; j++) {
        const dir = onSphere()
        if (dir[1] < -0.2) continue
        flat(add(centre, times(dir, radius)), unit(add(dir, [0, 0.6, 0])), 0.005, 0.004, 0.0015, jitter(pick(LEAF.slice(2)), 0.2), 0.8 + 0.2 * dir[1], {sheen: 0.7})
      }
    }
    // Blades of grass along each slope.
    for (let i = 0; i < 700; i++) {
      const s = random()
      const at: Vec3 = [a + s * tooth, H + s * HALL.rise, HALL.z0 + random() * depth]
      const tall = between(0.006, 0.016)
      const d = unit([between(-0.4, 0.4), 1, between(-0.4, 0.4)])
      long(add(at, times(d, tall * 0.5)), d, tall * 0.45, 0.0025, random() < 0.3 ? pick(GRASS_BRIGHT) : jitter(pick(GRASS), 0.2), unit([-0.3, 1, 0]), 0.9, {sheen: 0.6})
    }
  }

  // Inside: the floor, the timbered ceiling, a gantry with a robot hanging in it, lamps.
  const inner: Rect = {x0: HALL.x0 + HALL.thick, x1: HALL.x1 - HALL.thick, z0: HALL.z0 + HALL.thick, z1: HALL.z1 - HALL.thick}
  face([inner.x0, 0.004, inner.z0], [0, 0, inner.z1 - inner.z0], [inner.x1 - inner.x0, 0, 0], STEP * 1.4, (_s, t) => {
    const x = inner.x0 + t * (inner.x1 - inner.x0)
    const line = Math.abs(x - BELT.x) > BELT.half + 0.01 && Math.abs(x - BELT.x) < BELT.half + 0.02
    return {colour: jitter(line ? C.tangerine : mix(C.steel, C.amber, 0.25), 0.08), glow: line ? 0.5 : 0.3, open: 0.15}
  }, 0.15)
  face([inner.x0, H - 0.004, inner.z0], [inner.x1 - inner.x0, 0, 0], [0, 0, inner.z1 - inner.z0], STEP * 1.4, (s) => {
    const beam = ((s * (inner.x1 - inner.x0)) % 0.06) < 0.012
    return {colour: jitter(beam ? C.timber : mix(C.timberLight, C.amber, 0.3), 0.08), glow: 0.3, open: 0.05}
  }, 0.05)
  const gantry = (x: number) => box([x, 0.13, -0.5], AXES, [0.008, 0.13, 0.008], 0.004, plain(C.tangerine), 0.2, {glow: 0.35})
  gantry(-0.27)
  gantry(-0.03)
  box([-0.15, 0.255, -0.5], AXES, [0.13, 0.008, 0.01], 0.004, plain(C.tangerine), 0.2, {glow: 0.35})
  rod([-0.15, 0.247, -0.5], [-0.15, 0.19, -0.5], 0.003, C.steelDark, 0.2)
  box([-0.15, 0.16, -0.5], AXES, [0.03, 0.028, 0.02], 0.0035, plain(C.platinum), 0.2, {glow: 0.3})
  box([-0.33, 0.035, -0.3], AXES, [0.05, 0.035, 0.08], 0.004, (side) => ({colour: jitter(side === 2 ? C.timberLight : C.timber, 0.1)}), 0.2, {glow: 0.3})
  for (const x of [-0.32, -0.15, 0.02]) {
    rod([x, H, -0.3], [x, 0.27, -0.3], 0.002, C.steelDark, 0.1)
    ball([x, 0.262, -0.3], 0.009, C.lampHot, UP, 1, {glow: 1.5})
  }

  // The bay door: a shutter part way down, steel jambs, the crown sign above.
  const doorFront = HALL.z1
  face([DOOR.x - DOOR.half, -0.01, doorFront], [0, 0, -HALL.thick], [0, DOOR.top + 0.01, 0], STEP, plain(C.steelDark), 0.3)
  face([DOOR.x + DOOR.half, -0.01, doorFront - HALL.thick], [0, 0, HALL.thick], [0, DOOR.top + 0.01, 0], STEP, plain(C.steelDark), 0.3)
  face([DOOR.x - DOOR.half, DOOR.top, doorFront - HALL.thick], [2 * DOOR.half, 0, 0], [0, 0, HALL.thick], STEP, plain(C.steelDark), 0.2)
  face([DOOR.x - DOOR.half, DOOR.top - 0.03, doorFront - HALL.thick * 0.5], [2 * DOOR.half, 0, 0], [0, 0.03, 0], 0.004, (_s, t) => ({colour: jitter((t * 0.03) % 0.006 < 0.002 ? C.steelDark : C.steelLight, 0.05)}), 0.5)
  {
    const plaque: Vec3 = [DOOR.x, 0.252, doorFront + 0.008]
    box(plaque, AXES, [0.078, 0.046, 0.008], 0.004, plain(C.charcoal, 0.1), 0.6)
    const block = 0.018
    for (const [column, row] of CROWN_BLOCKS) {
      const centre = add(plaque, [column * block * CROWN_PITCH, row * block * CROWN_PITCH, 0.0095])
      face(add(centre, [-block / 2, -block / 2, 0]), [block, 0, 0], [0, block, 0], 0.003, () => ({colour: jitter(C.tangerine, 0.05), glow: 1.4}), 1)
    }
  }

  // The chimney: brick, a dark cap, a blinking light near the top.
  {
    const {x, z, half, top} = CHIMNEY
    face([x - half, -0.01, z + half], [2 * half, 0, 0], [0, top, 0], STEP, (s, t) => brick(s * 2 * half, t * top - 0.01), 0.9)
    face([x + half, -0.01, z - half], [-2 * half, 0, 0], [0, top, 0], STEP, (s, t) => brick(s * 2 * half + 0.007, t * top - 0.01), 0.9)
    face([x - half, -0.01, z - half], [0, 0, 2 * half], [0, top, 0], STEP, (s, t) => brick(s * 2 * half + 0.004, t * top - 0.01), 0.9)
    face([x + half, -0.01, z + half], [0, 0, -2 * half], [0, top, 0], STEP, (s, t) => brick(s * 2 * half + 0.011, t * top - 0.01), 0.9)
    box([x, top + 0.012, z], AXES, [half + 0.008, 0.012, half + 0.008], 0.004, (side) => ({colour: jitter(side === 2 ? C.charcoal : C.steelDark, 0.08)}), 0.9)
    box([x, top * 0.62, z], AXES, [half + 0.003, 0.012, half + 0.003], 0.004, plain(C.tangerine), 0.9)
    ball([x + half + 0.01, top - 0.02, z], 0.006, C.tangerine, UP, 1, {glow: 1.5, blink: 0.4})
    for (let i = 0; i < 220; i++) {
      const a = random() * Math.PI * 2
      const r = Math.sqrt(random()) * 0.025
      ball([x + Math.cos(a) * r, top + 0.03, z + Math.sin(a) * r], between(0.014, 0.022), jitter(mix(C.platinum, C.powder, 0.3), 0.05), SUN, 0.8, {kind: STEAM, phase: random(), opacity: 0.11})
    }
  }

  // ----- The glass hall: a barrel vault of glass on a brick plinth, plants and lamps inside -----
  {
    const {x0, x1, z, radius, plinth} = GLASSHOUSE
    const ribs = 8
    // Glass lit from inside: warm, with the cool gleam of the sky where it mirrors it.
    const glass = (): Look => ({colour: jitter(mix(times(C.glass, 0.5), C.amber, 0.35), 0.04), opacity: 0.12, shine: 0.5, glow: 0.35})
    const iron = (): Look => ({colour: jitter(C.steelDark, 0.08), shine: 0.3})
    const along = Math.round((x1 - x0) / 0.005)
    const round = Math.round((Math.PI * radius) / 0.005)
    for (let i = 0; i < along; i++) {
      for (let j = 0; j < round; j++) {
        const x = x0 + ((i + 0.5) / along) * (x1 - x0)
        const theta = ((j + 0.5) / round) * Math.PI
        const n: Vec3 = [0, Math.sin(theta), Math.cos(theta)]
        const at: Vec3 = [x, plinth + radius * n[1], z + radius * n[2]]
        const rib = Math.abs(((x - x0) / (x1 - x0)) * ribs - Math.round(((x - x0) / (x1 - x0)) * ribs)) * ((x1 - x0) / ribs) < 0.004
        const purlin = Math.abs((theta / Math.PI) * 8 - Math.round((theta / Math.PI) * 8)) * ((Math.PI * radius) / 8) < 0.003
        const look = rib || purlin ? iron() : glass()
        place({at, axes: [[1, 0, 0], unit(cross(n, [1, 0, 0])), n], reach: [0.0032, 0.0032, 0.0012], colour: look.colour, opacity: look.opacity ?? 0.985, facing: n, open: 0.9, glow: look.glow, shine: look.shine})
      }
    }
    // The far end: a half circle of glass with mullions and a door.
    face([x1, plinth, z + radius], [0, 0, -2 * radius], [0, radius, 0], 0.005, (s, t) => {
      const dz = (0.5 - s) * 2 * radius
      const dy = t * radius
      const d = Math.hypot(dz, dy)
      if (d > radius) return undefined
      if (Math.abs(dz) < 0.032 && dy < 0.11) return Math.abs(dz) > 0.032 - 0.005 || dy > 0.11 - 0.005 ? iron() : undefined
      const mullion = Math.abs(((dz + radius) % 0.04) - 0.02) > 0.0175 || d > radius - 0.005 || Math.abs(dy - 0.09) < 0.0025
      return mullion ? iron() : glass()
    }, 0.9)
    // The brick plinth all round, open at the door.
    const plinthWall = (corner: Vec3, along: Vec3, door: boolean) =>
      face(corner, along, [0, plinth + 0.01, 0], STEP, (s, t) => {
        const run = s * length(along)
        if (door && Math.abs(run - radius) < 0.032) return undefined
        return t > 0.85 ? {colour: jitter(C.stone, 0.06)} : brick(run, t * (plinth + 0.01) - 0.01)
      }, 0.9)
    plinthWall([x0, -0.01, z + radius], [x1 - x0, 0, 0], false)
    plinthWall([x1, -0.01, z - radius], [x0 - x1, 0, 0], false)
    plinthWall([x1, -0.01, z + radius], [0, 0, -2 * radius], true)
    // Inside: a warm floor, beds of plants down both sides, lamps along the ridge.
    face([x0, 0.006, z - radius], [0, 0, 2 * radius], [x1 - x0, 0, 0], STEP * 1.3, (s) => {
      const dz = Math.abs(s - 0.5) * 2 * radius
      return {colour: jitter(dz < 0.035 ? mix(C.stone, C.amber, 0.3) : C.soil, 0.12), glow: 0.25, open: 0.3}
    }, 0.3)
    for (let i = 0; i < 46; i++) {
      const side = random() < 0.5 ? -1 : 1
      const centre: Vec3 = [between(x0 + 0.03, x1 - 0.03), between(0.03, 0.1), z + side * between(0.06, 0.12)]
      const radiusOfPlant = between(0.02, 0.04)
      const flowering = random() < 0.3
      for (let j = 0; j < 120; j++) {
        const dir = onSphere()
        if (centre[1] + dir[1] * radiusOfPlant < 0.01) continue
        const colour = flowering && random() < 0.12 ? pick(FLOWERS) : jitter(pick(LEAF.slice(1)), 0.2)
        flat(add(centre, times(dir, radiusOfPlant * (0.7 + 0.3 * random()))), unit(add(dir, [0, 0.5, 0])), 0.006, 0.0045, 0.0015, colour, 0.45 + 0.3 * dir[1], {glow: 0.5, sheen: 0.5})
      }
    }
    for (const x of [0.32, 0.45, 0.58]) {
      rod([x, plinth + radius, z], [x, plinth + radius - 0.03, z], 0.002, C.steelDark, 0.3)
      ball([x, plinth + radius - 0.036, z], 0.008, C.lampHot, UP, 1, {glow: 1.5})
    }
  }

  // ----- Solar panels in three rows, tilted to the sky -----
  for (const row of SOLAR.rows) {
    const length3 = SOLAR.x1 - SOLAR.x0
    const up: Vec3 = [0, Math.sin(SOLAR.tilt) * SOLAR.depth, -Math.cos(SOLAR.tilt) * SOLAR.depth]
    const corner: Vec3 = [SOLAR.x0, 0.035, row + 0.5 * Math.cos(SOLAR.tilt) * SOLAR.depth]
    const panels = 3
    face(corner, [length3, 0, 0], up, 0.004, (s, t) => {
      const across = s * panels
      const which = Math.floor(across)
      const within = across - which
      const gap = 0.006 / (length3 / panels)
      if (within < gap / 2 || within > 1 - gap / 2) return undefined
      const frame = within < gap / 2 + 0.012 || within > 1 - gap / 2 - 0.012 || t < 0.05 || t > 0.95
      if (frame) return {colour: jitter(C.steelLight, 0.05), shine: 0.6}
      const cell = Math.abs(within * 4 - Math.round(within * 4)) < 0.05 || Math.abs(t * 2 - Math.round(t * 2)) < 0.04
      return cell ? {colour: jitter(C.panelLine, 0.05), shine: 0.4} : {colour: jitter(C.panel, 0.1), shine: 0.7}
    }, 1)
    // The back of the panels, and their legs.
    face(add(corner, [0, -0.003, 0]), up, [length3, 0, 0], 0.006, plain(C.steelDark), 0.4)
    for (const s of [0.02, 0.5, 0.98]) {
      const x = SOLAR.x0 + s * length3
      rod([x, 0, corner[2]], [x, corner[1], corner[2]], 0.004, C.steel, 0.7)
      rod([x, 0, corner[2] + up[2]], [x, corner[1] + up[1], corner[2] + up[2]], 0.004, C.steel, 0.7)
    }
  }

  // ----- Two wind turbines, their blades turning -----
  for (const turbine of TURBINES) {
    const foot: Vec3 = [turbine.x, ground(turbine.x, turbine.z), turbine.z]
    box(add(foot, [0, 0.008, 0]), AXES, [0.035, 0.012, 0.035], 0.004, (side) => ({colour: jitter(side === 2 ? C.stone : mix(C.stone, C.steel, 0.4), 0.06)}), 0.8)
    drum(foot, [0.022, 0.011], turbine.height, 0.0045, (_a, h) => ({colour: jitter(h > 0.6 && h < 0.66 ? C.tangerine : C.platinum, 0.04)}), 0.95)
    const top = add(foot, [0, turbine.height, 0])
    box(add(top, [0, 0.012, -0.008]), AXES, [0.016, 0.014, 0.036], 0.0035, (side) => ({colour: jitter(side === 2 ? C.platinum : mix(C.platinum, C.steelLight, 0.3), 0.04)}), 0.95)
    ball(add(top, [0, 0.03, -0.03]), 0.005, C.tangerine, UP, 1, {glow: 1.5, blink: 0.5})
    const hub = add(top, [0, 0.012, 0.034])
    ball(hub, 0.012, C.platinum, [0, 0, 1], 0.95, {part: turbine.part})
    for (let k = 0; k < 3; k++) {
      const a = (k / 3) * Math.PI * 2 + 0.3
      const out: Vec3 = [Math.cos(a), Math.sin(a), 0]
      const steps = Math.round(turbine.blade / 0.006)
      for (let i = 0; i < steps; i++) {
        const t = (i + 0.5) / steps
        const width = 0.012 * (1 - t) + 0.005 + 0.004 * Math.sin(t * Math.PI)
        const colour = t > 0.86 ? C.tangerine : C.platinum
        place({at: add(hub, times(out, 0.01 + t * turbine.blade)), axes: [out, [-out[1], out[0], 0], [0, 0, 1]], reach: [0.0042, width * 0.5, 0.0012], colour: jitter(colour, 0.03), opacity: 0.99, facing: unit([0, 0.25, 1]), open: 1, part: turbine.part})
      }
    }
  }

  // ----- The water tower: legs, braces, a riveted tank with a ladder, wrapped in vines -----
  {
    const {x, z, legs, radius, tank} = TOWER
    const foot: Vec3 = [x, ground(x, z), z]
    const corners: Vec3[] = [[1, 0, 1], [1, 0, -1], [-1, 0, -1], [-1, 0, 1]]
    const legTop = (c: Vec3): Vec3 => add(foot, [c[0] * radius * 0.72, legs, c[2] * radius * 0.72])
    const legFoot = (c: Vec3): Vec3 => add(foot, [c[0] * radius * 1.05, 0, c[2] * radius * 1.05])
    for (const c of corners) rod(legFoot(c), legTop(c), 0.0065, C.timber, 0.8)
    for (let k = 0; k < 4; k++) {
      const p = corners[k]!
      const q = corners[(k + 1) % 4]!
      for (const [low, high] of [[0.05, 0.45], [0.45, 0.85]] as const) {
        rod(mix(legFoot(p), legTop(p), low), mix(legFoot(q), legTop(q), high), 0.0025, C.timberLight, 0.8)
        rod(mix(legFoot(q), legTop(q), low), mix(legFoot(p), legTop(p), high), 0.0025, C.timberLight, 0.8)
      }
    }
    const tankFoot = add(foot, [0, legs, 0])
    drum(tankFoot, [radius, radius], tank, 0.0045, (a, h) => {
      const seam = [0.08, 0.5, 0.92].some(level => Math.abs(h - level) < 0.02) || Math.abs(((a * 12) % 1) - 0.5) > 0.47
      const streak = 0.5 + 0.5 * Math.sin(a * 40 + h * 3)
      return {colour: jitter(seam ? times(C.patina, 0.78) : mix(C.patina, C.powder, 0.3 * streak), 0.05), shine: 0.3}
    }, 0.95)
    // Rivets: bright points along every seam.
    for (const level of [0.08, 0.5, 0.92]) {
      for (let i = 0; i < 40; i++) {
        const a = (i / 40) * Math.PI * 2
        const out: Vec3 = [Math.cos(a), 0, Math.sin(a)]
        ball(add(tankFoot, [out[0] * (radius + 0.002), level * tank, out[2] * (radius + 0.002)]), 0.0022, C.steelLight, out, 0.95, {shine: 0.8})
      }
    }
    for (let k = 0; k < 12; k++) {
      const a = (k / 12) * Math.PI * 2
      const out: Vec3 = [Math.cos(a), 0, Math.sin(a)]
      for (let i = 0; i < 9; i++) ball(add(tankFoot, [out[0] * (radius + 0.002), (0.14 + i * 0.09) * tank, out[2] * (radius + 0.002)]), 0.0022, C.steelLight, out, 0.95, {shine: 0.8})
    }
    face(add(tankFoot, [-radius, 0, -radius]), [2 * radius, 0, 0], [0, 0, 2 * radius], 0.006, (s, t) => (Math.hypot(s - 0.5, t - 0.5) < 0.5 ? {colour: jitter(times(C.patina, 0.6), 0.05)} : undefined), 0.5)
    drum(add(tankFoot, [0, tank, 0]), [radius + 0.008, 0.004], 0.07, 0.0045, (a) => ({colour: jitter(Math.abs(((a * 16) % 1) - 0.5) > 0.42 ? times(C.slate, 0.7) : C.slate, 0.06)}), 1)
    ball(add(tankFoot, [0, tank + 0.075, 0]), 0.007, C.tangerine, UP, 1)
    // The ladder up the front leg.
    const ladderFoot = legFoot([1, 0, 1])
    const ladderTop = add(tankFoot, [radius * 0.72, tank, radius * 0.72])
    const sideways = unit([1, 0, -1])
    for (const offset of [-0.012, 0.012]) rod(add(ladderFoot, times(sideways, offset)), add(add(ladderTop, times(sideways, offset)), [0.008, 0, 0.008]), 0.0018, C.steel, 0.9)
    for (let i = 1; i < 26; i++) {
      const p = mix(ladderFoot, add(ladderTop, [0.008, 0, 0.008]), i / 26)
      rod(add(p, times(sideways, -0.012)), add(p, times(sideways, 0.012)), 0.0016, C.steelLight, 0.9)
    }
    // Vines climbing two legs and spilling over the tank.
    const vine = (path: (t: number) => Vec3, leaves: number) => {
      for (let i = 0; i < leaves; i++) {
        const t = random()
        const at = add(path(t), times(onSphere(), 0.006))
        flat(at, unit(add(onSphere(), [0.3, 0.5, 0.3])), between(0.004, 0.0065), 0.0035, 0.0012, jitter(pick(LEAF), 0.2), 0.8, {sheen: 0.6})
      }
    }
    for (const c of [corners[0]!, corners[2]!]) {
      vine(t => {
        const p = mix(legFoot(c), legTop(c), t)
        const a = t * 18
        return add(p, [Math.cos(a) * 0.009, 0, Math.sin(a) * 0.009])
      }, 520)
    }
    vine(t => {
      const a = t * Math.PI * 2.4 + 0.6
      return add(tankFoot, [Math.cos(a) * (radius + 0.004), tank * (0.2 + 0.7 * Math.abs(Math.sin(t * 7))), Math.sin(a) * (radius + 0.004)])
    }, 900)
    for (let k = 0; k < 9; k++) {
      const a = random() * Math.PI * 2
      const start = add(tankFoot, [Math.cos(a) * (radius + 0.005), between(0, 0.02), Math.sin(a) * (radius + 0.005)])
      const hang = between(0.03, 0.09)
      vine(t => add(start, [0, -t * hang, 0]), Math.round(hang * 900))
    }
    // The downpipe, and the pipe along the ground to the glass hall.
    const pipe = (points: readonly Vec3[]) => {
      for (let k = 0; k + 1 < points.length; k++) {
        rod(points[k]!, points[k + 1]!, 0.0065, C.copper, 0.85, {shine: 0.5})
        const span = length(sub(points[k + 1]!, points[k]!))
        for (let i = 1; i < span / 0.06; i++) rod(mix(points[k]!, points[k + 1]!, (i * 0.06 - 0.003) / span), mix(points[k]!, points[k + 1]!, (i * 0.06 + 0.003) / span), 0.0085, times(C.copper, 0.75), 0.85)
      }
    }
    pipe([add(tankFoot, [0, 0, 0]), add(foot, [0, 0.025, 0]), [x - 0.03, 0.025, GLASSHOUSE.z + 0.04], [GLASSHOUSE.x1, 0.025, GLASSHOUSE.z + 0.04]])
    pipe([[HALL.x0 - 0.008, 0, -0.2], [HALL.x0 - 0.008, HALL.wall - 0.01, -0.2], [HALL.x0 - 0.008, HALL.wall - 0.01, -0.28]])
    pipe([[HALL.x0 + 0.02, 0.06, HALL.z0 - 0.008], [HALL.x1, 0.06, HALL.z0 - 0.008]])
  }

  // ----- The conveyor, its moving belt, and the crate at its end -----
  {
    const {x, z0, z1, top, half} = BELT
    const span = z1 - z0
    face([x - half, top, z0], [0, 0, span], [2 * half, 0, 0], 0.005, () => ({colour: jitter(C.rubber, 0.08)}), 0.7)
    face([x - half, top - 0.02, z0], [2 * half, 0, 0], [0, 0, span], 0.007, plain(C.steelDark), 0.3)
    for (let k = 0; k < span / BELT.slat; k++) {
      long([x, top + 0.0012, z0 + k * BELT.slat], [1, 0, 0], half * 0.92, 0.0022, C.steel, UP, 0.8, {part: PART.belt})
    }
    for (const side of [-1, 1]) {
      box([x + side * (half + 0.006), top - 0.01, z0 + span / 2], AXES, [0.006, 0.017, span / 2], 0.0045, plain(C.tangerine, 0.05), 0.85)
      for (let z = z0 + 0.05; z < z1; z += 0.1) rod([x + side * (half + 0.006), 0, z], [x + side * (half + 0.006), top - 0.027, z], 0.004, C.steelDark, 0.7)
    }
    rod([x - half - 0.01, top - 0.01, z1], [x + half + 0.01, top - 0.01, z1], 0.012, C.steel, 0.8)
    // The crate the robots drop into.
    const crate: Vec3 = [CRATE.x, CRATE.top / 2 - 0.005, (CRATE.z0 + CRATE.z1) / 2]
    const plank = (side: number, _s: number, t: number): Look | undefined =>
      side === 2 ? undefined : {colour: jitter((t * 5) % 1 < 0.14 ? C.timber : C.timberLight, 0.1)}
    box(crate, AXES, [CRATE.half, CRATE.top / 2 + 0.005, (CRATE.z1 - CRATE.z0) / 2], 0.0045, plank, 0.85)
    box(crate, AXES, [CRATE.half - 0.006, CRATE.top / 2, (CRATE.z1 - CRATE.z0) / 2 - 0.006], 0.006, (side) => (side === 2 ? undefined : {colour: jitter(times(C.timber, 0.8), 0.1)}), 0.3)
  }

  // ----- Robots -----
  type Robot = {
    readonly foot: Vec3
    readonly yaw: number
    readonly part: number
    /** 0 a bare frame, 1 plated without a head, 2 finished but not switched on, 3 finished and awake. */
    readonly stage: 0 | 1 | 2 | 3
    readonly legs?: readonly [number, number]
    readonly arm?: number
    readonly carrying?: boolean
  }
  const robot = (r: Robot) => {
    const forward: Vec3 = [Math.sin(r.yaw), 0, Math.cos(r.yaw)]
    const across: Vec3 = [Math.cos(r.yaw), 0, -Math.sin(r.yaw)]
    const axes: readonly [Vec3, Vec3, Vec3] = [across, UP, forward]
    const at = (p: Vec3): Vec3 => add(add(add(r.foot, times(across, p[0])), [0, p[1], 0]), times(forward, p[2]))
    const open = 0.9
    const step = 0.0034
    for (const k of [-1, 1]) {
      const leg = r.legs ? r.legs[k < 0 ? 0 : 1] : r.part
      rod(at([k * 0.015, 0.006, 0]), at([k * 0.015, 0.044, 0]), 0.0072, C.steelDark, open, {part: leg})
      box(at([k * 0.015, 0.004, 0.004]), axes, [0.009, 0.0045, 0.013], step, plain(C.charcoal), open, {part: leg})
    }
    box(at([0, 0.047, 0]), axes, [0.024, 0.006, 0.015], step, plain(C.steel), open, {part: r.part})
    if (r.stage === 0) {
      // A bare frame: the torso's edges in steel round a dark core.
      box(at([0, 0.077, 0]), axes, [0.02, 0.02, 0.013], step, plain(C.steelDark), 0.6, {part: r.part})
      for (const [a, c] of [[-1, -1], [-1, 1], [1, -1], [1, 1]] as const) {
        rod(at([a * 0.028, 0.053, c * 0.019]), at([a * 0.028, 0.101, c * 0.019]), 0.0028, C.steelLight, open, {part: r.part})
      }
      for (const y of [0.053, 0.101]) {
        for (const c of [-1, 1]) rod(at([-0.028, y, c * 0.019]), at([0.028, y, c * 0.019]), 0.0028, C.steelLight, open, {part: r.part})
        for (const a of [-1, 1]) rod(at([a * 0.028, y, -0.019]), at([a * 0.028, y, 0.019]), 0.0028, C.steelLight, open, {part: r.part})
      }
      return
    }
    box(at([0, 0.077, 0]), axes, [0.029, 0.025, 0.02], step, (side, s, t) => {
      if (side === 4 && Math.abs(s - 0.5) < 0.2 && Math.abs(t - 0.55) < 0.22) return {colour: jitter(C.tangerine, 0.05)}
      if (side === 4 && Math.abs(s - 0.8) < 0.07 && Math.abs(t - 0.8) < 0.07) return {colour: C.powder, glow: r.stage === 3 ? 1.3 : 0, blink: r.stage === 3 ? 1 : 0}
      return {colour: jitter(t < 0.12 ? C.steelLight : C.platinum, 0.04)}
    }, open, {part: r.part})
    for (const k of [-1, 1]) {
      ball(at([k * 0.035, 0.094, 0]), 0.0085, C.tangerine, UP, open, {part: r.part})
      const arm = k > 0 && r.arm !== undefined ? r.arm : r.part
      if (r.stage === 1 && k > 0) continue
      const hand: Vec3 = r.carrying ? [k * 0.026, 0.074, 0.036] : r.arm !== undefined && k > 0 ? [k * 0.04, 0.084, 0.03] : [k * 0.04, 0.058, 0.004]
      rod(at([k * 0.037, 0.092, 0]), at(hand), 0.0048, C.steel, open, {part: arm})
      ball(at(hand), 0.0062, C.platinum, UP, open, {part: arm})
      if (r.arm !== undefined && k > 0) {
        // A watering can in its hand.
        box(at([k * 0.04, 0.072, 0.042]), axes, [0.008, 0.01, 0.012], 0.003, plain(C.tangerine), open, {part: arm})
        rod(at([k * 0.04, 0.074, 0.054]), at([k * 0.04, 0.084, 0.07]), 0.0022, C.tangerine, open, {part: arm})
      }
    }
    if (r.carrying) {
      box(at([0, 0.074, 0.046]), axes, [0.026, 0.017, 0.016], 0.0034, (side, _s, t) => (side === 2 ? {colour: jitter(C.soil, 0.1)} : {colour: jitter((t * 3) % 1 < 0.2 ? C.timber : C.timberLight, 0.08)}), open, {part: r.part})
      for (let i = 0; i < 14; i++) ball(at([between(-0.02, 0.02), 0.094 + between(0, 0.008), 0.046 + between(-0.012, 0.012)]), 0.0045, jitter(pick(GRASS_BRIGHT), 0.1), UP, 1, {part: r.part, sheen: 0.6})
    }
    if (r.stage === 1) return
    rod(at([0, 0.101, 0]), at([0, 0.108, 0]), 0.006, C.steelDark, open, {part: r.part})
    box(at([0, 0.122, 0]), axes, [0.024, 0.016, 0.019], step, (side, _s, t) => {
      if (side === 4 && t > 0.25 && t < 0.8) return {colour: jitter(C.charcoal, 0.1), shine: 0.6}
      return {colour: jitter(C.platinum, 0.04)}
    }, open, {part: r.part})
    for (const k of [-1, 1]) ball(at([k * 0.009, 0.1235, 0.0205]), 0.0042, r.stage === 3 ? C.eye : times(C.eye, 0.25), forward, 1, {part: r.part, glow: r.stage === 3 ? 1.7 : 0})
    if (r.stage === 3) {
      rod(at([0.012, 0.138, 0]), at([0.016, 0.156, 0]), 0.002, C.steel, open, {part: r.part})
      ball(at([0.016, 0.159, 0]), 0.0048, C.tangerine, UP, 1, {part: r.part, glow: 1.5, blink: 0.6})
    }
  }
  // Three robots at three stages on the belt, built where the belt leaves the door.
  PART.carried.forEach((part, k) => robot({foot: [BELT.x, BELT.top, 0], yaw: 0, part, stage: k as 0 | 1 | 2}))
  const walkerRest = onLoop(0)
  robot({foot: walkerRest.at, yaw: walkerRest.yaw, part: PART.walker, stage: 3, legs: [PART.legs[0]!, PART.legs[1]!], carrying: true})
  const tenderFoot: Vec3 = [TENDER.foot[0], ground(TENDER.foot[0], TENDER.foot[2]), TENDER.foot[2]]
  robot({foot: tenderFoot, yaw: TENDER.yaw, part: 0, stage: 3, arm: PART.watering})

  // The arm: a base, a turret, an upper arm and a forearm with a gripper, in Tangerine.
  {
    const {base, shoulder, elbow, wrist} = ARM
    drum(base, [0.032, 0.028], 0.035, 0.0045, (_a, h) => ({colour: jitter(h > 0.75 ? C.tangerine : C.steelDark, 0.06)}), 0.85)
    ball(add(base, [0.02, 0.03, 0.02]), 0.004, C.powder, UP, 1, {glow: 1.4, blink: 1.2})
    box(add(base, [0, 0.045, 0]), AXES, [0.022, 0.012, 0.022], 0.0035, plain(C.charcoal), 0.85, {part: PART.turret})
    const segment = (from: Vec3, to: Vec3, thick: number, part: number) => {
      const d = unit(sub(to, from))
      const side = unit(cross(d, [0, 0, 1]))
      box(mix(from, to, 0.5), [d, side, unit(cross(d, side))], [length(sub(to, from)) / 2, thick, thick * 0.9], 0.0035, plain(C.tangerine, 0.05), 0.9, {part})
    }
    segment(shoulder, elbow, 0.0075, PART.upperArm)
    ball(shoulder, 0.011, C.steelDark, UP, 0.85, {part: PART.upperArm})
    segment(elbow, wrist, 0.0065, PART.forearm)
    ball(elbow, 0.009, C.steelDark, UP, 0.85, {part: PART.forearm})
    for (const k of [-1, 1]) rod(add(wrist, [0, 0, k * 0.008]), add(wrist, [0, -0.03, k * 0.006]), 0.0028, C.steelLight, 0.9, {part: PART.forearm})
  }

  // ----- The pond, its stones, lily pads and reeds -----
  face([POND.x - POND.a, 0.002, POND.z - POND.b], [0, 0, 2 * POND.b], [2 * POND.a, 0, 0], 0.005, (s, t) => {
    const x = POND.x - POND.a + t * 2 * POND.a
    const z = POND.z - POND.b + s * 2 * POND.b
    return inPond(x, z) ? {colour: jitter(C.water, 0.06), shine: 0.6} : undefined
  }, 1, {kind: WATER, phase: 0.3})
  for (let i = 0; i < 70; i++) {
    const a = (i / 70) * Math.PI * 2 + between(-0.03, 0.03)
    const x = POND.x + Math.cos(a) * (POND.a + 0.008)
    const z = POND.z + Math.sin(a) * (POND.b + 0.008)
    const centre: Vec3 = [x, ground(x, z) + 0.004, z]
    const size = between(0.008, 0.014)
    for (let j = 0; j < 22; j++) {
      const dir = onSphere()
      if (dir[1] < -0.3) continue
      flat(add(centre, [dir[0] * size, dir[1] * size * 0.6, dir[2] * size]), dir, size * 0.5, size * 0.4, 0.001, jitter(pick(STONES), 0.1), 0.6 + 0.4 * dir[1])
    }
  }
  for (let i = 0; i < 7; i++) {
    const a = random() * Math.PI * 2
    const r = Math.sqrt(random()) * 0.7
    const centre: Vec3 = [POND.x + Math.cos(a) * POND.a * r, 0.004, POND.z + Math.sin(a) * POND.b * r]
    face(add(centre, [-0.014, 0, -0.014]), [0, 0, 0.028], [0.028, 0, 0], 0.004, (s, t) => (Math.hypot(s - 0.5, t - 0.5) < 0.5 && Math.atan2(t - 0.5, s - 0.5) > -2.6 + a ? {colour: jitter(LEAF[3]!, 0.12)} : undefined), 1)
    if (i < 2) ball(add(centre, [0, 0.006, 0]), 0.0055, FLOWERS[0]!, UP, 1)
  }
  for (let i = 0; i < 90; i++) {
    const a = between(-2.4, -0.9)
    const x = POND.x + Math.cos(a) * POND.a * between(0.85, 1.05)
    const z = POND.z + Math.sin(a) * POND.b * between(0.85, 1.05)
    const tall = between(0.03, 0.075)
    const d = unit([between(-0.15, 0.15), 1, between(-0.15, 0.15)])
    long(add([x, 0.0, z], times(d, tall / 2)), d, tall * 0.48, 0.0022, jitter(random() < 0.3 ? GRASS_BRIGHT[0]! : LEAF[2]!, 0.15), unit([0.3, 0.6, 0.5]), 0.9, {sheen: 0.7})
  }

  // ----- Beds, a trough of flowers, fruit trees -----
  const raisedBed = (r: Rect, height: number, crops: "greens" | "flowers") => {
    const centre: Vec3 = [(r.x0 + r.x1) / 2, height / 2 - 0.005, (r.z0 + r.z1) / 2]
    const half: Vec3 = [(r.x1 - r.x0) / 2, height / 2 + 0.005, (r.z1 - r.z0) / 2]
    box(centre, AXES, half, 0.0045, (side, _s, t) => (side === 2 ? {colour: jitter(C.soil, 0.15), open: 0.8} : {colour: jitter((t * 3) % 1 < 0.18 ? C.timber : C.timberLight, 0.1)}), 0.85)
    const count = Math.round(((r.x1 - r.x0) * (r.z1 - r.z0)) / 0.0012)
    for (let i = 0; i < count; i++) {
      const plant: Vec3 = [between(r.x0 + 0.012, r.x1 - 0.012), height + 0.008, between(r.z0 + 0.012, r.z1 - 0.012)]
      const size = between(0.008, 0.014)
      const fruit = crops === "greens" && random() < 0.3
      for (let j = 0; j < 40; j++) {
        const dir = onSphere()
        if (dir[1] < -0.3) continue
        const colour = crops === "flowers" && random() < 0.35 ? pick(FLOWERS) : fruit && random() < 0.15 ? hex("#c43c4c") : jitter(pick(LEAF.slice(2)), 0.2)
        flat(add(plant, times(dir, size)), unit(add(dir, [0, 0.5, 0])), 0.0045, 0.0035, 0.0012, colour, 0.65 + 0.3 * dir[1], {sheen: 0.6})
      }
    }
  }
  for (const bed of BEDS) raisedBed(bed, 0.035, "greens")
  raisedBed(TROUGH, 0.03, "flowers")

  for (const [k, tree] of TREES.entries()) {
    const foot = onGrass(tree[0], tree[2])
    const trunkTop = add(foot, [0.01, 0.13, 0])
    for (let i = 0; i < 200; i++) {
      const t = random()
      const a = random() * Math.PI * 2
      const radius = 0.012 * (1 - t * 0.5)
      const centre = mix(foot, trunkTop, t)
      const out: Vec3 = [Math.cos(a), 0, Math.sin(a)]
      place({at: add(centre, times(out, radius)), axes: [UP, unit(cross(UP, out)), out], reach: [0.006, 0.003, 0.001], colour: jitter(pick(BARK), 0.15), opacity: 0.98, facing: out, open: 0.6})
    }
    const crown = add(trunkTop, [0, 0.05, 0])
    for (let c = 0; c < 9; c++) {
      const dir = onSphere()
      const cluster = add(crown, [dir[0] * 0.06, dir[1] * 0.045, dir[2] * 0.06])
      const radius = between(0.04, 0.055)
      for (let i = 0; i < 520; i++) {
        const leaf = onSphere()
        const depthIn = 0.6 + 0.4 * Math.sqrt(random())
        const at = add(cluster, times(leaf, radius * depthIn))
        if (at[1] < trunkTop[1] - 0.025) continue
        const shade = Math.min(0.999, random() * 0.7 + 0.35 * smoothstep(-0.3, 0.8, leaf[1]) * depthIn)
        flat(at, unit(add(leaf, times(onSphere(), 0.35))), between(0.006, 0.009), 0.0045, 0.0015, jitter(LEAF[Math.floor(shade * LEAF.length)]!, 0.15), clamp01((0.35 + 0.65 * depthIn) * (0.55 + 0.45 * leaf[1])), {sheen: 0.8})
      }
    }
    for (let i = 0; i < 22 + k * 6; i++) {
      const dir = onSphere()
      if (dir[1] < -0.4) continue
      ball(add(crown, [dir[0] * 0.1, dir[1] * 0.075, dir[2] * 0.1]), 0.0065, C.tangerine, dir, 0.9)
    }
  }

  // ----- Lamp posts and strings of lights -----
  const lanterns: Vec3[] = []
  for (const lamp of LAMPS) {
    const foot = onGrass(lamp[0], lamp[2])
    rod(foot, add(foot, [0, 0.17, 0]), 0.0042, C.steelDark, 0.8)
    const head = add(foot, [0, 0.183, 0])
    box(head, AXES, [0.009, 0.012, 0.009], 0.003, () => ({colour: jitter(C.lamp, 0.05), glow: 1.6}), 1)
    box(add(head, [0, 0.016, 0]), AXES, [0.013, 0.004, 0.013], 0.003, plain(C.steelDark), 0.9)
    lanterns.push(head)
  }
  const string = (from: Vec3, to: Vec3, sag: number) => {
    const bulbs = Math.round(length(sub(to, from)) / 0.032)
    const along = (t: number): Vec3 => add(mix(from, to, t), [0, -sag * 4 * t * (1 - t), 0])
    for (let i = 0; i < bulbs * 3; i++) {
      const t = (i + 0.5) / (bulbs * 3)
      long(along(t), sub(along(t + 0.01), along(t - 0.01)), length(sub(to, from)) / (bulbs * 3) * 0.7, 0.0012, C.charcoal, UP, 0.6)
    }
    for (let i = 1; i < bulbs; i++) {
      const colour = i % 3 === 0 ? C.tangerine : i % 3 === 1 ? C.lamp : C.lampHot
      ball(add(along(i / bulbs), [0, -0.004, 0]), 0.0042, colour, UP, 1, {glow: 1.6})
    }
  }
  string([HALL.x1, HALL.wall - 0.01, HALL.z1 + 0.005], add(lanterns[0]!, [0, 0.01, 0]), 0.05)
  string(add(lanterns[0]!, [0, 0.01, 0]), add(lanterns[1]!, [0, 0.01, 0]), 0.06)
  string([HALL.x0, HALL.wall - 0.01, HALL.z1 + 0.005], add(lanterns[2]!, [0, 0.01, 0]), 0.05)

  // Vines hanging from the hall's eaves.
  for (const x of [HALL.x0 + 0.02, HALL.x0 + 0.115, -0.31, 0.02, HALL.x1 - 0.02]) {
    for (let k = 0; k < 3; k++) {
      const start: Vec3 = [x + between(-0.015, 0.015), HALL.wall + 0.005, HALL.z1 + 0.004]
      const hang = between(0.05, 0.13)
      for (let i = 0; i < hang * 700; i++) {
        const t = random()
        flat(add(start, [Math.sin(t * 9 + k) * 0.004, -t * hang, 0.003]), unit(add(onSphere(), [0, 0.4, 0.8])), between(0.004, 0.006), 0.0035, 0.0012, jitter(pick(LEAF), 0.2), 0.8, {sheen: 0.6})
      }
    }
  }

  // ----- The paths: a loop of stepping stones round the pond, and a way to the door -----
  const paver = (at: Vec3, size: number) => {
    const colour = jitter(pick([C.stone, C.stone, STONES[3]!, STONES[1]!]), 0.08)
    for (let j = 0; j < 7; j++) {
      const offset: Vec3 = [between(-0.5, 0.5) * size, 0, between(-0.5, 0.5) * size]
      flat(add(add(at, offset), [0, 0.003, 0]), UP, size * 0.55, size * 0.45, 0.0015, jitter(colour, 0.05), 0.95)
    }
  }
  for (let i = 0; i < 64; i++) {
    const a = (i / 64) * Math.PI * 2
    for (const across of [-0.016, 0.016]) {
      const x = LOOP.x + (LOOP.a + across) * Math.cos(a)
      const z = LOOP.z + (LOOP.b + across) * Math.sin(a)
      paver(onGrass(x, z), 0.016)
    }
  }
  for (let i = 0; i < 18; i++) {
    const p = mix([0.05, 0, -0.07], [LOOP.x - LOOP.a, 0, LOOP.z], (i + 0.5) / 18)
    for (const across of [-0.016, 0.016]) paver(onGrass(p[0] + across, p[2]), 0.016)
  }

  // ----- The grass, flowers and fireflies -----
  for (let i = 0; i < 30_000; i++) {
    const a = random() * Math.PI * 2
    const r = Math.sqrt(random()) * rim(a) * 0.985
    const x = r * Math.cos(a)
    const z = r * Math.sin(a)
    if (FOOTPRINTS.some(f => outside(x, z, f) === 0) || inPond(x, z)) continue
    const patch = 0.5 + 0.5 * Math.sin(4.3 * x + 1.1) * Math.cos(3.7 * z - 0.6)
    const colour = random() < 0.1 ? pick(GRASS) : random() < 0.08 ? pick(GRASS_BRIGHT) : jitter(mix(GRASS[3]!, GRASS[1]!, patch), 0.18)
    flat(onGrass(x, z), UP, between(0.011, 0.016), between(0.009, 0.013), 0.003, colour, groundOpen(x, z))
  }
  for (let i = 0; i < 11_000; i++) {
    const a = random() * Math.PI * 2
    const r = Math.pow(random(), 0.4) * rim(a) * 0.99
    const x = r * Math.cos(a)
    const z = r * Math.sin(a)
    if (FOOTPRINTS.some(f => outside(x, z, f) < 0.01) || inPond(x, z, 0.02)) continue
    const tall = between(0.012, 0.038)
    const d = unit([between(-0.35, 0.35), 1, between(-0.35, 0.35)])
    const colour = random() < 0.3 ? pick(GRASS_BRIGHT) : jitter(pick(GRASS), 0.2)
    long(add(onGrass(x, z), times(d, tall * 0.5)), d, tall * 0.45, 0.004, colour, unit([Math.cos(a), 1.4, Math.sin(a)]), groundOpen(x, z), {sheen: 0.6})
  }
  for (let i = 0; i < 260; i++) {
    const a = random() * Math.PI * 2
    const r = Math.sqrt(random()) * 0.95
    const x = r * Math.cos(a)
    const z = r * Math.sin(a)
    if (FOOTPRINTS.some(f => outside(x, z, f) < 0.03) || inPond(x, z, 0.04) || (x < -0.5 && z > 0.02 && z < 0.5)) continue
    const stem = between(0.012, 0.03)
    long(add(onGrass(x, z), [0, stem / 2, 0]), UP, stem * 0.45, 0.0025, GRASS[0]!, UP, 0.8)
    flat(add(onGrass(x, z), [0, stem, 0]), UP, 0.006, 0.0055, 0.002, jitter(pick(FLOWERS), 0.08), 0.95)
  }
  for (let i = 0; i < 50; i++) {
    const near = random() < 0.5 ? [POND.x, POND.z] : random() < 0.5 ? [TREES[0]![0], TREES[0]![2]] : [TREES[1]![0], TREES[1]![2]]
    const a = random() * Math.PI * 2
    const r = between(0.05, 0.22)
    ball([near[0]! + Math.cos(a) * r, between(0.05, 0.24), near[1]! + Math.sin(a) * r], 0.0032, C.firefly, UP, 1, {kind: FIREFLY, phase: random(), glow: 1.3})
  }

  // ----- Underneath: earth, roots, and a pipe hanging down with a valve -----
  const under = growUnderside(b, {rim, height: ground, depth: 0.6, tip: [-0.05, 0, 0.04], grass: GRASS, shade: hex("#1e4a3a"), earth: EARTH, stone: STONES, roots: BARK})
  {
    const from = under(2.2, 0.55)
    const bend = add(from, [0.02, -0.14, 0.03])
    const end = add(bend, [0.08, -0.03, 0.05])
    rod(from, bend, 0.008, C.copper, 0.6, {shine: 0.5})
    rod(bend, end, 0.008, C.copper, 0.6, {shine: 0.5})
    drum(add(end, [0, -0.012, 0]), [0.012, 0.012], 0.024, 0.004, () => ({colour: jitter(times(C.copper, 0.8), 0.06)}), 0.6)
    for (let i = 0; i < 18; i++) {
      const a = (i / 18) * Math.PI * 2
      ball(add(bend, [0.03 * Math.cos(a), 0.0, 0.03 * Math.sin(a)]), 0.004, C.tangerine, UP, 0.7)
    }
    for (let i = 0; i < 500; i++) {
      const t = random()
      const p = t < 0.75 ? mix(from, bend, t / 0.75) : mix(bend, end, (t - 0.75) / 0.25)
      const a = t * 30
      flat(add(p, [Math.cos(a) * 0.011, 0, Math.sin(a) * 0.011]), unit(onSphere()), 0.0045, 0.0035, 0.0012, jitter(pick(LEAF), 0.2), 0.55, {sheen: 0.5})
    }
  }

  const warm: Vec3 = [1.0, 0.62, 0.3]
  const doorLight: Vec3 = [DOOR.x, 0.1, HALL.z1 + 0.04]
  const lighting: Lighting = {
    key: SUN,
    keyColour: [1.0, 0.76, 0.58],
    sky: [0.4, 0.36, 0.58],
    bounce: [0.5, 0.34, 0.38],
    rim: RIM,
    rimColour: [0.62, 0.74, 0.92],
    shineColour: [0.7, 0.82, 1.0],
    warm,
    lamps: [
      {at: doorLight, strength: 1.3, reach: 0.2},
      {at: [-0.15, 0.24, -0.32], strength: 1.0, reach: 0.22},
      {at: [0.45, 0.15, GLASSHOUSE.z], strength: 1.4, reach: 0.2},
      ...lanterns.map(at => ({at, strength: 0.9, reach: 0.15})),
    ],
  }
  const {count, data, reach} = b.finish(lighting)
  const glows: readonly Glow[] = [
    {at: [DOOR.x, 0.09, HALL.z1], colour: [1.0, 0.62, 0.25], radius: 0.13, strength: 0.25, facing: [0, 0, 1]},
    {at: [DOOR.x, 0.252, HALL.z1 + 0.02], colour: [1.0, 0.36, 0.1], radius: 0.07, strength: 0.3, facing: [0, 0, 1]},
    {at: [DOOR.x, 0.175, HALL.z0], colour: [1.0, 0.62, 0.25], radius: 0.14, strength: 0.2, facing: [0, 0, -1]},
    {at: [0.45, 0.12, GLASSHOUSE.z], colour: [1.0, 0.7, 0.35], radius: 0.24, strength: 0.14},
    ...lanterns.map(at => ({at, colour: [1.0, 0.72, 0.35] as Vec3, radius: 0.06, strength: 0.32})),
  ]

  return {
    count,
    data,
    reach,
    camera: {pitch: (18 * Math.PI) / 180, field: (16.5 * Math.PI) / 180, distance: 6.9, lookAt: 0.17, radius: 1.0},
    palette: DUSK,
    sky: {
      zenith: hex("#120f24"),
      high: hex("#2b2752"),
      horizon: hex("#80548a"),
      below: hex("#1d1a3a"),
      glowAt: -0.5,
      glow: [0.5, 0.26, 0.1],
      cloud: hex("#5a4479"),
      stars: 0.002,
    },
    rim: RIM,
    edge: [0.85, 0.82, 0.74],
    glows,
    motes: {back: 30, front: 6, colours: [[1.0, 0.72, 0.45], [0.9, 0.89, 0.82]], size: 0.014},
    parts: PARTS,
    pose(seconds, into) {
      restPose(into, PARTS)
      setPart(into, PART.belt, {columns: STILL.columns, move: [0, 0, (seconds * BELT.speed) % BELT.slat]})
      // Each robot rides the belt out of the door, drops into the crate, and starts again inside.
      const lap = 0.96
      PART.carried.forEach((part, k) => {
        const travelled = ((seconds * BELT.speed) / lap + k / 3) % 1 * lap
        const onBelt = BELT.z1 - BELT.z0
        if (travelled < onBelt) {
          setPart(into, part, {columns: STILL.columns, move: [0, 0, BELT.z0 + travelled]})
        } else {
          const fall = Math.min(1, (travelled - onBelt) / 0.08)
          setPart(into, part, {columns: STILL.columns, move: [0, -0.14 * fall * fall, BELT.z1 + 0.07 * fall]}, 1 - smoothstep(0.55, 1, fall))
        }
      })
      // The arm swings over the belt.
      const swing = (seconds / 8) * Math.PI * 2
      const turret = turning(UP, 0.55 * Math.sin(swing), ARM.shoulder)
      const upper = after(turret, turning([0, 0, 1], 0.12 * Math.sin(swing + 1.2), ARM.shoulder))
      setPart(into, PART.turret, turret)
      setPart(into, PART.upperArm, upper)
      setPart(into, PART.forearm, after(upper, turning([0, 0, 1], 0.25 * Math.sin(swing * 2), ARM.elbow)))
      // The walker goes round the pond, its legs swinging.
      const now = onLoop(seconds)
      const body: Pose = turning(UP, now.yaw - walkerRest.yaw, walkerRest.at, sub(add(now.at, [0, 0.002 * Math.abs(Math.sin(seconds * 5.2)), 0]), walkerRest.at))
      setPart(into, PART.walker, body)
      const side: Vec3 = [Math.cos(walkerRest.yaw), 0, -Math.sin(walkerRest.yaw)]
      PART.legs.forEach((leg, k) => {
        const hip = add(add(walkerRest.at, times(side, (k === 0 ? -1 : 1) * 0.015)), [0, 0.045, 0])
        setPart(into, leg, after(body, turning(side, (k === 0 ? 1 : -1) * 0.45 * Math.sin(seconds * 5.2), hip)))
      })
      // The gardener tips its watering can.
      const shoulder = add(tenderFoot, [0, 0.092, 0.037])
      setPart(into, PART.watering, turning([0, 0, 1], 0.35 + 0.3 * Math.sin(seconds * 1.4), shoulder))
      for (const turbine of TURBINES) {
        const hub: Vec3 = [turbine.x, ground(turbine.x, turbine.z) + turbine.height + 0.012, turbine.z + 0.034]
        setPart(into, turbine.part, turning([0, 0, 1], -turbine.speed * seconds, hub))
      }
    },
    still: {turn: (-32 * Math.PI) / 180, pitch: (18 * Math.PI) / 180, seconds: 6.5},
  }
}
