/**
 * Draws the icon sheet with WebGPU through vgpu: every mark of every icon is one
 * instance of a single draw, a small quad round the mark whose pixels are covered by
 * its exact distance, so thin lines stay crisp at any screen density. The pen
 * (icon_sheet/pen.ts) packs the marks; this module only keeps the clock, eases how
 * present each icon is, and hands the batch to the GPU.
 *
 * Each icon runs its own loop, started at its own point, so the sheet never moves in
 * unison. With less motion asked for, each icon holds its chosen still frame and a
 * frame is drawn only when something changes. Loaded only once the picture is really
 * going to be drawn; the hook (hooks/icon_sheet.ts) reads the page.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {draw, frame, init, storage, surface, type StorageBuffer} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import type {Rgb} from "../token_colour"
import {ICONS} from "./icons"
import {fract} from "./loop"
import {SHAPE_FLOATS, createSheet, type Box} from "./pen"

export type IconCell = Box & {readonly id: string}

export type SheetScene = {
  /** The canvas's own CSS width; the drawing buffer's is this times the screen's density. */
  width: number
  cells: readonly IconCell[]
  /** The icon pointed at or focused, if any. */
  lit: string | undefined
  /** Less motion: every icon holds its still frame. */
  still: boolean
  colours: {ink: Rgb; quiet: Rgb; accent: Rgb; ground: Rgb}
}

export type IconSheetRenderer = IslandRenderer & {
  /** Where each frame's scene comes from. */
  show(read: () => SheetScene): void
}

/** How present an icon is at rest, the one pointed at, and the others while one is. */
const REST = 0.82
const LIT = 1
const QUIETED = 0.5
/** Seconds the presence takes to get most of the way to where it is going. */
const PRESENCE_TIME = 0.08
/** The longest step the clock takes between two frames, so a pause never throws it. */
const LONGEST_STEP = 1 / 30
/** Where each icon starts in its loop: the golden ratio apart, so neighbours never agree. */
const SPREAD = 0.618034

export const iconSheetWgsl = /* wgsl */ `
struct View {
  // The drawing's width and height in device px, device px per CSS px, unused.
  size: vec4f,
  ink: vec4f,
  quiet: vec4f,
  accent: vec4f,
  ground: vec4f,
}

// head: kind (0 line, 1 circle, 2 rectangle, 3 triangle), tone (0 ink, 1 quiet, 2 accent, 3 ground), alpha,
//   fill (0 outline, 1 solid, 2 hatched).
// geo, in CSS px from the canvas's top left: a line's two ends; a circle's centre and radius; a rectangle's
//   centre and half its width and height; a triangle's centre and the distance to its corners.
// look: stroke width in CSS px; a rectangle's or triangle's turn, or where a circle's arc starts, in turns;
//   how far the arc runs, in turns; the hatching's pitch in CSS px.
// dash: a line's dash and gap in CSS px, or a circle's dash count and share on; the offset in whole dashes.
//   No dashes when the first is 0.
// clip: a circle the shape shows only inside (w = 1) or outside (w = -1) of; no clip when w is 0.
struct Shape {
  head: vec4f,
  geo: vec4f,
  look: vec4f,
  dash: vec4f,
  clip: vec4f,
}

@group(0) @binding(0) var<uniform> view: View;
@group(0) @binding(1) var<storage, read> shapes: array<Shape>;

struct Out {
  @builtin(position) position: vec4f,
  @location(0) at: vec2f,
  @location(1) @interpolate(flat) index: u32,
}

const TAU = 6.28318530718;

// The box round a shape, with room for its stroke and the soft edge.
fn bounds(s: Shape) -> vec4f {
  let kind = u32(s.head.x);
  let pad = s.look.x + 2.0;
  if (kind == 0u) {
    return vec4f(min(s.geo.xy, s.geo.zw) - pad, max(s.geo.xy, s.geo.zw) + pad);
  }
  var reach = s.geo.z;
  if (kind == 2u) {
    reach = length(s.geo.zw);
  }
  return vec4f(s.geo.xy - reach - pad, s.geo.xy + reach + pad);
}

@vertex fn vs_main(@builtin(vertex_index) vertex: u32, @builtin(instance_index) i: u32) -> Out {
  var corners = array<vec2f, 4>(vec2f(0.0, 0.0), vec2f(1.0, 0.0), vec2f(0.0, 1.0), vec2f(1.0, 1.0));
  let box = bounds(shapes[i]);
  let at = mix(box.xy, box.zw, corners[vertex]);
  let pixel = at * view.size.z;
  var out: Out;
  out.position = vec4f(pixel.x / view.size.x * 2.0 - 1.0, 1.0 - pixel.y / view.size.y * 2.0, 0.0, 1.0);
  out.at = at;
  out.index = i;
  return out;
}

// A point in a shape's own frame, turned back by the shape's turn.
fn unturn(v: vec2f, turn: f32) -> vec2f {
  let a = -turn * TAU;
  return vec2f(cos(a) * v.x - sin(a) * v.y, sin(a) * v.x + cos(a) * v.y);
}

fn sdBox(p: vec2f, half: vec2f) -> f32 {
  let q = abs(p) - half;
  return length(max(q, vec2f(0.0))) + min(max(q.x, q.y), 0.0);
}

// An equilateral triangle round the origin, one corner radius along +x (after Inigo Quilez).
fn sdTriangle(q: vec2f, radius: f32) -> f32 {
  let k = sqrt(3.0);
  let r = radius * k * 0.5;
  var p = vec2f(abs(q.y) - r, q.x + r / k);
  if (p.x + k * p.y > 0.0) {
    p = vec2f(p.x - k * p.y, -k * p.x - p.y) * 0.5;
  }
  p.x -= clamp(p.x, -2.0 * r, 0.0);
  return -length(p) * sign(p.y);
}

// How far along a dashed run is from its nearest dash: below 0 inside one.
fn dashGap(along: f32, on: f32, off: f32) -> f32 {
  let period = on + off;
  let m = along - floor(along / period) * period;
  return select(min(m - on, period - m), max(-m, m - on), m < on);
}

@fragment fn fs_main(in: Out) -> @location(0) vec4f {
  let s = shapes[in.index];
  let kind = u32(s.head.x);
  let fill = u32(s.head.w);
  let half = s.look.x * 0.5;
  var d = 0.0;
  if (kind == 0u) {
    let a = s.geo.xy;
    let run = s.geo.zw - a;
    let extent = max(length(run), 0.0001);
    let way = run / extent;
    let rel = in.at - a;
    let along = dot(rel, way);
    if (s.dash.x > 0.0) {
      // Dashes have square ends, and stop at the line's own ends.
      let across = abs(dot(rel, vec2f(-way.y, way.x))) - half;
      let offset = s.dash.z * (s.dash.x + s.dash.y);
      d = max(max(across, dashGap(along + offset, s.dash.x, s.dash.y)), max(-along, along - extent));
    } else {
      d = length(rel - way * clamp(along, 0.0, extent)) - half;
    }
  } else {
    let rel = in.at - s.geo.xy;
    var region = 0.0;
    if (kind == 1u) {
      region = length(rel) - s.geo.z;
    } else if (kind == 2u) {
      region = sdBox(unturn(rel, s.look.y), s.geo.zw);
    } else {
      region = sdTriangle(unturn(rel, s.look.y), s.geo.z);
    }
    if (fill == 0u) {
      d = abs(region) - half;
      if (kind == 1u) {
        // How far round from the arc's start, in turns, and as a length on the circle.
        let turned = fract(atan2(rel.y, rel.x) / TAU - s.look.y);
        let around = TAU * s.geo.z;
        if (s.look.z < 1.0) {
          let sweep = s.look.z;
          d = max(d, select(-min(turned, sweep - turned), min(turned - sweep, 1.0 - turned), turned > sweep) * around);
        }
        if (s.dash.x > 0.0) {
          let period = around / s.dash.x;
          let offset = s.dash.z * period;
          d = max(d, dashGap(turned * around + offset, period * s.dash.y, period * (1.0 - s.dash.y)));
        }
      }
    } else {
      d = region;
      if (fill == 2u) {
        // Hatching at forty-five degrees, fixed to the shape so it travels with it.
        let pitch = s.look.w;
        let u = (rel.x + rel.y) * 0.70710678;
        let m = u - floor(u / pitch) * pitch;
        d = max(d, abs(m - pitch * 0.5) - half);
      }
    }
  }
  if (s.clip.w != 0.0) {
    d = max(d, (length(in.at - s.clip.xy) - s.clip.z) * s.clip.w);
  }
  let cover = clamp(0.5 - d * view.size.z, 0.0, 1.0) * s.head.z;
  var tones = array<vec3f, 4>(view.ink.rgb, view.quiet.rgb, view.accent.rgb, view.ground.rgb);
  return vec4f(tones[u32(s.head.y)] * cover, cover);
}
`

const rgba = (colour: Rgb): [number, number, number, number] => [colour[0], colour[1], colour[2], 1]

export async function createIconSheetRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<IconSheetRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a picture still in use reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  try {
    const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "premultiplied", label: "icon-sheet"})
    stage.resize([size[0], size[1]])
    const sheet = createSheet()
    // Room for every mark of a full sheet; a busier one makes room for twice as many.
    let store: StorageBuffer = storage(gpu, 2048 * SHAPE_FLOATS * 4, "read")
    const marks = draw(gpu, {
      shader: prepareShader(iconSheetWgsl, "icon_sheet.wgsl"),
      geometry: {topology: "triangle-strip"},
      vertices: 4,
      instances: 1,
      blend: "premultiplied",
      depth: false,
      label: "icon-sheet.marks",
      set: {
        view: {size: [1, 1, 1, 0], ink: [1, 1, 1, 1], quiet: [1, 1, 1, 1], accent: [1, 1, 1, 1], ground: [0, 0, 0, 1]},
        shapes: store,
      },
    })
    await marks.compile(stage)

    let read: (() => SheetScene) | undefined
    let current: SheetScene | undefined
    let clock = 0
    let last: number | undefined
    const presence = new Map<string, number>()

    const target = (scene: SheetScene, id: string) => (scene.lit === undefined ? REST : scene.lit === id ? LIT : QUIETED)

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
        current = read()
        if (!current.still) clock += dt
        const k = 1 - Math.exp(-dt / PRESENCE_TIME)
        let easing = false
        for (const cell of current.cells) {
          const goal = target(current, cell.id)
          const from = presence.get(cell.id) ?? goal
          const next = Math.abs(goal - from) < 0.002 ? goal : from + (goal - from) * k
          if (next !== goal) easing = true
          presence.set(cell.id, next)
        }
        // A still sheet draws only while a change of presence is settling.
        return !current.still || easing
      },
      present() {
        const scene = current ?? read?.()
        if (!scene) return
        sheet.clear()
        for (const [index, cell] of scene.cells.entries()) {
          const icon = ICONS[cell.id]!
          sheet.place(cell, presence.get(cell.id) ?? target(scene, cell.id))
          icon.draw(sheet.pen, scene.still ? icon.still : fract(clock / icon.period + index * SPREAD))
        }
        const data = sheet.data()
        if (store.size < data.byteLength) {
          store = storage(gpu, Math.max(data.byteLength, store.size * 2), "read")
          marks.set({shapes: store})
        }
        if (data.length) store.write(data)
        const {ink, quiet, accent, ground} = scene.colours
        marks.set({
          view: {
            size: [stage.size[0], stage.size[1], stage.size[0] / Math.max(scene.width, 1), 0],
            ink: rgba(ink),
            quiet: rgba(quiet),
            accent: rgba(accent),
            ground: rgba(ground),
          },
        })
        const count = sheet.count()
        frame(gpu, f => {
          f.pass({target: stage, clear: [0, 0, 0, 0]}, pass => {
            if (count > 0) pass.draw(marks, {instances: count})
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
