/* The baked scene file's layout, and the small codecs the baker and the decoder share. references/format.md explains every field. */

const MAGIC = 'RSPL',
  VERSION = 1,
  FRAME_RATE = 30; // track frames a second

/* the header, after the four magic bytes, in order: [name, type, how many]. Counts and palette places are 32-bit whole numbers, every
   other number a 64-bit float (the header is small, and so nothing in it is rounded on the way into the file). */
const HEADER = [
  ['version', 'u32', 1],
  ['splats', 'u32', 1],
  ['moving', 'u32', 1],
  ['styles', 'u32', 1],
  ['motions', 'u32', 1],
  ['parts', 'u32', 1],
  ['frames', 'u32', 1],
  ['cloth', 'u32', 1],
  ['clothFirst', 'u32', 1],
  ['colours', 'u32', 1],
  ['chunkSize', 'u32', 1],
  ['fogIndex', 'u32', 1],
  ['outlineIndex', 'u32', 1],
  ['backdropIndex', 'u32', 1],
  ['loop', 'f64', 1],
  ['clockStart', 'f64', 1],
  ['logScaleMin', 'f64', 1],
  ['logScaleMax', 'f64', 1],
  ['clothMin', 'f64', 3],
  ['clothMax', 'f64', 3],
  ['clothRadius', 'f64', 1],
  ['clothThickness', 'f64', 1],
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

// the tables and arrays after the header, in order: [name, typed array, numbers per entry, entries (from the header)]
const BLOCKS = [
  ['palette', Uint32Array, 1, h => h.colours],
  ['styleDensity', Float32Array, 1, h => h.styles],
  ['styleCode', Uint8Array, 1, h => h.styles],
  ['stylePart', Uint8Array, 1, h => h.styles],
  ['motionRange', Float32Array, 1, h => h.motions],
  ['motionExtra', Float32Array, 1, h => h.motions],
  ['chunkBounds', Float32Array, 6, h => chunks(h)],
  ['position', Uint16Array, 3, h => h.splats],
  ['rotation', Uint32Array, 1, h => h.splats],
  ['scale', Uint16Array, 3, h => h.splats],
  ['colour', Uint8Array, 1, h => h.splats],
  ['style', Uint8Array, 1, h => h.splats],
  ['cycles', Int8Array, 1, h => h.moving],
  ['phase', Uint16Array, 1, h => h.moving],
  ['motion', Uint8Array, 1, h => h.moving],
  ['track', Float32Array, 12, h => h.frames * h.parts],
  ['clothPosition', Uint16Array, 3, h => h.frames * h.cloth],
  ['clothNormal', Uint8Array, 2, h => h.frames * h.cloth],
  ['clothColour', Uint8Array, 1, h => h.frames * h.cloth]
];

// splats are placed within the box of their run of chunkSize splats (in file order): how many runs a file has
const CHUNK_SIZE = 256;
const chunks = h => Math.ceil(h.splats / h.chunkSize);

const pad4 = n => (n + 3) & ~3;
const headerBytes = () => 4 + HEADER.reduce((s, [, type, n]) => s + SIZE[type] * n, 0);

// the header written into a file's first bytes (after the magic), and read back
function writeHeader(dv, h) {
  let at = 4;
  for (const [name, type, n] of HEADER)
    for (let k = 0; k < n; k++, at += SIZE[type]) {
      const v = n === 1 ? h[name] : h[name][k];
      if (type === 'u32') dv.setUint32(at, v, true);
      else dv.setFloat64(at, v, true);
    }
}
function readHeader(dv) {
  const h = {};
  let at = 4;
  for (const [name, type, n] of HEADER) {
    const v = [];
    for (let k = 0; k < n; k++, at += SIZE[type]) v.push(type === 'u32' ? dv.getUint32(at, true) : dv.getFloat64(at, true));
    h[name] = n === 1 ? v[0] : v;
  }
  return h;
}

// where each block starts and how long it is, from the header's counts
function layout(h) {
  let at = headerBytes();
  return BLOCKS.map(([name, T, per, count]) => {
    const length = per * count(h),
      block = { name, T, per, at, length };
    at = pad4(at + length * T.BYTES_PER_ELEMENT);
    return block;
  }).concat([{ name: 'end', at }]);
}

// a number between lo and hi in 16 bits, and back (where lo and hi are the same, every number is lo)
const toU16 = (v, lo, hi) => (hi > lo ? Math.round(((v - lo) / (hi - lo)) * 65535) : 0);
const fromU16 = (q, lo, hi) => lo + ((hi - lo) * q) / 65535;

// a size (a standard deviation along one axis) as its logarithm between two bounds, in 16 bits, and back
const toLogScale = (s, lo, hi) => toU16(Math.log(s), lo, hi);
const fromLogScale = (q, lo, hi) => Math.exp(fromU16(q, lo, hi));

// the kinds of motion the format carries (FORMAT.md gives each one's maths)
const KINDS = new Set([0, 1, 2, 3, 4, 5, 6, 7, 11]);

// the kinds whose phase is a fraction of a cycle (it is added to a count of cycles); every other kind's phase is an angle
const FRACTION_KINDS = new Set([2, 3]);

// a kind's speed from its whole number of cycles in a loop: fraction kinds cover their range once a cycle
const speed = (kind, cycles, range, loop) => (FRACTION_KINDS.has(kind) ? (range * cycles) / loop : (cycles * 2 * Math.PI) / loop);

// a phase in 16 bits as the part of a turn it is (a fraction kind's phase is already a part of a cycle, in 0 to 1), and back
const toPhase = (kind, ph) => {
  const turn = FRACTION_KINDS.has(kind) ? ph : ph / (2 * Math.PI);
  return Math.round((turn - Math.floor(turn)) * 65536) % 65536;
};
const fromPhase = (kind, q) => (FRACTION_KINDS.has(kind) ? q / 65536 : (2 * Math.PI * q) / 65536);

/* rotation: a unit quaternion (x, y, z, w) in 32 bits. The largest part is left out (it is worked out from the other three, made
   positive by flipping the whole quaternion, which is the same turn); its place goes in the top two bits, and the other three, each
   within plus or minus 1/sqrt 2, in ten bits apiece. */
const S2 = Math.SQRT2;
function packRotation(q) {
  let big = 0;
  for (let i = 1; i < 4; i++) if (Math.abs(q[i]) > Math.abs(q[big])) big = i;
  const s = q[big] < 0 ? -1 : 1;
  let bits = big;
  for (let i = 0; i < 4; i++) {
    if (i === big) continue;
    const v = Math.round(((q[i] * s * S2 + 1) / 2) * 1023);
    bits = bits * 1024 + Math.min(1023, Math.max(0, v));
  }
  return bits >>> 0;
}
function unpackRotation(bits) {
  const big = bits >>> 30,
    q = [0, 0, 0, 0];
  let sum = 0,
    shift = 20;
  for (let i = 0; i < 4; i++) {
    if (i === big) continue;
    const v = ((((bits >>> shift) & 1023) / 1023) * 2 - 1) / S2;
    q[i] = v;
    sum += v * v;
    shift -= 10;
  }
  q[big] = Math.sqrt(Math.max(0, 1 - sum));
  return q;
}

// the turn a unit quaternion (x, y, z, w) makes, as a 3x3 matrix by rows
function rotationMatrix([x, y, z, w]) {
  return [
    1 - 2 * (y * y + z * z),
    2 * (x * y - z * w),
    2 * (x * z + y * w),
    2 * (x * y + z * w),
    1 - 2 * (x * x + z * z),
    2 * (y * z - x * w),
    2 * (x * z - y * w),
    2 * (y * z + x * w),
    1 - 2 * (x * x + y * y)
  ];
}

// a covariance (c00 c01 c02 c11 c12 c22) from a turn and three sizes: R diag(s^2) R^T
function covariance(q, s) {
  const m = rotationMatrix(q),
    a = s[0] * s[0],
    b = s[1] * s[1],
    c = s[2] * s[2],
    e = (i, j) => m[i * 3] * m[j * 3] * a + m[i * 3 + 1] * m[j * 3 + 1] * b + m[i * 3 + 2] * m[j * 3 + 2] * c;
  return [e(0, 0), e(0, 1), e(0, 2), e(1, 1), e(1, 2), e(2, 2)];
}

// a cloth dab's covariance: a disc of the given radius and thickness facing n
function discCovariance(n, radius, thickness) {
  const p = radius * radius,
    d = thickness * thickness - p;
  return [p + d * n[0] * n[0], d * n[0] * n[1], d * n[0] * n[2], p + d * n[1] * n[1], d * n[1] * n[2], p + d * n[2] * n[2]];
}

/* a direction in two bytes: folded onto an octahedron and opened out flat into a square, each axis of the square in 8 bits */
function packNormal(n) {
  const l = Math.abs(n[0]) + Math.abs(n[1]) + Math.abs(n[2]);
  let u = n[0] / l,
    v = n[1] / l;
  if (n[2] < 0) [u, v] = [(1 - Math.abs(v)) * (u < 0 ? -1 : 1), (1 - Math.abs(u)) * (v < 0 ? -1 : 1)];
  return [Math.round(((u + 1) / 2) * 255), Math.round(((v + 1) / 2) * 255)];
}
function unpackNormal(a, b) {
  let u = (a / 255) * 2 - 1,
    v = (b / 255) * 2 - 1;
  const z = 1 - Math.abs(u) - Math.abs(v);
  if (z < 0) [u, v] = [(1 - Math.abs(v)) * (u < 0 ? -1 : 1), (1 - Math.abs(u)) * (v < 0 ? -1 : 1)];
  const l = Math.hypot(u, v, z);
  return [u / l, v / l, z / l];
}

// the toolkit's kind-and-flags number from our code byte, and back: kind in the low four bits, then no-depth, no-fog, glass
const NO_DEPTH = 16,
  NO_FOG = 32,
  GLASS = 64;
const codeFromKraw = kraw => (kraw & 15) | (kraw & 16 ? NO_DEPTH : 0) | (kraw & 32 ? NO_FOG : 0) | (kraw & 256 ? GLASS : 0);
const krawFromCode = code => (code & 15) + (code & NO_DEPTH ? 16 : 0) + (code & NO_FOG ? 32 : 0) + (code & GLASS ? 256 : 0);
const KRAW_KNOWN = 15 | 16 | 32 | 256;

// a colour as the toolkit packs it into a splat's row (red + green * 256 + blue * 65536), from 0xRRGGBB
const packedColour = hex => ((hex >> 16) & 255) + (hex & 0xff00) + ((hex & 255) << 16);

/* the file's order of a toolkit stage's splats (its rows, 16 numbers each): those that move by their kind first, then the rest, each
   group in the toolkit's own order. The n-th splat of the file is the toolkit's splat order[n]. */
function fileOrder(rows, count) {
  const moving = i => Math.round(rows[i * 16 + 11]) % 16 !== 0,
    all = [...Array(count).keys()];
  return all.filter(moving).concat(all.filter(i => !moving(i)));
}

module.exports = {
  MAGIC,
  VERSION,
  FRAME_RATE,
  HEADER,
  BLOCKS,
  CHUNK_SIZE,
  chunks,
  layout,
  headerBytes,
  writeHeader,
  readHeader,
  toU16,
  fromU16,
  toLogScale,
  fromLogScale,
  KINDS,
  FRACTION_KINDS,
  speed,
  toPhase,
  fromPhase,
  packRotation,
  unpackRotation,
  rotationMatrix,
  covariance,
  discCovariance,
  packNormal,
  unpackNormal,
  codeFromKraw,
  krawFromCode,
  KRAW_KNOWN,
  packedColour,
  fileOrder
};
