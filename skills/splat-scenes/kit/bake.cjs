/* Bakes a built world into one scene file for the player: every splat at rest, packed small, and every moving part's matrix thirty
   times a second through one loop. references/format.md describes the file. */
const F = require('./format.cjs');
const { render, at } = require('./ink.cjs');

/* a symmetric 3x3 (c00 c01 c02 c11 c12 c22) as three variances along three axes, by Jacobi turns: the axes are the columns of a
   proper rotation (determinant +1), given by rows */
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

function bake(world) {
  const st = world.anim,
    rig = st.rig,
    base = st.base,
    N = world.count,
    L = world.loop,
    frames = Math.round(L * F.FRAME_RATE),
    P = rig.names.length,
    colourOf = new Map(world.pal.map((hex, k) => [F.packedColour(hex), k]));

  // every part's matrix, frame by frame through the loop
  const track = new Float32Array(frames * P * 12);
  for (let f = 0; f < frames; f++) {
    at(world, f / F.FRAME_RATE);
    track.set(rig.M, f * P * 12);
  }

  // the splats in file order, each at rest: its place, its shape as a turn and three sizes, and the box of its run of CHUNK_SIZE
  const order = F.fileOrder(base, N),
    M = order.filter(i => Math.round(base[i * 16 + 11]) % 16 !== 0).length,
    chunkBounds = new Float32Array(Math.ceil(N / F.CHUNK_SIZE) * 6).fill(Infinity);
  for (let c = 0; c < chunkBounds.length / 6; c++) chunkBounds.fill(-Infinity, c * 6 + 3, c * 6 + 6);
  const axes = order.map((i, n) => {
    const o = i * 16,
      cb = Math.floor(n / F.CHUNK_SIZE) * 6;
    for (let k = 0; k < 3; k++) {
      chunkBounds[cb + k] = Math.min(chunkBounds[cb + k], base[o + k]);
      chunkBounds[cb + 3 + k] = Math.max(chunkBounds[cb + 3 + k], base[o + k]);
    }
    const e = eigen([base[o + 4], base[o + 5], base[o + 6], base[o + 8], base[o + 9], base[o + 10]]);
    if (!e.values.every(v => v > 0)) throw new Error('splat ' + i + ', made by ' + world.who[i].who + ', has a flat or empty shape');
    return { q: quaternion(e.rows), s: e.values.map(Math.sqrt) };
  });
  let logScaleMin = Infinity,
    logScaleMax = -Infinity;
  for (const { s } of axes)
    for (const v of s) {
      logScaleMin = Math.min(logScaleMin, Math.log(v));
      logScaleMax = Math.max(logScaleMax, Math.log(v));
    }

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
      track
    },
    styles = new Map(),
    motions = new Map(),
    slot = (table, key, entry) => {
      if (!table.has(key)) table.set(key, Object.assign(entry, { at: table.size }));
      return table.get(key).at;
    };
  order.forEach((i, n) => {
    const o = i * 16,
      kraw = Math.round(base[o + 11]),
      kind = kraw % 16,
      cb = Math.floor(n / F.CHUNK_SIZE) * 6;
    for (let k = 0; k < 3; k++) A.position[n * 3 + k] = F.toU16(base[o + k], chunkBounds[cb + k], chunkBounds[cb + 3 + k]);
    A.rotation[n] = F.packRotation(axes[n].q);
    A.scale.set(axes[n].s.map(v => F.toLogScale(v, logScaleMin, logScaleMax)), n * 3);
    const colour = colourOf.get(base[o + 7]);
    if (colour === undefined) throw new Error(world.who[i].who + ': makes a splat in a colour off the palette');
    A.colour[n] = colour;
    const code = F.codeFromKraw(kraw),
      part = rig.bid[i];
    A.style[n] = slot(styles, base[o + 3] + ' ' + code + ' ' + part, { density: base[o + 3], code, part });
    if (n < M) {
      const [ph, sp, rg, ex] = base.subarray(o + 12, o + 16);
      A.cycles[n] = Math.round(F.FRACTION_KINDS.has(kind) ? (sp * L) / rg : (sp * L) / (2 * Math.PI));
      A.phase[n] = F.toPhase(kind, ph);
      A.motion[n] = slot(motions, rg + ' ' + ex, { range: rg, extra: ex });
    }
  });
  const S = [...styles.values()],
    Q = [...motions.values()];
  if (S.length > 256 || Q.length > 256 || P > 256) throw new Error('the scene has more than 256 styles, motions or parts');
  Object.assign(A, {
    palette: Uint32Array.from(world.pal),
    styleDensity: Float32Array.from(S, s => s.density),
    styleCode: Uint8Array.from(S, s => s.code),
    stylePart: Uint8Array.from(S, s => s.part),
    motionRange: Float32Array.from(Q, m => m.range),
    motionExtra: Float32Array.from(Q, m => m.extra)
  });

  const h = {
    splats: N,
    moving: M,
    styles: S.length,
    motions: Q.length,
    parts: P,
    frames,
    colours: world.pal.length,
    fogIndex: world.fog.c,
    outlineIndex: world.outline.c,
    loop: L,
    logScaleMin,
    logScaleMax,
    camTarget: world.cam.target,
    camDist: world.cam.dist,
    camPitch: world.cam.pitch,
    camYaw: world.cam.yaw,
    fov: render.FOV,
    detail: world.detail,
    radius: world.radius,
    fogStart: world.fog.start,
    fogMax: world.fog.max,
    outlineEdge: world.outline.edge,
    shadeStrength: world.ao.k,
    shadeRange: world.ao.range,
    dither: world.dither,
    glassBend: world.refract
  };
  const blocks = F.layout(h),
    end = blocks.pop().at,
    buf = Buffer.alloc(end);
  buf.write(F.MAGIC, 0, 'latin1');
  F.writeHeader(new DataView(buf.buffer, buf.byteOffset, buf.byteLength), h);
  for (const b of blocks) Buffer.from(A[b.name].buffer, A[b.name].byteOffset, A[b.name].byteLength).copy(buf, b.at);
  return { buf, header: h };
}

module.exports = { bake };
