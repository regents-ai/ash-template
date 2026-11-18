/* Bakes the scenes into the page's own scene files, priv/static/splats/<scene>.bin, and prints what each part of a
   file costs and how far a stored number can be from the toolkit's.

     INK_STUDIO=<toolkit checkout> node assets/js/splats/studio/bake.cjs [scene ...]        (from platform/)

   FORMAT.md describes the file. */
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const kit = require('./kit.cjs');
const F = require('./format.cjs');

const SCENES = ['island', 'factory', 'campfire-stories', 'trainer-battle', 'missile-circus', 'fishing', 'meteor-strike'];
const OUT = path.join(__dirname, '../../../../priv/static/splats');
// the loop starts after fifteen of its own lengths, by when the factory's cloth flag has settled into a steady swing
const WARM_LOOPS = 15;

/* a symmetric 3x3 (c00 c01 c02 c11 c12 c22) as three variances along three axes, by Jacobi turns: the axes are the columns of a proper
   rotation (determinant +1), given by rows */
function eigen(c) {
  const a = [
      [c[0], c[1], c[2]],
      [c[1], c[3], c[4]],
      [c[2], c[4], c[5]]
    ],
    v = [
      [1, 0, 0],
      [0, 1, 0],
      [0, 0, 1]
    ];
  for (let sweep = 0; sweep < 50; sweep++) {
    const off = a[0][1] * a[0][1] + a[0][2] * a[0][2] + a[1][2] * a[1][2],
      diag = a[0][0] * a[0][0] + a[1][1] * a[1][1] + a[2][2] * a[2][2];
    if (off <= 1e-30 * diag) break;
    for (const [p, q] of [
      [0, 1],
      [0, 2],
      [1, 2]
    ]) {
      if (a[p][q] === 0) continue;
      const th = (a[q][q] - a[p][p]) / (2 * a[p][q]),
        t = (th < 0 ? -1 : 1) / (Math.abs(th) + Math.sqrt(th * th + 1)),
        cs = 1 / Math.sqrt(t * t + 1),
        sn = t * cs;
      for (let k = 0; k < 3; k++) [a[k][p], a[k][q]] = [cs * a[k][p] - sn * a[k][q], sn * a[k][p] + cs * a[k][q]];
      for (let k = 0; k < 3; k++) [a[p][k], a[q][k]] = [cs * a[p][k] - sn * a[q][k], sn * a[p][k] + cs * a[q][k]];
      for (let k = 0; k < 3; k++) [v[k][p], v[k][q]] = [cs * v[k][p] - sn * v[k][q], sn * v[k][p] + cs * v[k][q]];
    }
  }
  const det =
    v[0][0] * (v[1][1] * v[2][2] - v[1][2] * v[2][1]) -
    v[0][1] * (v[1][0] * v[2][2] - v[1][2] * v[2][0]) +
    v[0][2] * (v[1][0] * v[2][1] - v[1][1] * v[2][0]);
  if (det < 0) for (let k = 0; k < 3; k++) v[k][2] = -v[k][2];
  return { values: [a[0][0], a[1][1], a[2][2]], rows: v.flat() };
}

// a unit quaternion (x, y, z, w) for a rotation given by rows
function quaternion(m) {
  const tr = m[0] + m[4] + m[8];
  let q;
  if (tr > 0) {
    const s = Math.sqrt(tr + 1) * 2;
    q = [(m[7] - m[5]) / s, (m[2] - m[6]) / s, (m[3] - m[1]) / s, s / 4];
  } else if (m[0] > m[4] && m[0] > m[8]) {
    const s = Math.sqrt(1 + m[0] - m[4] - m[8]) * 2;
    q = [s / 4, (m[1] + m[3]) / s, (m[2] + m[6]) / s, (m[7] - m[5]) / s];
  } else if (m[4] > m[8]) {
    const s = Math.sqrt(1 + m[4] - m[0] - m[8]) * 2;
    q = [(m[1] + m[3]) / s, s / 4, (m[5] + m[7]) / s, (m[2] - m[6]) / s];
  } else {
    const s = Math.sqrt(1 + m[8] - m[0] - m[4]) * 2;
    q = [(m[2] + m[6]) / s, (m[5] + m[7]) / s, s / 4, (m[3] - m[1]) / s];
  }
  const l = Math.hypot(...q);
  return q.map(x => x / l);
}

const covOf = (d, o) => [d[o + 4], d[o + 5], d[o + 6], d[o + 8], d[o + 9], d[o + 10]];
const frob = c => Math.hypot(c[0], c[3], c[5], Math.SQRT2 * c[1], Math.SQRT2 * c[2], Math.SQRT2 * c[4]);
const box = (pts, n) => {
  const lo = [Infinity, Infinity, Infinity],
    hi = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < n * 3; i++) {
    lo[i % 3] = Math.min(lo[i % 3], pts[i]);
    hi[i % 3] = Math.max(hi[i % 3], pts[i]);
  }
  return [lo, hi];
};

function bake(id) {
  const world = kit.build(path.join(__dirname, id + '.cjs')),
    st = world.anim,
    rig = st.rig,
    base = st.base,
    N = world.count,
    L = world.loop,
    T0 = WARM_LOOPS * L,
    frames = Math.round(L * F.FRAME_RATE),
    P = rig.names.length,
    cloth = st.systems.find(s => s.sim && s.first !== undefined),
    C = cloth ? cloth.count : 0,
    c0 = cloth ? cloth.first : 0,
    inCloth = i => i >= c0 && i < c0 + C;
  const paletteIndex = new Map(world.pal.map((hex, k) => [F.packedColour(hex), k])),
    indexOf = packed => {
      const k = paletteIndex.get(packed);
      if (k === undefined) throw new Error(id + ': a colour off the palette');
      return k;
    };
  if (world.back.length || world.grow || st.zoom || st.kick || st.grade)
    throw new Error(id + ': the scene uses a toolkit setting this format does not carry');

  // ---- walk the loop: every part's matrix and every cloth dab, frame by frame (and once more, a whole loop on, to measure the seam)
  const track = new Float32Array(frames * P * 12),
    clothP = new Float64Array((frames + 1) * C * 3),
    clothN = new Float64Array(frames * C * 3),
    clothColour = new Uint8Array(frames * C);
  let clothRadius = 0,
    clothThickness = 0;
  for (let f = 0; f <= frames; f++) {
    kit.pose(world, T0 + f / F.FRAME_RATE);
    for (let j = 0; j < C; j++) clothP.set(world.data.subarray((c0 + j) * 16, (c0 + j) * 16 + 3), (f * C + j) * 3);
    if (f === frames) break;
    track.set(rig.M, f * P * 12);
    for (let j = 0; j < C; j++) {
      const o = (c0 + j) * 16,
        e = eigen(covOf(world.data, o)),
        thin = e.values.indexOf(Math.min(...e.values)),
        wide = e.values.filter((_, k) => k !== thin).map(Math.sqrt),
        t = Math.sqrt(e.values[thin]);
      if (!clothRadius) [clothRadius, clothThickness] = [wide[0], t];
      if (wide.some(r => Math.abs(r / clothRadius - 1) > 1e-5) || Math.abs(t / clothThickness - 1) > 1e-3)
        throw new Error(id + ': a cloth dab is not a disc of the shared size');
      clothN.set([e.rows[thin], e.rows[3 + thin], e.rows[6 + thin]], (f * C + j) * 3);
      clothColour[f * C + j] = indexOf(world.data[o + 7]);
    }
  }
  let seam = 0;
  for (let j = 0; j < C * 3; j++) seam = Math.max(seam, Math.abs(clothP[frames * C * 3 + j] - clothP[j]));
  for (let f = 0; f < frames; f++)
    for (let k = 0; k < 12; k++)
      if (track[f * P * 12 + k] !== ([0, 4, 8].includes(k) ? 1 : 0)) throw new Error(id + ': part 0 moved');

  // ---- the file's order: the splats that move by their kind first (only they carry motion numbers), each group in the toolkit's order
  const order = F.fileOrder(base, N),
    M = order.filter(i => Math.round(base[i * 16 + 11]) % 16 !== 0).length,
    clothFirst = C ? order.indexOf(c0) : 0;
  for (let j = 0; j < C; j++) if (order[clothFirst + j] !== c0 + j) throw new Error(id + ': the cloth is not one run');

  // ---- each splat at rest: its base row, and for a cloth dab its place in the first frame
  const restP = new Float64Array(N * 3),
    restC = [];
  order.forEach((i, n) => {
    const o = i * 16;
    if (inCloth(i)) {
      const q = (i - c0) * 3;
      restP.set(clothP.subarray(q, q + 3), n * 3);
      restC.push(F.discCovariance(clothN.subarray(q, q + 3), clothRadius, clothThickness));
    } else {
      if (base[o + 1] < -30) throw new Error(id + ': a hidden splat (the toolkit keeps them below y -30)');
      restP.set(base.subarray(o, o + 3), n * 3);
      restC.push(covOf(base, o));
    }
  });
  const chunkBounds = new Float32Array(Math.ceil(N / F.CHUNK_SIZE) * 6);
  for (let c = 0; c * F.CHUNK_SIZE < N; c++) {
    const first = c * F.CHUNK_SIZE,
      [l, u] = box(restP.subarray(first * 3, Math.min(N, first + F.CHUNK_SIZE) * 3), Math.min(N - first, F.CHUNK_SIZE));
    chunkBounds.set(l.concat(u), c * 6);
  }
  const [clothMin, clothMax] = C ? box(clothP, frames * C) : [[0, 0, 0], [0, 0, 0]],
    axes = restC.map(c => {
      const e = eigen(c);
      if (!e.values.every(v => v > 0)) throw new Error(id + ': a splat with a flat or empty shape');
      return { q: quaternion(e.rows), s: e.values.map(Math.sqrt) };
    });
  let logScaleMin = Infinity,
    logScaleMax = -Infinity;
  for (const { s } of axes)
    for (const v of s) {
      logScaleMin = Math.min(logScaleMin, Math.log(v));
      logScaleMax = Math.max(logScaleMax, Math.log(v));
    }

  // ---- the arrays, and how near each stored number comes back
  const A = {
      chunkBounds,
      position: new Uint16Array(N * 3),
      rotation: new Uint32Array(N),
      scale: new Uint16Array(N * 3),
      colour: new Uint8Array(N),
      style: new Uint8Array(N),
      cycles: new Int8Array(M),
      phase: new Uint16Array(M),
      motion: new Uint8Array(M),
      track,
      clothPosition: new Uint16Array(frames * C * 3),
      clothNormal: new Uint8Array(frames * C * 2),
      clothColour
    },
    styles = new Map(),
    motions = new Map(),
    slot = (table, key, entry) => {
      if (!table.has(key)) table.set(key, Object.assign(entry, { at: table.size }));
      return table.get(key).at;
    },
    err = { position: 0, positionSum: 0, size: 0, turn: 0, shape: 0, shapeSum: 0, angle: 0, fraction: 0, clothPosition: 0, clothNormal: 0 };
  order.forEach((i, n) => {
    const o = i * 16,
      kraw = Math.round(base[o + 11]),
      kind = kraw % 16;
    if (kraw & ~F.KRAW_KNOWN || !F.KINDS.has(kind)) throw new Error(id + ': a splat with a kind or flag this format does not carry: ' + kraw);
    const cb = Math.floor(n / F.CHUNK_SIZE) * 6;
    for (let k = 0; k < 3; k++) {
      const v = restP[n * 3 + k],
        [l, u] = [chunkBounds[cb + k], chunkBounds[cb + 3 + k]],
        q = F.toU16(v, l, u);
      A.position[n * 3 + k] = q;
      const e = Math.abs(Math.fround(F.fromU16(q, l, u)) - v);
      err.position = Math.max(err.position, e);
      err.positionSum += e / 3;
    }
    const { q, s } = axes[n],
      bits = F.packRotation(q),
      qBack = F.unpackRotation(bits),
      sq = s.map(v => F.toLogScale(v, logScaleMin, logScaleMax)),
      sBack = sq.map(v => F.fromLogScale(v, logScaleMin, logScaleMax)),
      dc = F.covariance(qBack, sBack).map((v, k) => Math.fround(v) - restC[n][k]),
      shape = frob(dc) / frob(restC[n]);
    A.rotation[n] = bits;
    A.scale.set(sq, n * 3);
    s.forEach((v, k) => (err.size = Math.max(err.size, Math.abs(sBack[k] / v - 1))));
    err.turn = Math.max(err.turn, 2 * Math.acos(Math.min(1, Math.abs(q[0] * qBack[0] + q[1] * qBack[1] + q[2] * qBack[2] + q[3] * qBack[3]))));
    err.shape = Math.max(err.shape, shape);
    err.shapeSum += shape;
    A.colour[n] = inCloth(i) ? clothColour[i - c0] : indexOf(base[o + 7]);
    const code = F.codeFromKraw(kraw),
      part = inCloth(i) ? 0 : rig.bid[i];
    A.style[n] = slot(styles, base[o + 3] + ' ' + code + ' ' + part, { density: base[o + 3], code, part });
    if (n < M) {
      const [ph, sp, rg, ex] = base.subarray(o + 12, o + 16),
        cycles = Math.round(F.FRACTION_KINDS.has(kind) ? (sp * L) / rg : (sp * L) / (2 * Math.PI));
      if (Math.fround(F.speed(kind, cycles, rg, L)) !== sp) throw new Error(id + ': a speed that is not a whole number of cycles a loop');
      if (F.FRACTION_KINDS.has(kind) && !(ph >= 0 && ph < 1)) throw new Error(id + ': a fraction phase outside 0 to 1');
      A.cycles[n] = cycles;
      A.phase[n] = F.toPhase(kind, ph);
      const back = F.fromPhase(kind, A.phase[n]);
      if (F.FRACTION_KINDS.has(kind)) err.fraction = Math.max(err.fraction, Math.abs(back - ph));
      else err.angle = Math.max(err.angle, 2 * Math.abs(Math.sin((back - ph) / 2)));
      A.motion[n] = slot(motions, rg + ' ' + ex, { range: rg, extra: ex });
    }
  });
  if (styles.size > 256 || motions.size > 256) throw new Error(id + ': more than 256 styles or motions');
  for (let m = 0; m < frames * C; m++) {
    for (let k = 0; k < 3; k++) {
      const v = clothP[m * 3 + k],
        q = F.toU16(v, clothMin[k], clothMax[k]);
      A.clothPosition[m * 3 + k] = q;
      err.clothPosition = Math.max(err.clothPosition, Math.abs(Math.fround(F.fromU16(q, clothMin[k], clothMax[k])) - v));
    }
    const n = clothN.subarray(m * 3, m * 3 + 3),
      pk = F.packNormal(n),
      back = F.unpackNormal(pk[0], pk[1]);
    A.clothNormal.set(pk, m * 2);
    err.clothNormal = Math.max(err.clothNormal, Math.acos(Math.min(1, Math.abs(n[0] * back[0] + n[1] * back[1] + n[2] * back[2]))));
  }
  const S = [...styles.values()],
    Q = [...motions.values()];
  Object.assign(A, {
    palette: Uint32Array.from(world.pal),
    styleDensity: Float32Array.from(S, s => s.density),
    styleCode: Uint8Array.from(S, s => s.code),
    stylePart: Uint8Array.from(S, s => s.part),
    motionRange: Float32Array.from(Q, m => m.range),
    motionExtra: Float32Array.from(Q, m => m.extra)
  });

  // ---- the header and the file
  const h = {
    version: F.VERSION,
    splats: N,
    moving: M,
    styles: S.length,
    motions: Q.length,
    parts: P,
    frames,
    cloth: C,
    clothFirst,
    colours: world.pal.length,
    chunkSize: F.CHUNK_SIZE,
    fogIndex: world.fog.c,
    outlineIndex: world.outline.c,
    backdropIndex: 0,
    loop: L,
    clockStart: T0,
    logScaleMin,
    logScaleMax,
    clothMin,
    clothMax,
    clothRadius,
    clothThickness,
    camTarget: world.cam.target,
    camDist: world.cam.dist,
    camPitch: world.cam.pitch,
    camYaw: world.cam.yaw,
    fov: kit.render.FOV,
    detail: world.detail,
    radius: world.radius,
    fogStart: world.fog.start,
    fogMax: world.fog.max,
    outlineEdge: world.outline.edge,
    shadeStrength: world.ao.k,
    shadeRange: world.ao.range,
    dither: world.dither,
    glassBend: world.refract === undefined ? 6 : world.refract
  };
  const blocks = F.layout(h),
    end = blocks.pop().at,
    buf = Buffer.alloc(end);
  buf.write(F.MAGIC, 0, 'latin1');
  F.writeHeader(new DataView(buf.buffer, buf.byteOffset, buf.byteLength), h);
  for (const b of blocks) {
    const src = A[b.name];
    if (src.length !== b.length) throw new Error(id + ': ' + b.name + ' has ' + src.length + ' numbers, the layout wants ' + b.length);
    Buffer.from(src.buffer, src.byteOffset, src.byteLength).copy(buf, b.at);
  }
  fs.mkdirSync(OUT, { recursive: true });
  const file = path.join(OUT, id + '.bin');
  fs.writeFileSync(file, buf);

  // ---- what it cost, and how near it comes back (an art pixel is 1 / detail world units at the scene's own distance)
  const px = 1 / world.detail,
    mb = n => (n / 1e6).toFixed(2) + ' MB',
    deg = r => ((r * 180) / Math.PI).toFixed(3) + ' degrees';
  console.log(`\n${id}: ${N} splats (${M} moving by their kind), ${S.length} styles, ${Q.length} motions, ${P} parts, ${frames} frames, ${C} cloth dabs`);
  console.log(`  ${file}: ${mb(buf.length)} raw, ${mb(zlib.gzipSync(buf, { level: 9 }).length)} gzipped`);
  for (const b of blocks) {
    const bytes = b.length * b.T.BYTES_PER_ELEMENT;
    if (bytes > 20000) console.log(`    ${b.name.padEnd(14)} ${mb(bytes)}`);
  }
  console.log(
    `  position: within ${err.position.toExponential(2)} world units (${(err.position / px).toFixed(4)} of an art pixel), ` +
      `${(err.positionSum / N).toExponential(2)} on average`
  );
  console.log(
    `  shape: sizes within ${(err.size * 100).toFixed(4)}%, axes within ${deg(err.turn)}, whole shape within ` +
      `${(err.shape * 100).toFixed(2)}% (${((err.shapeSum / N) * 100).toFixed(3)}% on average)`
  );
  console.log(`  phase: angles within ${err.angle.toExponential(2)} radians, cycle fractions within ${err.fraction.toExponential(2)}`);
  if (C)
    console.log(
      `  cloth: places within ${err.clothPosition.toExponential(2)} world units (${(err.clothPosition / px).toFixed(4)} of an art pixel), ` +
        `facings within ${deg(err.clothNormal)}; a whole loop on, it is ${seam.toFixed(4)} world units from where it began`
    );
}

for (const id of process.argv.length > 2 ? process.argv.slice(2) : SCENES) bake(id);
