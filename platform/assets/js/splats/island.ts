/**
 * The floating island on the splats page (`AshTemplateWeb.SplatsLabLive`), grown
 * from one fixed seed into some fifty thousand small 3D gaussians, or splats.
 *
 * Each splat is a place, a shape (three axes at right angles and how far it reaches
 * along each, kept as its covariance), a colour, how opaque it is, the way it faces,
 * how open it is to the sky, and how much of the campfire's light reaches it. The
 * moonlight is worked out as the island turns (painter.ts); the rest is baked in here.
 *
 * Units: the grass disc is about one unit across from its middle, its top at height
 * 0, y up. Nothing here is random at run time: the same seed grows the same island.
 *
 * This file imports nothing, so the script that draws the page's still picture
 * (`stills.mjs`, beside it) grows exactly the island the browser does.
 */

type Vec3 = readonly [number, number, number]

/** Floats per splat, in the order `Splat` in painter.ts reads them. */
export const SPLAT_FLOATS = 20

/** What a splat is: lit by the moon and the fire, a flame, or a rising spark. */
export const SURFACE = 0
export const FLAME = 1
export const SPARK = 2

export type Island = {
  readonly count: number
  /**
   * `SPLAT_FLOATS` per splat: place and opacity; the covariance's xx, xy, xz, yy;
   * its yz, zz, the kind and the fire's light; the colour and a phase for flames
   * and sparks; the way it faces and how open it is to the sky.
   */
  readonly data: Float32Array<ArrayBuffer>
  /** The farthest any splat sits from the island's middle. */
  readonly reach: number
  /** Where the fire's light comes from. */
  readonly fire: Vec3
}

const SEED = 20_261_115

// A small seeded generator (mulberry32): the same seed, the same island.
function randomFrom(seed: number) {
  let state = seed >>> 0
  return () => {
    state = (state + 0x6d2b79f5) >>> 0
    let t = state
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4_294_967_296
  }
}

const add = (a: Vec3, b: Vec3): Vec3 => [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
const sub = (a: Vec3, b: Vec3): Vec3 => [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
const times = (a: Vec3, k: number): Vec3 => [a[0] * k, a[1] * k, a[2] * k]
const dot = (a: Vec3, b: Vec3) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
const cross = (a: Vec3, b: Vec3): Vec3 => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
const length = (a: Vec3) => Math.hypot(a[0], a[1], a[2])
const unit = (a: Vec3): Vec3 => times(a, 1 / (length(a) || 1))
const mix = (a: Vec3, b: Vec3, t: number): Vec3 => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
const clamp01 = (x: number) => Math.min(1, Math.max(0, x))
const smoothstep = (from: number, to: number, x: number) => {
  const t = clamp01((x - from) / (to - from))
  return t * t * (3 - 2 * t)
}

const hex = (value: string): Vec3 => {
  const n = Number.parseInt(value.slice(1), 16)
  return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255]
}

const UP: Vec3 = [0, 1, 0]

/** Two axes at right angles to `n`, turned by `spin` round it. */
function around(n: Vec3, spin: number): [Vec3, Vec3] {
  const helper: Vec3 = Math.abs(n[1]) < 0.92 ? UP : [1, 0, 0]
  const t = unit(cross(helper, n))
  const b = cross(n, t)
  const c = Math.cos(spin)
  const s = Math.sin(spin)
  return [add(times(t, c), times(b, s)), add(times(t, -s), times(b, c))]
}

// Colours, before light. The night palette they end on is palette.ts's.
const GRASS = ["#3c7a3f", "#4a8a44", "#5a9a49", "#336d3a"].map(hex)
const GRASS_BRIGHT = ["#78ad55", "#94bf5f"].map(hex)
const LEAF = ["#2a5c3a", "#356c3e", "#447f44", "#5a944b", "#7aab55"].map(hex)
const NEEDLE = ["#1d4a3a", "#255a40", "#2f6a45", "#3d7d4b"].map(hex)
const BARK = ["#6a4330", "#7d5238", "#553526", "#8d5f3d"].map(hex)
const EARTH = ["#5a3b2c", "#4a3027", "#664430", "#3a2520"].map(hex)
const STONE = ["#5f6878", "#6f7888", "#545c6b", "#7f8898"].map(hex)
const MOSS = ["#3a7340", "#4a8545"].map(hex)
const ASH = ["#2c2224", "#3a2a26", "#241c1e"].map(hex)
const FLOWER = ["#e07aa8", "#ffd86a", "#ecebdc", "#aecacd", "#e07aa8"].map(hex)
const FLAME_COLOURS = {core: hex("#fff0b0"), inner: hex("#ffd86a"), middle: hex("#ffa035"), outer: hex("#ff5b19"), tip: hex("#c2341a")}

/** Where things stand on the grass. */
const TRUNK: Vec3 = [0.2, 0, -0.14]
const CANOPY: Vec3 = [0.1, 1.12, -0.08]
const FIRE: Vec3 = [-0.3, 0, 0.4]
const ROCK: Vec3 = [0.56, 0, 0.44]
const PEBBLE_ROCK: Vec3 = [-0.62, 0, 0.6]
const MONUMENT: Vec3 = [0.72, 0, 0.02]
const PINES: readonly {at: Vec3; height: number; spread: number}[] = [
  {at: [-0.66, 0, -0.02], height: 0.8, spread: 0.27},
  {at: [-0.42, 0, -0.4], height: 0.6, spread: 0.21},
]

/** The grass disc's edge, a little ragged, by the angle round the island. */
const rim = (angle: number) =>
  1 + 0.045 * Math.sin(3 * angle + 0.7) + 0.03 * Math.sin(7 * angle + 2.1) + 0.018 * Math.sin(13 * angle + 0.3)

/** The grass's height: a gentle dome with soft swells. */
const ground = (x: number, z: number) =>
  0.05 * (1 - Math.min(1, x * x + z * z)) + 0.012 * Math.sin(3.1 * x + 1.3) * Math.cos(2.7 * z + 0.4) + 0.008 * Math.sin(5.3 * z - 0.7 * x)

const groundFacing = (x: number, z: number): Vec3 => {
  const e = 0.01
  return unit([ground(x - e, z) - ground(x + e, z), 2 * e, ground(x, z - e) - ground(x, z + e)])
}

/** How deep under the island its earth hangs, at each depth below the rim (0 to 1). */
const UNDER_DEPTH = 0.66
const underRadius = (depth: number) => Math.pow(Math.max(0, 1 - Math.pow(depth, 1.45)), 0.78)

export function buildIsland(): Island {
  const random = randomFrom(SEED)
  const between = (from: number, to: number) => from + (to - from) * random()
  const pick = <T>(list: readonly T[]) => list[Math.floor(random() * list.length)]!
  const jitter = (colour: Vec3, amount: number): Vec3 => {
    const k = 1 + (random() - 0.5) * amount
    return [colour[0] * k, colour[1] * k, colour[2] * k]
  }
  const onSphere = (): Vec3 => {
    const y = random() * 2 - 1
    const a = random() * Math.PI * 2
    const r = Math.sqrt(1 - y * y)
    return [r * Math.cos(a), y, r * Math.sin(a)]
  }

  const floats: number[] = []
  let count = 0

  type Shape = {
    at: Vec3
    axes: readonly [Vec3, Vec3, Vec3]
    reach: Vec3
    colour: Vec3
    opacity: number
    facing: Vec3
    open: number
    kind?: number
    phase?: number
  }

  const push = (s: Shape) => {
    let xx = 0
    let xy = 0
    let xz = 0
    let yy = 0
    let yz = 0
    let zz = 0
    for (let k = 0; k < 3; k++) {
      const a = s.axes[k]!
      const v = s.reach[k]! * s.reach[k]!
      xx += v * a[0] * a[0]
      xy += v * a[0] * a[1]
      xz += v * a[0] * a[2]
      yy += v * a[1] * a[1]
      yz += v * a[1] * a[2]
      zz += v * a[2] * a[2]
    }
    floats.push(
      s.at[0], s.at[1], s.at[2], s.opacity,
      xx, xy, xz, yy,
      yz, zz, s.kind ?? SURFACE, 0,
      s.colour[0], s.colour[1], s.colour[2], s.phase ?? 0,
      s.facing[0], s.facing[1], s.facing[2], s.open,
    )
    count += 1
  }

  /** A flat splat lying across `facing`. */
  const flat = (at: Vec3, facing: Vec3, wide: number, narrow: number, thin: number, colour: Vec3, open: number, opacity = 0.96) => {
    const [t, b] = around(facing, random() * Math.PI * 2)
    push({at, axes: [t, b, facing], reach: [wide, narrow, thin], colour, opacity, facing, open})
  }

  /** A long splat running along `along`, seen from `facing`. */
  const long = (at: Vec3, along: Vec3, reach: number, width: number, colour: Vec3, facing: Vec3, open: number, opacity = 0.96) => {
    const d = unit(along)
    const [t, b] = around(d, random() * Math.PI * 2)
    push({at, axes: [d, t, b], reach: [reach, width, width * 0.5], colour, opacity, facing, open})
  }

  const onGrass = (x: number, z: number): Vec3 => [x, ground(x, z), z]
  const distanceOnGround = (x: number, z: number, at: Vec3) => Math.hypot(x - at[0], z - at[2])

  /** How much of the sky a place on the grass sees: less under the tree and the pines. */
  const grassOpen = (x: number, z: number) => {
    const canopy = Math.hypot(x - CANOPY[0] * 0.9, z - CANOPY[2])
    let open = 0.42 + 0.58 * smoothstep(0.2, 1.0, canopy)
    for (const pine of PINES) open *= 0.72 + 0.28 * smoothstep(0.08, pine.spread * 1.15, distanceOnGround(x, z, pine.at))
    open *= 0.7 + 0.3 * smoothstep(0.12, 0.3, distanceOnGround(x, z, ROCK))
    return open
  }

  // ----- The grass on top -----
  const grassColour = (x: number, z: number) => {
    const patch = 0.5 + 0.5 * Math.sin(4.3 * x + 1.1) * Math.cos(3.7 * z - 0.6)
    const base = mix(GRASS[3]!, GRASS[1]!, patch)
    return random() < 0.12 ? pick(GRASS) : random() < 0.08 ? pick(GRASS_BRIGHT) : jitter(base, 0.18)
  }

  const inFire = (x: number, z: number) => distanceOnGround(x, z, FIRE) < 0.15

  for (let i = 0; i < 9200; i++) {
    const a = random() * Math.PI * 2
    const r = Math.sqrt(random()) * rim(a) * 0.985
    const x = r * Math.cos(a)
    const z = r * Math.sin(a)
    const at = onGrass(x, z)
    const facing = groundFacing(x, z)
    if (inFire(x, z)) {
      flat(at, facing, 0.024, 0.02, 0.005, jitter(pick(ASH), 0.2), grassOpen(x, z) * 0.8, 0.97)
      continue
    }
    flat(at, facing, between(0.02, 0.03), between(0.016, 0.024), 0.005, grassColour(x, z), grassOpen(x, z), 0.95)
  }

  // Blades standing out of the grass, thickest at the edge, so its outline is ragged.
  for (let i = 0; i < 3200; i++) {
    const a = random() * Math.PI * 2
    const r = Math.pow(random(), 0.32) * rim(a) * 0.99
    const x = r * Math.cos(a)
    const z = r * Math.sin(a)
    if (inFire(x, z) || distanceOnGround(x, z, TRUNK) < 0.12 || distanceOnGround(x, z, ROCK) < 0.16) continue
    const tall = between(0.02, 0.055)
    const lean: Vec3 = [between(-0.35, 0.35), 1, between(-0.35, 0.35)]
    const d = unit(lean)
    const base = onGrass(x, z)
    const colour = random() < 0.3 ? pick(GRASS_BRIGHT) : jitter(pick(GRASS), 0.2)
    long(add(base, times(d, tall * 0.5)), d, tall * 0.45, 0.007, colour, unit([Math.cos(a), 1.4, Math.sin(a)]), grassOpen(x, z))
  }

  // Grass hanging over the edge, of many lengths, so the underside is ragged.
  for (let i = 0; i < 3800; i++) {
    const a = random() * Math.PI * 2
    const out: Vec3 = [Math.cos(a), 0, Math.sin(a)]
    const r = rim(a) + between(-0.035, 0.012)
    const start: Vec3 = [out[0] * r, ground(out[0] * r, out[2] * r) - between(0, 0.03), out[2] * r]
    const hang = 0.03 + 0.2 * Math.pow(random(), 2.4)
    const d = unit([out[0] * between(0.05, 0.35), -1, out[2] * between(0.05, 0.35)])
    const colour = mix(jitter(pick(GRASS), 0.2), hex("#1e4a3a"), clamp01(hang * 4.5) * 0.75)
    long(add(start, times(d, hang * 0.5)), d, hang * 0.46, between(0.009, 0.014), colour, unit([out[0], -0.25, out[2]]), 0.62 - hang)
  }

  // ----- The earth hanging underneath -----
  const tip: Vec3 = [0.06, 0, -0.05]
  const underPoint = (a: number, depth: number): Vec3 => {
    const lump = 1 + 0.07 * Math.sin(5 * a + 3 * depth) + 0.05 * Math.sin(9 * a - 7 * depth + 1) + 0.03 * Math.sin(17 * a + 11 * depth)
    const r = rim(a) * 0.985 * underRadius(depth) * lump
    return [r * Math.cos(a) + tip[0] * depth, -0.02 - depth * UNDER_DEPTH, r * Math.sin(a) + tip[2] * depth]
  }
  for (let i = 0; i < 9000; ) {
    const depth = random()
    if (random() > underRadius(depth) * 1.05 + 0.08) continue
    i += 1
    const a = random() * Math.PI * 2
    const at = underPoint(a, depth)
    const e = 0.01
    const along = sub(underPoint(a + e, depth), underPoint(a - e, depth))
    const down = sub(underPoint(a, Math.min(1, depth + e)), underPoint(a, Math.max(0, depth - e)))
    let facing = unit(cross(down, along))
    if (dot(facing, [at[0], 0, at[2]]) < 0 && depth < 0.98) facing = times(facing, -1)
    const band = Math.sin(depth * 38 + Math.sin(a * 3) * 2)
    let colour = jitter(band > 0.55 ? EARTH[2]! : band < -0.6 ? EARTH[3]! : pick(EARTH), 0.25)
    if (depth < 0.08 && random() < 0.7) colour = jitter(mix(pick(GRASS), hex("#1e4a3a"), 0.5), 0.2)
    else if (random() < 0.07) colour = jitter(pick(STONE), 0.15)
    colour = times(colour, 0.95 - depth * 0.35)
    flat(at, facing, between(0.03, 0.044), between(0.024, 0.034), 0.008, colour, 0.8 - depth * 0.45, 0.98)
  }

  // Roots hanging from the earth.
  for (let i = 0; i < 46; i++) {
    const a = random() * Math.PI * 2
    let at = underPoint(a, between(0.12, 0.62))
    let heading: Vec3 = unit([between(-0.3, 0.3), -1, between(-0.3, 0.3)])
    const steps = 6 + Math.floor(random() * 12)
    const colour = jitter(pick(BARK), 0.2)
    for (let step = 0; step < steps; step++) {
      heading = unit(add(heading, [between(-0.25, 0.25), -0.15, between(-0.25, 0.25)]))
      const next = add(at, times(heading, 0.022))
      long(mix(at, next, 0.5), heading, 0.014, 0.006 * (1 - step / steps) + 0.003, times(colour, 0.9 - step / (steps * 3)), unit([at[0], 0, at[2]]), 0.35)
      at = next
    }
  }

  // ----- The tree -----
  type Limb = readonly {at: Vec3; radius: number}[]
  const bark = (limb: Limb, density: number, openAt: (y: number) => number) => {
    for (let k = 0; k + 1 < limb.length; k++) {
      const from = limb[k]!
      const to = limb[k + 1]!
      const axis = sub(to.at, from.at)
      const span = length(axis)
      const d = unit(axis)
      const [u, v] = around(d, 0)
      const n = Math.ceil((span * (from.radius + to.radius) * Math.PI) / density)
      for (let i = 0; i < n; i++) {
        const t = random()
        const angle = random() * Math.PI * 2
        const radius = from.radius + (to.radius - from.radius) * t
        const out = add(times(u, Math.cos(angle)), times(v, Math.sin(angle)))
        const at = add(add(from.at, times(axis, t)), times(out, radius))
        const streak = 0.5 + 0.5 * Math.sin(angle * 5 + at[1] * 9)
        const colour = jitter(streak > 0.7 ? BARK[3]! : streak < 0.25 ? BARK[2]! : pick(BARK), 0.2)
        push({at, axes: [d, unit(cross(d, out)), out], reach: [Math.min(0.032, radius * 0.9 + 0.006), Math.min(0.014, radius * 0.45 + 0.004), 0.004], colour, opacity: 0.97, facing: out, open: openAt(at[1])})
      }
    }
  }
  const base = TRUNK
  const trunk: Limb = [
    {at: add(base, [0, -0.03, 0]), radius: 0.15},
    {at: add(base, [0.0, 0.1, 0.0]), radius: 0.105},
    {at: add(base, [-0.03, 0.34, 0.02]), radius: 0.09},
    {at: add(base, [-0.07, 0.56, 0.03]), radius: 0.082},
  ]
  const fork = trunk[trunk.length - 1]!.at
  const trunkOpen = (y: number) => 0.85 - 0.45 * smoothstep(0.2, 0.9, y)
  bark(trunk, 0.0006, trunkOpen)
  // Two big limbs from the fork, and three smaller ones.
  const branches: readonly {mid: Vec3; end: Vec3; radius: number}[] = [
    {mid: [-0.2, 0.12, 0.05], end: [-0.42, 0.32, 0.1], radius: 0.07},
    {mid: [0.2, 0.15, -0.02], end: [0.4, 0.36, -0.06], radius: 0.07},
    {mid: [-0.02, 0.16, -0.18], end: [-0.04, 0.4, -0.34], radius: 0.045},
    {mid: [0.04, 0.14, 0.16], end: [0.1, 0.38, 0.3], radius: 0.045},
    {mid: [0.02, 0.24, 0.0], end: [0.04, 0.52, 0.02], radius: 0.05},
  ]
  for (const branch of branches) {
    bark([
      {at: fork, radius: branch.radius},
      {at: add(fork, branch.mid), radius: branch.radius * 0.68},
      {at: add(fork, branch.end), radius: branch.radius * 0.36},
    ], 0.0006, trunkOpen)
  }
  // Roots spreading over the grass from the foot of the trunk.
  for (let k = 0; k < 6; k++) {
    const a = (k / 6) * Math.PI * 2 + between(-0.3, 0.3)
    const reachOut = between(0.2, 0.32)
    const end: Vec3 = [base[0] + Math.cos(a) * reachOut, 0, base[2] + Math.sin(a) * reachOut]
    bark([
      {at: add(base, [Math.cos(a) * 0.06, 0.03, Math.sin(a) * 0.06]), radius: 0.045},
      {at: [base[0] + Math.cos(a) * reachOut * 0.55, ground(base[0] + Math.cos(a) * reachOut * 0.55, base[2] + Math.sin(a) * reachOut * 0.55) + 0.012, base[2] + Math.sin(a) * reachOut * 0.55], radius: 0.026},
      {at: [end[0], ground(end[0], end[2]) - 0.01, end[2]], radius: 0.008},
    ], 0.0007, () => 0.62)
  }

  // The crown of leaves: clumps round a wide, rounded, flat-bottomed head.
  const clumps: readonly {at: Vec3; radius: number}[] = [
    {at: [0, 0.3, 0], radius: 0.38},
    {at: [-0.46, 0.1, 0.12], radius: 0.34},
    {at: [0.46, 0.13, -0.06], radius: 0.34},
    {at: [0.06, 0.06, 0.46], radius: 0.33},
    {at: [-0.06, 0.08, -0.46], radius: 0.33},
    {at: [-0.6, -0.12, -0.26], radius: 0.28},
    {at: [0.62, -0.1, 0.26], radius: 0.28},
    {at: [-0.36, -0.14, 0.46], radius: 0.27},
    {at: [0.36, -0.12, -0.46], radius: 0.28},
    {at: [0.26, 0.32, 0.26], radius: 0.3},
    {at: [-0.26, 0.3, -0.22], radius: 0.3},
    {at: [0.0, -0.18, 0.0], radius: 0.38},
    {at: [-0.72, 0.02, 0.18], radius: 0.22},
    {at: [0.72, 0.04, -0.3], radius: 0.22},
    {at: [0.3, 0.1, 0.5], radius: 0.24},
    {at: [-0.3, 0.12, -0.5], radius: 0.24},
  ]
  const CROWN = 0.86
  const leafArea = clumps.reduce((sum, clump) => sum + clump.radius * clump.radius, 0)
  for (const clump of clumps) {
    const centre = add(CANOPY, times(clump.at, CROWN))
    const radius = clump.radius * CROWN
    const tint = between(0.84, 1.14)
    const leaves = Math.round((16_500 * clump.radius * clump.radius) / leafArea)
    for (let i = 0; i < leaves; i++) {
      const dir = onSphere()
      const depth = 0.6 + 0.4 * Math.pow(random(), 0.55)
      const at = add(centre, [dir[0] * radius * depth, dir[1] * radius * depth * 0.84, dir[2] * radius * depth])
      const outward = unit(sub(at, CANOPY))
      const facing = unit(add(times(dir, 0.7), times(outward, 0.3)))
      const height = (at[1] - CANOPY[1]) / (0.6 * CROWN)
      const open = clamp01(
        (0.35 + 0.65 * smoothstep(0.6, 1.0, depth)) *
          (0.5 + 0.5 * smoothstep(-1.1, 0.7, height)) *
          (0.45 + 0.55 * smoothstep(-0.85, 0.45, dir[1])) *
          (0.55 + 0.45 * smoothstep(0.35, 1.0, length(sub(at, CANOPY)) / (0.95 * CROWN))),
      )
      // Brighter leaves on top of each clump, where the sky catches them.
      const shade = Math.min(0.999, random() + 0.3 * smoothstep(0.1, 0.8, dir[1]) * depth)
      const colour = shade < 0.28 ? LEAF[0]! : shade < 0.58 ? LEAF[1]! : shade < 0.8 ? LEAF[2]! : shade < 0.93 ? LEAF[3]! : LEAF[4]!
      const leafFacing = unit(add(facing, times(onSphere(), 0.4)))
      flat(at, leafFacing, between(0.024, 0.04), between(0.014, 0.024), 0.006, times(jitter(colour, 0.22), tint), open, 0.97)
    }
  }
  // A few leaves hanging under the crown's rim, so its lower edge is ragged.
  for (let i = 0; i < 700; i++) {
    const clump = clumps[Math.floor(random() * clumps.length)]!
    const centre = add(CANOPY, times(clump.at, CROWN))
    const radius = clump.radius * CROWN
    const a = random() * Math.PI * 2
    const at = add(centre, [Math.cos(a) * radius * 0.8, -radius * between(0.65, 1.05), Math.sin(a) * radius * 0.8])
    flat(at, unit([Math.cos(a), -0.6, Math.sin(a)]), between(0.022, 0.034), 0.016, 0.006, jitter(LEAF[1]!, 0.25), 0.4, 0.97)
  }

  // ----- Two pines: tiers of drooping boughs, each tier's edge cut into branch tips -----
  for (const pine of PINES) {
    const foot: Vec3 = [pine.at[0], ground(pine.at[0], pine.at[2]), pine.at[2]]
    bark([
      {at: add(foot, [0, -0.02, 0]), radius: 0.03},
      {at: add(foot, [0, pine.height * 0.5, 0]), radius: 0.02},
    ], 0.0005, () => 0.55)
    const tiers = 5
    const needles = Math.round(5600 * pine.height)
    const tips = 7 + Math.floor(random() * 3)
    const twist = random() * Math.PI * 2
    const step = (pine.height - 0.14) / tiers
    for (let i = 0; i < needles; i++) {
      const tier = Math.floor(random() * tiers)
      const rise = tier / tiers
      const top = 0.14 + step * (tier + 1)
      const spread = pine.spread * Math.pow(1 - rise, 0.8) + 0.03
      const drop = step
      const a = random() * Math.PI * 2
      const tip = 0.68 + 0.32 * Math.pow(Math.abs(Math.cos(((a + twist + tier * 0.9) * tips) / 2)), 0.5)
      const t = Math.sqrt(between(0.02, 1))
      const r = t * spread * tip
      const sag = drop * (t + 0.5 * t * t * t)
      const at: Vec3 = [foot[0] + Math.cos(a) * r, foot[1] + top - sag + between(-0.01, 0.01), foot[2] + Math.sin(a) * r]
      const slope = unit([Math.cos(a) * spread, -drop * (1 + 2 * t * t), Math.sin(a) * spread])
      const facing = unit([Math.cos(a) * drop, spread, Math.sin(a) * drop])
      const colour = t > 0.72 ? pick(NEEDLE.slice(2)) : t < 0.55 ? NEEDLE[0]! : pick(NEEDLE.slice(0, 2))
      const open = clamp01((0.15 + 0.85 * t * t) * (0.62 + 0.38 * rise))
      long(at, add(slope, times(onSphere(), 0.2)), between(0.012, 0.019), 0.008, jitter(colour, 0.2), facing, open, 0.97)
    }
    for (let i = 0; i < 24; i++) {
      const at = add(foot, [between(-0.012, 0.012), pine.height + between(-0.06, 0.03), between(-0.012, 0.012)])
      long(at, UP, 0.02, 0.008, jitter(NEEDLE[3]!, 0.2), unit([between(-1, 1), 0.5, between(-1, 1)]), 0.9)
    }
  }

  // ----- Stones -----
  const stone = (at: Vec3, radii: Vec3, splats: number, mossy: number, size: number) => {
    const phase = random() * 10
    for (let i = 0; i < splats; i++) {
      let dir = onSphere()
      if (dir[1] < -0.35) dir = [dir[0], -dir[1] * 0.5, dir[2]]
      const lump = 1 + 0.12 * Math.sin(dir[0] * 4 + phase) * Math.cos(dir[2] * 5 - phase) + 0.06 * Math.sin(dir[1] * 9 + phase)
      const p = add(at, [dir[0] * radii[0] * lump, dir[1] * radii[1] * lump, dir[2] * radii[2] * lump])
      const facing = unit([dir[0] / radii[0], dir[1] / radii[1], dir[2] / radii[2]])
      let colour = facing[1] > 0.5 ? STONE[3]! : facing[1] < -0.1 ? STONE[2]! : pick(STONE)
      if (facing[1] > 0.55 && random() < mossy) colour = pick(MOSS)
      flat(p, facing, size * between(0.85, 1.2), size * between(0.7, 1), size * 0.25, jitter(colour, 0.14), 0.45 + 0.5 * clamp01(facing[1] * 0.5 + 0.5), 0.98)
    }
  }
  stone(add(onGrass(ROCK[0], ROCK[2]), [0, 0.06, 0]), [0.19, 0.13, 0.16], 1500, 0.55, 0.024)
  stone(add(onGrass(PEBBLE_ROCK[0], PEBBLE_ROCK[2]), [0, 0.035, 0]), [0.1, 0.075, 0.09], 560, 0.3, 0.02)
  for (let i = 0; i < 40; i++) {
    const a = random() * Math.PI * 2
    const r = Math.sqrt(random()) * 0.9
    const x = r * Math.cos(a)
    const z = r * Math.sin(a)
    if (inFire(x, z)) continue
    stone(add(onGrass(x, z), [0, 0.008, 0]), [0.014, 0.01, 0.012], 4, 0, 0.01)
  }

  // ----- The crown: thirteen stone blocks on a low slab, five wide and three high,
  // the top row only at the first, middle and last places -----
  {
    const out = unit([MONUMENT[0], 0, MONUMENT[2]])
    const side = unit(cross(UP, out))
    const foot: Vec3 = [MONUMENT[0], ground(MONUMENT[0], MONUMENT[2]), MONUMENT[2]]
    const block = 0.068
    const pitch = 0.08
    const box = (centre: Vec3, half: Vec3, top: Vec3, faces: Vec3, open: number) => {
      const axes: readonly [Vec3, Vec3, Vec3] = [out, UP, side]
      for (let f = 0; f < 3; f++) {
        for (const sign of [-1, 1]) {
          const n = times(axes[f]!, sign)
          const u = axes[(f + 1) % 3]!
          const v = axes[(f + 2) % 3]!
          const hu = half[(f + 1) % 3]!
          const hv = half[(f + 2) % 3]!
          const across = Math.max(1, Math.round(hu / 0.017))
          const down = Math.max(1, Math.round(hv / 0.017))
          for (let i = 0; i < across; i++) {
            for (let j = 0; j < down; j++) {
              const at = add(add(add(centre, times(n, half[f]!)), times(u, hu * ((2 * i + 1) / across - 1))), times(v, hv * ((2 * j + 1) / down - 1)))
              const colour = f === 1 && sign > 0 ? top : faces
              push({at, axes: [u, v, n], reach: [(hu / across) * 0.85, (hv / down) * 0.85, 0.003], colour: jitter(colour, 0.1), opacity: 0.99, facing: n, open})
            }
          }
        }
      }
    }
    box(add(foot, [0, 0.012, 0]), [0.07, 0.03, 0.23], hex("#6a7383"), hex("#4f5766"), 0.7)
    const rows = [[1, 0, 1, 0, 1], [1, 1, 1, 1, 1], [1, 1, 1, 1, 1]]
    rows.forEach((row, r) => {
      row.forEach((filled, c) => {
        if (!filled) return
        const centre = add(add(foot, times(side, (c - 2) * pitch)), [0, 0.042 + block / 2 + (2 - r) * pitch, 0])
        box(centre, [block * 0.42, block / 2, block / 2], hex("#9aa3b0"), hex("#7c8595"), 0.85)
      })
    })
  }

  // ----- The campfire: a ring of stones, four logs, embers, flames and sparks -----
  const fireFoot: Vec3 = [FIRE[0], ground(FIRE[0], FIRE[2]), FIRE[2]]
  for (let k = 0; k < 9; k++) {
    const a = (k / 9) * Math.PI * 2 + between(-0.15, 0.15)
    stone(add(fireFoot, [Math.cos(a) * 0.13, 0.014, Math.sin(a) * 0.13]), [0.034, 0.024, 0.03], 22, 0, 0.014)
  }
  for (let k = 0; k < 4; k++) {
    const a = (k / 4) * Math.PI * 2 + 0.4
    const foot = add(fireFoot, [Math.cos(a) * 0.09, 0.012, Math.sin(a) * 0.09])
    const apex = add(fireFoot, [Math.cos(a) * 0.012, 0.12, Math.sin(a) * 0.012])
    bark([{at: foot, radius: 0.017}, {at: apex, radius: 0.012}], 0.0004, () => 0.6)
  }
  for (let i = 0; i < 30; i++) {
    const a = random() * Math.PI * 2
    const r = Math.sqrt(random()) * 0.075
    const at = add(fireFoot, [Math.cos(a) * r, 0.012, Math.sin(a) * r])
    push({at, axes: [[1, 0, 0], UP, [0, 0, 1]], reach: [0.012, 0.006, 0.012], colour: random() < 0.5 ? FLAME_COLOURS.tip : FLAME_COLOURS.outer, opacity: 0.95, facing: UP, open: 1, kind: FLAME, phase: random()})
  }
  const FLAME_HEIGHT = 0.27
  for (let i = 0; i < 170; i++) {
    const h = Math.pow(random(), 1.35) * FLAME_HEIGHT
    const t = h / FLAME_HEIGHT
    const width = 0.065 * Math.pow(1 - t, 0.7) + 0.006
    const a = random() * Math.PI * 2
    const r = Math.sqrt(random()) * width
    const centre = r / width
    const at = add(fireFoot, [Math.cos(a) * r, 0.03 + h, Math.sin(a) * r])
    const colour =
      t < 0.3 && centre < 0.45 ? mix(FLAME_COLOURS.core, FLAME_COLOURS.inner, t * 2) :
      t < 0.55 && centre < 0.7 ? FLAME_COLOURS.inner :
      t < 0.75 ? FLAME_COLOURS.middle :
      t < 0.92 ? FLAME_COLOURS.outer : FLAME_COLOURS.tip
    push({at, axes: [[1, 0, 0], UP, [0, 0, 1]], reach: [0.016 * (1 - t * 0.5), 0.03 * (1 - t * 0.3), 0.016 * (1 - t * 0.5)], colour, opacity: 0.88, facing: UP, open: 1, kind: FLAME, phase: random()})
  }
  for (let i = 0; i < 20; i++) {
    const at = add(fireFoot, [between(-0.04, 0.04), 0.14, between(-0.04, 0.04)])
    push({at, axes: [[1, 0, 0], UP, [0, 0, 1]], reach: [0.007, 0.009, 0.007], colour: random() < 0.5 ? FLAME_COLOURS.inner : FLAME_COLOURS.middle, opacity: 1, facing: UP, open: 1, kind: SPARK, phase: random()})
  }

  // ----- Two bushes -----
  for (const bush of [{at: [-0.06, 0, 0.74] as Vec3, size: 0.11}, {at: [0.7, 0, -0.5] as Vec3, size: 0.13}]) {
    const foot = onGrass(bush.at[0], bush.at[2])
    for (let c = 0; c < 4; c++) {
      const centre = add(foot, [between(-1, 1) * bush.size * 0.6, bush.size * between(0.55, 0.95), between(-1, 1) * bush.size * 0.6])
      const radius = bush.size * between(0.6, 0.85)
      for (let i = 0; i < 150; i++) {
        const dir = onSphere()
        if (centre[1] + dir[1] * radius < foot[1]) continue
        const at = add(centre, times(dir, radius * (0.75 + 0.25 * random())))
        const open = 0.4 + 0.5 * clamp01((at[1] - foot[1]) / (bush.size * 1.6))
        flat(at, unit(add(dir, times(onSphere(), 0.6))), between(0.02, 0.03), 0.016, 0.006, jitter(pick(LEAF), 0.2), open, 0.97)
      }
    }
  }

  // ----- Flowers in the open grass -----
  for (let i = 0; i < 90; ) {
    const a = random() * Math.PI * 2
    const r = Math.sqrt(random()) * 0.9
    const x = r * Math.cos(a)
    const z = r * Math.sin(a)
    if (distanceOnGround(x, z, TRUNK) < 0.35 || distanceOnGround(x, z, FIRE) < 0.22 || distanceOnGround(x, z, ROCK) < 0.24 || distanceOnGround(x, z, MONUMENT) < 0.26) continue
    if (PINES.some(pine => distanceOnGround(x, z, pine.at) < pine.spread)) continue
    i += 1
    const colour = pick(FLOWER)
    const at = add(onGrass(x, z), [0, between(0.02, 0.04), 0])
    flat(at, UP, 0.013, 0.011, 0.006, jitter(colour, 0.1), 0.95, 0.99)
  }

  // ----- The fire's light: falls off with distance and with how a splat faces it -----
  const light: Vec3 = add(fireFoot, [0, 0.1, 0])
  let reach = 0
  for (let i = 0; i < count; i++) {
    const o = i * SPLAT_FLOATS
    const at: Vec3 = [floats[o]!, floats[o + 1]!, floats[o + 2]!]
    reach = Math.max(reach, length(at))
    if (floats[o + 10] !== SURFACE || at[1] < -0.03) continue
    const towards = sub(light, at)
    const distance = length(towards)
    const facing: Vec3 = [floats[o + 16]!, floats[o + 17]!, floats[o + 18]!]
    const turned = 0.3 + 0.7 * Math.max(0, dot(facing, times(towards, 1 / distance)))
    floats[o + 11] = turned / Math.pow(1 + (distance / 0.4) ** 2, 1.3)
  }

  return {count, data: Float32Array.from(floats), reach: reach + 0.1, fire: light}
}
