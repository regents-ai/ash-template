/* Reads a baked scene file back into the toolkit's own shape: one row of 16 numbers a splat, at any frame of the loop, with the camera
   and the look beside them. It needs nothing from the toolkit, and is how verify.cjs proves a file draws what the toolkit drew and how
   stills.cjs and gif.cjs draw the file. references/format.md describes the file. */
const fs = require('node:fs');
const F = require('./format.cjs');

// a file's header and a view onto each of its blocks
function open(file) {
  const bytes = new Uint8Array(fs.readFileSync(file)), // (a copy of its own, so every block starts where the layout says)
    magic = String.fromCharCode(...bytes.subarray(0, 4));
  if (magic !== F.MAGIC) throw new Error(file + ' is not a baked scene file');
  const h = F.readHeader(new DataView(bytes.buffer)),
    blocks = F.layout(h).slice(0, -1),
    A = Object.fromEntries(blocks.map(b => [b.name, new b.T(bytes.buffer, b.at, b.length)]));
  return { h, A, rest: restRows(h, A) };
}

// every splat at rest, as toolkit rows (a cloth dab at its place in the first frame)
function restRows(h, A) {
  const D = new Float32Array(h.splats * 16);
  for (let n = 0; n < h.splats; n++) {
    const o = n * 16,
      st = A.style[n],
      code = A.styleCode[st],
      kind = code & 15,
      s = [0, 1, 2].map(k => F.fromLogScale(A.scale[n * 3 + k], h.logScaleMin, h.logScaleMax)),
      c = F.covariance(F.unpackRotation(A.rotation[n]), s),
      cb = Math.floor(n / h.chunkSize) * 6;
    for (let k = 0; k < 3; k++) D[o + k] = F.fromU16(A.position[n * 3 + k], A.chunkBounds[cb + k], A.chunkBounds[cb + 3 + k]);
    D[o + 3] = A.styleDensity[st];
    [D[o + 4], D[o + 5], D[o + 6], D[o + 8], D[o + 9], D[o + 10]] = c;
    D[o + 7] = F.packedColour(A.palette[A.colour[n]]);
    D[o + 11] = F.krawFromCode(code);
    if (n < h.moving) {
      const m = A.motion[n];
      D[o + 12] = F.fromPhase(kind, A.phase[n]);
      D[o + 13] = F.speed(kind, A.cycles[n], A.motionRange[m], h.loop);
      D[o + 14] = A.motionRange[m];
      D[o + 15] = A.motionExtra[m];
    }
  }
  return D;
}

/* the rows at one frame: a splat on a moving part is carried by that part's matrix for the frame (x' = A x + t, and its shape
   A C A^T), a cloth dab takes its row for the frame, and every other splat stays at rest */
function rowsAt({ h, A, rest }, frame) {
  const D = Float32Array.from(rest),
    track = A.track.subarray(frame * h.parts * 12, (frame + 1) * h.parts * 12);
  for (let n = 0; n < h.splats; n++) {
    const part = A.stylePart[A.style[n]];
    if (!part) continue;
    const o = n * 16,
      m = track.subarray(part * 12, part * 12 + 12),
      [x, y, z] = [D[o], D[o + 1], D[o + 2]],
      c = [D[o + 4], D[o + 5], D[o + 6], D[o + 5], D[o + 8], D[o + 9], D[o + 6], D[o + 9], D[o + 10]], // the whole 3 x 3, by rows
      ac = [0, 1, 2].flatMap(i => [0, 1, 2].map(j => m[i * 3] * c[j] + m[i * 3 + 1] * c[3 + j] + m[i * 3 + 2] * c[6 + j])),
      acat = (i, j) => ac[i * 3] * m[j * 3] + ac[i * 3 + 1] * m[j * 3 + 1] + ac[i * 3 + 2] * m[j * 3 + 2];
    for (let i = 0; i < 3; i++) D[o + i] = m[i * 3] * x + m[i * 3 + 1] * y + m[i * 3 + 2] * z + m[9 + i];
    [D[o + 4], D[o + 5], D[o + 6], D[o + 8], D[o + 9], D[o + 10]] = [acat(0, 0), acat(0, 1), acat(0, 2), acat(1, 1), acat(1, 2), acat(2, 2)];
  }
  for (let j = 0; j < h.cloth; j++) {
    const o = (h.clothFirst + j) * 16,
      f = frame * h.cloth + j;
    for (let k = 0; k < 3; k++) D[o + k] = F.fromU16(A.clothPosition[f * 3 + k], h.clothMin[k], h.clothMax[k]);
    const nrm = F.unpackNormal(A.clothNormal[f * 2], A.clothNormal[f * 2 + 1]);
    [D[o + 4], D[o + 5], D[o + 6], D[o + 8], D[o + 9], D[o + 10]] = F.discCovariance(nrm, h.clothRadius, h.clothThickness);
    D[o + 7] = F.packedColour(A.palette[A.clothColour[f]]);
  }
  return D;
}

// a world the toolkit's renderer can draw: the rows at a frame, the camera, the look, and the moment (the motion clock)
function world(scene, frame) {
  const { h, A } = scene;
  return {
    count: h.splats,
    data: rowsAt(scene, frame),
    pal: Array.from(A.palette),
    cam: { target: h.camTarget, dist: h.camDist, pitch: h.camPitch, yaw: h.camYaw },
    detail: h.detail,
    radius: h.radius,
    fog: { c: h.fogIndex, start: h.fogStart, max: h.fogMax },
    outline: { c: h.outlineIndex, edge: h.outlineEdge },
    ao: { k: h.shadeStrength, range: h.shadeRange },
    dither: h.dither,
    refract: h.glassBend,
    back: [],
    loop: h.loop,
    clock: h.clockStart + frame / F.FRAME_RATE
  };
}

module.exports = { open, rowsAt, world };
