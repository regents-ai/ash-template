/**
 * What every scene on the splats page (`AshTemplateWeb.SplatsLabLive`) is made of, and
 * the kit its generators grow it with: 3D gaussians (splats) in the standard layout of
 * Gaussian splatting (Kerbl et al., 2023), placed by code from a fixed seed rather
 * than trained from photographs.
 *
 * Each splat is a place; a rotation (a unit quaternion, real part first) and the log
 * of its three scales, which together give its covariance Σ = R S Sᵀ Rᵀ; its opacity
 * before the sigmoid; and its colour as spherical harmonics of degrees 0 and 1, so it
 * may look different from different sides. The light is baked into those colours
 * here, as a trained scene's is: a key light, the sky, a rim light from behind, warm
 * lamps, and how open each splat is to the sky. Five more numbers per splat say how it
 * moves, if it does (painter.ts reads them): its kind, a phase, the moving part it
 * belongs to, the share of its colour a flickering light gives it, and a blink rate.
 *
 * Units: a scene's ground is about one unit from its middle to its edge, y up. This
 * file imports nothing, so the scripts beside it (`stills.mjs`, `export_ply.mjs`) grow
 * exactly the scenes the browser does.
 */

export type Vec3 = readonly [number, number, number]

/** Floats per splat, in the order `Splat` in painter.ts reads them. */
export const SPLAT_FLOATS = 28
/** Where the moving part's number sits in a splat, for the sort (order.ts). */
export const PART_FLOAT = 19

/** The constants of real spherical harmonics of degrees 0 and 1. */
export const SH_C0 = 0.28209479177387814
export const SH_C1 = 0.4886025119029199

/** What a splat does: stays lit where it is, licks up as a flame, rises as a spark or as
 * steam, wanders as a firefly, or ripples as water. */
export const SURFACE = 0
export const FLAME = 1
export const SPARK = 2
export const STEAM = 3
export const FIREFLY = 4
export const WATER = 5

/** A warm lamp baked into the colours: where it is, how bright, how far it reaches, and
 * whether it flickers (a fire) or holds steady (a window). */
export type Lamp = {readonly at: Vec3; readonly strength: number; readonly reach: number; readonly flickers?: boolean}

/** The light a scene is baked in. Directions point toward the light. */
export type Lighting = {
  readonly key: Vec3
  readonly keyColour: Vec3
  readonly sky: Vec3
  readonly bounce: Vec3
  readonly rim: Vec3
  readonly rimColour: Vec3
  readonly shineColour: Vec3
  readonly warm: Vec3
  readonly lamps: readonly Lamp[]
}

/** A soft halo the picture adds round a bright place, brighter when its face is toward the camera. */
export type Glow = {
  readonly at: Vec3
  readonly colour: Vec3
  readonly radius: number
  readonly strength: number
  /** The way it faces, or none for a lamp seen from every side. */
  readonly facing?: Vec3
}

/** How the sky behind a scene looks, by the height of each ray above the horizon. */
export type Sky = {
  readonly zenith: Vec3
  readonly high: Vec3
  readonly horizon: Vec3
  readonly below: Vec3
  /** The glow on the horizon toward the sun or the moon, by angle round from +z. */
  readonly glowAt: number
  readonly glow: Vec3
  readonly cloud: Vec3
  readonly stars: number
}

export type Camera = {
  /** The resting tilt above the scene, the vertical angle the picture's height sees, how
   * far back the camera orbits, and the height it orbits round. */
  readonly pitch: number
  readonly field: number
  /** How wide the scene stands as it turns, in heights of the field: a picture at least
   * this wide shows the field top to bottom, and a narrower one (a phone's square) shows
   * this width side to side instead, so the scene fills either. */
  readonly width: number
  readonly distance: number
  readonly lookAt: number
  /** The scene's radius, the distance a drag at its edge carries one to one. */
  readonly radius: number
}

export type Scene = {
  readonly count: number
  /** `SPLAT_FLOATS` per splat, as painter.ts's `Splat` lays them out. */
  readonly data: Float32Array<ArrayBuffer>
  /** The farthest any splat sits from the scene's middle, moving parts included. */
  readonly reach: number
  readonly camera: Camera
  readonly palette: readonly string[]
  readonly sky: Sky
  /** The way toward the rim light, and the colour of the bright pixels along the edge of the
   * scene's outline on that side. */
  readonly rim: Vec3
  readonly edge: Vec3
  readonly glows: readonly Glow[]
  /** Soft motes over the picture: how many behind the scene and in front, and their two colours. */
  readonly motes: {readonly back: number; readonly front: number; readonly colours: readonly [Vec3, Vec3]; readonly size: number}
  /** How many moving parts, and where each is at a moment: 16 floats a part (three axes, a
   * move and an opacity), part 0 standing still. In a recorded loop of `loop` seconds
   * every part comes round a whole number of times (`rate`); 0 is the page's own clock. */
  readonly parts: number
  pose(seconds: number, into: Float32Array<ArrayBuffer>, loop: number): void
  /** The turn, tilt and moment of the still picture, the first frame and a still scene. */
  readonly still: {readonly turn: number; readonly pitch: number; readonly seconds: number}
}

export const add = (a: Vec3, b: Vec3): Vec3 => [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
export const sub = (a: Vec3, b: Vec3): Vec3 => [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
export const times = (a: Vec3, k: number): Vec3 => [a[0] * k, a[1] * k, a[2] * k]
export const dot = (a: Vec3, b: Vec3) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
export const cross = (a: Vec3, b: Vec3): Vec3 => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
export const length = (a: Vec3) => Math.hypot(a[0], a[1], a[2])
export const unit = (a: Vec3): Vec3 => times(a, 1 / (length(a) || 1))
export const mix = (a: Vec3, b: Vec3, t: number): Vec3 => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
export const clamp01 = (x: number) => Math.min(1, Math.max(0, x))
export const smoothstep = (from: number, to: number, x: number) => {
  const t = clamp01((x - from) / (to - from))
  return t * t * (3 - 2 * t)
}
export const UP: Vec3 = [0, 1, 0]

/**
 * The loop rule: something that comes round `cycles` times a second, as the clock runs
 * in a recorded loop of `loop` seconds (gif.ts). In a loop it comes round the nearest
 * whole number of times, and at least once, so the loop's last moment runs on into its
 * first; with no loop (0, the page) it keeps its own pace. `floor(x + 0.5)` rather than
 * `round`, so painter.ts's shaders, which round halves to even, snap the same way.
 */
export const rate = (cycles: number, loop: number) => (loop > 0 ? Math.max(1, Math.floor(cycles * loop + 0.5)) / loop : cycles)
/** `rate` for a wave given in radians a second. */
export const wave = (radians: number, loop: number) => (loop > 0 ? 2 * Math.PI * rate(radians / (2 * Math.PI), loop) : radians)

export const hex = (value: string): Vec3 => {
  const n = Number.parseInt(value.slice(1), 16)
  return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255]
}

/** Two axes at right angles to `n`, turned by `spin` round it. */
export function around(n: Vec3, spin: number): [Vec3, Vec3] {
  const helper: Vec3 = Math.abs(n[1]) < 0.92 ? UP : [1, 0, 0]
  const t = unit(cross(helper, n))
  const b = cross(n, t)
  const c = Math.cos(spin)
  const s = Math.sin(spin)
  return [add(times(t, c), times(b, s)), add(times(t, -s), times(b, c))]
}

/** The unit quaternion (real part first) of the rotation whose columns are these axes. */
export function quaternion(a: Vec3, b: Vec3, c: Vec3): [number, number, number, number] {
  // A left-handed set of axes describes the same ellipsoid with its third axis flipped.
  const z = dot(cross(a, b), c) < 0 ? times(c, -1) : c
  const [m00, m10, m20] = a
  const [m01, m11, m21] = b
  const [m02, m12, m22] = z
  const trace = m00 + m11 + m22
  let q: [number, number, number, number]
  if (trace > 0) {
    const s = Math.sqrt(trace + 1) * 2
    q = [0.25 * s, (m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s]
  } else if (m00 > m11 && m00 > m22) {
    const s = Math.sqrt(1 + m00 - m11 - m22) * 2
    q = [(m21 - m12) / s, 0.25 * s, (m01 + m10) / s, (m02 + m20) / s]
  } else if (m11 > m22) {
    const s = Math.sqrt(1 + m11 - m00 - m22) * 2
    q = [(m02 - m20) / s, (m01 + m10) / s, 0.25 * s, (m12 + m21) / s]
  } else {
    const s = Math.sqrt(1 + m22 - m00 - m11) * 2
    q = [(m10 - m01) / s, (m02 + m20) / s, (m12 + m21) / s, 0.25 * s]
  }
  const n = Math.hypot(...q)
  return [q[0] / n, q[1] / n, q[2] / n, q[3] / n]
}

/** A seeded generator (mulberry32): the same seed, the same scene. */
export function randomFrom(seed: number) {
  let state = seed >>> 0
  return () => {
    state = (state + 0x6d2b79f5) >>> 0
    let t = state
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4_294_967_296
  }
}

/** One splat as a generator places it, before its light is baked. */
export type Placed = {
  at: Vec3
  /** Three axes at right angles, and how far the splat reaches along each (one standard deviation). */
  axes: readonly [Vec3, Vec3, Vec3]
  reach: Vec3
  /** Its colour before light, or the colour it gives off when it glows. */
  colour: Vec3
  opacity: number
  /** The way its surface faces, and how open it is to the sky (1 open, 0 shut in). */
  facing: Vec3
  open: number
  kind?: number
  phase?: number
  part?: number
  /** How much light it gives off itself: 1 shows its colour whatever the light. */
  glow?: number
  /** A mirror-like gleam that moves as the view moves (glass, panels, water). */
  shine?: number
  /** A bright edge when seen against the rim light (leaves, grass). */
  sheen?: number
  /** Blinks this many times a second. */
  blink?: number
}

// The raw fields kept per splat until the light is baked.
const RAW = 26

export function createBuilder(seed: number) {
  const random = randomFrom(seed)
  let raw = new Float32Array(RAW * 65_536)
  let count = 0

  const between = (from: number, to: number) => from + (to - from) * random()
  const pick = <T>(list: readonly T[]) => list[Math.floor(random() * list.length)]!
  const jitter = (colour: Vec3, amount: number): Vec3 => times(colour, 1 + (random() - 0.5) * amount)
  const onSphere = (): Vec3 => {
    const y = random() * 2 - 1
    const a = random() * Math.PI * 2
    const r = Math.sqrt(1 - y * y)
    return [r * Math.cos(a), y, r * Math.sin(a)]
  }

  const place = (s: Placed) => {
    if ((count + 1) * RAW > raw.length) {
      const grown = new Float32Array(raw.length * 2)
      grown.set(raw)
      raw = grown
    }
    const q = quaternion(s.axes[0], s.axes[1], s.axes[2])
    const o = count * RAW
    raw.set([
      s.at[0], s.at[1], s.at[2], Math.min(0.995, Math.max(0.005, s.opacity)),
      q[0], q[1], q[2], q[3],
      Math.max(1e-5, s.reach[0]), Math.max(1e-5, s.reach[1]), Math.max(1e-5, s.reach[2]),
      s.colour[0], s.colour[1], s.colour[2],
      s.facing[0], s.facing[1], s.facing[2], s.open,
      s.kind ?? SURFACE, s.phase ?? 0, s.part ?? 0, s.glow ?? 0, s.shine ?? 0, s.sheen ?? 0, s.blink ?? 0, 0,
    ], o)
    count += 1
  }

  /** A flat splat lying across `facing`. */
  const flat = (at: Vec3, facing: Vec3, wide: number, narrow: number, thin: number, colour: Vec3, open: number, extra: Partial<Placed> = {}) => {
    const [t, b] = around(facing, random() * Math.PI * 2)
    place({at, axes: [t, b, facing], reach: [wide, narrow, thin], colour, opacity: 0.96, facing, open, ...extra})
  }

  /** A flat splat lying across `facing`, its long side along `along`. */
  const tile = (at: Vec3, facing: Vec3, along: Vec3, wide: number, narrow: number, colour: Vec3, open: number, extra: Partial<Placed> = {}) => {
    const across = unit(cross(facing, along))
    place({at, axes: [unit(along), across, facing], reach: [wide, narrow, Math.min(wide, narrow) * 0.25], colour, opacity: 0.97, facing, open, ...extra})
  }

  /** A long splat running along `along`, seen from `facing`. */
  const long = (at: Vec3, along: Vec3, reach: number, width: number, colour: Vec3, facing: Vec3, open: number, extra: Partial<Placed> = {}) => {
    const d = unit(along)
    const [t, b] = around(d, random() * Math.PI * 2)
    place({at, axes: [d, t, b], reach: [reach, width, width * 0.6], colour, opacity: 0.96, facing, open, ...extra})
  }

  /** A round splat. */
  const ball = (at: Vec3, radius: number, colour: Vec3, facing: Vec3, open: number, extra: Partial<Placed> = {}) =>
    place({at, axes: [[1, 0, 0], UP, [0, 0, 1]], reach: [radius, radius, radius], colour, opacity: 0.95, facing, open, ...extra})

  /**
   * Bakes the light into every splat's colour and hands back the splats in the standard
   * layout: the colour each would show lit from every side, plus a degree-1 lobe for how
   * it changes with the view, and the share a flickering lamp gives it.
   */
  const finish = (light: Lighting): {count: number; data: Float32Array<ArrayBuffer>; reach: number} => {
    const data = new Float32Array(count * SPLAT_FLOATS)
    const key = unit(light.key)
    const rim = unit(light.rim)
    let reach = 0
    for (let i = 0; i < count; i++) {
      const r = i * RAW
      const o = i * SPLAT_FLOATS
      const at: Vec3 = [raw[r]!, raw[r + 1]!, raw[r + 2]!]
      const colour: Vec3 = [raw[r + 11]!, raw[r + 12]!, raw[r + 13]!]
      const n: Vec3 = [raw[r + 14]!, raw[r + 15]!, raw[r + 16]!]
      const open = raw[r + 17]!
      const kind = raw[r + 18]!
      const glow = raw[r + 21]!
      const shine = raw[r + 22]!
      const sheen = raw[r + 23]!
      reach = Math.max(reach, length(at) + 3 * Math.max(raw[r + 8]!, raw[r + 9]!, raw[r + 10]!))

      let lit: Vec3
      let flickering = 0
      let lobe: Vec3 = [0, 0, 0]
      let lobeColour: Vec3 = [0, 0, 0]
      if (kind === FLAME || kind === SPARK || kind === FIREFLY || glow >= 1) {
        lit = times(colour, Math.max(1, glow))
      } else {
        const ambient = times(mix(light.bounce, light.sky, n[1] * 0.5 + 0.5), open)
        const keyLit = times(light.keyColour, Math.max(0, dot(n, key)) * (0.3 + 0.7 * open))
        let steady = 0
        let flicker = 0
        for (const lamp of light.lamps) {
          const towards = sub(lamp.at, at)
          const distance = length(towards) || 1e-6
          const facing = 0.25 + 0.75 * Math.max(0, dot(n, times(towards, 1 / distance)))
          const amount = (lamp.strength * facing) / Math.pow(1 + (distance / lamp.reach) ** 2, 1.5)
          if (lamp.flickers) flicker += amount
          else steady += amount
        }
        const warm = times(light.warm, steady + flicker)
        const received = add(add(ambient, keyLit), warm)
        lit = add([colour[0] * received[0], colour[1] * received[1], colour[2] * received[2]], times(colour, glow))
        const total = lit[0] + lit[1] + lit[2]
        flickering = total > 0 ? clamp01((dot(colour, light.warm) * flicker) / total) : 0
        // A gleam of the cool light in glass, panels and water: the clamped lobe toward
        // where that light would mirror off the surface, projected onto degrees 0 and 1.
        if (shine > 0) {
          const mirrored = sub(times(n, 2 * dot(n, rim)), rim)
          lobe = times(mirrored, -1)
          lobeColour = times(light.shineColour, shine)
        } else if (sheen > 0) {
          // Leaves and grass seen against the rim light glow along their edges.
          lobe = rim
          lobeColour = times(light.rimColour, sheen * (1 - Math.abs(dot(n, rim))) * (0.4 + 0.6 * open))
        }
      }
      // A clamped cosine lobe max(0, d·l) is about 1/4 + (d·l)/2 in degrees 0 and 1.
      const base = add(lit, times(lobeColour, 0.25))
      data.set([at[0], at[1], at[2], Math.log(raw[r + 3]! / (1 - raw[r + 3]!))], o)
      data.set([raw[r + 4]!, raw[r + 5]!, raw[r + 6]!, raw[r + 7]!], o + 4)
      data.set([Math.log(raw[r + 8]!), Math.log(raw[r + 9]!), Math.log(raw[r + 10]!), kind], o + 8)
      data.set([(base[0] - 0.5) / SH_C0, (base[1] - 0.5) / SH_C0, (base[2] - 0.5) / SH_C0, raw[r + 19]!], o + 12)
      // colour(d) = 0.5 + C0 dc + C1 (-y s1 + z s2 - x s3), so a lobe g · d has s1 = -g.y/C1, s2 = g.z/C1, s3 = -g.x/C1.
      for (let c = 0; c < 3; c++) {
        const g = times(lobe, lobeColour[c]! * 0.5)
        data.set([-g[1] / SH_C1, g[2] / SH_C1, -g[0] / SH_C1], o + 16 + c * 4)
      }
      data[o + 19] = raw[r + 20]!
      data[o + 23] = flickering
      data[o + 27] = raw[r + 24]!
    }
    return {count, data, reach}
  }

  return {random, between, pick, jitter, onSphere, place, flat, tile, long, ball, finish, count: () => count}
}

export type Builder = ReturnType<typeof createBuilder>

/** The underside of a floating island: what hangs under its grass disc. */
export type Underside = {
  /** The grass disc's edge by the angle round it, about 1. */
  readonly rim: (angle: number) => number
  /** The grass's height at a place. */
  readonly height: (x: number, z: number) => number
  /** How deep the earth hangs, and where its lowest point leans to. */
  readonly depth: number
  readonly tip: Vec3
  readonly grass: readonly Vec3[]
  /** The colour grass darkens to as it hangs. */
  readonly shade: Vec3
  /** Four earth colours: the last two are its light and dark bands. */
  readonly earth: readonly Vec3[]
  readonly stone: readonly Vec3[]
  readonly roots: readonly Vec3[]
}

/**
 * Grows the underside of a floating island: grass hanging over the rim in many
 * lengths, the grass's underside, the earth hanging below in bands with stones in it,
 * and roots. Hands back a point on the earth, by the angle round and the depth (0 at
 * the rim, 1 at the tip), for anything else hung from it.
 */
export function growUnderside(b: Builder, under: Underside): (angle: number, depth: number) => Vec3 {
  const {random, between, pick, jitter, flat, long} = b
  const {rim, height, depth: deep, tip, grass, shade, earth, stone, roots} = under

  // Grass hanging over the edge, of many lengths, so the outline below the rim is ragged.
  for (let i = 0; i < 7000; i++) {
    const a = random() * Math.PI * 2
    const out: Vec3 = [Math.cos(a), 0, Math.sin(a)]
    const r = rim(a) + between(-0.035, 0.012)
    const start: Vec3 = [out[0] * r, height(out[0] * r, out[2] * r) - between(0, 0.03), out[2] * r]
    const hang = 0.02 + 0.13 * Math.pow(random(), 2.2)
    const d = unit([out[0] * between(0.05, 0.35), -1, out[2] * between(0.05, 0.35)])
    const colour = mix(jitter(pick(grass), 0.2), shade, clamp01(hang * 4.5) * 0.7)
    long(add(start, times(d, hang * 0.5)), d, hang * 0.46, between(0.0055, 0.008), colour, unit([out[0], -0.25, out[2]]), 0.7 - hang, {sheen: 0.4})
  }
  // The grass's underside, so the disc is closed seen from below.
  for (let i = 0; i < 2600; i++) {
    const a = random() * Math.PI * 2
    const r = Math.sqrt(random()) * rim(a) * 0.9
    flat([r * Math.cos(a), -0.03, r * Math.sin(a)], [0, -1, 0], 0.03, 0.026, 0.006, jitter(pick(earth), 0.2), 0.4)
  }

  const narrowing = (d: number) => Math.pow(Math.max(0, 1 - Math.pow(d, 1.45)), 0.78)
  const point = (a: number, d: number): Vec3 => {
    const lump = 1 + 0.07 * Math.sin(5 * a + 3 * d) + 0.05 * Math.sin(9 * a - 7 * d + 1) + 0.03 * Math.sin(17 * a + 11 * d)
    const r = rim(a) * 0.985 * narrowing(d) * lump
    return [r * Math.cos(a) + tip[0] * d, -0.02 - d * deep, r * Math.sin(a) + tip[2] * d]
  }
  // The earth, in bands, with stones in it; grass roots near the rim.
  for (let i = 0; i < 26_000; ) {
    const d = random()
    if (random() > narrowing(d) * 1.05 + 0.08) continue
    i += 1
    const a = random() * Math.PI * 2
    const at = point(a, d)
    const e = 0.01
    const along = sub(point(a + e, d), point(a - e, d))
    const down = sub(point(a, Math.min(1, d + e)), point(a, Math.max(0, d - e)))
    let facing = unit(cross(down, along))
    if (dot(facing, [at[0], 0, at[2]]) < 0 && d < 0.98) facing = times(facing, -1)
    const band = Math.sin(d * 38 + Math.sin(a * 3) * 2)
    let colour = jitter(band > 0.55 ? earth[2] : band < -0.6 ? earth[3] : pick(earth), 0.25)
    if (d < 0.08 && random() < 0.7) colour = jitter(mix(pick(grass), shade, 0.5), 0.2)
    else if (random() < 0.07) colour = jitter(pick(stone), 0.15)
    colour = times(colour, 1 - d * 0.3)
    flat(at, facing, between(0.016, 0.024), between(0.013, 0.02), 0.005, colour, 0.85 - d * 0.4)
  }
  // Roots hanging from the earth.
  for (let i = 0; i < 70; i++) {
    let at = point(random() * Math.PI * 2, between(0.12, 0.66))
    let heading: Vec3 = unit([between(-0.3, 0.3), -1, between(-0.3, 0.3)])
    const steps = 8 + Math.floor(random() * 14)
    const colour = jitter(pick(roots), 0.2)
    for (let step = 0; step < steps; step++) {
      heading = unit(add(heading, [between(-0.25, 0.25), -0.15, between(-0.25, 0.25)]))
      const next = add(at, times(heading, 0.016))
      long(mix(at, next, 0.5), heading, 0.01, 0.0045 * (1 - step / steps) + 0.0025, times(colour, 0.9 - step / (steps * 3)), unit([at[0], 0, at[2]]), 0.45)
      at = next
    }
  }
  return point
}

/** Where a moving part is: a rotation (its three columns), then a move. */
export type Pose = {readonly columns: readonly [Vec3, Vec3, Vec3]; readonly move: Vec3}

export const STILL: Pose = {columns: [[1, 0, 0], [0, 1, 0], [0, 0, 1]], move: [0, 0, 0]}

const apply = (pose: Pose, p: Vec3): Vec3 =>
  add(add(add(times(pose.columns[0], p[0]), times(pose.columns[1], p[1])), times(pose.columns[2], p[2])), pose.move)

/** Turned by `angle` round `axis` through `pivot`, then moved by `move`. */
export function turning(axis: Vec3, angle: number, pivot: Vec3, move: Vec3 = [0, 0, 0]): Pose {
  const [x, y, z] = unit(axis)
  const c = Math.cos(angle)
  const s = Math.sin(angle)
  const k = 1 - c
  // The rotation's columns (Rodrigues).
  const columns: [Vec3, Vec3, Vec3] = [
    [c + x * x * k, y * x * k + z * s, z * x * k - y * s],
    [x * y * k - z * s, c + y * y * k, z * y * k + x * s],
    [x * z * k + y * s, y * z * k - x * s, c + z * z * k],
  ]
  const turned = add(add(times(columns[0], pivot[0]), times(columns[1], pivot[1])), times(columns[2], pivot[2]))
  return {columns, move: add(sub(pivot, turned), move)}
}

/** `inner`, then `outer`: a part carried by another (a forearm by its upper arm). */
export function after(outer: Pose, inner: Pose): Pose {
  const turn = (v: Vec3) => sub(apply(outer, v), outer.move)
  return {columns: [turn(inner.columns[0]), turn(inner.columns[1]), turn(inner.columns[2])], move: apply(outer, inner.move)}
}

/** Writes a part's pose as painter.ts's `Part` reads it: three columns, then the move and an opacity. */
export function setPart(into: Float32Array, part: number, pose: Pose, opacity = 1) {
  const [a, b, c] = pose.columns
  const t = pose.move
  into.set([a[0], a[1], a[2], 0, b[0], b[1], b[2], 0, c[0], c[1], c[2], 0, t[0], t[1], t[2], opacity], part * 16)
}

/** Every part standing still. */
export function restPose(into: Float32Array, parts: number) {
  for (let p = 0; p < parts; p++) setPart(into, p, STILL)
}

/** The Regents crown: thirteen square blocks, five wide and three high, the top row only
 * at the first, middle and last places, by column and row from its middle. */
export const CROWN_BLOCKS: readonly (readonly [number, number])[] = [
  [-2, 1], [0, 1], [2, 1],
  [-2, 0], [-1, 0], [0, 0], [1, 0], [2, 0],
  [-2, -1], [-1, -1], [0, -1], [1, -1], [2, -1],
]
/** From one block's middle to the next, in blocks: a gap of 0.025 to a block of 0.22. */
export const CROWN_PITCH = 0.245 / 0.22
