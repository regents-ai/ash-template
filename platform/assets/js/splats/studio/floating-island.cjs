/* The floating island both scenes stand on, and the few things both scenes need around it.
   It only calls the toolkit's public API (the K, B and S it is handed); none of the toolkit's own code is copied here. */
const TAU = Math.PI * 2;
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const smooth = (a, b, x) => {
  const t = clamp((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
};

// a ragged outline: radius by angle, worked out once into a table
function outline(B, R, wob, seed) {
  const N = 720,
    T = new Float32Array(N + 1);
  for (let i = 0; i <= N; i++) {
    const a = (i / N) * TAU;
    T[i] =
      R *
      (1 +
        wob * 2.2 * (B.fbm(Math.cos(a) * 1.4 + seed, Math.sin(a) * 1.4 + 3.1, 2.7 + seed * 0.1, 3) - 0.5) +
        0.045 * Math.sin(3 * a + seed));
  }
  return a => {
    let u = ((((a % TAU) + TAU) % TAU) / TAU) * N;
    const i = Math.floor(u);
    u -= i;
    return T[i] * (1 - u) + T[i + 1] * u;
  };
}

/* The island's body: a slab of turf with a ragged rim that overhangs a hanging cone of bedded rock.
   o: R (radius), thick (turf depth), depth (rock below the turf), ground(x, z) (the land's own rise and fall), turf and rock
   (materials), res, seed. Returns h(x, z) (the top of the land), rim(a), and the rock's radius by height. */
function body(K, B, S, o) {
  const R = o.R,
    thick = o.thick,
    depth = o.depth,
    seed = o.seed || 5,
    res = o.res || S.res,
    rim = outline(B, R, 0.1, seed),
    ground = o.ground || (() => 0);
  // the top rounds over at the rim, so the edge reads as a lip of turf rather than a cut
  const lip = (x, z, r) => {
    const e = rim(Math.atan2(z, x)),
      u = smooth(e - 0.9, e + 0.05, r);
    return -0.32 * u * u;
  };
  const h = (x, z) => ground(x, z) + lip(x, z, Math.hypot(x, z));
  const Rt = R * 0.8,
    yTop = -thick + 0.25,
    yBot = -thick - depth,
    prim = outline(B, Rt, 0.12, seed + 11);
  // beds of rock: soft ones stand further back than hard ones, so the cone is stepped with ledges
  const beds = [];
  for (let y = yBot, k = 0; y < yTop + 1; k++) {
    const hgt = 0.28 + 0.5 * B.n3(k * 1.7, 3.1, seed);
    beds.push([y, 0.15 + 0.85 * B.n3(k * 2.3 + 9, 1.3, seed)]);
    y += hgt;
  }
  const bed = y => {
    let i = 0;
    while (i + 1 < beds.length && y >= beds[i + 1][0]) i++;
    let hard = beds[i][1];
    if (i + 1 < beds.length) hard += (beds[i + 1][1] - hard) * smooth(beds[i + 1][0] - 0.07, beds[i + 1][0], y);
    return { i, hard };
  };
  const rockR = (y, a) => {
    const t = clamp((y - yBot) / (yTop - yBot), 0, 1),
      cone = prim(a) * (0.02 + 0.98 * Math.pow(t, 0.62));
    return cone - 0.42 * (1 - bed(y).hard) * (0.3 + 0.7 * t);
  };
  // the turf: top, rim and the strip of underside that hangs out past the rock
  S.solid(
    [0, 0, 0],
    R * 1.4,
    (x, y, z) => {
      const r = Math.hypot(x, z);
      return Math.max((y - ground(x, z) - lip(x, z, r)) * 0.8, (r - rim(Math.atan2(z, x))) * 0.92, -thick - y);
    },
    (rs, f) => {
      const Rm = R * 1.2;
      let row = 0;
      for (let z = -Rm; z <= Rm; z += rs * 0.87, row++)
        for (let x = -Rm + (row % 2) * rs * 0.5; x <= Rm; x += rs) {
          const r = Math.hypot(x, z),
            e = rim(Math.atan2(z, x));
          if (r < e) f(x, h(x, z), z);
          if (r < e && r > prim(Math.atan2(z, x)) - 0.25) f(x, -thick, z);
        }
      const n = Math.ceil((TAU * Rm) / rs);
      for (let k = 0; k < n; k++) {
        const a = (k / n) * TAU,
          e = rim(a),
          c = Math.cos(a),
          s = Math.sin(a),
          yh = h(c * e, s * e);
        for (let y = -thick + rs * 0.5; y < yh; y += rs * 0.8) f(c * e, y, s * e);
      }
    },
    o.turf,
    { res }
  );
  // the rock beneath, melted together with a few hanging lumps
  const G = S.grp(0.45),
    grain = K.tex.noise(1.6, 3);
  S.solid(
    [0, (yTop + yBot) / 2, 0],
    Math.hypot(Rt * 1.2, depth / 2 + 0.5),
    (x, y, z) => {
      const wy = y + (yTop + yBot) / 2,
        a = Math.atan2(z, x);
      return Math.max(
        (Math.hypot(x, z) - rockR(wy, a) - 0.16 * (grain(x, wy, z) - 0.5)) * 0.72,
        wy - yTop,
        yBot - wy
      );
    },
    (rs, f) => {
      const ym = (yTop + yBot) / 2;
      for (let y = yBot; y <= yTop; y += rs * 0.75) {
        const n = Math.max(6, Math.ceil((TAU * Rt * 1.15) / rs));
        for (let k = 0; k < n; k++) {
          const a = ((k + (y * 7) % 1) / n) * TAU,
            r = rockR(y, a);
          f(Math.cos(a) * r, y - ym, Math.sin(a) * r);
        }
      }
    },
    o.rock,
    Object.assign({ res, reach: 0.12 }, G)
  );
  const lumps = [];
  for (let k = 0; k < (o.lumps || 9); k++) {
    const a = (k / (o.lumps || 9)) * TAU * 2.618 + B.rr(-0.3, 0.3),
      y = B.rr(yBot + depth * 0.15, yTop - 0.6),
      r = rockR(y, a) * 0.92,
      s = B.rr(0.35, 0.8);
    lumps.push([Math.cos(a) * r, y, Math.sin(a) * r, s]);
    S.rock([Math.cos(a) * r, y, Math.sin(a) * r], [s * 1.1, s * 0.75, s], o.rock, Object.assign({ res }, G));
  }
  return { h, rim, rockR, yTop, yBot, thick, R, Rt, bed, lumps };
}

/* grass and moss hanging over the rim, as loose blades that sway: drawn after the bake, lit by hand from which way the rim faces */
function skirt(B, isle, o) {
  const { rim, h } = isle,
    ramp = o.ramp,
    sun = o.sun,
    n = Math.ceil((TAU * isle.R * 1.1) / (o.gap || 0.045));
  for (let k = 0; k < n; k++) {
    const a = (k / n) * TAU + B.rr(-0.01, 0.01),
      c = Math.cos(a),
      s = Math.sin(a),
      e = rim(a) + 0.03,
      y0 = h(c * (e - 0.06), s * (e - 0.06)) - 0.02,
      lit = clamp(0.35 + 0.55 * (c * sun[0] + s * sun[2]), 0, 1);
    const blades = 1 + (B.R() < 0.6 ? 1 : 0);
    for (let j = 0; j < blades; j++) {
      const len = (o.len || 0.32) * (0.4 + B.R() * B.R() * 2.2),
        out = B.rr(0.05, 0.35),
        ax = B.norm([c * out, -1, s * out]),
        tone = clamp(Math.floor(lit * (ramp.length - 1) + B.rr(-0.8, 0.8)), 0, ramp.length - 1),
        sway = { k: 11, ph: B.rr(0, 6), sp: 1.9, rg: 0.018 };
      B.stick(c * e + ax[0] * len * 0.5, y0 + ax[1] * len * 0.5, s * e + ax[2] * len * 0.5, ax, len * 0.5, 0.022, B.P[ramp[tone]], 3, sway);
      B.stick(
        c * e + ax[0] * len * 1.05,
        y0 + ax[1] * len * 1.05,
        s * e + ax[2] * len * 1.05,
        ax,
        len * 0.12,
        0.016,
        B.P[ramp[Math.max(0, tone - 1)]],
        3,
        sway
      );
    }
  }
}

/* roots hanging from the turf's underside, past the rock */
function roots(K, B, S, isle, mat, o) {
  const n = o.n || 9;
  for (let k = 0; k < n; k++) {
    const a = (k / n) * TAU + B.rr(-0.25, 0.25),
      e = (isle.rim(a) + isle.Rt) * 0.5 + 0.15;
    if (o.skip && o.skip(a)) continue;
    const
      at = [Math.cos(a) * e, -isle.thick + 0.05, Math.sin(a) * e],
      grown = K.grow.branch({
        at,
        dir: [Math.cos(a) * 0.25, -1, Math.sin(a) * 0.25],
        len: B.rr(0.6, 2.0) * (o.len || 1),
        r: B.rr(0.026, 0.042),
        depth: 2,
        forks: 2,
        spread: 0.42,
        shrink: 0.7,
        segs: 6,
        light: [0, -1, 0],
        lean: 0.25,
        droop: 0,
        wobble: 0.9,
        seed: (o.seed || 40) + k
      });
    K.grow.limbs(S, grown, mat, { res: 0.04, melt: 0.03 });
  }
}

/* stars, soft bokeh and a few clouds: a backdrop that turns with the camera */
function backdrop(B, o) {
  // (all of it well beyond the camera's own distance, so nothing drifts between the eye and the island)
  for (let i = 0; i < (o.stars || 0); i++) {
    const d = B.randDir(),
      r = B.rr(40, 48),
      y = d[1] * r * 0.6 + 2;
    B.star(d[0] * r, y, d[2] * r, B.rr(0.1, 0.22), B.pick(o.starCols), {
      em: true,
      nd: true,
      k: 4,
      ph: B.rr(0, 6),
      sp: B.rr(1.5, 3)
    });
  }
  for (let i = 0; i < (o.bokeh || 0); i++) {
    const d = B.randDir(),
      r = B.rr(30, 38);
    B.iso(d[0] * r, d[1] * r * 0.6 + 1, d[2] * r, B.rr(0.3, 0.7), B.P[B.pick(o.bokehCols)], B.rr(0.35, 0.7), {
      em: true,
      nd: true,
      k: 6,
      ph: B.rr(0, 6),
      sp: B.rr(0.3, 0.7),
      rg: B.rr(0.1, 0.3)
    });
  }
  for (const c of o.clouds || []) {
    for (let i = 0; i < c.n; i++) {
      const u = B.gauss() * c.r[0],
        v = B.gauss() * c.r[1] * 0.6,
        w = B.gauss() * c.r[2],
        top = clamp(0.5 + v / (c.r[1] * 1.2), 0, 1);
      B.iso(c.p[0] + u, c.p[1] + v, c.p[2] + w, B.rr(0.25, 0.55), B.P[c.cols[Math.min(c.cols.length - 1, Math.floor(top * c.cols.length))]], c.a || 0.22, {
        em: true,
        nd: true
      });
    }
  }
}

/* A tree whose crown is many small leaf clumps, not a few big lobes. While the tree is made, each lobe it asks for is shared out
   into small clumps round the lobe's outside, each lit on its own (a lit top, a shaded underside), over a darker inner mass that
   fills the gaps between them. size is a clump's radius; o is the toolkit's own tree options. */
function clumpyTree(B, S, size, x, y, z, o) {
  const crown = S.crown;
  S.crown = (lobes, mat, count, co) => {
    const clumps = [];
    for (const c of lobes) {
      clumps.push({ p: c.p, r: c.r.map(v => v * 0.6), band: 0.05 });
      const n = Math.max(4, Math.round((3.2 * c.r[0] * (c.r[1] + c.r[2])) / (size * size)));
      for (let k = 0; k < n; k++) {
        const d = B.randDir();
        if (d[1] < -0.55) continue; // the underside is the inner mass's
        const s = size * B.rr(0.75, 1.2),
          // clumps on the top and the lit side of their lobe run lighter (past 1, a clump's lit top reaches the ramp's lightest tone)
          band = clamp(0.76 + 0.35 * d[1] + 0.3 * (d[0] * S.sun[0] + d[1] * S.sun[1] + d[2] * S.sun[2]) + B.rr(-0.22, 0.22), 0.1, 1.3);
        clumps.push({ p: [c.p[0] + d[0] * c.r[0] * 0.78, c.p[1] + d[1] * c.r[1] * 0.78, c.p[2] + d[2] * c.r[2] * 0.78], r: [s, s * 0.75, s], band });
      }
    }
    crown(clumps, mat, count, co);
  };
  const tree = S.tree(x, y, z, o);
  S.crown = crown;
  return tree;
}

/* every repeating motion made to come round in exactly L seconds, so a turn of that length loops without a jump */
function loopable(W, L) {
  const d = W.data,
    snapSp = sp => {
      if (!sp) return sp;
      const m = Math.max(1, Math.round((Math.abs(sp) * L) / TAU));
      return (Math.sign(sp) * m * TAU) / L;
    },
    // a swaying dab (kind 11) also rises and falls at 1.3 times its speed, which never comes round exactly: of the cycle counts
    // either side of its own, take the one that brings that second motion nearest a whole number of cycles
    swaySp = sp => {
      if (!sp) return sp;
      const m0 = Math.round((Math.abs(sp) * L) / TAU);
      let best = Math.max(1, m0),
        off = 1;
      for (let m = Math.max(1, m0 - 1); m <= m0 + 1; m++) {
        const o = Math.abs(1.3 * m - Math.round(1.3 * m));
        if (o < off) {
          off = o;
          best = m;
        }
      }
      return (Math.sign(sp) * best * TAU) / L;
    };
  for (let i = 0; i < W.count; i++) {
    const q = i * 16,
      kind = Math.round(d[q + 11]) % 16,
      sp = d[q + 13],
      rg = d[q + 14];
    if (kind === 2 || kind === 3 || kind === 15) {
      if (sp && rg) d[q + 13] = (rg * Math.max(1, Math.round((L * sp) / rg))) / L;
    } else if (kind === 11) d[q + 13] = swaySp(sp);
    else if (kind) d[q + 13] = snapSp(sp);
  }
  return W;
}

/* the whole island rises and falls a little, once every L seconds (the stars stay where they are) */
function bob(K, st, rig, part, amp, L) {
  st.add({
    update(dt, t) {
      rig.set(part, K.M.id(), [0, 0, 0], [0, amp * Math.sin((TAU * t) / L), 0]);
      rig.apply();
    }
  });
}

module.exports = { TAU, clamp, smooth, outline, body, skirt, roots, backdrop, clumpyTree, loopable, bob };
