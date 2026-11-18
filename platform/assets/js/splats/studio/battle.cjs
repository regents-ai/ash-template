/* Battle: a terraformed crater sitting on a giant twenty-sided die, at golden hour against a charcoal sky. Inside the red Martian
   rim the crater has been turned green: corn rows on either side, a pond in the middle, a battle field painted in front of it. A crowned
   swamp toad with wide eyes squares up to a barn spider on that field and, twice a loop, winds its arm round and throws a spark that
   bursts on the spider, which rears back. Behind them a belt carries bundles of 1999 newspapers out of one Y2K cryo pod and into the
   other, a stamp coming down on each; behind that a castle keep stands on the rim, its battlements in the shape of the Regents crown and
   the spider's web across its door spelling FEW. Underneath, stalactites hang round the die, whose faces are numbered and dotted like a
   Lichtenstein print, its edges drawn as glowing wire. Seeded: it builds the same way every time. */
const FI = require('./floating-island.cjs');

const L = 8; // seconds in one loop: every repeating motion comes round in this time

// 48 colours in the Lichtenstein print's primaries, each ramp shifting hue as it goes from dark to light
const PAL = [
  0x2a2a30, 0x141418, 0x3c3b45, 0x5b5967, // 0-3   charcoal sky, ink, charcoal, haze
  0x3a0f22, 0x7c1428, 0xc4202c, 0xec5636, 0xf89e78, 0xffd6bc, // 4-9   red: maroon to print red to coral to dot pink
  0x4a2a10, 0x8c5812, 0xd89818, 0xf8cc1c, 0xfff07c, 0xfffbe4, // 10-15 yellow: brown to ochre to print yellow to cream
  0x121a40, 0x1c347c, 0x2462ba, 0x46a4e2, 0x90daf4, 0xdaf8ff, // 16-21 blue: navy to print blue to sky to the wire's pale cyan
  0x0e2a28, 0x16483a, 0x2a7040, 0x4e9a3a, 0x8ec43c, 0xd2e86a, // 22-27 green: teal to grass to yellow-green
  0x2e1428, 0x5c2028, 0x903a26, 0xc4622e, 0xe49a58, 0xf4ca98, // 28-33 Martian rock: plum to rust to sand
  0x24263a, 0x404258, 0x686678, 0x9a9298, 0xccc2b6, // 34-38 keep stone: blue-grey to warm grey
  0x2a1610, 0x56301e, 0x8c5a32, // 39-41 wood and soil
  0x5a2a7a, 0xa064c8, 0xff74b4, // 42-44 Y2K grape to print pink
  0x0a0a0c, 0xfafcff, 0x40f0d0 // 45-47 ink black, spark white, the wire's green-cyan
];

// ramps, dark to light; *_SUN is the same thing where the low gold sun reaches it, warmer
const RED = [4, 5, 6, 7, 8],
  RED_SUN = [5, 6, 7, 8, 9],
  GRASS = [22, 23, 24, 25, 26],
  GRASS_SUN = [24, 25, 26, 27, 14],
  MARS = [28, 29, 30, 31],
  MARS_SUN = [29, 30, 31, 32, 33],
  STONE = [34, 35, 36, 37],
  STONE_SUN = [35, 36, 37, 38, 33],
  WOOD = [39, 40, 41],
  WOOD_SUN = [40, 41, 32],
  BONDI = [16, 17, 18, 19, 20],
  BONDI_SUN = [17, 18, 19, 20, 21],
  GRAPE = [16, 42, 43, 44],
  TANGERINE = [5, 6, 7, 8],
  TANGERINE_SUN = [6, 7, 8, 9],
  STEEL = [34, 35, 36, 37],
  STEEL_SUN = [35, 36, 37, 38, 46];

module.exports = kit => {
  const { makeBuilder, makeSculpt, KIT: K, courses } = kit;
  return {
    id: 'battle',
    name: 'Crater duel',
    seed: 2,
    loop: L,
    build(seed) {
      const B = makeBuilder(seed, PAL),
        S = K.sculpt(makeSculpt(B)),
        rig = K.rig(B, S),
        M = K.M,
        { clamp, smooth: sm, TAU } = FI;
      // golden hour: a low sun from the front left, warm and strong; no lamps, daylight only
      S.sun = B.norm([-0.6, 0.27, 0.75]);
      S.amb = 0.2;
      S.sky = 0.2;
      S.sunK = 0.95;
      S.res = 0.085;
      S.view = [0, Math.sin(0.5), Math.cos(0.5)];

      // ---------------- small vector helpers
      const UP = [0, 1, 0],
        I = M.id(),
        add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]],
        sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]],
        mad = (a, b, s) => [a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s],
        lerp = (a, b, s) => mad(a, sub(b, a), s),
        dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2],
        cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]],
        len = a => Math.hypot(a[0], a[1], a[2]),
        mv = (A, v) => [A[0] * v[0] + A[1] * v[1] + A[2] * v[2], A[3] * v[0] + A[4] * v[1] + A[5] * v[2], A[6] * v[0] + A[7] * v[1] + A[8] * v[2]],
        // a frame for o.ax whose y runs along dir
        frameY = dir => {
          const V = B.norm(dir),
            U = B.norm(cross(Math.abs(V[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0], V));
          return [U, V, cross(U, V)];
        },
        pickT = (ramp, t) => ramp[clamp(Math.floor(t * ramp.length), 0, ramp.length - 1)],
        // a stick of splats from p to q
        line = (p, q, w, c, a, an) => {
          const d = sub(q, p),
            l = len(d);
          B.stick((p[0] + q[0]) / 2, (p[1] + q[1]) / 2, (p[2] + q[2]) / 2, [d[0] / l, d[1] / l, d[2] / l], l / 2, w, B.P[c], a, an);
        },
        // a glowing wire along an edge, as short sticks so it stays crisp
        wire = (p, q, c) => {
          const n = Math.max(1, Math.ceil(len(sub(q, p)) / 0.12));
          for (let i = 0; i < n; i++) line(lerp(p, q, i / n), lerp(p, q, (i + 1) / n), 0.026, c, 3, { em: true });
        };

      // ---------------- where things stand (the hero camera looks from +z, straight down the middle)
      const RL = 5.8, // the crater's outer edge
        POND = [0, -0.5],
        PR = [1.05, 0.62],
        WL = -0.07, // the water's level
        KZ = -4.6, // the keep, on the back rim
        KY = 0.55,
        BZ = -2.0, // the belt between the cryo pods
        BY = 0.46,
        PODX = 2.45,
        TOAD = [-1.45, 1.8],
        SPIDER = [1.45, 1.8],
        BIKE = [-2.95, 2.75],
        MAP = [2.95, 2.75];

      // ---------------- the land: a flat green crater floor, a red Martian rim, a plinth for the keep, a dip for the pond
      const pondD = (x, z) => Math.hypot((x - POND[0]) / PR[0], (z - POND[1]) / PR[1]);
      const crater = r => (r < 4.2 ? 0 : r < 5.0 ? 0.55 * sm(4.2, 5.0, r) : 0.55 - 0.3 * sm(5.0, 5.9, r));
      const plinth = (x, z) => KY * (1 - sm(1.3, 1.65, Math.abs(x))) * sm(-3.0, -3.6, z);
      const ground = (x, z) =>
        Math.max(crater(Math.hypot(x, z)), plinth(x, z)) + 0.035 * (B.fbm(x * 0.5 + 3, 1.7, z * 0.5, 2) - 0.5) - 0.3 * (1 - sm(0.75, 1.05, pondD(x, z)));
      const gy = ground;
      const under = (x, z) => -0.6 - 0.7 * Math.max(0, 1 - (x * x + z * z) / (RL * RL));
      const rim = a => RL * (1 + 0.02 * Math.sin(5 * a + 1.3) + 0.03 * (B.n3(Math.cos(a) * 1.5 + 4, Math.sin(a) * 1.5 + 2, 1.1) - 0.5));
      const inArena = (x, z) => Math.abs(x) < 2.2 && z > 0.85 && z < 2.75;
      // a battle field's lines: the edge, the half-way line and the middle ring, in the wire's pale cyan
      const arenaLine = (x, z) => {
        const ax = Math.abs(x),
          inside = z > 0.93 && z < 2.67;
        return (
          (ax > 2.05 && ax < 2.12 && inside) ||
          ((Math.abs(z - 0.965) < 0.035 || Math.abs(z - 2.635) < 0.035) && ax < 2.12) ||
          (ax < 0.035 && inside) ||
          Math.abs(Math.hypot(x, z - 1.8) - 0.42) < 0.035
        );
      };
      const inField = (x, z) => Math.abs(x) > 2.42 && Math.abs(x) < 3.95 && z > -1.35 && z < 0.9;
      const ROWS = [2.7, 3.15, 3.6];
      const LAND = {
        r: MARS,
        s: MARS_SUN,
        // the red rock in beds
        mod: (x, y, z) => 0.16 * (B.n3(x * 0.6, y * 6, z * 0.6) - 0.5),
        // the side of the crater shaded in Ben-Day dots: bigger dots where it is darker, as a print shades
        tex: (x, y, z, ny, t) => {
          if (ny > 0.5 || ny < -0.6) return undefined;
          const u = (Math.atan2(z, x) * RL) / 0.15,
            v = y / (0.15 * 0.866),
            row = Math.round(v),
            du = u - (row & 1) * 0.5 - Math.round(u - (row & 1) * 0.5),
            dv = (v - row) * 0.866,
            rad = 0.46 * (1 - clamp(t, 0, 1));
          return du * du + dv * dv < rad * rad ? 29 : undefined;
        },
        top: {
          min: 0.55,
          r: GRASS,
          s: GRASS_SUN,
          blade: { h: 0.07, w: 0.02 },
          tex: (x, y, z, ny, t) => {
            const r = Math.hypot(x, z);
            // the terraforming stops short of the rim, which stays Martian red
            if (r > 4.45 + 0.4 * (B.n3(x * 0.9, z * 0.9, 3.3) - 0.5)) return pickT(MARS_SUN, t);
            if (y < WL + 0.015 && pondD(x, z) < 1.3) return 23;
            if (pondD(x, z) < 1.2) return pickT([40, 41, 32], t);
            if (inArena(x, z)) return arenaLine(x, z) ? 47 : pickT([30, 31, 32, 33], t);
            if (inField(x, z)) {
              const u = (Math.abs(x) - ROWS[0]) / 0.45,
                furrow = Math.abs(u - Math.round(u)) > 0.28;
              return pickT(furrow ? [39, 39, 40] : [40, 41, 32], t);
            }
            return undefined;
          }
        }
      };
      S.solid(
        [0, 0, 0],
        RL * 1.3,
        (x, y, z) => Math.max((y - ground(x, z)) * 0.8, (Math.hypot(x, z) - rim(Math.atan2(z, x))) * 0.9, (under(x, z) - y) * 0.8),
        (rs, f) => {
          const Rm = RL * 1.1;
          let row = 0;
          for (let z = -Rm; z <= Rm; z += rs * 0.87, row++)
            for (let x = -Rm + (row % 2) * rs * 0.5; x <= Rm; x += rs)
              if (Math.hypot(x, z) < rim(Math.atan2(z, x))) {
                f(x, ground(x, z), z);
                f(x, under(x, z), z);
              }
          const n = Math.ceil((TAU * Rm) / rs);
          for (let k = 0; k < n; k++) {
            const a = (k / n) * TAU,
              e = rim(a),
              c = Math.cos(a),
              s = Math.sin(a);
            for (let y = under(c * e, s * e) + rs * 0.5; y < ground(c * e, s * e); y += rs * 0.8) f(c * e, y, s * e);
          }
        },
        LAND,
        { res: 0.085 }
      );
      const MARSROCK = { r: MARS, s: MARS_SUN, b: 0.1 };
      // boulders along the rim, in mirrored pairs
      [0.2, 0.7, -0.3, -0.85].forEach((a, i) => {
        for (const side of [1, -1]) {
          const aa = side > 0 ? a : Math.PI - a,
            e = rim(aa) - 0.75,
            x = Math.cos(aa) * e,
            z = Math.sin(aa) * e,
            r = 0.22 + 0.12 * ((i * 7) % 3) / 2;
          K.grow.rock(S, [x, gy(x, z) + r * 0.25, z], r, MARSROCK, { facets: 8, chip: 0.3, beds: { n: 3 }, seed: 3 + i, res: 0.035 });
        }
      });

      // ---------------- the twenty-sided die under it all, a face up, mirrored about the middle of the view
      const PHI = (1 + Math.sqrt(5)) / 2,
        V0 = [];
      for (const a of [-1, 1]) for (const b of [-1, 1]) V0.push([0, a, b * PHI], [a, b * PHI, 0], [b * PHI, 0, a]);
      const F0 = [];
      for (let i = 0; i < 12; i++)
        for (let j = i + 1; j < 12; j++)
          for (let k = j + 1; k < 12; k++)
            if ([len(sub(V0[i], V0[j])), len(sub(V0[j], V0[k])), len(sub(V0[i], V0[k]))].every(d => Math.abs(d - 2) < 1e-6)) F0.push([i, j, k]);
      const ctr = f => B.norm(add(add(V0[f[0]], V0[f[1]]), V0[f[2]]));
      // one face straight up (it is sunk in the land), and one of the faces below the middle turned square to the camera
      const n0 = ctr(F0[0]),
        tilt = M.rot(B.norm(cross(n0, UP)), Math.acos(clamp(dot(n0, UP), -1, 1))),
        front = F0.map(f => mv(tilt, ctr(f))).find(n => Math.abs(n[1] + 1 / 3) < 0.05),
        turn = M.mul(M.rot(UP, Math.atan2(-front[0], front[2])), tilt);
      const RD = 3.0,
        ds = RD / Math.hypot(1, PHI),
        inR = ds * dot(n0, V0[F0[0][0]]),
        DC = [0, -1.15 - inR, 0],
        DV = V0.map(v => add(DC, mv(turn, v).map(c => c * ds))),
        faces = F0.map(f => {
          const n = B.norm(mv(turn, ctr(f))),
            c = [0, 1, 2].map(k => (DV[f[0]][k] + DV[f[1]][k] + DV[f[2]][k]) / 3);
          return { f, n, c };
        });
      // Ben-Day dots: a hexagonal grid of print-pink dots laid flat on each face
      const dieDots = (x, y, z, ny, t, nx, nz) => {
        const n = [nx, ny, nz],
          e1 = B.norm(cross(n, Math.abs(ny) > 0.9 ? [1, 0, 0] : [0, 1, 0])),
          e2 = cross(n, e1),
          p = sub([x, y, z], DC),
          u = dot(p, e1) / 0.2,
          v = dot(p, e2) / (0.2 * 0.866),
          row = Math.round(v),
          du = u - (row & 1) * 0.5 - Math.round(u - (row & 1) * 0.5),
          dv = (v - row) * 0.866;
        if (du * du + dv * dv < 0.09) return t > 0.55 ? 9 : 8;
        return undefined;
      };
      S.convex(DC, faces.map(F => ({ n: F.n, d: inR })), { r: RED, s: RED_SUN, tex: dieDots }, { res: 0.07 });
      // its numbers, raised in cream: 20 on the face that looks at the camera, and every pair of opposite faces adding to 21
      const hero = faces.reduce((b, F) => (F.n[2] - 0.35 * F.n[1] > b.n[2] - 0.35 * b.n[1] ? F : b), faces[0]);
      const opposite = F => faces.find(G => dot(G.n, F.n) < -0.999);
      const numbered = new Map([
        [hero, 20],
        [opposite(hero), 1]
      ]);
      let next = 2;
      for (const F of faces)
        if (!numbered.has(F)) {
          numbered.set(F, next);
          numbered.set(opposite(F), 21 - next);
          next++;
        }
      const NUM = { r: [12, 13, 14, 15], s: [13, 14, 15, 46] };
      for (const F of faces) {
        if (F.n[1] > 0.99) continue; // the top face is under the land
        const Vup = Math.abs(F.n[1]) > 0.99 ? [0, 0, 1] : B.norm(mad(UP, F.n, -F.n[1])),
          U = B.norm(cross(Vup, F.n));
        S.strokes(K.poly2.text(String(numbered.get(F)), 0.62, { width: 0.11 }), F.c, 0.1, NUM, { ax: [U, Vup, F.n], res: 0.025 });
      }

      // ---------------- the castle keep on the back rim: stone in courses, an arched door, battlements in the shape of the crown
      const KEEPM = { r: STONE, s: STONE_SUN, mod: courses(0.24, 0.14, B.n3, 0.14) },
        DARK = { r: [45, 1, 34] },
        KH = 3.3, // its height to the battlements
        KW = 1.05, // its half width
        KF = KZ + KW; // its front face
      {
        const wall = S.box([0, KY + KH / 2, KZ], [KW, KH / 2, KW], KEEPM, { hold: true, res: 0.05 }),
          doorBox = S.box([0, KY + 0.75, KF], [0.72, 0.77, 0.3], KEEPM, { hold: true }),
          doorArch = S.lathe([0, KY + 1.52, KF - 0.3], 0.6, 0.72, KEEPM, { hold: true, ax: S.AZ });
        S.join('cut', wall, [doorBox, doorArch], { r: 0.02, inner: DARK.r, res: 0.04 });
        /* the dark of the hall inside, and across it the spider's web with FEW written in it: silk drawn flat on the dark, so no edge
           line runs round each letter */
        const hub = [0, KY + 1.15],
          segs = pts => pts.slice(1).map((q, i) => [pts[i][0], pts[i][1], q[0], q[1]]),
          letters = K.poly2.text('FEW', 0.5, { width: 0.1 }).strokes.flatMap(st => segs(st.map(p => [p[0] + hub[0], p[1] + hub[1]]))),
          inDoor = (x, y) => Math.abs(x) < 0.68 && y > KY + 0.05 && (y < KY + 1.52 || Math.hypot(x, y - KY - 1.52) < 0.68),
          NS = 12,
          spokes = [],
          web = [];
        for (let k = 0; k < NS; k++) {
          const a = (k / NS) * TAU + 0.13;
          let r = 0.05;
          while (inDoor(hub[0] + Math.cos(a) * (r + 0.02), hub[1] + Math.sin(a) * (r + 0.02))) r += 0.02;
          spokes.push([hub[0] + Math.cos(a) * r, hub[1] + Math.sin(a) * r]);
          web.push([hub[0], hub[1], spokes[k][0], spokes[k][1]]);
        }
        for (let ring = 1; ring <= 5; ring++) {
          const f = ring / 5.5,
            at = p => [hub[0] + (p[0] - hub[0]) * f, hub[1] + (p[1] - hub[1]) * f];
          for (let k = 0; k < NS; k++) web.push([...at(spokes[k]), ...at(spokes[(k + 1) % NS])]);
        }
        const near = (list, x, y, w) =>
          list.some(([ax, ay, bx, by]) => {
            const dx = bx - ax,
              dy = by - ay,
              s = clamp(((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy), 0, 1);
            return Math.hypot(x - ax - dx * s, y - ay - dy * s) < w;
          });
        const HALL = {
          r: [45, 45, 1],
          tex: (x, y, z, ny, t, nx, nz) => {
            if (nz < 0.9) return undefined;
            if (near(letters, x, y, 0.05)) return 46;
            if (near(web, x, y, 0.016)) return 37;
            return undefined;
          }
        };
        S.box([0, KY + 1.2, KF - 0.27], [0.74, 1.2, 0.02], HALL, { res: 0.02 });
      }
      // a corbel course, then the battlements: a 5 by 5 ring of blocks, two high all round and a third on the corners and middles
      S.box([0, KY + KH + 0.06, KZ], [KW + 0.1, 0.08, KW + 0.1], KEEPM, { res: 0.045 });
      {
        const b = ((KW + 0.1) * 2) / 5;
        for (let i = 0; i < 5; i++)
          for (let j = 0; j < 5; j++) {
            if (i > 0 && i < 4 && j > 0 && j < 4) continue;
            const x = (i - 2) * b,
              z = KZ + (j - 2) * b;
            S.box([x, KY + KH + 0.14 + b * 0.5, z], [b * 0.47, b * 0.5, b * 0.47], KEEPM, { res: 0.04 });
            if (i % 2 === 0 && j % 2 === 0) S.box([x, KY + KH + 0.14 + b * 1.5, z], [b * 0.47, b * 0.5, b * 0.47], KEEPM, { res: 0.04 });
          }
      }
      // arrow slits, and a chimney on the roof
      for (const s of [-1, 1]) {
        S.box([s * 0.62, KY + 2.75, KF + 0.01], [0.05, 0.24, 0.03], DARK, { res: 0.02 });
        S.box([s * (KW + 0.01), KY + 2.1, KZ], [0.03, 0.24, 0.05], DARK, { res: 0.02 });
        S.box([s * 0.5, KY + 2.1, KZ - KW - 0.01], [0.05, 0.24, 0.03], DARK, { res: 0.02 });
      }
      S.box([0.42, KY + KH + 0.45, KZ - 0.42], [0.13, 0.32, 0.13], KEEPM, { res: 0.035 });

      // ---------------- the cryo pods: Y2K translucent blue capsules on grape plinths, a frosted window in each
      const BONDIM = { r: BONDI, s: BONDI_SUN, gloss: { c: 21, at: 0.92, c2: 20, at2: 0.86 } },
        GRAPEM = { r: GRAPE, s: [42, 43, 44, 9], gloss: { c: 9, at: 0.92 } },
        FROST = { r: [19, 20, 21], em: true, v: 0.6 },
        STEELM = { r: STEEL, s: STEEL_SUN },
        podR = t => 0.45 * Math.pow(Math.sin(Math.PI * (0.03 + 0.94 * clamp(t, 0, 1))), 0.32);
      for (const s of [-1, 1]) {
        const px = s * PODX;
        S.lathe([px, -0.05, BZ], 0.24, [0.58, 0.52], GRAPEM, { res: 0.035 });
        S.lathe([px, 0.17, BZ], 1.8, podR, BONDIM, { res: 0.035 });
        S.torus([px, 0.95, BZ], 0.46, 0.035, GRAPEM, { res: 0.025 });
        S.lathe([px, 1.93, BZ], 0.14, [0.14, 0.1], STEELM, { res: 0.025 });
        S.box([px, 1.08, BZ + 0.41], [0.2, 0.44, 0.05], FROST, { res: 0.025, rd: 0.04 });
        S.box([px, 1.08, BZ + 0.405], [0.25, 0.5, 0.04], GRAPEM, { res: 0.025, rd: 0.05 });
        // the mouth the belt runs into
        S.box([px - s * 0.42, BY + 0.12, BZ], [0.08, 0.2, 0.22], GRAPEM, { res: 0.025, rd: 0.03 });
      }

      // ---------------- the belt between the pods, and the stamp's gantry over its middle
      S.box([0, BY - 0.04, BZ], [2.05, 0.04, 0.24], { r: [45, 1, 2], tex: (x, y, z, ny) => (ny > 0.5 ? (((x + 9) / 0.16) % 1 < 0.2 ? 45 : 2) : undefined) }, { res: 0.03 });
      S.box([0, BY - 0.15, BZ], [2.05, 0.06, 0.28], STEELM, { res: 0.035 });
      for (const s of [-1, 1]) S.tube([[-2.05, BY + 0.03, BZ + s * 0.27], [2.05, BY + 0.03, BZ + s * 0.27]], 0.025, 0.025, BONDIM, { res: 0.025 });
      for (const x of [-1.5, -0.5, 0.5, 1.5]) for (const s of [-1, 1]) S.box([x, (BY - 0.2) / 2, BZ + s * 0.22], [0.03, (BY - 0.2) / 2 + 0.03, 0.03], STEELM, { res: 0.025 });
      const TANGM = { r: TANGERINE, s: TANGERINE_SUN, gloss: { c: 9, at: 0.92 } };
      for (const s of [-1, 1]) S.box([0, 0.6, BZ + s * 0.36], [0.05, 0.6, 0.05], TANGM, { res: 0.025, rd: 0.02 });
      S.box([0, 1.15, BZ], [0.09, 0.06, 0.42], TANGM, { res: 0.025, rd: 0.03 });

      // ---------------- the trainer's bicycle, Y2K tangerine, parked on its stand with a bundle of papers in the basket
      const CHROME = { r: [35, 36, 37, 38], s: [36, 37, 38, 46], gloss: { c: 46, at: 0.9 } },
        TYRE = { r: [45, 1, 2] },
        PAPER = {
          r: [36, 37, 38, 15],
          s: [37, 38, 15, 46],
          // the edges of the sheets on the sides, columns of print on the top
          tex: (x, y, z, ny, t) => {
            if (ny > 0.7) return Math.abs(((z * 11 + 0.3) % 1) - 0.5) < 0.2 && ((x * 7) % 1) > 0.1 ? 36 : undefined;
            return ((y * 55) % 1) < 0.3 ? 36 : undefined;
          }
        },
        TWINE = { r: [10, 11, 41] };
      const bundle = (c, yaw, opt) => {
        const F = [
          [Math.cos(yaw), 0, -Math.sin(yaw)],
          [0, 1, 0],
          [Math.sin(yaw), 0, Math.cos(yaw)]
        ];
        S.box(c, [0.15, 0.09, 0.12], PAPER, Object.assign({ ax: F, res: 0.022, rd: 0.01 }, opt));
        S.box(c, [0.153, 0.093, 0.014], TWINE, Object.assign({ ax: F, res: 0.015 }, opt));
        S.box(c, [0.014, 0.093, 0.123], TWINE, Object.assign({ ax: F, res: 0.015 }, opt));
      };
      {
        const z = BIKE[1],
          bx = BIKE[0],
          by = gy(bx, z),
          wy = by + 0.32,
          RH = [bx - 0.42, wy, z],
          FH = [bx + 0.42, wy, z],
          BB = [bx - 0.02, wy - 0.02, z],
          ST = [bx - 0.17, wy + 0.45, z],
          HT = [bx + 0.3, wy + 0.47, z],
          HB = [bx + 0.35, wy + 0.3, z],
          AXZ = frameY([0, 0, 1]);
        for (const h of [RH, FH]) {
          S.torus(h, 0.285, 0.035, TYRE, { ax: AXZ, res: 0.02 });
          S.torus(h, 0.25, 0.014, CHROME, { ax: AXZ, res: 0.016 });
          S.ball(h, 0.035, CHROME, { res: 0.015 });
          for (let k = 0; k < 8; k++) {
            const a = (k / 8) * TAU;
            S.tube([h, [h[0] + Math.cos(a) * 0.245, h[1] + Math.sin(a) * 0.245, z]], 0.008, 0.008, STEELM, { res: 0.015 });
          }
        }
        const FRAME = { r: TANGERINE, s: TANGERINE_SUN, gloss: { c: 9, at: 0.9 } };
        for (const [p, q] of [
          [BB, ST],
          [ST, HT],
          [BB, HB],
          [BB, RH],
          [ST, RH],
          [HB, HT]
        ])
          S.tube([p, q], 0.036, 0.036, FRAME, { res: 0.02 });
        S.tube([HB, FH], 0.02, 0.016, CHROME, { res: 0.018 });
        S.tube([ST, add(ST, [-0.02, 0.09, 0])], 0.016, 0.016, CHROME, { res: 0.016 });
        S.ball(add(ST, [-0.04, 0.12, 0]), [0.12, 0.035, 0.055], TYRE, { res: 0.018 });
        const bar = add(HT, [-0.05, 0.12, 0]);
        S.tube([HT, bar], 0.016, 0.016, CHROME, { res: 0.016 });
        S.tube([add(bar, [0, 0, -0.22]), add(bar, [0, 0, 0.22])], 0.014, 0.014, CHROME, { res: 0.016 });
        for (const s of [-1, 1]) S.ball(add(bar, [0, 0, s * 0.22]), [0.025, 0.025, 0.05], TYRE, { res: 0.014 });
        S.torus(BB, 0.08, 0.012, CHROME, { ax: AXZ, res: 0.015 });
        S.tube([BB, [bx - 0.12, by + 0.01, z - 0.13]], 0.012, 0.01, CHROME, { res: 0.015 });
        // the basket over the front wheel, and a bundle of papers in it
        const BK = [FH[0] + 0.04, wy + 0.42, z];
        S.box(BK, [0.15, 0.012, 0.16], CHROME, { res: 0.016 });
        for (const s of [-1, 1]) {
          S.box(add(BK, [s * 0.15, 0.07, 0]), [0.008, 0.07, 0.16], CHROME, { res: 0.014 });
          S.box(add(BK, [0, 0.07, s * 0.16]), [0.15, 0.07, 0.008], CHROME, { res: 0.014 });
        }
        S.tube([add(BK, [-0.05, 0, 0]), HB], 0.01, 0.01, CHROME, { res: 0.014 });
        bundle(add(BK, [0, 0.1, 0]), 0.1);
      }
      // stacks of newspapers either side of the field, as left about
      for (const s of [-1, 1]) {
        const x = s * 3.5,
          z = 1.7,
          y = gy(x, z) - 0.01;
        for (let k = 0; k < 3; k++) bundle([x, y + 0.09 + k * 0.18, z], 0.3 * Math.sin(k * 2.1 + s));
        bundle([x + s * 0.32, y + 0.09, z + 0.08], 0.5 * s);
        bundle([x + s * 0.32, y + 0.27, z + 0.06], -0.2 * s);
      }

      // ---------------- the map with an X, on an easel turned to the field
      {
        const z = MAP[1],
          mx = MAP[0],
          by = gy(mx, z),
          Fm = B.norm([-0.3, 0, 1]),
          tl = 0.22,
          Nb = B.norm(add(Fm.map(v => v * Math.cos(tl)), [0, Math.sin(tl), 0])),
          Vb = B.norm(add([0, Math.cos(tl), 0], Fm.map(v => -v * Math.sin(tl)))),
          Ub = cross(Vb, Nb),
          C = [mx, by + 0.78, z],
          HW = 0.72,
          HH = 0.52;
        const MAPM = {
          r: WOOD,
          s: WOOD_SUN,
          tex: (x, y, zz, ny, t, nx, nz) => {
            if (nx * Nb[0] + ny * Nb[1] + nz * Nb[2] < 0.6) return undefined;
            const d = sub([x, y, zz], C),
              u = dot(d, Ub),
              v = dot(d, Vb);
            if (Math.abs(u) > HW - 0.04 || Math.abs(v) > HH - 0.04) return 11;
            // a red X, thick enough to read across the crater
            const xu = u - 0.24,
              xv = v + 0.08;
            if (Math.max(Math.abs(xu), Math.abs(xv)) < 0.15 && (Math.abs(xu - xv) < 0.05 || Math.abs(xu + xv) < 0.05)) return 6;
            // a dashed path from the far shore to it
            const pv = 0.16 * Math.sin(u * 4.5 + 1.2) - 0.02;
            if (u > -0.42 && u < 0.12 && Math.abs(v - pv) < 0.025 && ((u * 9 + 9) % 1) < 0.55) return 5;
            // the island, and the sea round it
            const isl = (u / 0.5) ** 2 + (v / 0.34) ** 2 + 0.5 * (B.n3(u * 4 + 2, v * 4, 1.3) - 0.5);
            if (isl > 1.0) return isl > 1.12 ? pickT([18, 19, 20], t) : 11;
            return pickT([33, 14, 15], t);
          }
        };
        S.box(C, [HW, HH, 0.02], MAPM, { ax: [Ub, Vb, Nb], res: 0.02 });
        const top = mad(C, Vb, HH),
          WOODM = { r: WOOD, s: WOOD_SUN };
        for (const s of [-1, 1]) S.tube([mad(top, Ub, s * 0.3), [mx + Ub[0] * s * 0.45 + Fm[0] * 0.18, by - 0.02, z + Ub[2] * s * 0.45 + Fm[2] * 0.18]], 0.022, 0.02, WOODM, { res: 0.02 });
        S.tube([top, [mx - Fm[0] * 0.5, by - 0.02, z - Fm[2] * 0.5]], 0.022, 0.02, WOODM, { res: 0.02 });
        S.box(mad(C, Vb, -HH - 0.03), [HW * 0.9, 0.025, 0.05], WOODM, { ax: [Ub, Vb, Nb], res: 0.02 });
      }

      // ---------------- stalactites under the land round the die, and a few hanging from the die's own lowest faces
      S.ready();
      K.form.drips(S, { box: [-5.4, 5.4, -5.4, 5.4], y: -2.0, n: 150, gap: 0.42, len: [0.4, 1.5], r: 0.18, mites: false, mat: MARSROCK, seed: 9, res: 0.04 });
      K.form.drips(S, { box: [-1.9, 1.9, -1.9, 1.9], y: DC[1] - inR - 1.5, n: 40, gap: 0.4, len: [0.3, 0.9], r: 0.2, mites: false, mat: MARSROCK, seed: 4, res: 0.04 });

      S.bake();

      // ---------------- drawn by hand on the still world
      // the die's edges as glowing wire, and the keep's corners
      {
        const topY = DC[1] + inR - 0.01;
        for (let i = 0; i < 12; i++)
          for (let j = i + 1; j < 12; j++) {
            if (Math.abs(len(sub(V0[i], V0[j])) - 2) > 1e-6) continue;
            if (DV[i][1] > topY && DV[j][1] > topY) continue;
            const o = B.norm(sub(lerp(DV[i], DV[j], 0.5), DC)),
              p = mad(DV[i], o, 0.03),
              q = mad(DV[j], o, 0.03);
            wire(p, q, 47);
          }
        for (const sx of [-1, 1])
          for (const sz of [-1, 1]) wire([sx * (KW + 0.015), KY + 0.05, KZ + sz * (KW + 0.015)], [sx * (KW + 0.015), KY + KH, KZ + sz * (KW + 0.015)], 47);
      }
      // the pond: flat blues in soft patches, a pale line at the bank, glints that wink; lily pads with a pink flower
      {
        const step = 0.06;
        for (let x = POND[0] - 1.2; x < POND[0] + 1.2; x += step)
          for (let z = POND[1] - 0.8; z < POND[1] + 0.8; z += step * 0.87) {
            const xx = x + (Math.round((z - POND[1]) / (step * 0.87)) % 2) * step * 0.5,
              g = ground(xx, z);
            if (g > WL - 0.005) continue;
            const shore = g > WL - 0.05,
              v = B.fbm(xx * 1.4 + 7, z * 1.4, 1.7, 2),
              c = shore ? 20 : v > 0.6 ? 20 : v > 0.47 ? 19 : v < 0.36 ? 17 : 18,
              glint = !shore && Math.sin(z * 9 + 2 * Math.sin(xx * 2.1)) > 0.9 && B.n3(xx * 2, z * 2, 4) > 0.45;
            B.disc(xx, WL, z, UP, step * 0.62, 0.012, B.P[glint ? 21 : c], 3, glint ? { em: true, k: 4, ph: B.rr(0, 6), sp: B.rr(2, 4) } : { em: true });
          }
        for (let i = 0; i < 6; i++) {
          const a = (i / 6) * TAU + 0.4,
            q = 0.45 + 0.25 * (i % 2),
            x = POND[0] + Math.cos(a) * q * PR[0],
            z = POND[1] + Math.sin(a) * q * PR[1],
            s = 0.12;
          for (let k = 0; k < 16; k++) {
            const t = B.rr(0, TAU),
              d = Math.sqrt(B.rr(0, 1)) * s;
            if (Math.abs(((t - a + 9.42) % 6.283) - 3.14) < 0.4) continue;
            B.disc(x + Math.cos(t) * d, WL + 0.01, z + Math.sin(t) * d, UP, 0.04, 0.01, B.P[d > s * 0.7 ? 24 : 25], 3);
          }
          if (i % 2 === 0) B.iso(x, WL + 0.04, z, 0.04, B.P[44], 3);
        }
      }
      // corn in rows either side of the field: stalks, arching leaves, cobs in their husks, tassels; the leaves sway
      {
        let sd = 0;
        const sunny = d => d[0] * S.sun[0] + d[2] * S.sun[2] > 0;
        for (const s of [-1, 1])
          for (const rx of ROWS)
            for (let z = -1.1; z <= 0.65; z += 0.29) {
              const x = s * rx + B.rr(-0.04, 0.04),
                zz = z + B.rr(-0.04, 0.04),
                y0 = gy(x, zz),
                H = B.rr(1.35, 1.7),
                sw = { k: 11, ph: B.rr(0, 6), sp: 1.9, rg: 0.018 },
                at = h => [x + 0.02 * Math.sin(sd) * h, y0 + h, zz + 0.02 * Math.cos(sd) * h];
              sd += 1.7;
              for (let i = 0; i < 4; i++) line(at((H * i) / 4), at((H * (i + 1)) / 4), 0.04, [23, 24, 24, 25][i], 3, sw);
              // long leaves that arch out and droop
              for (let j = 0; j < 7; j++) {
                const a = sd + j * 2.4,
                  d = [Math.cos(a), 0, Math.sin(a)],
                  p0 = at(H * (0.15 + 0.1 * j)),
                  p1 = mad(add(p0, [0, 0.16, 0]), d, 0.22),
                  p2 = mad(add(p1, [0, -0.12, 0]), d, 0.2);
                line(p0, p1, 0.032, sunny(d) ? 26 : 24, 3, sw);
                line(p1, p2, 0.024, sunny(d) ? 27 : 25, 3, sw);
              }
              // cobs held against the stalk in green husks, a little yellow showing at the tip
              for (let c = 0; c < (H > 1.5 ? 2 : 1); c++) {
                const a = sd + c * 3.1 + 0.8,
                  d = [Math.cos(a), 0, Math.sin(a)],
                  p = mad(at(H * (0.42 + 0.14 * c)), d, 0.07),
                  ax = B.norm([d[0] * 0.4, 1, d[2] * 0.4]);
                B.stick(p[0], p[1], p[2], ax, 0.13, 0.05, B.P[sunny(d) ? 26 : 25], 3, sw);
                const q = mad(mad(p, ax, 0.1), d, 0.02);
                B.stick(q[0], q[1], q[2], ax, 0.06, 0.036, B.P[sunny(d) ? 14 : 13], 3, sw);
              }
              // the tassel at the top
              const top = at(H);
              for (let k = 0; k < 5; k++) {
                const a = sd + k * 1.3;
                line(top, add(top, [Math.cos(a) * 0.1, 0.12, Math.sin(a) * 0.1]), 0.012, k % 2 ? 11 : 12, 3, sw);
              }
            }
      }
      // in each pod's frosted window, the dark shape of a frozen toad; lights that blink on the plinths; cold vapour from the vents
      for (const s of [-1, 1]) {
        const px = s * PODX,
          fz = BZ + 0.465;
        B.disc(px, 1.0, fz, [0, 0, 1], 0.13, 0.01, B.P[23], 3);
        B.disc(px, 0.86, fz, [0, 0, 1], 0.17, 0.01, B.P[23], 3);
        for (const e of [-1, 1]) B.disc(px + e * 0.07, 1.1, fz + 0.002, [0, 0, 1], 0.05, 0.01, B.P[22], 3);
        B.iso(px - 0.12, 0.2, BZ + 0.56, 0.03, B.P[6], 3, { em: true, k: 4, ph: 0, sp: 3 });
        B.iso(px + 0.12, 0.2, BZ + 0.56, 0.03, B.P[26], 3, { em: true, k: 4, ph: 2, sp: 2 });
        for (let i = 0; i < 40; i++)
          B.iso(px + B.rr(-0.05, 0.05), 2.1, BZ + B.rr(-0.05, 0.05), 0.08, B.P[B.pick([20, 21, 21, 3])], 0.45, { nd: true, k: 3, ph: B.R(), sp: 0.4, rg: 1.4, ex: 1.8 });
      }
      // smoke from the keep's chimney
      for (let i = 0; i < 50; i++)
        B.iso(0.42 + B.rr(-0.05, 0.05), KY + KH + 0.8, KZ - 0.42 + B.rr(-0.05, 0.05), 0.1, B.P[B.pick([2, 3, 3, 36])], 0.55, { nd: true, k: 3, ph: B.R(), sp: 0.5, rg: 2.2, ex: 2.2 });

      // ---------------- what moves: the two monsters, the belt's papers and the stamp, made in a bake of their own
      // the toad, three-quarters to the camera, facing the spider; its right arm (the camera side) throws
      const TS = 1.55,
        T0 = [TOAD[0], gy(TOAD[0], TOAD[1]) - 0.02, TOAD[1]],
        TA = 0.42,
        TF = [Math.cos(TA), 0, Math.sin(TA)],
        TR = [-TF[2], 0, TF[0]],
        TAX = [TF, UP, TR],
        TP = l => [T0[0] + (TF[0] * l[0] + TR[0] * l[2]) * TS, T0[1] + l[1] * TS, T0[2] + (TF[2] * l[0] + TR[2] * l[2]) * TS];
      const SKIN = { r: GRASS, s: [23, 24, 25, 26, 27], tex: (x, y, z, ny, t) => (ny < -0.4 ? pickT([25, 26, 27], t + 0.3) : undefined) },
        LIPS = { r: [5, 6, 7], s: [6, 7, 8] },
        EYE = { r: [37, 38, 15], s: [38, 15, 46] },
        INK = { r: [45, 45, 1] },
        GOLD = { r: [11, 12, 13], s: [12, 13, 14, 15], gloss: { c: 15, at: 0.93 } };
      {
        const G = S.grp(0.07 * TS),
          o = extra => Object.assign({ res: 0.03, tag: 'toad', whole: true, ax: TAX }, extra || {}),
          og = () => o(G);
        S.ball(TP([-0.08, 0.4, 0]), [0.55 * TS, 0.4 * TS, 0.5 * TS], SKIN, og());
        S.ball(TP([0.3, 0.58, 0]), [0.36 * TS, 0.3 * TS, 0.46 * TS], SKIN, og());
        for (const s of [-1, 1]) {
          S.ball(TP([-0.32, 0.26, s * 0.42]), [0.3 * TS, 0.22 * TS, 0.2 * TS], SKIN, og());
          S.ball(TP([-0.05, 0.04, s * 0.6]), [0.2 * TS, 0.05 * TS, 0.12 * TS], SKIN, o());
          // wide eyes: big whites, small pupils looking at the spider
          S.ball(TP([0.36, 0.86, s * 0.21]), 0.16 * TS, EYE, o({ res: 0.022 }));
          S.ball(TP([0.49, 0.89, s * 0.21]), 0.055 * TS, INK, o({ res: 0.015 }));
        }
        S.tube([TP([0.28, 0.42, -0.36]), TP([0.45, 0.06, -0.44])], 0.07 * TS, 0.06 * TS, SKIN, o());
        S.ball(TP([0.48, 0.04, -0.46]), [0.1 * TS, 0.04 * TS, 0.09 * TS], SKIN, o());
        // the swamp toad's big lips
        S.tube(
          [
            [0.4, 0.53, -0.42],
            [0.565, 0.5, -0.3],
            [0.66, 0.5, 0],
            [0.565, 0.5, 0.3],
            [0.4, 0.53, 0.42]
          ].map(TP),
          0.04 * TS,
          0.04 * TS,
          LIPS,
          o({ res: 0.02 })
        );
        // the Regents crown on its back: a 5 by 5 ring of gold blocks, two high, a third on the corners and middles
        const b = 0.09;
        for (let i = 0; i < 5; i++)
          for (let j = 0; j < 5; j++) {
            if (i > 0 && i < 4 && j > 0 && j < 4) continue;
            for (let k = 0; k < (i % 2 === 0 && j % 2 === 0 ? 3 : 2); k++)
              S.box(TP([-0.1 + (i - 2) * b, 0.8 + (k + 0.5) * b, (j - 2) * b]), [b * 0.45 * TS, b * 0.45 * TS, b * 0.45 * TS], GOLD, o({ res: 0.016 }));
          }
      }
      const SH = TP([0.22, 0.46, 0.4]),
        HAND = TP([0.5, 0.04, 0.5]);
      {
        const o = { res: 0.028, tag: 'toadArm', whole: true };
        S.ball(SH, 0.09 * TS, SKIN, o);
        S.tube([SH, TP([0.38, 0.28, 0.5]), HAND], 0.075 * TS, 0.06 * TS, SKIN, o);
        S.ball(HAND, [0.1 * TS, 0.045 * TS, 0.09 * TS], SKIN, Object.assign({ ax: TAX }, o));
      }
      // the spider, a grey barn spider with print dots on its back, mirrored across the field
      const SS = 1.5,
        S0 = [SPIDER[0], gy(SPIDER[0], SPIDER[1]) - 0.02, SPIDER[1]],
        SA = Math.PI - 0.42,
        SF = [Math.cos(SA), 0, Math.sin(SA)],
        SR = [-SF[2], 0, SF[0]],
        SAX = [SF, UP, SR],
        SP = l => [S0[0] + (SF[0] * l[0] + SR[0] * l[2]) * SS, S0[1] + l[1] * SS, S0[2] + (SF[2] * l[0] + SR[2] * l[2]) * SS];
      const ABD = {
          r: STONE,
          s: STONE_SUN,
          tex: (x, y, z) => {
            const f = v => v / 0.1 - Math.round(v / 0.1);
            return Math.hypot(f(x), f(y), f(z)) < 0.27 ? 38 : undefined;
          }
        },
        BROWN = { r: WOOD, s: WOOD_SUN },
        LEGM = { r: [45, 1, 2], s: [1, 2, 3, 36] };
      {
        const o = extra => Object.assign({ res: 0.028, tag: 'spider', whole: true, ax: SAX }, extra || {});
        S.ball(SP([-0.36, 0.5, 0]), [0.36 * SS, 0.3 * SS, 0.32 * SS], ABD, o());
        S.ball(SP([-0.06, 0.42, 0]), [0.08 * SS, 0.07 * SS, 0.07 * SS], BROWN, o());
        S.ball(SP([0.07, 0.4, 0]), [0.2 * SS, 0.14 * SS, 0.17 * SS], BROWN, o());
        for (const s of [-1, 1]) {
          S.ball(SP([0.24, 0.47, s * 0.055]), 0.04 * SS, INK, o({ res: 0.014 }));
          S.ball(SP([0.2, 0.5, s * 0.11]), 0.025 * SS, INK, o({ res: 0.012 }));
          S.tube([SP([0.24, 0.38, s * 0.04]), SP([0.29, 0.27, s * 0.03])], 0.025 * SS, 0.012 * SS, INK, o({ res: 0.014 }));
        }
      }
      const LEGS = [];
      for (let k = 0; k < 8; k++) {
        const sd = k < 4 ? 1 : -1,
          idx = k % 4,
          al = [0.95, 0.35, -0.3, -0.85][idx],
          hipL = [0.1 - idx * 0.05, 0.42, sd * 0.13],
          dir = [Math.sin(al), 0, sd * Math.cos(al)],
          knee = add(mad(hipL, dir, 0.42), [0, 0.36, 0]),
          foot = mad(hipL, dir, 0.9);
        foot[1] = 0.02;
        const hip = SP(hipL),
          tag = 'leg' + k,
          o = { res: 0.022, tag, whole: true };
        S.tube([hip, SP(knee), SP(foot)], 0.045 * SS, 0.022 * SS, LEGM, o);
        S.ball(SP(knee), 0.045 * SS, LEGM, o);
        const dW = B.norm([SF[0] * dir[0] + SR[0] * dir[2], 0, SF[2] * dir[0] + SR[2] * dir[2]]);
        LEGS.push({ tag, hip, lift: cross(dW, UP), front: idx < 2 ? 1 - idx * 0.6 : 0, ph: k * 1.3 });
      }
      // newspaper bundles riding the belt, and the stamp over it
      const NP = 5,
        PAPERS = [];
      for (let k = 0; k < NP; k++) {
        const x = -2.4 + ((k + 0.5) * 4.8) / NP,
          tag = 'paper' + k;
        bundle([x, BY + 0.09, BZ], 0, { tag, whole: true });
        PAPERS.push({ x, tag });
      }
      const STAMP = [0, 0.86, BZ];
      S.lathe([0, 0.86, BZ], 0.28, 0.03, STEELM, { res: 0.018, tag: 'stamp', whole: true });
      S.box([0, 0.83, BZ], [0.13, 0.04, 0.13], { r: RED, s: RED_SUN }, { res: 0.02, rd: 0.01, tag: 'stamp', whole: true });

      S.bake();

      // ---------------- drawn by hand on the parts that move
      rig.own('toad', () => {
        for (const s of [-1, 1]) {
          const p = TP([0.53, 0.92, s * 0.23]);
          B.iso(p[0], p[1], p[2], 0.018, B.P[46], 3, { em: true });
        }
      });
      // the spark: a white-hot core in a yellow ball, a soft glow, and forks of lightning that flicker. It and the burst are built
      // where they hide between throws, in the middle of the die
      const HIDE = DC;
      const spark = (tag, s, bolts) =>
        rig.own(tag, () => {
          const c = HIDE;
          B.iso(c[0], c[1], c[2], 0.2 * s, B.P[13], 3, { em: true });
          B.iso(c[0], c[1], c[2], 0.12 * s, B.P[46], 3, { em: true });
          B.iso(c[0], c[1], c[2], 0.5 * s, B.P[14], 0.45, { em: true, nd: true, k: 7, ph: 0, sp: 6 });
          for (let i = 0; i < bolts; i++) {
            const d = B.randDir();
            let p = c;
            for (let j = 0; j < 3; j++) {
              const q = mad(p, B.norm(add(d, B.randDir().map(v => v * 0.7))), 0.14 * s);
              line(p, q, 0.022, j % 2 ? 21 : 14, 3, { em: true, nd: true, k: 1, ph: B.rr(0, 6), sp: 20 });
              p = q;
            }
          }
        });
      spark('spark', 1, 10);
      const TRAIL = [0.75, 0.55, 0.4];
      TRAIL.forEach((s, j) => spark('trail' + j, s, 0));
      // the burst where it lands: rays of white, yellow and cyan, a hot middle and a ring of sparks
      rig.own('burst', () => {
        const c = HIDE;
        B.iso(c[0], c[1], c[2], 0.2, B.P[46], 3, { em: true });
        B.iso(c[0], c[1], c[2], 0.7, B.P[13], 0.4, { em: true, nd: true, k: 7, ph: 0, sp: 9 });
        for (let i = 0; i < 20; i++) {
          const d = B.randDir(),
            l = B.rr(0.35, 0.85);
          line(mad(c, d, 0.1), mad(c, d, l), 0.03, [46, 14, 21, 13][i % 4], 3, { em: true, nd: true, k: 1, ph: B.rr(0, 6), sp: 25 });
        }
        for (let i = 0; i < 14; i++) {
          const a = (i / 14) * TAU;
          B.iso(c[0] + Math.cos(a) * 0.75, c[1] + Math.sin(a) * 0.75, c[2], 0.045, B.P[i % 2 ? 21 : 14], 3, { em: true, nd: true, k: 4, ph: i, sp: 12 });
        }
      });

      const W = B.finish({
        cam: { target: [0, 0, 0], dist: 21, pitch: 0.5, yaw: 0 },
        detail: 22,
        dither: 0.25,
        radius: 9,
        palName: 'Dots',
        fog: { c: 0, start: 0.78, max: 0.22 },
        outline: { c: 47, edge: 0.45 },
        ao: { k: 0.4, range: 0.5 }
      });
      FI.loopable(W, L);
      const st = K.stage(W);
      rig.bind(st);

      // ---------------- the loop. Twice in it the toad winds its arm right round and throws a spark, which lands on the spider in a
      // burst; the spider rears back and settles. The belt carries its papers one full length; the stamp comes down on each.
      const ease = x => (x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x)),
        win = (u, a, b, c, d) => ease((u - a) / (b - a)) * (1 - ease((u - c) / (d - c))),
        CYCLE = 4,
        // the toad at a moment: its lean and hop about its feet, and its arm's turn (a whole turn by the end of the throw)
        toad = t => {
          const u = (((t + 0.5) % CYCLE) + CYCLE) % CYCLE,
            arm = -3.0 * ease((u - 0.1) / 0.65) - 2.3 * ease((u - 0.85) / 0.2) - (TAU - 5.3) * ease((u - 1.05) / 0.55),
            lean = 0.15 * win(u, 0.1, 0.75, 0.85, 1.0) - 0.22 * win(u, 0.85, 1.0, 1.1, 1.8),
            hop = 0.03 * (0.5 - 0.5 * Math.cos((8 * TAU * t) / L)) + 0.16 * win(u, 0.9, 1.05, 1.1, 1.45),
            A = M.rot(TR, lean),
            Ra = M.rot(TR, arm),
            p = add(T0, [0, hop, 0]),
            at = v => add(mv(A, sub(v, T0)), p),
            hand = at(add(SH, mv(Ra, sub(HAND, SH))));
          return { u, A, Ra, p, hand };
        },
        TG = SP([0.24, 0.5, 0]),
        held = h => add(h, [0, 0.1 * TS, 0]),
        // where the spark is at cycle time u of the throw that started at time t0, or null while it is hidden
        sparkAt = (t, u) => {
          if (u >= 0.2 && u < 1.0) return held(toad(t).hand);
          if (u >= 1.0 && u < 2.0) {
            const s = u - 1.0,
              from = held(toad(t - s).hand);
            return add(lerp(from, TG, s), [0, 1.1 * 4 * s * (1 - s), 0]);
          }
          return null;
        };
      st.add({
        update(dt, t) {
          const w = (TAU * t) / L,
            T = toad(t),
            u = T.u;
          rig.set('toad', T.A, T0, T.p);
          rig.child('toadArm', 'toad', T.Ra, SH);
          const sp = sparkAt(t, u);
          rig.set('spark', sp ? M.rot(UP, 9 * u) : I, HIDE, sp || HIDE);
          TRAIL.forEach((s, j) => {
            const d = 0.06 * (j + 1),
              ud = u - d,
              q = ud >= 1.0 ? sparkAt(t - d, ud) : null;
            rig.set('trail' + j, I, HIDE, q || HIDE);
          });
          const hit = u >= 2.0 && u < 2.85;
          rig.set('burst', hit ? M.rot(SF, 3 * u) : I, HIDE, hit ? TG : HIDE);
          // the spider: sways while it waits, rears up and shakes when the spark lands, then settles
          const rear = 0.5 * win(u, 2.0, 2.15, 2.35, 3.3),
            shake = 0.12 * Math.sin(30 * (u - 2.0)) * win(u, 2.0, 2.05, 2.3, 2.9),
            sway = 0.05 * Math.sin(4 * w),
            pivot = SP([-0.7, 0, 0]);
          rig.set('spider', M.mul(M.rot(UP, shake), M.rot(SR, rear)), pivot, mad(pivot, SR, sway));
          for (const g of LEGS) {
            const tap = 0.12 * Math.sin(8 * w + g.ph),
              lift = g.front * 1.4 * rear + 0.08 * Math.max(0, Math.sin(8 * w + g.ph));
            rig.child(g.tag, 'spider', M.mul(M.rot(UP, tap), M.rot(g.lift, lift)), g.hip);
          }
          for (const it of PAPERS) {
            const x = -2.4 + ((((it.x + 2.4 + (4.8 * t) / L) % 4.8) + 4.8) % 4.8);
            rig.set(it.tag, I, [it.x, BY, BZ], [x, BY, BZ]);
          }
          rig.set('stamp', I, STAMP, add(STAMP, [0, -0.15 * Math.pow(0.5 + 0.5 * Math.cos(5 * w), 6), 0]));
          rig.apply();
        }
      });
      return W;
    }
  };
};
