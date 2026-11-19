/**
 * A baked splat scene (`priv/static/splats/<scene>.bin`), read as studio/FORMAT.md lays
 * it out: the header's counts, camera and look, and a typed view onto each block. Every
 * block starts on a multiple of four bytes, so the whole file goes to the graphics card
 * as one buffer of 32-bit words and the painter (painter.ts) reads each block from its
 * place in it; the views here are for the few things worked out on the processor (the
 * order of the splats drawn far to near, order.ts).
 *
 * Shared by the page, the GIF and the stills script, so it imports nothing.
 */

/** The four bytes every scene file starts with. */
const MAGIC = "RSPL"

/** Stored part matrices and cloth frames a second. */
export const FRAME_RATE = 30

/** Header fields in file order: a name, and how many 32-bit whole numbers or 64-bit floats it holds. */
const COUNTS = [
  "version", "splats", "moving", "styles", "motions", "parts", "frames", "cloth", "clothFirst",
  "colours", "chunkSize", "fogIndex", "outlineIndex", "backdropIndex",
] as const
const FLOATS = [
  ["loop", 1], ["clockStart", 1], ["logScaleMin", 1], ["logScaleMax", 1], ["clothMin", 3], ["clothMax", 3],
  ["clothRadius", 1], ["clothThickness", 1], ["camTarget", 3], ["camDist", 1], ["camPitch", 1], ["camYaw", 1],
  ["fov", 1], ["detail", 1], ["radius", 1], ["fogStart", 1], ["fogMax", 1], ["outlineEdge", 1],
  ["shadeStrength", 1], ["shadeRange", 1], ["dither", 1], ["glassBend", 1],
] as const

type Vec3 = readonly [number, number, number]
type Ones = Extract<(typeof FLOATS)[number], readonly [string, 1]>[0]
type Threes = Extract<(typeof FLOATS)[number], readonly [string, 3]>[0]

export type Header = {readonly [K in (typeof COUNTS)[number]]: number} & {readonly [K in Ones]: number} & {readonly [K in Threes]: Vec3}

type Typed = typeof Uint8Array | typeof Int8Array | typeof Uint16Array | typeof Uint32Array | typeof Float32Array

/** The blocks after the header, in file order: element type, numbers an entry, and how many entries. */
const BLOCKS = {
  palette: [Uint32Array, 1, h => h.colours],
  styleDensity: [Float32Array, 1, h => h.styles],
  styleCode: [Uint8Array, 1, h => h.styles],
  stylePart: [Uint8Array, 1, h => h.styles],
  motionRange: [Float32Array, 1, h => h.motions],
  motionExtra: [Float32Array, 1, h => h.motions],
  chunkBounds: [Float32Array, 6, h => Math.ceil(h.splats / h.chunkSize)],
  position: [Uint16Array, 3, h => h.splats],
  rotation: [Uint32Array, 1, h => h.splats],
  scale: [Uint16Array, 3, h => h.splats],
  colour: [Uint8Array, 1, h => h.splats],
  style: [Uint8Array, 1, h => h.splats],
  cycles: [Int8Array, 1, h => h.moving],
  phase: [Uint16Array, 1, h => h.moving],
  motion: [Uint8Array, 1, h => h.moving],
  track: [Float32Array, 12, h => h.frames * h.parts],
  clothPosition: [Uint16Array, 3, h => h.frames * h.cloth],
  clothNormal: [Uint8Array, 2, h => h.frames * h.cloth],
  clothColour: [Uint8Array, 1, h => h.frames * h.cloth],
} as const satisfies Record<string, readonly [Typed, number, (h: Header) => number]>

export type BlockName = keyof typeof BLOCKS
export const BLOCK_NAMES = Object.keys(BLOCKS) as BlockName[]
type Blocks = {readonly [K in BlockName]: InstanceType<(typeof BLOCKS)[K][0]>}

export type Scene = {
  readonly header: Header
  /** The whole file, its length a whole number of 32-bit words. */
  readonly words: Uint32Array<ArrayBuffer>
  /** Where each block starts, in 32-bit words from the file's start. */
  readonly at: {readonly [K in BlockName]: number}
  readonly blocks: Blocks
}

/** Flags in a style's code byte, above its kind of motion (code & 15). */
export const NO_DEPTH = 16
export const NO_FOG = 32
export const GLASS = 64

/** Reads a scene file: its header, and where each block is in it. */
export function decodeScene(file: ArrayBuffer): Scene {
  // A copy whose length is a whole number of words, so the graphics card takes it as it is.
  const bytes = new Uint8Array(Math.ceil(file.byteLength / 4) * 4)
  bytes.set(new Uint8Array(file))
  if (String.fromCharCode(...bytes.subarray(0, 4)) !== MAGIC) throw new Error("Not a baked splat scene")
  const data = new DataView(bytes.buffer)
  let offset = 4
  const header: Record<string, number | number[]> = {}
  for (const name of COUNTS) {
    header[name] = data.getUint32(offset, true)
    offset += 4
  }
  for (const [name, size] of FLOATS) {
    const values = Array.from({length: size}, (_, k) => data.getFloat64(offset + k * 8, true))
    header[name] = size === 1 ? values[0]! : values
    offset += size * 8
  }
  const h = header as unknown as Header
  const at: Record<string, number> = {}
  const blocks: Record<string, ArrayBufferView> = {}
  for (const name of BLOCK_NAMES) {
    const [Type, per, entries] = BLOCKS[name]
    const length = per * entries(h)
    at[name] = offset / 4
    blocks[name] = new Type(bytes.buffer, offset, length)
    offset += Math.ceil((length * Type.BYTES_PER_ELEMENT) / 4) * 4
  }
  if (offset > bytes.length) throw new Error("The scene file is shorter than its header says")
  return {header: h, words: new Uint32Array(bytes.buffer), at: at as Scene["at"], blocks: blocks as unknown as Blocks}
}

/** Fetches and reads a scene file. */
export async function loadScene(url: string, signal?: AbortSignal): Promise<Scene> {
  const answer = await fetch(url, {signal})
  if (!answer.ok) throw new Error(`The scene file answered ${answer.status}`)
  return decodeScene(await answer.arrayBuffer())
}

/** A palette entry as red, green and blue from 0 to 1. */
export const rgb = (value: number): Vec3 => [((value >> 16) & 255) / 255, ((value >> 8) & 255) / 255, (value & 255) / 255]

/** Splat n's centre at rest (FORMAT.md 2.1). */
export function restCentre({header, blocks}: Scene, n: number): [number, number, number] {
  const c = Math.floor(n / header.chunkSize) * 6
  const box = blocks.chunkBounds
  return [0, 1, 2].map(k => box[c + k]! + ((box[c + 3 + k]! - box[c + k]!) * blocks.position[3 * n + k]!) / 65535) as [number, number, number]
}

/** Cloth dab j's centre at frame f (FORMAT.md 3.2). */
export function clothCentre({header, blocks}: Scene, j: number, f: number): [number, number, number] {
  const k = f * header.cloth + j
  return [0, 1, 2].map(i => header.clothMin[i]! + ((header.clothMax[i]! - header.clothMin[i]!) * blocks.clothPosition[3 * k + i]!) / 65535) as [number, number, number]
}
