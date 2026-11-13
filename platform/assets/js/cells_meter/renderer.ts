/**
 * Draws the Cells meter's moving picture with WebGPU through vgpu, on the same grid
 * as the still cells: one pass paints every cell of the bar from a row of numbers
 * per column (cells_meter/picture.ts), and the sparks are drawn over it as small
 * squares. The canvas reaches the headroom above the bar; the bar is drawn that far
 * down, and only sparks rise into the room above it.
 *
 * A run's cells twinkle: each cell is lit in the part's colour for a while, then
 * rests at a dim tint of it, each on its own slow, uneven clock, with more of the
 * bottom rows lit, and now and then one glints toward the foreground. Hot cells, a
 * counting run's leading edge, a cut edge and the sparks, are the part's colour
 * lifted toward the theme's foreground. The dim cells stay still. Each run keeps
 * the 1px edge the still meter draws round it.
 *
 * As the picture takes over, every cell is lit, exactly as the still cells are, and
 * each settles into its twinkle in its own moment.
 *
 * Loaded only once the picture is really going to be drawn; the hook
 * (hooks/cells_meter.ts) reads the page.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {draw, effect, frame, init, storage, surface, type StorageBuffer} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import {EASE_OUT} from "../hooks/motion/shared"
import {COLUMN_FLOATS, MOST_SPARKS, SPARK_FLOATS, createCellsPicture, type MeterScene} from "./picture"

export type CellsMeterRenderer = IslandRenderer & {
  /** Where each frame's scene comes from. */
  show(read: () => MeterScene): void
}

/** How far a hot cell is lifted toward the foreground. */
const HOT = 0.85
/** The longest step the picture takes between two frames, so a pause never throws it. */
const LONGEST_STEP = 1 / 30

export const cellsWgsl = /* wgsl */ `
struct View {
  // The drawing's width and height in device px, device px per CSS px, the columns in the bar.
  size: vec4f,
  // A cell's side and the gap between cells in CSS px, the rows, the clock in seconds.
  grid: vec4f,
  // The dim cells' colour already multiplied by their opacity, and that opacity.
  dim: vec4f,
  // The theme's foreground, and how much of a run's colour an unlit cell shows.
  fg: vec4f,
  // Seconds since the picture took over from the still cells, the room above the bar in CSS px, unused, unused.
  extra: vec4f,
}

// paint: the part's colour, how lit the part is (1, or less while another part is lit).
// cell: the column's place in its run, the part's seed, how hot it is, its flags (1 in a run, 2 first, 4 last).
struct Column {
  paint: vec4f,
  cell: vec4f,
}

@group(0) @binding(0) var<uniform> view: View;
@group(0) @binding(1) var<storage, read> columns: array<Column>;

// A cell is lit for a while, then rests, each on its own clock this many seconds long at least, and longer by up to this.
const PERIOD = 16.0;
const PERIOD_SPREAD = 20.0;
// Seconds a cell takes to light or dim.
const FADE = 0.8;
// The share of its clock a cell is lit: in the top rows, and in the bottom rows, where more of them gather.
const LIT_TOP = 0.3;
const LIT_BOTTOM = 0.75;
// A glint: one cell in this many per window flashes toward the foreground, for this many seconds, this far.
const GLINTS = 0.004;
const GLINT_WINDOW = 7.0;
const GLINT_TIME = 0.5;
const GLINT_LIFT = 0.6;
// Seconds over which the cells settle from all lit, as the still cells are, into their twinkle.
const SETTLE = 0.7;
const HOT = ${HOT};

fn hash(n: u32) -> f32 {
  var x = n * 747796405u + 2891336453u;
  x = ((x >> ((x >> 28u) + 4u)) ^ x) * 277803737u;
  x = (x >> 22u) ^ x;
  return f32(x) / 4294967295.0;
}

// A number from 0 to 1 that belongs to one cell of one part, so its twinkle moves with its run.
fn cellHash(seed: f32, index: f32, row: f32, salt: u32) -> f32 {
  return hash((u32(seed) * 73856093u) ^ (u32(index) * 19349663u) ^ (u32(row) * 83492791u) ^ (salt * 2654435761u));
}

// How lit a run's cell is (x) and how much it glints (y).
fn twinkle(seed: f32, index: f32, row: f32) -> vec2f {
  let clock = view.grid.w;
  let period = PERIOD + PERIOD_SPREAD * cellHash(seed, index, row, 1u);
  let u = (clock + cellHash(seed, index, row, 2u) * period) % period;
  let on = mix(LIT_TOP, LIT_BOTTOM, smoothstep(view.grid.z * 0.5, view.grid.z - 1.0, row)) * period;
  var shine = smoothstep(0.0, FADE, u) * (1.0 - smoothstep(on, on + FADE, u));
  let delay = cellHash(seed, index, row, 3u) * SETTLE;
  shine = mix(1.0, shine, smoothstep(delay, delay + 0.4, view.extra.x));

  let window = floor(clock / GLINT_WINDOW);
  var glint = 0.0;
  if (cellHash(seed, index, row, 4u + u32(window) * 2u) < GLINTS) {
    let at = cellHash(seed, index, row, 5u + u32(window) * 2u) * (GLINT_WINDOW - GLINT_TIME);
    let t = clock - window * GLINT_WINDOW - at;
    glint = max(0.0, 1.0 - abs(t / (0.5 * GLINT_TIME) - 1.0));
  }
  return vec2f(shine, glint);
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  // Where this pixel is in CSS px from the bar's top left, the room above it the headroom down.
  let p = uv * view.size.xy / view.size.z - vec2f(0.0, view.extra.y);
  let cell = view.grid.x;
  let pitch = cell + view.grid.y;
  let bar = view.grid.z * pitch - view.grid.y;
  let c = floor(p.x / pitch);
  // The room above the bar is the sparks' alone.
  if (c >= view.size.w || p.y < 0.0 || p.y >= bar) {
    return vec4f(0.0);
  }
  let dx = p.x - c * pitch;
  let r = floor(p.y / pitch);
  let inCell = dx < cell && p.y - r * pitch < cell;
  // The dim cells under everything, as the still meter's track.
  let under = select(vec4f(0.0), view.dim, inCell);

  let column = columns[u32(c)];
  let flags = u32(column.cell.w);
  if ((flags & 1u) == 0u) {
    return under;
  }
  let heat = column.cell.z;
  var colour = mix(column.paint.rgb, view.fg.rgb, heat * HOT);
  // The run's edge: four 1px strips round its box, which ends at its last cell.
  let last = (flags & 4u) != 0u;
  let edge = ((dx < cell || !last) && (p.y < 1.0 || p.y >= bar - 1.0))
    || ((flags & 2u) != 0u && dx < 1.0)
    || (last && dx >= cell - 1.0 && dx < cell);
  var a = 0.0;
  if (edge) {
    a = 1.0;
  } else if (inCell) {
    let look = twinkle(column.cell.y, column.cell.x, r);
    a = mix(view.fg.a, 1.0, max(look.x, heat));
    colour = mix(colour, view.fg.rgb, look.y * GLINT_LIFT);
  }
  a *= column.paint.w;
  return vec4f(colour * a, a) + under * (1.0 - a);
}
`

export const sparksWgsl = /* wgsl */ `
struct View {
  // The drawing's width and height in device px, device px per CSS px, the room above the bar in CSS px.
  size: vec4f,
  // The theme's foreground, unused.
  fg: vec4f,
}

// place: where it is (xy, CSS px from the bar's top left, above it when y is negative), its side in CSS px, how much of it shows.
// colour: its part's colour, how hot it still is.
struct Spark {
  place: vec4f,
  colour: vec4f,
}

@group(0) @binding(0) var<uniform> view: View;
@group(0) @binding(1) var<storage, read> sparks: array<Spark>;

struct Out {
  @builtin(position) position: vec4f,
  @location(0) colour: vec4f,
}

@vertex fn vs_main(@builtin(vertex_index) vertex: u32, @builtin(instance_index) i: u32) -> Out {
  var corners = array<vec2f, 4>(vec2f(0.0, 0.0), vec2f(1.0, 0.0), vec2f(0.0, 1.0), vec2f(1.0, 1.0));
  let s = sparks[i];
  // A square on whole device pixels, so it stays as sharp as the cells; the bar is the headroom down.
  let at = round((s.place.xy + vec2f(0.0, view.size.w)) * view.size.z);
  let pixel = at + corners[vertex] * round(s.place.z * view.size.z);
  var out: Out;
  out.position = vec4f(pixel.x / view.size.x * 2.0 - 1.0, 1.0 - pixel.y / view.size.y * 2.0, 0.0, 1.0);
  // White-hot, the foreground itself, as it breaks off; its part's colour as it cools.
  let colour = mix(s.colour.rgb, view.fg.rgb, s.colour.w);
  out.colour = vec4f(colour * s.place.w, s.place.w);
  return out;
}

@fragment fn fs_main(in: Out) -> @location(0) vec4f {
  return in.colour;
}
`

const rgba = (colour: readonly [number, number, number], a: number): [number, number, number, number] => [
  colour[0],
  colour[1],
  colour[2],
  a,
]

/** The share of a run's colour an unlit cell shows. */
const UNLIT = 0.35

export async function createCellsMeterRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<CellsMeterRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a picture still in use reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  try {
    const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "premultiplied", label: "cells-meter"})
    stage.resize([size[0], size[1]])
    // Room for a bar 256 cells across; a wider one makes room for twice as many.
    let columnStore: StorageBuffer = storage(gpu, 256 * COLUMN_FLOATS * 4, "read")
    const sparkStore = storage(gpu, MOST_SPARKS * SPARK_FLOATS * 4, "read")
    const cells = effect(gpu, prepareShader(cellsWgsl, "cells_meter.wgsl"), {
      label: "cells-meter.cells",
      set: {
        view: {size: [1, 1, 1, 0], grid: [3, 2, 10, 0], dim: [0, 0, 0, 0], fg: [1, 1, 1, UNLIT], extra: [0, 0, 0, 0]},
        columns: columnStore,
      },
    })
    const paintSparks = draw(gpu, {
      shader: prepareShader(sparksWgsl, "cells_meter_sparks.wgsl"),
      geometry: {topology: "triangle-strip"},
      vertices: 4,
      instances: MOST_SPARKS,
      blend: "premultiplied",
      depth: false,
      label: "cells-meter.sparks",
      set: {view: {size: [1, 1, 1, 0], fg: [1, 1, 1, 0]}, sparks: sparkStore},
    })
    await Promise.all([cells.compile(stage), paintSparks.compile(stage)])

    const picture = createCellsPicture(EASE_OUT)
    let read: (() => MeterScene) | undefined
    let current: MeterScene | undefined
    let clock = 0
    let settle: number | undefined
    let last: number | undefined

    return {
      show(next) {
        read = next
      },
      resize(width, height) {
        stage.resize([width, height])
      },
      step() {
        if (!read) return false
        const now = performance.now() / 1000
        const dt = last === undefined ? 0 : Math.min(now - last, LONGEST_STEP)
        last = now
        clock += dt
        current = read()
        picture.step(current, dt, settle === undefined)
        if (settle === undefined) settle = clock
        // The twinkle never rests, so there is always a next frame while the picture is wanted.
        return true
      },
      present() {
        const view = current ?? read?.()
        if (!view) return
        const ratio = stage.size[0] / Math.max(view.width, 1)
        const data = picture.columnData()
        if (columnStore.size < data.byteLength) {
          columnStore = storage(gpu, Math.max(data.byteLength, columnStore.size * 2), "read")
          cells.set({columns: columnStore})
        }
        columnStore.write(data)
        const count = picture.sparkCount()
        if (count > 0) sparkStore.write(picture.sparkData(view.grid).subarray(0, count * SPARK_FLOATS))
        const fg = view.fg
        cells.set({
          view: {
            size: [stage.size[0], stage.size[1], ratio, picture.columns()],
            grid: [view.grid.cell, view.grid.gap, view.grid.rows, clock],
            dim: rgba(view.dim, view.dimAlpha),
            fg: rgba(fg, UNLIT),
            extra: [clock - (settle ?? clock), view.headroom, 0, 0],
          },
        })
        paintSparks.set({view: {size: [stage.size[0], stage.size[1], ratio, view.headroom], fg: rgba(fg, 0)}})
        frame(gpu, f => {
          f.pass({target: stage, clear: [0, 0, 0, 0]}, pass => {
            pass.draw(cells)
            if (count > 0) pass.draw(paintSparks, {instances: count})
          })
        })
      },
      settled() {
        return gpu.settled()
      },
      dispose() {
        if (disposed) return
        disposed = true
        stage.dispose()
        gpu.dispose()
      },
    }
  } catch (error) {
    gpu.dispose()
    throw error
  }
}
