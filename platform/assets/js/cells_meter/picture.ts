/**
 * What the Cells meter's moving picture holds between frames, worked out on the
 * processor and handed to the GPU as one row of numbers per column of cells and a
 * list of sparks.
 *
 * Each part's run eases from where it is shown to where the page now puts it, all
 * runs together on one curve, so a change part-way through starts from the cells on
 * screen and two runs never part or overlap. Shown edges always land on whole cells.
 * Cells a part gains when its share grows come in hot and cool into the part's
 * colour; while the total is being counted its last cell is held hot. Cells a part
 * loses when its share shrinks break off as sparks that drift up out of the bar into
 * the room above it and fade before they reach that room's top, its cut edge
 * flashes, and the runs after it close up. A part that leaves shrinks to
 * nothing the same way. A run that only moves can round to a cell more or less; that
 * cell comes and goes quietly.
 */
import type {Rgb} from "../token_colour"
import {columnsIn, runOf, type Grid} from "./layout"

/** One part as the page shows it now. */
export type Part = {key: string; start: number; share: number; colour: Rgb}

/** Everything the page says about the meter, read when it changes. */
export type MeterScene = {
  /** The bar's width in CSS pixels. */
  width: number
  /** The room above the bar in CSS pixels, from `--rg-cells-headroom`, which only sparks rise into. */
  headroom: number
  grid: Grid
  parts: Part[]
  counting: boolean
  /** The parts pointed at or focused, which the others dim for. */
  lit: ReadonlySet<string>
  /** The dim cells' colour and opacity, from `--rg-cells-dim`. */
  dim: Rgb
  dimAlpha: number
  /** The theme's foreground, which hot cells and sparks are lifted toward. */
  fg: Rgb
}

/** Floats per column handed to the GPU: colour and how lit the part is; run index, seed, heat, flags. */
export const COLUMN_FLOATS = 8
/** Floats per spark: where, how big and how much shows; its colour. */
export const SPARK_FLOATS = 8
export const MOST_SPARKS = 2048

/** Flags on a column: it is in a run, the run's first column, its last. */
export const IN_RUN = 1
export const FIRST = 2
export const LAST = 4

/** Seconds the runs take to reach where the page puts them, however far that is. */
const MOVE = 0.45
/** A part's light closer than this to where it is going is there. */
const NEAR = 0.02
/** Seconds a hot cell takes to cool to a third. */
const COOL = 0.3
/** How hot a cut edge flashes. */
const CUT_HEAT = 0.9
/** The opacity of the other parts while one is lit, as the still meter dims them, and how fast it follows, per second. */
const DIMMED = 0.3
const LIGHT_RATE = 21
/** The share of a lost column's cells that break off as sparks. */
const SPARKING = 0.6
/** Seconds a spark lasts, at least and how much longer at most. */
const SPARK_LIFE = 0.3
const SPARK_LIFE_SPREAD = 0.25
/**
 * How fast a spark rises, in headrooms a second, at least and how much faster at most:
 * the fastest, from the top row, goes out before it has risen nineteen twentieths of the room.
 */
const SPARK_RISE = 1.1
const SPARK_RISE_SPREAD = 1.5
/** How fast a spark wanders sideways, in CSS px a second. */
const SPARK_WANDER = 26
/** How quickly a spark slows as it drifts, per second. */
const SPARK_DRAG = 1.6

type Shown = {
  key: string
  seed: number
  colour: Rgb
  from: number
  length: number
  /** Where the run was when it last set off, and where it is going. */
  startFrom: number
  startLength: number
  goalFrom: number
  goalLength: number
  leaving: boolean
  /** The part's share on the page, and which way it last changed: 1 grew, -1 shrank, 0 only moved. */
  share: number
  change: number
  /** Cells in the run on screen last frame. */
  count: number
  light: number
  /** How hot each cell of the run is, by its place in the run. */
  heat: Float32Array<ArrayBuffer>
}

type Spark = {x: number; y: number; vx: number; vy: number; age: number; life: number; colour: Rgb; light: number}

/** A part's own number, so its cells twinkle the same way wherever its run moves. */
const seedOf = (key: string): number => {
  let h = 2166136261
  for (let i = 0; i < key.length; i++) h = Math.imul(h ^ key.charCodeAt(i), 16777619)
  return (h >>> 0) % 65536
}

const toward = (value: number, goal: number, k: number) => {
  const next = value + (goal - value) * k
  return Math.abs(goal - next) < NEAR ? goal : next
}

export type CellsPicture = ReturnType<typeof createCellsPicture>

/** `ease` is the curve the runs move on, from 0 to 1 over the move. */
export function createCellsPicture(ease: (progress: number) => number) {
  let shown: Shown[] = []
  // Seconds since the runs last set off.
  let since = MOVE
  let sparks: Spark[] = []
  let columns = 0
  let columnData = new Float32Array(0)
  const sparkData = new Float32Array(MOST_SPARKS * SPARK_FLOATS)

  const heatOf = (part: Shown, count: number) => {
    if (part.heat.length < count) {
      const grown = new Float32Array(Math.max(count, part.heat.length * 2))
      grown.set(part.heat)
      part.heat = grown
    }
    return part.heat
  }

  /**
   * Lines the parts on screen up with the page's: new ones open where they stand in
   * order, gone ones close. True when any run is now going somewhere new.
   */
  const follow = (scene: MeterScene, snap: boolean): boolean => {
    // Parts already shown keep their place; a new one opens, empty, after the part before it on the page.
    scene.parts.forEach((part, i) => {
      if (shown.some(other => other.key === part.key)) return
      const before = scene.parts[i - 1]
      const at = before ? shown.findIndex(other => other.key === before.key) + 1 : 0
      const opening = shown[at - 1]
      shown.splice(at, 0, {
        key: part.key,
        seed: seedOf(part.key),
        colour: part.colour,
        from: opening ? opening.from + opening.length : 0,
        length: 0,
        startFrom: 0,
        startLength: 0,
        goalFrom: 0,
        goalLength: 0,
        leaving: false,
        share: 0,
        change: 0,
        count: 0,
        light: 1,
        heat: new Float32Array(16),
      })
    })
    // Where each part belongs: its own run, or for a part that is going, nothing, where the one before it ends.
    const goals = new Map(scene.parts.map(part => [part.key, part]))
    let edge = 0
    let moved = false
    for (const part of shown) {
      const goal = goals.get(part.key)
      part.leaving = !goal
      const run = goal ? runOf(goal.start, goal.share, columns) : {from: edge, to: edge}
      if (goal) part.colour = goal.colour
      const share = goal ? goal.share : 0
      const going = run.from !== part.goalFrom || run.to - run.from !== part.goalLength
      if (going) part.change = Math.sign(share - part.share)
      part.share = share
      moved ||= going
      part.goalFrom = run.from
      part.goalLength = Math.max(0, run.to - run.from)
      edge = part.goalFrom + part.goalLength
      if (snap) {
        part.from = part.goalFrom
        part.length = part.goalLength
        part.count = part.goalLength
        part.heat.fill(0)
      }
    }
    return moved && !snap
  }

  /** A lost column's cells break off where they stand, in CSS px from the bar's top left. */
  const spark = (part: Shown, column: number, scene: MeterScene) => {
    const {grid, headroom} = scene
    const pitch = grid.cell + grid.gap
    for (let row = 0; row < grid.rows; row++) {
      if (sparks.length >= MOST_SPARKS || Math.random() > SPARKING) continue
      sparks.push({
        x: column * pitch,
        y: row * pitch,
        vx: (Math.random() - 0.5) * SPARK_WANDER,
        vy: -headroom * (SPARK_RISE + Math.random() * SPARK_RISE_SPREAD),
        age: 0,
        life: SPARK_LIFE + Math.random() * SPARK_LIFE_SPREAD,
        colour: part.colour,
        light: part.light,
      })
    }
  }

  return {
    /**
     * Moves the picture on by `dt` seconds toward `scene`. With `snap` every run is put
     * where it belongs at once, as on the first frame and when the bar changes width,
     * which is no change to explain.
     */
    step(scene: MeterScene, dt: number, snap: boolean) {
      const across = columnsIn(scene.width, scene.grid)
      snap ||= across !== columns
      columns = across
      if (follow(scene, snap)) {
        // Every run sets off afresh from where it is shown, together.
        since = 0
        for (const part of shown) {
          part.startFrom = part.from
          part.startLength = part.length
        }
      }
      since = snap ? MOVE : since + dt
      const along = since >= MOVE ? 1 : ease(since / MOVE)
      const cool = Math.exp(-dt / COOL)
      const lighten = 1 - Math.exp(-LIGHT_RATE * dt)
      for (const part of shown) {
        part.from = part.startFrom + (part.goalFrom - part.startFrom) * along
        part.length = part.startLength + (part.goalLength - part.startLength) * along
        part.light = toward(part.light, scene.lit.size === 0 || scene.lit.has(part.key) ? 1 : DIMMED, lighten)
        // A run keeps its own width while it slides, so it grows or loses cells only when it
        // really changes size, never from the rounding of a run on the move.
        const from = Math.round(part.from)
        const count = Math.max(0, Math.min(columns - from, Math.round(part.length)))
        const heat = heatOf(part, count)
        for (let i = 0; i < count; i++) heat[i]! *= cool
        if (count > part.count) heat.fill(part.change > 0 ? 1 : 0, part.count, count)
        if (count < part.count) {
          heat.fill(0, count, part.count)
          if (part.change < 0) {
            for (let i = count; i < part.count; i++) spark(part, from + i, scene)
            if (count > 0) heat[count - 1] = Math.max(heat[count - 1]!, CUT_HEAT)
          }
        }
        part.count = count
      }
      shown = shown.filter(part => !part.leaving || part.length > 0)

      // While the total is being counted, its leading edge is held hot.
      if (scene.counting) {
        const head = shown.filter(part => !part.leaving && part.count > 0).at(-1)
        if (head) head.heat[head.count - 1] = 1
      }

      for (const s of sparks) {
        s.age += dt
        const drag = Math.exp(-SPARK_DRAG * dt)
        s.vx *= drag
        s.vy *= drag
        s.x += s.vx * dt
        s.y += s.vy * dt
      }
      sparks = sparks.filter(s => s.age < s.life)
    },

    columns: () => columns,

    /** One row per column of the bar, for the GPU. */
    columnData(): Float32Array<ArrayBuffer> {
      const size = Math.max(1, columns) * COLUMN_FLOATS
      if (columnData.length !== size) columnData = new Float32Array(size)
      columnData.fill(0)
      for (const part of shown) {
        const from = Math.round(part.from)
        for (let i = 0; i < part.count; i++) {
          const o = (from + i) * COLUMN_FLOATS
          if (o < 0 || o >= size) continue
          columnData[o] = part.colour[0]
          columnData[o + 1] = part.colour[1]
          columnData[o + 2] = part.colour[2]
          columnData[o + 3] = part.light
          columnData[o + 4] = i
          columnData[o + 5] = part.seed
          columnData[o + 6] = part.heat[i]!
          columnData[o + 7] = IN_RUN | (i === 0 ? FIRST : 0) | (i === part.count - 1 ? LAST : 0)
        }
      }
      return columnData
    },

    sparkCount: () => sparks.length,

    /**
     * The sparks, for the GPU: each one's place (CSS px from the bar's top left, above
     * it when negative), size and how much shows, then its colour.
     */
    sparkData(grid: Grid): Float32Array<ArrayBuffer> {
      sparks.forEach((s, i) => {
        const t = s.age / s.life
        const o = i * SPARK_FLOATS
        sparkData[o] = s.x
        sparkData[o + 1] = s.y
        // A spark breaks smaller as it goes.
        sparkData[o + 2] = t < 0.5 ? grid.cell : Math.max(1, grid.cell - 1)
        sparkData[o + 3] = (1 - t) ** 1.5 * s.light
        sparkData[o + 4] = s.colour[0]
        sparkData[o + 5] = s.colour[1]
        sparkData[o + 6] = s.colour[2]
        // How hot it still is: white-hot as it breaks off, its own colour as it fades.
        sparkData[o + 7] = 1 - t
      })
      return sparkData
    },
  }
}
