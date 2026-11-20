/* Reads a baked scene file (references/format.md): the header's counts, camera and look, and a typed view onto each block. Every
   block starts on a multiple of four bytes, so the whole file goes to the graphics card as one buffer of 32-bit words and the painter
   reads each block from its place in it. */

const MAGIC = 'SPLT';
export const FRAME_RATE = 30;
export const CHUNK_SIZE = 256;

// the header after the magic, in file order: [name, 'u32' or 'f64', how many]
const HEADER = [
  ['splats', 'u32', 1], ['moving', 'u32', 1], ['styles', 'u32', 1], ['motions', 'u32', 1], ['parts', 'u32', 1], ['frames', 'u32', 1],
  ['colours', 'u32', 1], ['fogIndex', 'u32', 1], ['outlineIndex', 'u32', 1],
  ['loop', 'f64', 1], ['logScaleMin', 'f64', 1], ['logScaleMax', 'f64', 1], ['camTarget', 'f64', 3], ['camDist', 'f64', 1],
  ['camPitch', 'f64', 1], ['camYaw', 'f64', 1], ['fov', 'f64', 1], ['detail', 'f64', 1], ['radius', 'f64', 1], ['fogStart', 'f64', 1],
  ['fogMax', 'f64', 1], ['outlineEdge', 'f64', 1], ['shadeStrength', 'f64', 1], ['shadeRange', 'f64', 1], ['dither', 'f64', 1],
  ['glassBend', 'f64', 1]
];

// the blocks after the header, in file order: [name, typed array, numbers per entry, entries]
const BLOCKS = [
  ['palette', Uint32Array, 1, h => h.colours],
  ['styleDensity', Float32Array, 1, h => h.styles],
  ['styleCode', Uint8Array, 1, h => h.styles],
  ['stylePart', Uint8Array, 1, h => h.styles],
  ['motionRange', Float32Array, 1, h => h.motions],
  ['motionExtra', Float32Array, 1, h => h.motions],
  ['chunkBounds', Float32Array, 6, h => Math.ceil(h.splats / CHUNK_SIZE)],
  ['position', Uint16Array, 3, h => h.splats],
  ['rotation', Uint32Array, 1, h => h.splats],
  ['scale', Uint16Array, 3, h => h.splats],
  ['colour', Uint8Array, 1, h => h.splats],
  ['style', Uint8Array, 1, h => h.splats],
  ['cycles', Int8Array, 1, h => h.moving],
  ['phase', Uint16Array, 1, h => h.moving],
  ['motion', Uint8Array, 1, h => h.moving],
  ['track', Float32Array, 12, h => h.frames * h.parts]
];

// flags in a style's code byte, above its kind of motion (code & 15)
export const NO_DEPTH = 16;
export const NO_FOG = 32;
export const GLASS = 64;

// a scene file as { header, words (the whole file as 32-bit words), at (where each block starts, in words), blocks (typed views) }
export function decodeScene(file) {
  const bytes = new Uint8Array(Math.ceil(file.byteLength / 4) * 4);
  bytes.set(new Uint8Array(file));
  if (String.fromCharCode(...bytes.subarray(0, 4)) !== MAGIC) throw new Error('not a baked splat scene');
  const data = new DataView(bytes.buffer),
    header = {},
    at = {},
    blocks = {};
  let offset = 4;
  for (const [name, type, n] of HEADER) {
    const values = Array.from({ length: n }, (_, k) => (type === 'u32' ? data.getUint32(offset + k * 4, true) : data.getFloat64(offset + k * 8, true)));
    header[name] = n === 1 ? values[0] : values;
    offset += n * (type === 'u32' ? 4 : 8);
  }
  for (const [name, Type, per, entries] of BLOCKS) {
    const length = per * entries(header);
    at[name] = offset / 4;
    blocks[name] = new Type(bytes.buffer, offset, length);
    offset += Math.ceil((length * Type.BYTES_PER_ELEMENT) / 4) * 4;
  }
  if (offset !== bytes.length) throw new Error('the scene file is not the length its header says');
  return { header, words: new Uint32Array(bytes.buffer), at, blocks };
}

export async function loadScene(url) {
  const answer = await fetch(url);
  if (!answer.ok) throw new Error('the scene file answered ' + answer.status);
  return decodeScene(await answer.arrayBuffer());
}

// splat n's centre at rest
export function restCentre({ blocks }, n) {
  const c = Math.floor(n / CHUNK_SIZE) * 6,
    box = blocks.chunkBounds;
  return [0, 1, 2].map(k => box[c + k] + ((box[c + 3 + k] - box[c + k]) * blocks.position[3 * n + k]) / 65535);
}
