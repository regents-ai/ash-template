/**
 * The floating island on the splats page (`AshTemplateWeb.SplatsLabLive`): a big tree,
 * two pines, rocks, flowers, the Regents crown in stone and a campfire, at night,
 * grown from one fixed seed into about a quarter of a million splats (build.ts).
 *
 * The moon lights it from the upper left, a cool rim light from behind on the right,
 * and the fire's warm light, baked in, flickers with the fire. Units: the grass disc
 * is about one unit across from its middle, its top at height 0, y up.
 */
import {
  add, around, clamp01, createBuilder, CROWN_BLOCKS, CROWN_PITCH, cross, dot, FLAME, growUnderside, hex, length, mix, restPose, smoothstep, SPARK, sub, times, unit, UP,
  type Glow, type Lighting, type Scene, type Vec3,
} from "./build.ts"
import {NIGHT} from "./palette.ts"

const SEED = 20_261_115

// Colours, before light.
const GRASS = ["#3c7a3f", "#4a8a44", "#5a9a49", "#336d3a"].map(hex)
const GRASS_BRIGHT = ["#78ad55", "#94bf5f"].map(hex)
const LEAF = ["#2a5c3a", "#356c3e", "#447f44", "#5a944b", "#7aab55", "#9cc263"].map(hex)
const NEEDLE = ["#1d4a3a", "#255a40", "#2f6a45", "#3d7d4b", "#5a9452"].map(hex)
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
  {at: [-0.66, 0, -0.02], height: 0.82, spread: 0.27},
  {at: [-0.42, 0, -0.42], height: 0.62, spread: 0.22},
]

/** The moon high on the left and in front, a cool rim light from behind on the right. */
const MOON: Vec3 = unit([-0.55, 0.7, 0.45])
const RIM: Vec3 = unit([0.65, 0.35, -0.68])

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

export function buildIsland(): Scene {
  const b = createBuilder(SEED)
  const {random, between, pick, jitter, onSphere, place, flat, long} = b

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

  for (let i = 0; i < 17_000; i++) {
    const a = random() * Math.PI * 2
    const r = Math.sqrt(random()) * rim(a) * 0.985
    const x = r * Math.cos(a)
    const z = r * Math.sin(a)
    const at = onGrass(x, z)
    const facing = groundFacing(x, z)
    if (inFire(x, z)) {
      flat(at, facing, 0.016, 0.014, 0.004, jitter(pick(ASH), 0.2), grassOpen(x, z) * 0.8)
      continue
    }
    flat(at, facing, between(0.014, 0.02), between(0.011, 0.016), 0.004, grassColour(x, z), grassOpen(x, z))
  }
  // Blades standing out of the grass, thickest at the edge, so its outline is ragged.
  for (let i = 0; i < 9000; i++) {
    const a = random() * Math.PI * 2
    const r = Math.pow(random(), 0.32) * rim(a) * 0.99
    const x = r * Math.cos(a)
    const z = r * Math.sin(a)
    if (inFire(x, z) || distanceOnGround(x, z, TRUNK) < 0.12 || distanceOnGround(x, z, ROCK) < 0.16) continue
    const tall = between(0.016, 0.05)
    const d = unit([between(-0.35, 0.35), 1, between(-0.35, 0.35)])
    const base = onGrass(x, z)
    const colour = random() < 0.3 ? pick(GRASS_BRIGHT) : jitter(pick(GRASS), 0.2)
    long(add(base, times(d, tall * 0.5)), d, tall * 0.45, 0.0045, colour, unit([Math.cos(a), 1.4, Math.sin(a)]), grassOpen(x, z), {sheen: 0.6})
  }

  // ----- What hangs underneath -----
  growUnderside(b, {
    rim,
    height: ground,
    depth: 0.66,
    tip: [0.06, 0, -0.05],
    grass: GRASS,
    shade: hex("#1e4a3a"),
    earth: EARTH,
    stone: STONE,
    roots: BARK,
  })

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
        place({at, axes: [d, unit(cross(d, out)), out], reach: [Math.min(0.022, radius * 0.7 + 0.004), Math.min(0.009, radius * 0.35 + 0.003), 0.003], colour, opacity: 0.97, facing: out, open: openAt(at[1])})
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
  bark(trunk, 0.00028, trunkOpen)
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
    ], 0.00028, trunkOpen)
  }
  // Roots spreading over the grass from the foot of the trunk.
  for (let k = 0; k < 6; k++) {
    const a = (k / 6) * Math.PI * 2 + between(-0.3, 0.3)
    const reachOut = between(0.2, 0.32)
    const end: Vec3 = [base[0] + Math.cos(a) * reachOut, 0, base[2] + Math.sin(a) * reachOut]
    const half: Vec3 = [base[0] + Math.cos(a) * reachOut * 0.55, 0, base[2] + Math.sin(a) * reachOut * 0.55]
    bark([
      {at: add(base, [Math.cos(a) * 0.06, 0.03, Math.sin(a) * 0.06]), radius: 0.045},
      {at: [half[0], ground(half[0], half[2]) + 0.012, half[2]], radius: 0.026},
      {at: [end[0], ground(end[0], end[2]) - 0.01, end[2]], radius: 0.008},
    ], 0.0003, () => 0.62)
  }

  // The crown of leaves: hundreds of small clusters over a wide, rounded, flat-bottomed
  // head, each lit on its own top, so the crown reads as sprays of leaves with shade
  // between them.
  const CROWN = 0.86
  const heads: readonly {at: Vec3; radius: number}[] = [
    {at: [0, 0.3, 0], radius: 0.38}, {at: [-0.46, 0.1, 0.12], radius: 0.34}, {at: [0.46, 0.13, -0.06], radius: 0.34},
    {at: [0.06, 0.06, 0.46], radius: 0.33}, {at: [-0.06, 0.08, -0.46], radius: 0.33}, {at: [-0.6, -0.12, -0.26], radius: 0.28},
    {at: [0.62, -0.1, 0.26], radius: 0.28}, {at: [-0.36, -0.14, 0.46], radius: 0.27}, {at: [0.36, -0.12, -0.46], radius: 0.28},
    {at: [0.26, 0.32, 0.26], radius: 0.3}, {at: [-0.26, 0.3, -0.22], radius: 0.3}, {at: [0.0, -0.18, 0.0], radius: 0.38},
  ]
  const clusters: {at: Vec3; radius: number; tint: number}[] = []
  for (const head of heads) {
    const centre = add(CANOPY, times(head.at, CROWN))
    const radius = head.radius * CROWN
    const many = Math.round(40 * (head.radius / 0.3) ** 2)
    for (let k = 0; k < many; k++) {
      const dir = onSphere()
      if (dir[1] < -0.55 && random() < 0.6) continue
      clusters.push({at: add(centre, [dir[0] * radius * 0.86, dir[1] * radius * 0.74, dir[2] * radius * 0.86]), radius: between(0.042, 0.075), tint: between(0.84, 1.16)})
    }
  }
  for (const cluster of clusters) {
    const outward = unit(sub(cluster.at, add(CANOPY, [0, -0.15, 0])))
    const height = (cluster.at[1] - CANOPY[1]) / (0.6 * CROWN)
    const leaves = Math.round(950 * (cluster.radius / 0.1) ** 2)
    for (let i = 0; i < leaves; i++) {
      const dir = onSphere()
      const depth = 0.55 + 0.45 * Math.pow(random(), 0.5)
      const at = add(cluster.at, [dir[0] * cluster.radius * depth, dir[1] * cluster.radius * depth * 0.8, dir[2] * cluster.radius * depth])
      const facing = unit(add(times(dir, 0.65), times(outward, 0.35)))
      const open = clamp01(
        (0.3 + 0.7 * smoothstep(0.55, 1.0, depth)) *
          (0.45 + 0.55 * smoothstep(-1.1, 0.7, height)) *
          (0.4 + 0.6 * smoothstep(-0.7, 0.5, dir[1])) *
          (0.5 + 0.5 * smoothstep(-0.2, 0.6, dot(outward, unit([dir[0], dir[1] + 0.3, dir[2]])))),
      )
      const shade = Math.min(0.999, random() * 0.75 + 0.3 * smoothstep(-0.2, 0.8, dir[1]) * depth)
      const colour = LEAF[Math.min(LEAF.length - 1, Math.floor(shade * LEAF.length))]!
      const leafFacing = unit(add(facing, times(onSphere(), 0.35)))
      flat(at, leafFacing, between(0.009, 0.015), between(0.006, 0.01), 0.003, times(jitter(colour, 0.2), cluster.tint), open, {opacity: 0.97, sheen: 0.8})
    }
  }
  // Leaves hanging under the crown's rim, so its lower edge is ragged.
  for (let i = 0; i < 1600; i++) {
    const head = heads[Math.floor(random() * heads.length)]!
    const centre = add(CANOPY, times(head.at, CROWN))
    const radius = head.radius * CROWN
    const a = random() * Math.PI * 2
    const at = add(centre, [Math.cos(a) * radius * 0.8, -radius * between(0.65, 1.0), Math.sin(a) * radius * 0.8])
    flat(at, unit([Math.cos(a), -0.6, Math.sin(a)]), between(0.01, 0.016), 0.008, 0.003, jitter(LEAF[1]!, 0.25), 0.35)
  }

  // ----- Two pines: whorls of drooping boughs, each a branch with needles along it -----
  for (const pine of PINES) {
    const foot: Vec3 = [pine.at[0], ground(pine.at[0], pine.at[2]), pine.at[2]]
    bark([
      {at: add(foot, [0, -0.02, 0]), radius: 0.028},
      {at: add(foot, [0, pine.height * 0.85, 0]), radius: 0.01},
    ], 0.0003, () => 0.5)
    const whorls = 9
    for (let w = 0; w < whorls; w++) {
      const rise = w / (whorls - 1)
      const y = 0.1 + rise * (pine.height - 0.16)
      const spread = pine.spread * Math.pow(1 - rise, 0.85) + 0.035
      const boughs = Math.max(5, Math.round(9 - rise * 4))
      const twist = random() * Math.PI * 2
      for (let k = 0; k < boughs; k++) {
        const a = twist + (k / boughs) * Math.PI * 2 + between(-0.2, 0.2)
        const out: Vec3 = [Math.cos(a), 0, Math.sin(a)]
        const side = unit(cross(UP, out))
        const reachOut = spread * between(0.85, 1.1)
        const droop = 0.35 + 0.25 * (1 - rise)
        const steps = Math.max(6, Math.round(reachOut / 0.012))
        for (let s = 0; s < steps; s++) {
          const t = (s + 0.5) / steps
          // The bough sags along its length and turns up a little at its tip.
          const at = add(foot, [out[0] * reachOut * t, y - droop * reachOut * t * t + 0.25 * reachOut * Math.pow(t, 6), out[2] * reachOut * t])
          const along = unit([out[0], -2 * droop * t + 1.5 * Math.pow(t, 5), out[2]])
          const lit = 0.35 + 0.65 * t
          const tone = t > 0.82 ? 4 : t > 0.6 ? 3 : t > 0.35 ? 2 : 1
          const needleColour = jitter(NEEDLE[Math.min(4, tone - (random() < 0.3 ? 1 : 0))]!, 0.15)
          const facing = unit(add(UP, times(out, 0.5)))
          // Needles fan out to both sides of the bough, shorter toward its tip.
          const fan = Math.round(4 + 3 * (1 - t))
          for (let n = 0; n < fan; n++) {
            const sideways = (random() < 0.5 ? -1 : 1) * between(0.3, 1)
            const needle = unit(add(add(along, times(side, sideways * 1.4)), [0, between(-0.35, 0.1), 0]))
            const length = 0.012 * (1.1 - 0.5 * t)
            long(add(at, times(needle, length * 0.9)), needle, length, 0.0035, needleColour, facing, clamp01(lit * (0.55 + 0.45 * rise)), {sheen: 0.35})
          }
        }
      }
    }
    // The top: a few upright tufts.
    for (let i = 0; i < 40; i++) {
      const at = add(foot, [between(-0.01, 0.01), pine.height + between(-0.08, 0.02), between(-0.01, 0.01)])
      long(at, unit([between(-0.3, 0.3), 1, between(-0.3, 0.3)]), 0.014, 0.004, jitter(NEEDLE[3]!, 0.2), unit([between(-1, 1), 0.6, between(-1, 1)]), 0.9, {sheen: 0.35})
    }
  }

  // ----- Stones -----
  const stone = (at: Vec3, radii: Vec3, splats: number, mossy: number, size: number) => {
    const phase = random() * 10
    for (let i = 0; i < splats; i++) {
      const dir = onSphere()
      const lump = 1 + 0.12 * Math.sin(dir[0] * 4 + phase) * Math.cos(dir[2] * 5 - phase) + 0.06 * Math.sin(dir[1] * 9 + phase)
      const p = add(at, [dir[0] * radii[0] * lump, dir[1] * radii[1] * lump, dir[2] * radii[2] * lump])
      const facing = unit([dir[0] / radii[0], dir[1] / radii[1], dir[2] / radii[2]])
      let colour = facing[1] > 0.5 ? STONE[3]! : facing[1] < -0.1 ? STONE[2]! : pick(STONE)
      if (facing[1] > 0.55 && random() < mossy) colour = pick(MOSS)
      flat(p, facing, size * between(0.85, 1.2), size * between(0.7, 1), size * 0.25, jitter(colour, 0.14), 0.45 + 0.5 * clamp01(facing[1] * 0.5 + 0.5), {opacity: 0.98})
    }
  }
  stone(add(onGrass(ROCK[0], ROCK[2]), [0, 0.05, 0]), [0.19, 0.13, 0.16], 3600, 0.55, 0.015)
  stone(add(onGrass(PEBBLE_ROCK[0], PEBBLE_ROCK[2]), [0, 0.03, 0]), [0.1, 0.075, 0.09], 1300, 0.3, 0.013)
  for (let i = 0; i < 60; i++) {
    const a = random() * Math.PI * 2
    const r = Math.sqrt(random()) * 0.9
    const x = r * Math.cos(a)
    const z = r * Math.sin(a)
    if (inFire(x, z)) continue
    stone(add(onGrass(x, z), [0, 0.006, 0]), [0.014, 0.01, 0.012], 8, 0, 0.007)
  }

  // ----- The crown: thirteen stone blocks on a low slab, five wide and three high,
  // the top row only at the first, middle and last places -----
  {
    const out = unit([MONUMENT[0], 0, MONUMENT[2]])
    const side = unit(cross(UP, out))
    const foot: Vec3 = [MONUMENT[0], ground(MONUMENT[0], MONUMENT[2]), MONUMENT[2]]
    const block = 0.07
    const pitch = block * CROWN_PITCH
    const box = (centre: Vec3, half: Vec3, top: Vec3, faces: Vec3, open: number) => {
      const axes: readonly [Vec3, Vec3, Vec3] = [out, UP, side]
      for (let f = 0; f < 3; f++) {
        for (const sign of [-1, 1]) {
          const n = times(axes[f]!, sign)
          const u = axes[(f + 1) % 3]!
          const v = axes[(f + 2) % 3]!
          const hu = half[(f + 1) % 3]!
          const hv = half[(f + 2) % 3]!
          const across = Math.max(1, Math.round(hu / 0.009))
          const down = Math.max(1, Math.round(hv / 0.009))
          for (let i = 0; i < across; i++) {
            for (let j = 0; j < down; j++) {
              const at = add(add(add(centre, times(n, half[f]!)), times(u, hu * ((2 * i + 1) / across - 1))), times(v, hv * ((2 * j + 1) / down - 1)))
              const colour = f === 1 && sign > 0 ? top : faces
              place({at, axes: [u, v, n], reach: [(hu / across) * 0.8, (hv / down) * 0.8, 0.002], colour: jitter(colour, 0.1), opacity: 0.99, facing: n, open})
            }
          }
        }
      }
    }
    box(add(foot, [0, 0.012, 0]), [0.07, 0.03, 0.23], hex("#6a7383"), hex("#4f5766"), 0.7)
    for (const [column, row] of CROWN_BLOCKS) {
      const centre = add(add(foot, times(side, column * pitch)), [0, 0.042 + block / 2 + (row + 1) * pitch, 0])
      box(centre, [block * 0.42, block / 2, block / 2], hex("#9aa3b0"), hex("#7c8595"), 0.85)
    }
  }

  // ----- The campfire: a ring of stones, four logs, embers, flames and sparks -----
  const fireFoot: Vec3 = [FIRE[0], ground(FIRE[0], FIRE[2]), FIRE[2]]
  for (let k = 0; k < 9; k++) {
    const a = (k / 9) * Math.PI * 2 + between(-0.15, 0.15)
    stone(add(fireFoot, [Math.cos(a) * 0.13, 0.014, Math.sin(a) * 0.13]), [0.034, 0.024, 0.03], 60, 0, 0.009)
  }
  for (let k = 0; k < 4; k++) {
    const a = (k / 4) * Math.PI * 2 + 0.4
    const footOfLog = add(fireFoot, [Math.cos(a) * 0.09, 0.012, Math.sin(a) * 0.09])
    const apex = add(fireFoot, [Math.cos(a) * 0.012, 0.12, Math.sin(a) * 0.012])
    bark([{at: footOfLog, radius: 0.017}, {at: apex, radius: 0.012}], 0.0002, () => 0.6)
  }
  for (let i = 0; i < 40; i++) {
    const a = random() * Math.PI * 2
    const r = Math.sqrt(random()) * 0.075
    place({at: add(fireFoot, [Math.cos(a) * r, 0.012, Math.sin(a) * r]), axes: [[1, 0, 0], UP, [0, 0, 1]], reach: [0.01, 0.005, 0.01], colour: random() < 0.5 ? FLAME_COLOURS.tip : FLAME_COLOURS.outer, opacity: 0.95, facing: UP, open: 1, kind: FLAME, phase: random()})
  }
  const FLAME_HEIGHT = 0.27
  for (let i = 0; i < 260; i++) {
    const h = Math.pow(random(), 1.35) * FLAME_HEIGHT
    const t = h / FLAME_HEIGHT
    const width = 0.065 * Math.pow(1 - t, 0.7) + 0.006
    const a = random() * Math.PI * 2
    const r = Math.sqrt(random()) * width
    const centre = r / width
    const colour =
      t < 0.3 && centre < 0.45 ? mix(FLAME_COLOURS.core, FLAME_COLOURS.inner, t * 2) :
      t < 0.55 && centre < 0.7 ? FLAME_COLOURS.inner :
      t < 0.75 ? FLAME_COLOURS.middle :
      t < 0.92 ? FLAME_COLOURS.outer : FLAME_COLOURS.tip
    place({at: add(fireFoot, [Math.cos(a) * r, 0.03 + h, Math.sin(a) * r]), axes: [[1, 0, 0], UP, [0, 0, 1]], reach: [0.013 * (1 - t * 0.5), 0.024 * (1 - t * 0.3), 0.013 * (1 - t * 0.5)], colour, opacity: 0.88, facing: UP, open: 1, kind: FLAME, phase: random()})
  }
  for (let i = 0; i < 26; i++) {
    place({at: add(fireFoot, [between(-0.04, 0.04), 0.14, between(-0.04, 0.04)]), axes: [[1, 0, 0], UP, [0, 0, 1]], reach: [0.006, 0.008, 0.006], colour: random() < 0.5 ? FLAME_COLOURS.inner : FLAME_COLOURS.middle, opacity: 1, facing: UP, open: 1, kind: SPARK, phase: random()})
  }

  // ----- Two bushes -----
  for (const bush of [{at: [-0.06, 0, 0.74] as Vec3, size: 0.11}, {at: [0.7, 0, -0.5] as Vec3, size: 0.13}]) {
    const foot = onGrass(bush.at[0], bush.at[2])
    for (let c = 0; c < 6; c++) {
      const centre = add(foot, [between(-1, 1) * bush.size * 0.6, bush.size * between(0.5, 0.95), between(-1, 1) * bush.size * 0.6])
      const radius = bush.size * between(0.5, 0.75)
      for (let i = 0; i < 380; i++) {
        const dir = onSphere()
        if (centre[1] + dir[1] * radius < foot[1]) continue
        const at = add(centre, times(dir, radius * (0.75 + 0.25 * random())))
        const open = 0.35 + 0.55 * clamp01((at[1] - foot[1]) / (bush.size * 1.6)) * (0.5 + 0.5 * dir[1])
        const shade = Math.min(0.999, random() * 0.7 + 0.35 * smoothstep(-0.2, 0.8, dir[1]))
        flat(at, unit(add(dir, times(onSphere(), 0.5))), between(0.009, 0.014), 0.008, 0.003, jitter(LEAF[Math.floor(shade * (LEAF.length - 1))]!, 0.2), open, {sheen: 0.7})
      }
    }
  }

  // ----- Flowers in the open grass -----
  for (let i = 0; i < 160; ) {
    const a = random() * Math.PI * 2
    const r = Math.sqrt(random()) * 0.9
    const x = r * Math.cos(a)
    const z = r * Math.sin(a)
    if (distanceOnGround(x, z, TRUNK) < 0.35 || distanceOnGround(x, z, FIRE) < 0.22 || distanceOnGround(x, z, ROCK) < 0.24 || distanceOnGround(x, z, MONUMENT) < 0.26) continue
    if (PINES.some(pine => distanceOnGround(x, z, pine.at) < pine.spread)) continue
    i += 1
    const colour = pick(FLOWER)
    const stem = between(0.02, 0.04)
    long(add(onGrass(x, z), [0, stem * 0.5, 0]), UP, stem * 0.45, 0.003, GRASS[0]!, UP, 0.8)
    flat(add(onGrass(x, z), [0, stem, 0]), UP, 0.009, 0.008, 0.004, jitter(colour, 0.1), 0.95, {opacity: 0.99})
  }

  const light: Vec3 = add(fireFoot, [0, 0.1, 0])
  const lighting: Lighting = {
    key: MOON,
    keyColour: [0.5, 0.58, 0.76],
    sky: [0.3, 0.36, 0.5],
    bounce: [0.26, 0.22, 0.3],
    rim: RIM,
    rimColour: [0.62, 0.78, 0.82],
    shineColour: [0.62, 0.78, 0.82],
    warm: [1.0, 0.52, 0.2],
    lamps: [{at: light, strength: 2.2, reach: 0.4, flickers: true}],
  }
  const {count, data, reach} = b.finish(lighting)
  const glows: readonly Glow[] = [{at: add(light, [0, 0.02, 0]), colour: [1.0, 0.42, 0.12], radius: 0.36, strength: 0.3, facing: UP}]

  return {
    count,
    data,
    reach,
    camera: {pitch: (17 * Math.PI) / 180, field: (16.5 * Math.PI) / 180, distance: 8.7, lookAt: 0.46, radius: 1.0},
    palette: NIGHT,
    sky: {
      zenith: hex("#070b18"),
      high: hex("#122044"),
      horizon: hex("#2c4580"),
      below: hex("#0b1226"),
      glowAt: -2.2,
      glow: [0.08, 0.1, 0.16],
      cloud: hex("#26396a"),
      stars: 0.0035,
    },
    rim: RIM,
    edge: [0.68, 0.79, 0.8],
    glows,
    motes: {back: 34, front: 6, colours: [[0.68, 0.79, 0.8], [0.62, 0.7, 0.86]], size: 0.02},
    parts: 1,
    pose: (_seconds, into) => restPose(into, 1),
    still: {turn: (-24 * Math.PI) / 180, pitch: (17 * Math.PI) / 180, seconds: 3.2},
  }
}
