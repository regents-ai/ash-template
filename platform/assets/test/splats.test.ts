/// <reference types="node" />
// The splats page's baked scenes without a GPU: each file reads back exactly as the
// studio's own decoder reads it, every splat standing where that decoder puts it at every
// frame; every kind of motion comes back to where it started at the end of the loop, and
// the moving parts with it; the splats drawn far to near are the ones that must be, and
// come out farthest first from any side; the art-pixel grid and the camera frame the
// scene as the reference pictures do, and, zoomed in, as FORMAT.md 5.1 and 5.2 say for
// the person's zoom times the stage's fit; and a GIF's frames read back in the palette's own
// colours, one loop of the scene long.
import {readFileSync} from "node:fs"
import {createRequire} from "node:module"
import {describe, expect, it} from "vitest"
import {gridFor, TILT_LIMIT, viewFrom, ZOOM_LIMIT} from "../js/splats/camera"
import {createGif, DELAY, FRAMES} from "../js/splats/gif"
import {centreAt, FALL, FLICKER, frameAt, motionOf, moved, PULSE, RISE, SWAY, type Vec3} from "../js/splats/motion"
import {createOrder} from "../js/splats/order"
import {BLOCK_NAMES, decodeScene, NO_DEPTH, restCentre} from "../js/splats/scene"

const studio = createRequire(import.meta.url)("../js/splats/studio/decode.cjs")
const fileOf = (name: string) => new URL(`../../priv/static/splats/${name}.bin`, import.meta.url)

const scenes = [
  {name: "island", splats: 294_707},
  {name: "factory", splats: 399_656},
].map(({name, splats}) => {
  const file = readFileSync(fileOf(name))
  const scene = decodeScene(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength))
  return {name, splats, scene, theirs: studio.open(fileOf(name))}
})

/** The largest gap between two lists of numbers. */
const furthest = (a: ArrayLike<number>, b: ArrayLike<number>) => {
  let most = 0
  for (let i = 0; i < a.length; i++) most = Math.max(most, Math.abs(a[i]! - b[i]!))
  return most
}

describe.each(scenes)("the $name", ({splats, scene, theirs}) => {
  const {header, blocks} = scene

  it("holds the splats and the 48 colours the page says it does", () => {
    expect(header.splats).toBe(splats)
    expect(header.colours).toBe(48)
    expect(blocks.palette).toHaveLength(48)
  })

  it("reads the header and every block exactly as the studio's decoder does", () => {
    expect({...header}).toEqual(theirs.h)
    expect(BLOCK_NAMES).toEqual(Object.keys(theirs.A))
    const bytesOf = (block: ArrayBufferView) => Buffer.from(block.buffer, block.byteOffset, block.byteLength)
    for (const name of BLOCK_NAMES) expect(Buffer.compare(bytesOf(blocks[name]), bytesOf(theirs.A[name])), name).toBe(0)
  })

  it("puts every splat at rest where the studio's decoder does", () => {
    const centres = new Float64Array(header.splats * 3)
    const theirCentres = new Float64Array(header.splats * 3)
    for (let n = 0; n < header.splats; n++) {
      centres.set(restCentre(scene, n), n * 3)
      theirCentres.set(theirs.rest.subarray(n * 16, n * 16 + 3), n * 3)
    }
    expect(furthest(centres, theirCentres)).toBeLessThan(1e-5)
  })

  it("carries every splat its kind leaves in place where the studio's decoder does, frame by frame", () => {
    for (const frame of [0, 97, header.frames - 1]) {
      const rows = studio.rowsAt(theirs, frame) as Float32Array
      const centres = new Float64Array((header.splats - header.moving) * 3)
      const theirCentres = new Float64Array(centres.length)
      for (let n = header.moving; n < header.splats; n++) {
        centres.set(centreAt(scene, n, frame / 30), (n - header.moving) * 3)
        theirCentres.set(rows.subarray(n * 16, n * 16 + 3), (n - header.moving) * 3)
      }
      expect(furthest(centres, theirCentres), `frame ${frame}`).toBeLessThan(1e-4)
    }
  }, 30_000)

  it("holds each stored frame until the next, the last up to the end of the loop", () => {
    expect(header.frames).toBe(header.loop * 30)
    expect(frameAt(header, 0)).toBe(0)
    expect(frameAt(header, 1 / 30 - 1e-9)).toBe(0)
    expect(frameAt(header, 1 / 30)).toBe(1)
    expect(frameAt(header, header.loop - 1e-9)).toBe(header.frames - 1)
  })

  it("brings every moving splat back to how it started when the loop comes round", () => {
    // An art pixel's width at the camera's target, on the reference pictures' grid.
    const pixel = header.camDist / gridFor(header, 1440, 960, 1).focal
    let seam = 0
    let swaySeam = 0
    for (let n = 0; n < header.moving; n++) {
      const motion = motionOf(scene, n)
      const centre = restCentre(scene, n)
      const start = moved(motion, centre, header.clockStart, header.loop)
      const end = moved(motion, centre, header.clockStart + header.loop, header.loop)
      const [dx, dy, dz] = start.centre.map((v, k) => Math.abs(v - end.centre[k]!))
      seam = Math.max(seam, dx!, dz!, Math.abs(start.alpha - end.alpha), Math.abs(start.grow - end.grow), Math.abs(start.glow - end.glow))
      // A swaying splat's up-and-down goes 1.3 times as fast as its side to side (FORMAT.md 4), so only it may not quite close.
      if (motion.kind === SWAY) swaySeam = Math.max(swaySeam, dy!)
      else seam = Math.max(seam, dy!)
    }
    expect(seam).toBeLessThan(1e-9)
    expect(swaySeam).toBeLessThan(pixel / 2)
  })

  it("brings every moving part back from its last frame no further than it moves between any two frames", () => {
    const track = blocks.track
    const step = (part: number, from: number, to: number) => {
      const a = (from * header.parts + part) * 12
      const b = (to * header.parts + part) * 12
      return furthest(track.subarray(a, a + 12), track.subarray(b, b + 12))
    }
    for (let part = 0; part < header.parts; part++) {
      let largest = 0
      for (let f = 1; f < header.frames; f++) largest = Math.max(largest, step(part, f - 1, f))
      expect(step(part, header.frames - 1, 0), `part ${part}`).toBeLessThanOrEqual(largest + 1e-6)
    }
  })

  describe("drawn far to near", () => {
    const order = createOrder(scene)
    const sorted = order.farToNear([0, 0, 1], 0)

    it("is every splat that does not always hide what is behind it, and only those", () => {
      const fading = new Set([FLICKER, FALL, RISE, PULSE])
      const blends = (n: number) => {
        const style = blocks.style[n]!
        const code = blocks.styleCode[style]!
        return blocks.styleDensity[style]! < 1 || (code & NO_DEPTH) !== 0 || (n < header.moving && fading.has(code & 15))
      }
      const drawn = [...order.solid, ...sorted].sort((a, b) => a - b)
      expect(drawn).toEqual(Array.from({length: header.splats}, (_, n) => n))
      expect(order.solid.some(blends)).toBe(false)
      expect(sorted.every(blends)).toBe(true)
    })

    it.each([
      ["the front", header.camYaw, header.camPitch, 0],
      ["above", 1.1, TILT_LIMIT, 2.5],
      ["below", -2.4, -TILT_LIMIT, header.loop - 0.01],
    ])("comes out farthest first seen from %s, ties in file order", (_, yaw, pitch, seconds) => {
      const {back} = viewFrom(header, yaw, pitch, 1, header.camTarget)
      const ids = Array.from(order.farToNear(back, seconds))
      const depth = (n: number) => {
        const [x, y, z] = centreAt(scene, n, seconds)
        return back[0] * x + back[1] * y + back[2] * z
      }
      const expected = [...ids].sort((a, b) => depth(a) - depth(b) || a - b)
      expect(ids).toEqual(expected)
    })
  })

  describe("framed", () => {
    it("on the reference pictures' grid on a wide stage, and on a square one for phones", () => {
      expect(gridFor(header, 1440, 960, 1)).toMatchObject({zoom: 1, scale: 3, columns: 480, rows: 320})
      expect(gridFor(header, 1080, 1080, 1)).toMatchObject({scale: 3, columns: 360, rows: 360})
    })

    for (const [width, height] of [[2172, 1446], [972, 972], [716, 716], [641, 427], [100, 60]] as const) {
      it(`covers a ${width} by ${height} stage in whole art pixels, the scene still fitting across it`, () => {
        const grid = gridFor(header, width, height, 1)
        expect(Number.isInteger(grid.scale)).toBe(true)
        expect(grid.columns * grid.scale - width).toBeGreaterThanOrEqual(0)
        expect(grid.columns * grid.scale - width).toBeLessThan(grid.scale)
        expect(grid.rows * grid.scale - height).toBeGreaterThanOrEqual(0)
        expect(grid.rows * grid.scale - height).toBeLessThan(grid.scale)
        expect(grid.zoom).toBeCloseTo(Math.min(1, width / height / 1.5))
      })
    }

    it("looks at the target from the scene's distance with level, upright, square axes at any tilt", () => {
      const dot = (a: readonly number[], b: readonly number[]) => a[0]! * b[0]! + a[1]! * b[1]! + a[2]! * b[2]!
      for (const pitch of [-TILT_LIMIT, 0, header.camPitch, TILT_LIMIT]) {
        const view = viewFrom(header, 0.7, pitch, 0.8, header.camTarget)
        const offset = view.eye.map((v, k) => v - header.camTarget[k]!)
        expect(Math.hypot(...offset)).toBeCloseTo(header.camDist / 0.8)
        expect(view.right[1]).toBe(0)
        expect(view.up[1]).toBeGreaterThan(0)
        for (const [a, b] of [[view.right, view.up], [view.up, view.back], [view.back, view.right]] as const) expect(dot(a, b)).toBeCloseTo(0)
        for (const axis of [view.right, view.up, view.back]) expect(dot(axis, axis)).toBeCloseTo(1)
      }
    })

    // FORMAT.md 5.2's grid for a stage this big at the camera's zoom s.
    const formatGrid = (width: number, height: number, s: number) => {
      const span = 2 * Math.tan(header.fov / 2)
      const rho = header.detail * s ** (s > 1 ? 1 / 2 : 1 / 4)
      const q = Math.min(18, Math.max(1, Math.floor(height / (span * rho * (header.camDist / s)) + 0.5)))
      const rows = Math.ceil(height / q)
      return {zoom: s, scale: q, columns: Math.ceil(width / q), rows, focal: rows / span}
    }
    const stages = [[1440, 960], [1080, 1080], [2172, 1446], [716, 716], [641, 427]] as const

    it("at zoom 1, is the scene's own framing: the stage's fit alone, as the page had it before it zoomed", () => {
      for (const [width, height] of stages) expect(gridFor(header, width, height, 1)).toEqual(formatGrid(width, height, Math.min(1, width / height / 1.5)))
    })

    it("zoomed in, takes the person's zoom times the stage's fit as s, its art pixels growing with it", () => {
      for (const [width, height] of stages)
        for (const zoom of [Math.SQRT2, 2, 3, ZOOM_LIMIT]) expect(gridFor(header, width, height, zoom)).toEqual(formatGrid(width, height, zoom * Math.min(1, width / height / 1.5)))
      // The reference pictures' stage four times nearer: 7 screen pixels an art pixel, not 3.
      expect(gridFor(header, 1440, 960, ZOOM_LIMIT)).toMatchObject({zoom: 4, scale: 7, columns: 206, rows: 138})
      // A phone's square stage at the nearest zoom: s is 4 times its fit of 2/3.
      expect(gridFor(header, 1080, 1080, ZOOM_LIMIT)).toMatchObject({scale: 6, columns: 180, rows: 180})
      expect(gridFor(header, 1080, 1080, ZOOM_LIMIT).zoom).toBeCloseTo(8 / 3, 12)
    })

    it("zoomed in, looks at the target it is given from the scene's distance over s, its axes those of the yaw and pitch alone", () => {
      const [x, y, z] = header.camTarget
      const target = [x + 1.5, y - 0.5, z + 2] as const
      const [yaw, pitch] = [0.7, header.camPitch]
      const resting = viewFrom(header, yaw, pitch, 1, header.camTarget)
      for (const s of [Math.SQRT2, 8 / 3, ZOOM_LIMIT]) {
        const view = viewFrom(header, yaw, pitch, s, target)
        const d = header.camDist / s
        const eye = [x + 1.5 + d * Math.cos(pitch) * Math.sin(yaw), y - 0.5 + d * Math.sin(pitch), z + 2 + d * Math.cos(pitch) * Math.cos(yaw)]
        eye.forEach((v, k) => expect(view.eye[k]).toBeCloseTo(v, 12))
        expect(view.distance).toBeCloseTo(d, 12)
        expect([view.right, view.up, view.back]).toEqual([resting.right, resting.up, resting.back])
      }
    })
  })

  it("makes a GIF one loop long", () => {
    expect((FRAMES * DELAY) / 100).toBe(header.loop)
  })
})

/** GIF's LZW undone: codes of a width that grows as the table does, low bits first. */
const unpack = (minimum: number, data: number[]) => {
  const clear = 1 << minimum
  const out: number[] = []
  let table: number[][] = []
  let width = 0
  let previous: number[] | undefined
  const reset = () => {
    table = Array.from({length: clear + 2}, (_, i) => [i])
    width = minimum + 1
    previous = undefined
  }
  reset()
  for (let bit = 0; bit + width <= data.length * 8; ) {
    let code = 0
    for (let k = 0; k < width; k++, bit++) code |= ((data[bit >> 3]! >> (bit & 7)) & 1) << k
    if (code === clear) {
      reset()
      continue
    }
    if (code === clear + 1) break
    const entry = code < table.length ? table[code]! : [...previous!, previous![0]!]
    out.push(...entry)
    if (previous && table.length < 4096) table.push([...previous, entry[0]!])
    if (table.length === 1 << width && width < 12) width += 1
    previous = entry
  }
  return out
}

/** A GIF read back as a viewer shows it: its colour table, how often it loops, and each frame's colours once laid over the frame before. */
const readGif = (bytes: Uint8Array) => {
  let at = 0
  const byte = () => bytes[at++]!
  const word = () => byte() | (byte() << 8)
  const blocks = () => {
    const data: number[] = []
    for (let n = byte(); n; n = byte()) data.push(...bytes.subarray(at, (at += n)))
    return data
  }
  const signature = String.fromCharCode(...bytes.subarray(0, (at = 6)))
  const [width, height, flags] = [word(), word(), byte()]
  at += 2
  const table = Array.from({length: flags & 0x80 ? 2 << (flags & 7) : 0}, () => [byte(), byte(), byte()])
  const shown: number[][] = Array.from({length: width * height}, () => [0, 0, 0])
  // Each frame, and whether it held one index for every pixel of its rectangle.
  const frames: {delay: number; dispose: number; clear?: number; local: boolean; pixels: boolean; colours: number[][]}[] = []
  let loops: number | undefined
  let control = {delay: 0, dispose: 0, clear: undefined as number | undefined}
  for (let kind = byte(); kind !== 0x3b; kind = byte()) {
    if (kind === 0x21) {
      const label = byte()
      const data = blocks()
      if (label === 0xf9) control = {dispose: (data[0]! >> 2) & 7, delay: data[1]! | (data[2]! << 8), clear: data[0]! & 1 ? data[3] : undefined}
      if (label === 0xff && String.fromCharCode(...data.slice(0, 11)) === "NETSCAPE2.0") loops = data[12]! | (data[13]! << 8)
      continue
    }
    const [left, top, w, h, image] = [word(), word(), word(), word(), byte()]
    const local = Boolean(image & 0x80)
    const indices = unpack(byte(), blocks())
    indices.forEach((index, p) => {
      if (index !== control.clear) shown[(top + Math.floor(p / w)) * width + left + (p % w)] = table[index]!
    })
    frames.push({...control, local, pixels: indices.length === w * h, colours: [...shown]})
  }
  return {signature, width, height, table, loops, frames}
}

describe("a GIF of the scene", () => {
  const palette = Array.from(scenes[0]!.scene.blocks.palette)
  const columns = 6
  const rows = 4
  const scale = 3
  // Palette colours as the painter hands them back: four bytes a pixel.
  const bytes = (value: number) => [(value >> 16) & 255, (value >> 8) & 255, value & 255]
  const drawn = (indices: number[]) => Uint8Array.from(indices.flatMap(i => [...bytes(palette[i]!), 255]))
  const first = Array.from({length: columns * rows}, (_, p) => (p * 7 + 3) % palette.length)
  const second = first.map((i, p) => (p % 3 ? i : (i + 11) % palette.length))
  // A frame like the one before it in every pixel, and the loop's way back to its first.
  const frames = [first, second, second, first]

  const gif = createGif(palette, columns, rows, scale)
  for (const indices of frames) gif.add(drawn(indices))
  const read = readGif(gif.finish())

  it("is a GIF89a that loops for ever, each frame shown for the same time", () => {
    expect(read.signature).toBe("GIF89a")
    expect([read.width, read.height]).toEqual([columns * scale, rows * scale])
    expect(read.loops).toBe(0)
    expect(read.frames.map(f => [f.delay, f.dispose, f.local, f.pixels])).toEqual(frames.map(() => [DELAY, 1, false, true]))
  })

  it("keeps the palette as its one colour table, with one more entry for a pixel left as it was", () => {
    expect(read.table.slice(0, palette.length)).toEqual(palette.map(bytes))
    expect(read.table.length).toBeGreaterThan(palette.length)
    expect(read.frames.map(f => f.clear)).toEqual([undefined, palette.length, palette.length, palette.length])
  })

  it("shows every pixel in exactly its drawn colour, as a whole square of the scaled-up frame", () => {
    read.frames.forEach((frame, k) => {
      const expected = Array.from({length: read.width * read.height}, (_, p) => {
        const [x, y] = [p % read.width, Math.floor(p / read.width)]
        return bytes(palette[frames[k]![Math.floor(y / scale) * columns + Math.floor(x / scale)]!]!)
      })
      expect(frame.colours).toEqual(expected)
    })
  })

  it("will not take a pixel that is not one of the palette's colours", () => {
    const off = drawn(first)
    off.set([1, 2, 3], 4 * 5)
    expect(palette.map(bytes)).not.toContainEqual([1, 2, 3])
    expect(() => createGif(palette, columns, rows, scale).add(off)).toThrow()
  })
})
