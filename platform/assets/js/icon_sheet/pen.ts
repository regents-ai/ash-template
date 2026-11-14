/**
 * What every icon on the icon sheet is drawn with: lines, circles and arcs, rectangles
 * and triangles on one unit grid, the art box running from -50 to 50 on both axes with
 * y downwards. The pen turns each mark into one shape of twenty numbers in CSS pixels
 * from the canvas's top left, for the renderer (icon_sheet/renderer.ts) to draw in a
 * single batch. Lines keep the sheet's own weight however large the box is drawn.
 */

/** The numbers one shape takes. */
export const SHAPE_FLOATS = 20

const KINDS = {line: 0, circle: 1, rect: 2, tri: 3} as const
const TONES = {ink: 0, quiet: 1, accent: 2, ground: 3} as const
const FILLS = {line: 0, solid: 1, hatch: 2} as const

export type Tone = keyof typeof TONES
export type Point = readonly [number, number]

export type Look = {
  /** Ink for lines, quiet for secondary marks, the accent once, ground to cover what is under it. */
  readonly tone?: Tone
  readonly alpha?: number
  /** The stroke, in the sheet's line weights. */
  readonly weight?: number
  /** Drawn as an outline, filled, or hatched. */
  readonly fill?: keyof typeof FILLS
  /**
   * A line's dashes as [on, off, offset]: on and off in units, the offset in whole
   * dashes. A circle's as [count, share on, offset], the offset in whole dashes.
   */
  readonly dash?: readonly [number, number, number?]
  /** A rectangle's or triangle's turn, in turns; a triangle at 0 points right. */
  readonly turn?: number
  /** Part of a circle: where it starts and how far it runs, in turns, clockwise from the right. */
  readonly arc?: readonly [number, number]
  /** Only what lies inside, or outside, this circle shows. */
  readonly clip?: {readonly x: number; readonly y: number; readonly r: number; readonly keep: "in" | "out"}
}

export type Pen = {
  line(ax: number, ay: number, bx: number, by: number, look?: Look): void
  /** A line through every point in turn. */
  path(points: readonly Point[], look?: Look): void
  /** An outline unless the look fills it. */
  circle(x: number, y: number, r: number, look?: Look): void
  /** A filled circle. */
  dot(x: number, y: number, r: number, look?: Look): void
  /** An outline unless the look fills it, by its centre and half its width and height. */
  rect(x: number, y: number, halfWidth: number, halfHeight: number, look?: Look): void
  /** A filled equilateral triangle by its centre and the distance to each corner. */
  tri(x: number, y: number, r: number, look?: Look): void
  /** An open arrowhead whose point is at x, y, pointing along `turn`. */
  head(x: number, y: number, turn: number, size: number, look?: Look): void
}

/** An icon's art box, in CSS pixels from the canvas's top left. */
export type Box = {readonly x: number; readonly y: number; readonly size: number}

export type Sheet = {
  readonly pen: Pen
  /** Starts a new frame. */
  clear(): void
  /** Points the pen at one icon's box, drawn this present (0 to 1). */
  place(box: Box, presence: number): void
  count(): number
  data(): Float32Array<ArrayBuffer>
}

export function createSheet(): Sheet {
  let data = new Float32Array(512 * SHAPE_FLOATS)
  let count = 0
  let left = 0
  let top = 0
  let scale = 1
  let hair = 1
  let pitch = 3
  let presence = 1

  const px = (u: number) => left + (u + 50) * scale
  const py = (u: number) => top + (u + 50) * scale

  const shape = (kind: number, look: Look | undefined, defaultFill: number): number => {
    const alpha = (look?.alpha ?? 1) * presence
    if (alpha <= 0.001) return -1
    if ((count + 1) * SHAPE_FLOATS > data.length) {
      const grown = new Float32Array(data.length * 2)
      grown.set(data)
      data = grown
    }
    const at = count * SHAPE_FLOATS
    count += 1
    data.fill(0, at, at + SHAPE_FLOATS)
    data[at] = kind
    data[at + 1] = TONES[look?.tone ?? "ink"]
    data[at + 2] = Math.min(alpha, 1)
    data[at + 3] = look?.fill === undefined ? defaultFill : FILLS[look.fill]
    data[at + 8] = hair * (look?.weight ?? 1)
    data[at + 11] = pitch
    const clip = look?.clip
    if (clip) {
      data[at + 16] = px(clip.x)
      data[at + 17] = py(clip.y)
      data[at + 18] = clip.r * scale
      data[at + 19] = clip.keep === "in" ? 1 : -1
    }
    return at
  }

  const pen: Pen = {
    line(ax, ay, bx, by, look) {
      const at = shape(KINDS.line, look, FILLS.line)
      if (at < 0) return
      data[at + 4] = px(ax)
      data[at + 5] = py(ay)
      data[at + 6] = px(bx)
      data[at + 7] = py(by)
      const dash = look?.dash
      if (dash) {
        data[at + 12] = dash[0] * scale
        data[at + 13] = dash[1] * scale
        data[at + 14] = dash[2] ?? 0
      }
    },
    path(points, look) {
      for (let i = 1; i < points.length; i += 1) {
        const a = points[i - 1]!
        const b = points[i]!
        pen.line(a[0], a[1], b[0], b[1], look)
      }
    },
    circle(x, y, r, look) {
      const at = shape(KINDS.circle, look, FILLS.line)
      if (at < 0) return
      data[at + 4] = px(x)
      data[at + 5] = py(y)
      data[at + 6] = r * scale
      data[at + 9] = look?.arc?.[0] ?? 0
      data[at + 10] = look?.arc?.[1] ?? 1
      const dash = look?.dash
      if (dash) {
        data[at + 12] = dash[0]
        data[at + 13] = dash[1]
        data[at + 14] = dash[2] ?? 0
      }
    },
    dot(x, y, r, look) {
      pen.circle(x, y, r, {fill: "solid", ...look})
    },
    rect(x, y, halfWidth, halfHeight, look) {
      const at = shape(KINDS.rect, look, FILLS.line)
      if (at < 0) return
      data[at + 4] = px(x)
      data[at + 5] = py(y)
      data[at + 6] = halfWidth * scale
      data[at + 7] = halfHeight * scale
      data[at + 9] = look?.turn ?? 0
    },
    tri(x, y, r, look) {
      const at = shape(KINDS.tri, look, FILLS.solid)
      if (at < 0) return
      data[at + 4] = px(x)
      data[at + 5] = py(y)
      data[at + 6] = r * scale
      data[at + 9] = look?.turn ?? 0
    },
    head(x, y, turn, size, look) {
      for (const side of [-1, 1]) {
        const a = (turn + 0.5 + side * 0.11) * Math.PI * 2
        pen.line(x, y, x + Math.cos(a) * size, y + Math.sin(a) * size, look)
      }
    },
  }

  return {
    pen,
    clear() {
      count = 0
    },
    place(box, shown) {
      left = box.x
      top = box.y
      scale = box.size / 100
      // A hairline on a small box, a little more on a large one, never soft.
      hair = Math.min(1.5, Math.max(1, box.size / 80))
      pitch = Math.max(3, box.size / 30)
      presence = shown
    },
    count: () => count,
    data: () => data.subarray(0, count * SHAPE_FLOATS),
  }
}
