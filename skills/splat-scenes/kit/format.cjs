/* The baked scene file's layout and the small codecs the baker uses. references/format.md explains every field. */

const MAGIC = 'SPLT',
  FRAME_RATE = 30, // part frames a second
  CHUNK_SIZE = 256; // splats share a position box in runs of this many, in file order

// the header after the four magic bytes, in order: [name, type, how many]
const HEADER = [
  ['splats', 'u32', 1],
  ['moving', 'u32', 1],
  ['styles', 'u32', 1],
  ['motions', 'u32', 1],
  ['parts', 'u32', 1],
  ['frames', 'u32', 1],
  ['colours', 'u32', 1],
  ['fogIndex', 'u32', 1],
  ['outlineIndex', 'u32', 1],
  ['loop', 'f64', 1],
  ['logScaleMin', 'f64', 1],
  ['logScaleMax', 'f64', 1],
  ['camTarget', 'f64', 3],
  ['camDist', 'f64', 1],
  ['camPitch', 'f64', 1],
  ['camYaw', 'f64', 1],
  ['fov', 'f64', 1],
  ['detail', 'f64', 1],
  ['radius', 'f64', 1],
  ['fogStart', 'f64', 1],
  ['fogMax', 'f64', 1],
  ['outlineEdge', 'f64', 1],
  ['shadeStrength', 'f64', 1],
  ['shadeRange', 'f64', 1],
  ['dither', 'f64', 1],
  ['glassBend', 'f64', 1]
];
const SIZE = { u32: 4, f64: 8 };

// the blocks after the header, in order: [name, typed array, numbers per entry, entries]
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

const pad4 = n => (n + 3) & ~3;
const headerBytes = () => 4 + HEADER.reduce((s, [, type, n]) => s + SIZE[type] * n, 0);

function writeHeader(dv, h) {
  let at = 4;
  for (const [name, type, n] of HEADER)
    for (let k = 0; k < n; k++, at += SIZE[type]) {
      const v = n === 1 ? h[name] : h[name][k];
      if (type === 'u32') dv.setUint32(at, v, true);
      else dv.setFloat64(at, v, true);
    }
}

function readHeader(buf) {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength),
    h = {};
  let at = 4;
  for (const [name, type, n] of HEADER) {
    const values = [];
    for (let k = 0; k < n; k++, at += SIZE[type]) values.push(type === 'u32' ? dv.getUint32(at, true) : dv.getFloat64(at, true));
    h[name] = n === 1 ? values[0] : values;
  }
  return h;
}

// where each block starts and how long it is; the last entry is where the file ends
function layout(h) {
  let at = headerBytes();
  return BLOCKS.map(([name, T, per, count]) => {
    const block = { name, T, at, length: per * count(h) };
    at = pad4(at + block.length * T.BYTES_PER_ELEMENT);
    return block;
  }).concat([{ name: 'end', at }]);
}

// a number between lo and hi in 16 bits (where lo and hi are the same, every number is lo)
const toU16 = (v, lo, hi) => (hi > lo ? Math.round(((v - lo) / (hi - lo)) * 65535) : 0);
// a size (a standard deviation along one axis) as its logarithm between two bounds, in 16 bits
const toLogScale = (s, lo, hi) => toU16(Math.log(s), lo, hi);

// the kinds of motion the file carries, and those whose phase is a fraction of a cycle (every other kind's phase is an angle)
const KINDS = new Set([0, 1, 2, 3, 4, 5, 6, 7, 11]);
const FRACTION_KINDS = new Set([2, 3]);
// a kind's speed for a whole number of cycles a loop: fraction kinds cover their range once a cycle
const speed = (kind, cycles, range, loop) => (FRACTION_KINDS.has(kind) ? (range * cycles) / loop : (cycles * 2 * Math.PI) / loop);
// a phase in 16 bits, as the part of a cycle it is
const toPhase = (kind, ph) => {
  const turn = FRACTION_KINDS.has(kind) ? ph : ph / (2 * Math.PI);
  return Math.round((turn - Math.floor(turn)) * 65536) % 65536;
};

/* a unit quaternion (x, y, z, w) in 32 bits: the largest part is left out (made positive by flipping the whole quaternion, the same
   turn) and its place goes in the top two bits; the other three, each within plus or minus 1/sqrt 2, take ten bits apiece */
function packRotation(q) {
  let big = 0;
  for (let i = 1; i < 4; i++) if (Math.abs(q[i]) > Math.abs(q[big])) big = i;
  const s = q[big] < 0 ? -1 : 1;
  let bits = big;
  for (let i = 0; i < 4; i++) {
    if (i === big) continue;
    const v = Math.round(((q[i] * s * Math.SQRT2 + 1) / 2) * 1023);
    bits = bits * 1024 + Math.min(1023, Math.max(0, v));
  }
  return bits >>> 0;
}

// a style's code byte from the toolkit's kind-and-flags number: kind in the low four bits, then no-depth, no-fog, glass
const NO_DEPTH = 16,
  NO_FOG = 32,
  GLASS = 64;
const codeFromKraw = kraw => (kraw & 15) | (kraw & 16 ? NO_DEPTH : 0) | (kraw & 32 ? NO_FOG : 0) | (kraw & 256 ? GLASS : 0);
const KRAW_KNOWN = 15 | 16 | 32 | 256;

// a colour as the toolkit packs it into a splat's row (red + green * 256 + blue * 65536), from 0xRRGGBB
const packedColour = hex => ((hex >> 16) & 255) + (hex & 0xff00) + ((hex & 255) << 16);

// the file's order of the toolkit's splats: those that move by their kind first, then the rest, each group in the toolkit's order
function fileOrder(rows, count) {
  const moving = i => Math.round(rows[i * 16 + 11]) % 16 !== 0,
    all = [...Array(count).keys()];
  return all.filter(moving).concat(all.filter(i => !moving(i)));
}

module.exports = {
  MAGIC,
  FRAME_RATE,
  CHUNK_SIZE,
  layout,
  writeHeader,
  readHeader,
  toU16,
  toLogScale,
  KINDS,
  FRACTION_KINDS,
  speed,
  toPhase,
  packRotation,
  codeFromKraw,
  KRAW_KNOWN,
  packedColour,
  fileOrder
};
