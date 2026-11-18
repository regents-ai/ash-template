/* Campfire: a robot factory on a floating rock at blue hour, painted in rain-neon colours.
   Round a campfire in the yard a robot night owl in a flower crown tells a story with its wings, its eyes glowing; a frog, two factory
   robots and an old television listen from stacks of books, and a 1989 camcorder on a tripod films it. The Power Glove the story is
   about turns on a stone plinth. Behind them stand the factory, its INSERT COIN sign buzzing on the roof, and a giant robot head half
   sunk in the snow; to the left a chain-reaction marble run ticks over beside an aquarium; to the right a lava pool where lotus float
   runs off the edge as a lava fall, and a traffic light changes by the rim. Snow falls, a rainbow stands behind, icicles hang
   underneath, and the Regents crown is carved into the rock below the rim. Seeded: it builds the same way every time.
   It only calls the ink-studio toolkit (handed in as kit) and the shared island helpers; none of the toolkit's code is copied here. */
const FI = require('./floating-island.cjs');

const L = 8; // seconds in one loop: every motion comes round in this time

// 48 colours, each ramp shifting hue as it goes from dark to light
const PAL = [
  0x1f4ea6, 0x173c8a, 0x3f72c8, 0x8fb4ea, // 0-3   clear blue-hour sky, deep to pale
  0x090c1e, 0x121a36, 0x1c2a4e, 0x2a3d66, 0x41587e, 0x667e9c, 0x9aaec4, // 4-10  wet slate and steel, indigo to grey-blue
  0x0a3540, 0x0f5c64, 0x17908e, 0x36cdc2, 0xa6f7e8, // 11-15 cyan neon, deep teal to mint
  0x34093c, 0x6a1262, 0xb21f80, 0xf34ca2, 0xffaad2, // 16-20 magenta neon, plum to pink
  0x3c0d12, 0x7c1d16, 0xc43b16, 0xf4741e, 0xffb43c, 0xffe48e, // 21-26 fire and lava, maroon to straw
  0x0b2523, 0x123f30, 0x1d6a3c, 0x3e9a46, 0x8ed25c, // 27-31 greens, teal to lime
  0x3d5f9e, 0x6e9ad0, 0xb6d8f2, 0xf0fbff, // 32-35 ice and snow, blue to white
  0x1d1120, 0x40222a, 0x6c3a30, 0x9c6444, 0xc8a07a, 0xf2e2c0, // 36-41 wood and paper, plum to cream
  0x520a1a, 0xff2d48, // 42-43 red lamp, dark and lit
  0x0a4a30, 0x46ffa0, // 44-45 green lamp, dark and lit
  0x4b2e9a, 0xa98cff // 46-47 violet
];

const ROCK = [4, 5, 6, 7, 8, 9],
  STEEL = [5, 6, 7, 8, 9, 10],
  DARK = [4, 5, 6],
  CYAN = [11, 12, 13, 14, 15],
  PINK = [16, 17, 18, 19, 20],
  FIRE = [21, 22, 23, 24, 25, 26],
  GRASS = [27, 28, 29, 30],
  SNOW = [32, 33, 34, 35],
  WOOD = [36, 37, 38, 39],
  PAPER = [39, 40, 41],
  EARTH = [4, 36, 37, 38],
  COVERS = [[21, 22, 23], [11, 12, 13], [16, 17, 18], [27, 28, 29], [36, 37, 38], [22, 23, 24], [46, 47], [12, 13, 14]];

module.exports = kit => {
  const { makeBuilder, makeSculpt, KIT: K, flame } = kit;
  return {
    id: 'campfire',
    name: 'Campfire stories',
    seed: 31,
    loop: L,
    build(seed) {
      const B = makeBuilder(seed, PAL),
        S = K.sculpt(makeSculpt(B)),
        rig = K.rig(B, S),
        M = K.M,
        { clamp, smooth, TAU } = FI;
      const ISL = rig.part('island');
      // tagged solids are parts that move; everything else rides the island
      rig.resolve = pr => (pr.tag ? undefined : ISL);
      // blue hour: the sun is down, a weak cool light from the west, the sky and the lamps do the rest
      S.sun = B.norm([-0.55, 0.3, -0.45]);
      S.amb = 0.3;
      S.sky = 0.34;
      S.sunK = 0.32;
      S.res = 0.085;
      const HY = 0.45,
        HP = 0.22;
      S.view = B.norm([Math.sin(HY) * Math.cos(HP), Math.sin(HP), Math.cos(HY) * Math.cos(HP)]);

      // ---------------- small helpers
      const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]],
        sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]],
        mad = (a, b, s) => [a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s],
        lerp3 = (a, b, u) => [a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u],
        cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]],
        frac = x => x - Math.floor(x),
        // a frame for o.ax whose y runs along dir
        frameY = dir => {
          const V = B.norm(dir),
            U = B.norm(cross(Math.abs(V[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0], V));
          return [U, V, cross(U, V)];
        },
        // a frame turned about the vertical: its z (the way a thing faces) goes to (sin a, 0, cos a)
        yawF = a => [
          [Math.cos(a), 0, -Math.sin(a)],
          [0, 1, 0],
          [Math.sin(a), 0, Math.cos(a)]
        ],
        // a point in a thing's own frame (x right, y up, z the way it faces), standing at x, y0, z, at scale s
        placer = (F, x, y0, z, s) => l => [x + (F[0][0] * l[0] + F[2][0] * l[2]) * s, y0 + l[1] * s, z + (F[0][2] * l[0] + F[2][2] * l[2]) * s],
        segDist = (pts, x, z) => {
          let d = 1e9;
          for (let i = 0; i < pts.length - 1; i++) {
            const [ax, az] = pts[i],
              bx = pts[i + 1][0] - ax,
              bz = pts[i + 1][1] - az,
              t = clamp(((x - ax) * bx + (z - az) * bz) / (bx * bx + bz * bz), 0, 1);
            d = Math.min(d, Math.hypot(x - ax - bx * t, z - az - bz * t));
          }
          return d;
        };

      /* Halftone: a dot screen laid over the surfaces as the hero camera sees them, at 45 degrees like a printer's screen. Inside a dot a
         surface is a tone lighter; the format has no screen of its own, so this is baked into the colours. */
      const HK = [Math.cos(HP) * Math.sin(HY), Math.sin(HP), Math.cos(HP) * Math.cos(HY)],
        HI = [Math.cos(HY), 0, -Math.sin(HY)],
        HJ = [HK[1] * HI[2], HK[2] * HI[0] - HK[0] * HI[2], -HK[1] * HI[0]],
        CELL = 0.25;
      const inDot = (x, y, z) => {
        const a = x * HI[0] + z * HI[2],
          b = x * HJ[0] + y * HJ[1] + z * HJ[2],
          u = ((a + b) * Math.SQRT1_2) / CELL,
          v = ((a - b) * Math.SQRT1_2) / CELL;
        return Math.hypot(u - Math.round(u), v - Math.round(v)) < 0.32;
      };
      const tone = (amp, base) => (x, y, z, ny, A) => (base ? base(x, y, z, ny, A) : 0) + (inDot(x, y, z) ? amp * 1.3 : -0.04);

      // ---------------- where things stand
      const FIREP = [0.05, 0.95],
        OWL = [-0.05, -0.12],
        FROG = [1.05, 1.32],
        ROBA = [-1.0, 1.25],
        ROBB = [1.14, -0.27],
        GLOVE = [2.1, 0.0],
        TVP = [-1.3, 0.2],
        CAMP = [-0.8, 2.65],
        AQ = [-1.14, 3.86],
        FAC = { x: -1.7, z: -2.7, hx: 1.4, hz: 0.8, h: 1.5 },
        CHIM = [-3.38, -3.25],
        HEAD = [2.3, -2.2],
        LAVA = [2.75, 1.55],
        LAVA_R = [1.0, 0.72],
        RUN = [
          [3.55, 1.95],
          [4.5, 2.35],
          [6.2, 2.95]
        ],
        TL = [4.0, -1.36],
        MZ = 0.5; // the marble run stands in the plane z = MZ
      const lavaD = (x, z) => Math.hypot((x - LAVA[0]) / LAVA_R[0], (z - LAVA[1]) / LAVA_R[1]),
        LL = -0.12; // the lava's level
      const ground = (x, z) =>
        0.1 * (B.fbm(x * 0.35 + 3, 1.7, z * 0.35, 2) - 0.5) +
        0.3 * Math.exp(-((x - HEAD[0]) ** 2 + (z - HEAD[1]) ** 2) / 4) -
        0.32 * (1 - smooth(0.55, 1.12, lavaD(x, z))) -
        0.2 * (1 - smooth(0.12, 0.3, segDist(RUN, x, z)));

      // ---------------- materials
      const TURF = {
        r: EARTH,
        mod: tone(0.18, (x, y, z) => 0.12 * (B.n3(x * 2.6, y * 4.1, z * 2.6) - 0.5) + 0.06),
        top: {
          min: 0.5,
          r: GRASS,
          g: [27],
          blade: { h: 0.08, w: 0.022 },
          tex: (x, y, z, ny, t) => {
            const lv = lavaD(x, z);
            // the lava's bed, and the scorched ground round it
            if (y < LL + 0.03 && (lv < 1.3 || segDist(RUN, x, z) < 0.45)) return 21;
            if (lv < 1.45 || segDist(RUN, x, z) < 0.55) return S.pick([4, 36, 37, 22], t);
            // the trodden ring round the fire
            if (Math.hypot(x - FIREP[0], z - FIREP[1]) < 1.55 + 0.15 * B.n3(x * 2, z * 2, 4.4)) return S.pick(EARTH, t);
            // snow lying in drifts, grass showing through
            if (B.n3(x * 0.7, z * 0.7, 3.3) + 0.15 * B.n3(x * 4, z * 4, 1.1) > 0.5) return S.pick(SNOW, t - 0.2);
            return undefined;
          }
        }
      };
      let isle = null;
      const ROCKMAT = {
        r: ROCK,
        g: [5],
        b: 0.06,
        mod: tone(0.2, (x, y, z) => {
          const bd = isle ? isle.bed(y) : { i: 0, hard: 0.5 };
          return 0.24 * (B.n3(bd.i * 3.1, 0.5, 1.7) - 0.5) + 0.12 * (B.n3(x * 2.2, y * 5.5, z * 2.2) - 0.5);
        })
      };
      const SNOWROCK = { r: ROCK, g: [5], b: 0.08, mod: tone(0.18), top: { min: 0.6, r: SNOW } },
        STEELM = { r: STEEL, g: [5], gloss: { c: 10, at: 0.94 }, mod: tone(0.17) },
        DARKM = { r: DARK, g: [4] },
        WOODM = { r: WOOD, g: [36], mod: (x, y, z) => 0.12 * (B.n3(x * 9, y * 3, z * 9) - 0.5) },
        GREYM = { r: [6, 7, 8, 9, 10], g: [6], gloss: { c: 10, at: 0.93 } },
        ICEM = { r: SNOW, g: [32], b: 0.32, gloss: { c: 35, at: 0.9 } },
        CYANGLOW = { r: [13, 14, 15], em: true, v: 0.6 },
        AMBERGLOW = { r: [24, 25, 26], em: true, v: 0.7 };

      // ---------------- the island itself
      isle = FI.body(K, B, S, {
        R: 5.6,
        thick: 0.7,
        depth: 4.3,
        ground,
        turf: TURF,
        rock: ROCKMAT,
        lumps: 9,
        seed: 6,
        res: 0.09
      });
      const gy = (x, z) => isle.h(x, z);

      // ---------------- the factory: a steel hall with a sawtooth roof of lit glass under snow, a chimney, a lit door
      const fy = gy(FAC.x, FAC.z) - 0.08;
      const hallTex = (x, y, z, ny, t, nx, nz) => {
        if (Math.abs(ny) > 0.5) return undefined;
        const front = Math.abs(nz) > 0.7,
          u = front ? x - FAC.x : z - FAC.z,
          h = y - fy;
        if (h < 0.18) return 4; // a dark plinth
        if (frac((u + 9) / 0.35) < 0.07) return 5; // panel seams
        if (front && Math.abs(u) > 0.42 && Math.abs(u) < 1.25 && h > 0.72 && h < 1.18) {
          const du = frac((u + 9) / 0.27);
          if (du < 0.14 || Math.abs(h - 0.95) < 0.02) return 5;
          return h > 0.98 ? 15 : 14;
        }
        return undefined;
      };
      S.box([FAC.x, fy + FAC.h / 2, FAC.z], [FAC.hx, FAC.h / 2, FAC.hz], { r: [5, 6, 7, 8], g: [5], mod: tone(0.17), tex: hallTex }, { res: 0.045 });
      // the door, lit from within, with a frame
      S.box([FAC.x, fy + 0.5, FAC.z + FAC.hz + 0.005], [0.32, 0.5, 0.025], CYANGLOW, { res: 0.03 });
      for (const s of [-1, 1]) S.box([FAC.x + s * 0.36, fy + 0.52, FAC.z + FAC.hz + 0.03], [0.04, 0.54, 0.04], DARKM, { res: 0.025 });
      S.box([FAC.x, fy + 1.06, FAC.z + FAC.hz + 0.03], [0.4, 0.04, 0.05], DARKM, { res: 0.025 });
      S.lights.push({ p: [FAC.x, fy + 0.6, FAC.z + FAC.hz + 0.7], r: 2.4, s: 0.85, c: [13, 14] });
      // the roof: four teeth, a slope under snow and a face of lit glass behind each
      {
        const teeth = 4,
          tw = (2 * FAC.hx) / teeth,
          th = 0.5,
          ty = fy + FAC.h,
          tl = Math.hypot(th / tw, 1);
        const roofMat = {
          r: [5, 6, 7],
          g: [5],
          tex: (x, y, z, ny, t, nx) => {
            if (nx > -0.7) return undefined;
            const v = (y - ty) / 0.13,
              u = (z - FAC.z) / 0.2;
            if (frac(u) < 0.14 || frac(v) < 0.16 || y < ty + 0.04) return 5;
            return frac(v) > 0.6 ? 15 : 14;
          },
          top: { min: 0.35, r: SNOW }
        };
        for (let i = 0; i < teeth; i++) {
          const x0 = FAC.x - FAC.hx + i * tw;
          S.convex(
            [x0, ty, FAC.z],
            [
              { n: [0, -1, 0], d: 0 },
              { n: [-1, 0, 0], d: 0 },
              { n: [th / tw / tl, 1 / tl, 0], d: th / tl },
              { n: [0, 0, 1], d: FAC.hz + 0.06 },
              { n: [0, 0, -1], d: FAC.hz + 0.06 }
            ],
            roofMat,
            { res: 0.045 }
          );
        }
        S.lights.push({ p: [FAC.x, ty + 0.4, FAC.z], r: 1.6, s: 0.5, c: [13, 14] });
      }
      // the chimney, steel with bands
      const chy = gy(CHIM[0], CHIM[1]) - 0.1;
      S.lathe([CHIM[0], chy, CHIM[1]], 3.3, t => 0.24 - 0.06 * t + (t > 0.95 ? 0.04 : 0), STEELM, { res: 0.04 });
      for (const y of [1.2, 2.2, 3.1]) S.torus([CHIM[0], chy + y, CHIM[1]], 0.24 - 0.06 * (y / 3.3) + 0.012, 0.025, { r: PINK.slice(1), em: true, v: 0.5 }, { res: 0.025 });

      // ---------------- the INSERT COIN sign on the roof, neon on a dark board, facing the yard (and the same on its back)
      const SGN = { c: [FAC.x + 0.05, fy + FAC.h + 1.25, FAC.z + 0.25], F: yawF(0.3) };
      {
        const F = SGN.F,
          c = SGN.c;
        S.box(c, [1.55, 0.72, 0.09], DARKM, { ax: F, res: 0.035 });
        for (const s of [-1, 1]) {
          const foot = mad(c, F[0], s * 1.1);
          S.tube([[foot[0], fy + FAC.h - 0.05, foot[2]], [foot[0], c[1] - 0.6, foot[2]]], 0.04, 0.04, DARKM, { res: 0.03 });
        }
        // a cyan neon frame round the board, front and back
        for (const side of [1, -1]) {
          const W = F[2].map(v => v * side),
            U = F[0].map(v => v * side),
            face = mad(c, W, 0.1),
            corners = [
              [-1.47, -0.64],
              [1.47, -0.64],
              [1.47, 0.64],
              [-1.47, 0.64],
              [-1.47, -0.64]
            ].map(([a, b]) => add(mad(face, U, a), [0, b, 0]));
          S.tube(corners, 0.022, 0.022, { r: [14, 15], em: true, v: 0.7 }, { res: 0.02 });
          const ax = [U, [0, 1, 0], W];
          // INSERT steady; COIN buzzing on and off the way a failing tube does
          S.strokes(K.poly2.text('INSERT', 0.44, { width: 0.065 }), add(mad(c, W, 0.11), [0, 0.29, 0]), 0.04, { r: [19, 20], em: true, v: 0.75 }, { ax, res: 0.02 });
          S.strokes(K.poly2.text('COIN', 0.44, { width: 0.065 }), add(mad(c, W, 0.11), [0, -0.29, 0]), 0.04, { r: [19, 20], em: true, v: 0.75, fl: { em: true, k: 4, ph: 0, sp: (TAU * 3) / L } }, { ax, res: 0.02 });
        }
        S.lights.push({ p: mad(c, F[2], 1.2), r: 3.2, s: 1.0, c: [18, 19] });
        S.lights.push({ p: mad(c, F[2], -1.2), r: 2.4, s: 0.7, c: [18, 19] });
      }

      // ---------------- the giant robot head, sunk to its chin, its big jaw jutting, looking out past the fire
      const HEADF = yawF(0.15),
        headY = gy(HEAD[0], HEAD[1]) - 0.35,
        HPL = placer(HEADF, HEAD[0], headY, HEAD[1], 1);
      {
        const F = HEADF,
          hb = headY,
          P = HPL,
          HM = {
            r: STEEL,
            g: [5],
            gloss: { c: 10, at: 0.95 },
            mod: tone(0.18, (x, y) => (frac((y - hb) / 0.42) < 0.06 ? -0.25 : 0)),
            top: { min: 0.62, r: SNOW }
          };
        S.ball(P([0, 1.4, -0.1]), [1.0, 1.35, 0.95], HM, { ax: F, res: 0.05 });
        S.box(P([0, 0.52, 0.28]), [0.88, 0.44, 0.84], HM, { ax: F, rd: 0.3, res: 0.05 });
        S.box(P([0, 1.66, 0.8]), [0.82, 0.08, 0.14], HM, { ax: F, rd: 0.05, res: 0.035 });
        const fwd = F[2];
        for (const s of [-1, 1]) {
          const e = P([s * 0.42, 1.34, 0.86]);
          S.torus(e, 0.25, 0.055, DARKM, { ax: frameY(fwd), res: 0.025 });
          S.lathe(e, 0.08, 0.21, { r: [14, 15], em: true, v: 0.85, fl: { em: true, k: 7, ph: 0, sp: TAU / L } }, { ax: frameY(fwd), res: 0.03 });
          // the bolts on either side of the head
          S.lathe(P([s * 0.95, 1.05, -0.1]), 0.2, 0.22, STEELM, { ax: frameY(F[0].map(v => v * s)), res: 0.035 });
        }
        // the mouth: a dark slot across the jaw, and a ridge where the jaw meets the dome
        S.box(P([0, 0.5, 1.12]), [0.55, 0.04, 0.03], DARKM, { ax: F, res: 0.025 });
        S.box(P([0, 0.98, 1.0]), [0.82, 0.03, 0.12], DARKM, { ax: F, res: 0.025 });
        // a short antenna on the crown of the head
        S.tube([P([0, 2.55, -0.1]), P([0, 2.9, -0.12])], 0.05, 0.03, STEELM, { res: 0.025 });
        S.ball(P([0, 2.95, -0.12]), 0.07, { r: [42, 43], em: true, v: 0.8 }, { res: 0.02 });
        S.lights.push({ p: P([0, 1.2, 1.9]), r: 2.6, s: 0.8, c: [14, 15] });
      }

      // ---------------- books: one book, and a stack of them (a seat, a table, a pile left lying about)
      const book = (c, half, yaw, ci) => {
        const F = yawF(yaw),
          cov = COVERS[ci % COVERS.length];
        S.box(
          c,
          half,
          {
            r: cov,
            g: [cov[0]],
            // the spine is cover; the three other edges show the pages
            tex: (x, y, z, ny, t, nx, nz) => {
              if (Math.abs(ny) > 0.6 || nx * F[0][0] + nz * F[0][2] < -0.7) return undefined;
              return S.pick(PAPER, t + 0.1);
            }
          },
          { ax: F, res: 0.03, rd: 0.006 }
        );
      };
      const stack = (x, z, n, k0, w) => {
        let y = gy(x, z) - 0.02;
        for (let k = 0; k < n; k++) {
          const th = 0.032 + 0.012 * B.n3(k * 1.7, x, z),
            ww = (w || 0.2) * (0.85 + 0.25 * B.n3(k, x * 3, 2));
          book([x + B.rr(-0.02, 0.02), y + th, z + B.rr(-0.02, 0.02)], [ww, th, ww * 0.72], B.rr(-0.3, 0.3) + k * 0.4, k0 + k);
          y += 2 * th;
        }
        return y;
      };
      const owlTop = stack(OWL[0], OWL[1], 6, 0, 0.28),
        robATop = stack(ROBA[0], ROBA[1], 5, 2, 0.2),
        robBTop = stack(ROBB[0], ROBB[1], 5, 4, 0.2),
        tvTop = stack(TVP[0], TVP[1], 4, 6, 0.26);
      // piles by the factory door, and one lying open in the snow
      stack(FAC.x + 0.7, FAC.z + FAC.hz + 0.35, 7, 1, 0.18);
      stack(FAC.x + 1.05, FAC.z + FAC.hz + 0.3, 4, 3, 0.18);
      stack(FAC.x - 0.75, FAC.z + FAC.hz + 0.35, 6, 5, 0.18);
      stack(2.0, 3.4, 3, 2, 0.17);
      // and round the back, where the factory's books wait to go in
      stack(FAC.x - 0.6, FAC.z - FAC.hz - 0.4, 8, 0, 0.19);
      stack(FAC.x - 0.15, FAC.z - FAC.hz - 0.45, 5, 4, 0.19);
      stack(FAC.x + 0.9, FAC.z - FAC.hz - 0.35, 6, 6, 0.17);
      stack(HEAD[0] - 0.2, HEAD[1] - 1.45, 4, 1, 0.2);
      {
        const x = 0.9,
          z = 3.0,
          y = gy(x, z) + 0.03;
        for (const s of [-1, 1]) {
          const F = yawF(0.5),
            tilt = [F[0].map(v => v * Math.cos(0.18)).map((v, i) => v + [0, s * Math.sin(0.18), 0][i]), [0, 1, 0], F[2]];
          S.box(mad([x, y, z], F[0], s * 0.13), [0.13, 0.012, 0.18], { r: PAPER, tex: (xx, yy, zz) => (frac((zz - z) / 0.05) < 0.2 ? 39 : undefined) }, { ax: [tilt[0], cross(F[2], tilt[0]).map(v => -v), F[2]], res: 0.022 });
        }
      }

      // ---------------- the campfire, its ring of stones and logs
      const fx = FIREP[0],
        fz = FIREP[1],
        fyy = gy(fx, fz);
      for (let k = 0; k < 9; k++) {
        const a = (k / 9) * TAU;
        S.rock([fx + Math.cos(a) * 0.34, fyy + 0.04, fz + Math.sin(a) * 0.34], 0.1, { r: ROCK, g: [5] }, { res: 0.03 });
      }
      for (let k = 0; k < 3; k++) {
        const a = (k / 3) * TAU + 0.4;
        S.tube(
          [
            [fx + Math.cos(a) * 0.26, fyy + 0.02, fz + Math.sin(a) * 0.26],
            [fx - Math.cos(a) * 0.05, fyy + 0.2, fz - Math.sin(a) * 0.05]
          ],
          0.045,
          0.035,
          { r: [36, 21, 22], g: [21] },
          { res: 0.025 }
        );
      }
      S.lights.push({ p: [fx, fyy + 0.5, fz], r: 2.4, s: 0.9, sh: true, c: [24, 25] });

      // ---------------- the Power Glove's plinth
      const gTop = gy(GLOVE[0], GLOVE[1]) + 0.32;
      S.box([GLOVE[0], gTop - 0.2, GLOVE[1]], [0.24, 0.2, 0.24], SNOWROCK, { res: 0.035, rd: 0.03 });
      S.box([GLOVE[0], gTop - 0.02, GLOVE[1]], [0.3, 0.03, 0.3], SNOWROCK, { res: 0.03, rd: 0.01 });

      // ---------------- the television on its stack of books: a 1989 set in a wood cabinet, rabbit ears, a lit screen
      {
        const F = yawF(0.75),
          P = placer(F, TVP[0], tvTop, TVP[1], 1);
        S.box(P([0, 0.2, 0]), [0.24, 0.2, 0.2], WOODM, { ax: F, rd: 0.03, res: 0.03 });
        S.box(P([-0.04, 0.2, 0.2]), [0.16, 0.14, 0.015], {
          r: [12, 13, 14, 15],
          em: true,
          v: 0.7,
          tex: (x, y) => (frac((y - tvTop) / 0.035) < 0.3 ? 13 : undefined),
          fl: { em: true, k: 4, ph: 0, sp: (TAU * 4) / L }
        }, { ax: F, res: 0.02 });
        for (const dy of [0.28, 0.2, 0.12]) S.ball(P([0.17, dy, 0.2]), 0.025, GREYM, { res: 0.015 });
        for (const s of [-1, 1]) S.tube([P([0, 0.4, -0.05]), P([s * 0.2, 0.75, -0.1])], 0.01, 0.008, GREYM, { res: 0.015 });
        S.lights.push({ p: P([0, 0.3, 0.7]), r: 1.6, s: 0.6, c: [13, 14] });
      }

      // ---------------- the camcorder on its tripod, filming the owl
      const CAMF = yawF(Math.atan2(OWL[0] - CAMP[0], OWL[1] - CAMP[1])),
        camH = gy(CAMP[0], CAMP[1]) + 0.95,
        CP = placer(CAMF, CAMP[0], camH, CAMP[1], 1.2);
      {
        for (let k = 0; k < 3; k++) {
          const a = (k / 3) * TAU + 0.5,
            fx2 = CAMP[0] + Math.cos(a) * 0.32,
            fz2 = CAMP[1] + Math.sin(a) * 0.32;
          S.tube([[CAMP[0], camH - 0.02, CAMP[1]], [fx2, gy(fx2, fz2) - 0.03, fz2]], 0.018, 0.014, DARKM, { res: 0.02 });
        }
        // a shoulder camcorder of 1989: a grey body with a black side panel and stripes, a fat lens, a handle and an eyepiece
        S.box(CP([0, 0.1, 0]), [0.09, 0.1, 0.2], { r: [6, 7, 8, 9], g: [6], gloss: { c: 10, at: 0.93 }, tex: (x, y) => (Math.abs(y - camH - 0.17 * 1.2) < 0.012 ? 18 : Math.abs(y - camH - 0.15 * 1.2) < 0.012 ? 14 : undefined) }, { ax: CAMF, rd: 0.02, res: 0.02 });
        S.box(CP([0.095, 0.1, -0.02]), [0.01, 0.07, 0.14], DARKM, { ax: CAMF, res: 0.02 });
        S.lathe(CP([0, 0.1, 0.18]), 0.13, [0.065, 0.075], DARKM, { ax: frameY(CAMF[2]), res: 0.018 });
        S.torus(CP([0, 0.1, 0.31]), 0.07, 0.012, GREYM, { ax: frameY(CAMF[2]), res: 0.012 });
        S.lathe(CP([0, 0.1, 0.305]), 0.012, 0.06, { r: [46, 47, 15], gloss: { c: 35, at: 0.85 } }, { ax: frameY(CAMF[2]), res: 0.012 });
        S.tube([CP([-0.04, 0.21, -0.12]), CP([-0.04, 0.24, 0.0]), CP([-0.04, 0.21, 0.12])], 0.014, 0.014, DARKM, { res: 0.015 });
        S.tube([CP([-0.12, 0.17, -0.06]), CP([-0.12, 0.17, -0.22])], 0.03, 0.035, DARKM, { res: 0.015 });
      }

      // ---------------- the aquarium on its cabinet
      const AQF = yawF(0.45),
        AQY = gy(AQ[0], AQ[1]) - 0.02,
        AP = placer(AQF, AQ[0], AQY, AQ[1], 1),
        TANK = AP([0, 0.56, 0]);
      {
        S.box(AP([0, 0.14, 0]), [0.52, 0.15, 0.27], WOODM, { ax: AQF, res: 0.035 });
        S.box(AP([0, 0.14, 0.27]), [0.48, 0.1, 0.012], { r: [36, 37, 38] }, { ax: AQF, res: 0.03 });
        S.box(TANK, [0.48, 0.26, 0.22], K.look.glass([11, 12, 13, 14], { a: 0.16 }), { ax: AQF, ghost: true, res: 0.04 });
        // a black frame round its edges, a lid with a lamp
        for (const sy of [-1, 1])
          for (const sz of [-1, 1]) S.box(add(TANK, [AQF[2][0] * sz * 0.22, sy * 0.26, AQF[2][2] * sz * 0.22]), [0.49, 0.015, 0.015], DARKM, { ax: AQF, res: 0.015 });
        for (const sx of [-1, 1])
          for (const sz of [-1, 1]) S.box(add(TANK, [AQF[0][0] * sx * 0.48 + AQF[2][0] * sz * 0.22, 0, AQF[0][2] * sx * 0.48 + AQF[2][2] * sz * 0.22]), [0.015, 0.26, 0.015], DARKM, { ax: AQF, res: 0.015 });
        S.box(add(TANK, [0, 0.29, 0]), [0.5, 0.03, 0.24], DARKM, { ax: AQF, res: 0.03 });
        // gravel, and a lotus growing from it
        S.box(add(TANK, [0, -0.22, 0]), [0.46, 0.035, 0.2], { r: [37, 38, 39, 40], tex: (x, y, z) => S.pick([37, 38, 39, 40, 12], B.n3(x * 30, y * 30, z * 30)) }, { ax: AQF, res: 0.025 });
        S.tube([add(TANK, [0.15, -0.2, 0]), add(TANK, [0.17, 0.05, 0.02]), add(TANK, [0.12, 0.17, 0])], 0.012, 0.01, { r: GRASS }, { res: 0.015 });
        S.lights.push({ p: add(TANK, mad([0, 0.1, 0], AQF[2], 0.7)), r: 1.8, s: 0.6, c: [13, 14] });
      }

      // ---------------- the chain-reaction marble run: a bucket lift, two ramps, a seesaw that kicks a hammer onto a bell
      const yb = gy(-3.45, MZ),
        LB = [-4.07, yb + 0.3, MZ],
        LT = [-4.07, yb + 1.95, MZ],
        R1a = [-3.92, yb + 1.86, MZ],
        R1b = [-2.72, yb + 1.44, MZ],
        R2a = [-2.76, yb + 1.04, MZ],
        R2b = [-3.64, yb + 0.7, MZ],
        SP = [-3.42, yb + 0.36, MZ], // the seesaw's pivot
        HPV = [-2.95, yb + 0.8, MZ + 0.22], // the hammer's hinge
        BELL = [-2.6, yb + 0.66, MZ + 0.22], // where the bell hangs from
        WT = [-4.25, yb + 1.95, MZ],
        WB = [-4.25, yb + 0.3, MZ];
      {
        S.box([-3.45, yb + 0.03, MZ + 0.05], [1.08, 0.04, 0.38], WOODM, { res: 0.035 });
        for (const s of [-1, 1]) S.tube([[-4.25, yb, MZ + s * 0.1], [-4.25, yb + 2.12, MZ + s * 0.1]], 0.025, 0.025, STEELM, { res: 0.022 });
        // the belt between the two wheels
        for (const x of [-4.43, -4.07]) S.tube([[x, yb + 0.3, MZ], [x, yb + 1.95, MZ]], 0.012, 0.012, { r: [4, 5] }, { res: 0.015 });
        // rails: each ramp is a pair, under where the ball runs
        const rails = (a, b, extra) => {
          for (const s of [-1, 1]) S.tube([add(a, [0, -0.095, s * 0.05]), add(b, [0, -0.095, s * 0.05])], 0.014, 0.014, { r: [16, 17, 18, 19], g: [16] }, { res: 0.015 });
          for (const u of extra) {
            const p = lerp3(a, b, u);
            S.tube([[p[0], yb + 0.05, MZ - 0.06], [p[0], p[1] - 0.09, MZ - 0.06]], 0.016, 0.016, STEELM, { res: 0.018 });
          }
        };
        rails(R1a, R1b, [0.35, 0.95]);
        rails(R2a, R2b, [0.2]);
        rails(add(lerp3(SP, LB, 0.15), [0, 0, 0]), LB, []);
        // a backboard where the ball turns from the first ramp to the second
        S.box([-2.6, yb + 1.22, MZ - 0.02], [0.02, 0.3, 0.09], WOODM, { res: 0.02 });
        // the seesaw's stand, and the bell's post and arm
        S.box([SP[0], yb + 0.2, MZ], [0.035, 0.16, 0.07], STEELM, { res: 0.02 });
        S.tube([[BELL[0] + 0.12, yb + 0.05, BELL[2]], [BELL[0] + 0.12, BELL[1] + 0.06, BELL[2]], [BELL[0], BELL[1] + 0.06, BELL[2]]], 0.016, 0.016, STEELM, { res: 0.018 });
        S.tube([[HPV[0], yb + 0.05, HPV[2] + 0.08], [HPV[0], HPV[1], HPV[2] + 0.08], [HPV[0], HPV[1], HPV[2]]], 0.016, 0.016, STEELM, { res: 0.018 });
      }
      // the seesaw angle: three balls go round a loop, so the seesaw tips three times; its cup end rests up and goes down when loaded
      const seesawAt = t => {
          const q = frac((3 * t) / L);
          return -0.22 + 0.42 * smooth(0.49, 0.53, q) * (1 - smooth(0.76, 0.88, q));
        },
        hammerAt = t => {
          const q = frac((3 * t) / L);
          return 0.62 * smooth(0.49, 0.545, q) * (1 - smooth(0.56, 0.74, q));
        },
        bellAt = t => {
          const q = frac((3 * t) / L);
          return q > 0.545 ? 0.16 * Math.exp(-(q - 0.545) * 9) * Math.sin((q - 0.545) * 70) : 0;
        },
        cupAt = t => {
          const th = seesawAt(t),
            c = Math.cos(th),
            s = Math.sin(th);
          return [SP[0] - 0.36 * c - 0.075 * s, SP[1] - 0.36 * s + 0.075 * c, MZ];
        },
        // where a ball is, s of the way round its loop (s from 0 to 1), at time t
        ballAt = (s, t) => {
          const seg = (a, b) => (s - a) / (b - a);
          if (s < 0.29) return lerp3(LB, LT, s / 0.29);
          if (s < 0.32) {
            const u = seg(0.29, 0.32),
              p = lerp3(LT, R1a, u);
            p[1] += 0.06 * Math.sin(Math.PI * u);
            return p;
          }
          if (s < 0.55) return lerp3(R1a, R1b, Math.pow(seg(0.32, 0.55), 1.4));
          if (s < 0.585) {
            const u = seg(0.55, 0.585);
            return [R1b[0] + (R2a[0] - R1b[0]) * u + 0.06 * Math.sin(Math.PI * u), R1b[1] + (R2a[1] - R1b[1]) * u * u, MZ];
          }
          if (s < 0.8) return lerp3(R2a, R2b, Math.pow(seg(0.585, 0.8), 1.4));
          const c = cupAt(t);
          if (s < 0.83) {
            const u = seg(0.8, 0.83);
            return [R2b[0] + (c[0] - R2b[0]) * u, R2b[1] + (c[1] - R2b[1]) * u * u, MZ];
          }
          if (s < 0.92) return c;
          return lerp3(c, LB, seg(0.92, 1));
        };

      // ---------------- the traffic light by the rim: two heads, back to back
      const TLF = yawF(0.45),
        tly = gy(TL[0], TL[1]) - 0.05,
        TLH = [TL[0], tly + 1.62, TL[1]],
        TLAMPS = [
          { k: 2, dy: 0.2, dim: [42], lit: [43] },
          { k: 1, dy: 0, dim: [22], lit: [25, 26] },
          { k: 0, dy: -0.2, dim: [44], lit: [45] }
        ];
      {
        S.tube([[TL[0], tly, TL[1]], [TL[0], tly + 1.32, TL[1]]], 0.045, 0.035, DARKM, { res: 0.025 });
        S.box(TLH, [0.13, 0.32, 0.09], { r: [4, 5, 6], g: [4], top: { min: 0.6, r: SNOW } }, { ax: TLF, rd: 0.03, res: 0.025 });
        for (const side of [1, -1]) {
          const W = TLF[2].map(v => v * side);
          S.box(mad(TLH, W, 0.095), [0.15, 0.35, 0.012], { r: [23, 24, 25] }, { ax: TLF, res: 0.025 });
          for (const lp of TLAMPS) {
            const c = add(mad(TLH, W, 0.1), [0, lp.dy, 0]);
            S.ball(c, [0.07, 0.07, 0.03], { r: lp.dim, em: true, v: 0.5 }, { ax: TLF, res: 0.015 });
            S.box(add(mad(c, W, 0.05), [0, 0.075, 0]), [0.08, 0.01, 0.05], DARKM, { ax: TLF, res: 0.015 });
          }
        }
        S.lights.push({ p: mad(TLH, TLF[2], 0.8), r: 2.4, s: 0.8, c: [42, 43] });
        S.lights.push({ p: mad(TLH, TLF[2], -0.8), r: 2.0, s: 0.6, c: [44, 45] });
      }

      // ---------------- the lava: its light, and the rocks round the island with snow on their tops
      S.lights.push({ p: [LAVA[0], LL + 0.5, LAVA[1]], r: 2.0, s: 0.9, c: [23, 25] });
      S.lights.push({ p: [4.6, LL + 0.3, 2.4], r: 1.8, s: 0.8, c: [23, 25] });
      [
        [-4.2, -1.7, 0.42, 3],
        [-3.85, -2.2, 0.22, 4],
        [4.2, -0.4, 0.36, 5],
        [-2.6, 4.2, 0.3, 6],
        [4.0, -3.0, 0.3, 7],
        [0.2, -4.6, 0.34, 8],
        [-3.7, 3.3, 0.28, 9],
        [2.5, 4.1, 0.24, 10]
      ].forEach(([x, z, r, sd]) => K.grow.rock(S, [x, gy(x, z) + r * 0.25, z], r, SNOWROCK, { facets: 8, chip: 0.3, beds: { n: 3 }, seed: sd, res: Math.max(0.03, r * 0.12) }));

      /* ---------------- the Regents crown, carved into a dressed face of the cliff below the rim where the first view looks. The face
         leans back with the cliff, so it is cut along the slope of the rock there */
      const aC = Math.atan2(Math.cos(HY), Math.sin(HY)),
        yC = -2.3,
        rC = isle.rockR(yC, aC),
        slope = (isle.rockR(yC + 0.25, aC) - isle.rockR(yC - 0.25, aC)) / 0.5,
        CD = [Math.cos(aC), 0, Math.sin(aC)],
        CW = B.norm([CD[0], -slope, CD[2]]),
        CU = [Math.cos(HY), 0, -Math.sin(HY)],
        CV = cross(CW, CU),
        surf = [CD[0] * rC, yC, CD[2] * rC],
        tablet = S.box(mad(surf, CW, -0.2), [1.32, 0.9, 0.32], { r: [6, 7, 8, 9, 10], g: [6], b: 0.1, mod: tone(0.18, (x, y, z) => 0.1 * (B.n3(x * 3, y * 3, z * 3) - 0.5)) }, { ax: [CU, CV, CW], rd: 0.08, res: 0.035 }),
        crownLoops = [];
      for (let row = 0; row < 3; row++)
        for (let col = 0; col < 5; col++) {
          if (row === 2 && col % 2) continue;
          const u = (col - 2) * 0.44,
            v = (row - 1) * 0.44,
            h = 0.17;
          crownLoops.push([
            [u - h, v - h],
            [u + h, v - h],
            [u + h, v + h],
            [u - h, v + h]
          ]);
        }
      S.engrave(crownLoops, {
        on: tablet,
        at: mad(surf, CW, 0.12),
        n: CW,
        up: CV,
        depth: 0.15,
        mat: { r: [4, 5, 6], g: [4] },
        res: 0.03
      });

      // ---------------- underneath: icicles under every edge, and long ones from the rock
      S.ready();
      K.form.drips(S, { box: [-3.9, 3.9, -3.9, 3.9], y: isle.yBot - 0.5, n: 80, gap: 0.4, len: [0.5, 1.7], r: 0.12, mites: false, mat: ICEM, seed: 9, res: 0.035 });
      K.form.icicles(S, { box: [-5.9, 5.9, -5.9, 5.9], top: 3.4, n: 320, gap: 0.14, len: [0.2, 0.8], mat: ICEM, seed: 13, res: 0.03 });
      S.lights.push({ p: [0.5, isle.yBot - 4.5, 2.5], r: 10, s: 0.4 });

      rig.own('island', () => S.bake());

      // ---------------- drawn by hand after the bake: lava and its fall, lotus, fire, smoke, snow on the wind, lamps, sign glow
      rig.own('island', () => {
        // the lava: dark crust in plates, hot cracks between them, a few that flare
        const step = 0.06;
        for (let x = LAVA[0] - 1.2, i = 0; x < 6.4; x += step, i++)
          for (let z = LAVA[1] - 1.0, row = 0; z < 3.4; z += step * 0.87, row++) {
            const xx = x + (row % 2) * step * 0.5;
            if (Math.hypot(xx, z) > isle.rim(Math.atan2(z, xx)) + 0.02) continue;
            const g = ground(xx, z);
            if (!(lavaD(xx, z) < 1.12 || segDist(RUN, xx, z) < 0.3) || g > LL - 0.005) continue;
            const y = Math.min(LL, isle.h(xx, z) + 0.05),
              v = B.fbm(xx * 1.6 + 2, z * 1.6, 3.1, 3),
              crack = Math.abs(B.n3(xx * 3.2, z * 3.2, 7.7) - 0.5) < 0.06,
              c = crack ? 26 : v > 0.6 ? 21 : v > 0.52 ? 22 : v < 0.4 ? 25 : 24;
            B.disc(xx, y, z, B.UP, step * 0.62, 0.012, B.P[c], 3, crack && B.R() < 0.3 ? { em: true, k: 4, ph: B.rr(0, 6), sp: B.rr(2, 4) } : { em: true });
          }
        // bubbles that rise and burst in the pool
        for (let i = 0; i < 24; i++) {
          const a = B.rr(0, TAU),
            q = Math.sqrt(B.R()) * 0.8;
          B.iso(LAVA[0] + Math.cos(a) * q * LAVA_R[0], LL + 0.02, LAVA[1] + Math.sin(a) * q * LAVA_R[1], 0.045, B.P[B.pick([24, 25, 26])], 3, { em: true, k: 6, ph: B.rr(0, 6), sp: (TAU * 2) / L, rg: 0.03 });
        }
        // the lava fall: it bends over the lip and drops as a glowing sheet
        const ex = RUN[RUN.length - 1],
          aw = Math.atan2(ex[1], ex[0]),
          e = isle.rim(aw),
          ox = Math.cos(aw),
          oz = Math.sin(aw),
          tx = -oz,
          tz = ox;
        for (let i = 0; i < 26; i++) {
          const u = B.rr(-0.22, 0.22),
            ang = B.rr(0, 1) * Math.PI * 0.5;
          B.disc(ox * (e + 0.16 * Math.sin(ang)) + tx * u, LL - 0.16 * (1 - Math.cos(ang)), oz * (e + 0.16 * Math.sin(ang)) + tz * u, B.norm([ox * Math.sin(ang), Math.cos(ang), oz * Math.sin(ang)]), 0.05, 0.012, B.P[B.pick([24, 25])], 3, { em: true });
        }
        const fall = 4.6;
        for (let i = 0; i < 1600; i++) {
          const u = B.rr(-0.26, 0.26),
            out = 0.17 + B.rr(0, 0.12);
          B.stick(ox * (e + out) + tx * u, LL - 0.18, oz * (e + out) + tz * u, B.UP, 0.08 + 0.06 * B.R(), 0.026, B.P[B.pick([22, 23, 24, 24, 25, 25, 26])], 3, {
            em: true,
            k: 2,
            ph: B.R(),
            sp: fall / 2,
            rg: fall,
            ex: 1.2
          });
        }
        // lotus floating on the lava, pads and pink petals, rocking gently
        [
          [2.45, 1.35, 0.0],
          [3.15, 1.75, 1.3],
          [2.9, 1.1, 2.6],
          [2.25, 1.85, 4.0]
        ].forEach(([x, z, ph]) => {
          const bobA = { k: 6, ph, sp: (TAU * 2) / L, rg: 0.018 },
            y = LL + 0.02;
          for (let k = 0; k < 18; k++) {
            const a = (k / 18) * TAU,
              r = 0.1 + 0.08 * (k % 2);
            if (Math.abs(a - 5.6) < 0.35) continue;
            B.disc(x + Math.cos(a) * r, y, z + Math.sin(a) * r, B.UP, 0.075, 0.012, B.P[k % 3 ? 29 : 28], 3, bobA);
          }
          const petals = K.grow.arrange('rosette', 16, { rings: 2, per: 8, r: 0.15, open: 0.55 });
          for (const pt of petals) {
            const c = [x + pt.p[0] + pt.dir[0] * pt.s * 0.5, y + 0.05 + pt.p[1] + pt.dir[1] * pt.s * 0.5, z + pt.p[2] + pt.dir[2] * pt.s * 0.5];
            B.stick(c[0], c[1], c[2], pt.dir, pt.s * 0.5, pt.s * 0.2, B.P[pt.t < 0.5 ? 20 : 19], 3, bobA);
          }
          B.iso(x, y + 0.07, z, 0.035, B.P[25], 3, Object.assign({ em: true }, bobA));
        });
        // the fire, its embers and smoke
        flame(B, fx, fyy + 0.12, fz, 0.75, [24, 25, 26]);
        flame(B, fx + 0.08, fyy + 0.1, fz - 0.05, 0.45, [23, 24, 25]);
        for (let i = 0; i < 9; i++) {
          const a = (i / 9) * TAU + 0.3,
            q = i % 3 === 0 ? 0.02 : 0.1,
            h = i % 3 === 0 ? 0.46 : B.rr(0.24, 0.36),
            lean = B.norm([Math.cos(a) * 0.25, 1, Math.sin(a) * 0.25]),
            x = fx + Math.cos(a) * q,
            z = fz + Math.sin(a) * q;
          B.stick(x + lean[0] * h * 0.5, fyy + 0.14 + h * 0.5, z + lean[2] * h * 0.5, lean, h * 0.5, i % 3 === 0 ? 0.05 : 0.065, B.P[i % 3 === 0 ? 26 : i % 2 ? 25 : 24], 3, { em: true, k: 1, ph: i * 1.7, sp: 9 });
        }
        for (let i = 0; i < 70; i++)
          B.iso(fx + B.rr(-0.15, 0.15), fyy + 0.25, fz + B.rr(-0.15, 0.15), 0.022, B.P[B.pick([24, 25, 26])], 3, { em: true, nd: true, k: 3, ph: B.R(), sp: B.rr(0.5, 0.9), rg: B.rr(1.2, 2.2), ex: 0 });
        for (let i = 0; i < 30; i++)
          B.iso(fx + B.rr(-0.06, 0.06), fyy + 0.7, fz + B.rr(-0.06, 0.06), 0.08, B.P[B.pick([7, 8, 9])], 0.5, { nd: true, k: 3, ph: B.R(), sp: 0.5, rg: 1.6, ex: 1.8 });
        // smoke from the factory chimney
        for (let i = 0; i < 50; i++)
          B.iso(CHIM[0] + B.rr(-0.07, 0.07), chy + 3.45, CHIM[1] + B.rr(-0.07, 0.07), 0.1, B.P[B.pick([7, 8, 9, 10])], 0.55, { nd: true, k: 3, ph: B.R(), sp: 0.5, rg: 2.4, ex: 2.4 });
        // the camcorder's red recording light
        const rec = CP([0.06, 0.18, 0.2]);
        B.iso(rec[0], rec[1], rec[2], 0.022, B.P[43], 3, { em: true, k: 4, ph: 0, sp: (TAU * 2) / L });
        // water in the tank, a line at its top, and bubbles rising
        for (let i = 0; i < 260; i++) {
          const p = add(TANK, add(mad([0, 0, 0], AQF[0], B.rr(-0.44, 0.44)), add(mad([0, 0, 0], AQF[2], B.rr(-0.19, 0.19)), [0, B.rr(-0.2, 0.18), 0])));
          B.iso(p[0], p[1], p[2], 0.06, B.P[B.pick([12, 13])], 0.16, { em: true, nd: true });
        }
        for (let i = 0; i < 40; i++) {
          const p = add(TANK, add(mad([0, 0, 0], AQF[0], B.rr(-0.45, 0.45)), [0, 0.2, 0]));
          B.disc(p[0], p[1], p[2], B.UP, 0.03, 0.006, B.P[14], 3, { em: true });
        }
        for (let i = 0; i < 24; i++) {
          const p = add(TANK, add(mad([0, 0, 0], AQF[0], B.R() < 0.5 ? -0.32 : 0.2), [0, -0.17, 0]));
          B.iso(p[0] + B.rr(-0.02, 0.02), p[1], p[2] + B.rr(-0.02, 0.02), 0.015, B.P[B.pick([14, 15])], 3, { em: true, nd: true, k: 3, ph: B.R(), sp: 0.4, rg: 0.36, ex: 0 });
        }
        // the lotus in the tank
        const lt = add(TANK, [0.12, 0.18, 0]);
        for (const pt of K.grow.arrange('rosette', 10, { rings: 2, per: 5, r: 0.07, open: 0.5 }))
          B.stick(lt[0] + pt.p[0] + pt.dir[0] * pt.s * 0.5, lt[1] + pt.dir[1] * pt.s * 0.5, lt[2] + pt.p[2] + pt.dir[2] * pt.s * 0.5, pt.dir, pt.s * 0.5, pt.s * 0.22, B.P[pt.t < 0.5 ? 20 : 19], 3);
        // the grass that hangs over the rim
        FI.skirt(B, isle, { ramp: [27, 28, 28, 29, 29, 30], sun: S.sun, len: 0.28, gap: 0.05 });
        // rivets along the giant head's jaw
        for (let k = -5; k <= 5; k++) {
          const p = HPL([k * 0.13, 0.72, 1.13]);
          B.iso(p[0], p[1], p[2], 0.022, B.P[10], 3);
        }
      });

      // ---------------- what moves: made in a bake of its own so nothing still is cut where it stood
      // the owl: a robot night owl in a flower crown, standing on its books, wings for hands
      const OWLF = yawF(0.18),
        OS = 1.3,
        OP = placer(OWLF, OWL[0], owlTop, OWL[1], OS),
        oo = (tag, extra) => Object.assign({ res: 0.03, tag, whole: true }, extra || {});
      const OWLM = {
          r: STEEL,
          g: [5],
          gloss: { c: 10, at: 0.94 },
          mod: tone(0.17, (x, y) => (frac((y - owlTop) / 0.11) < 0.14 ? -0.28 : 0))
        },
        BELLY = {
          r: [7, 8, 9, 10],
          g: [7],
          // overlapping steel plates, like the feathers of an owl's breast, with a rivet at each
          tex: (x, y, z, ny, t) => {
            const lx = (x - OWL[0]) * OWLF[0][0] + (z - OWL[1]) * OWLF[0][2],
              v = (y - owlTop) / 0.085 + Math.abs(lx) * 6;
            if (frac(v) < 0.18) return 6;
            if (frac(v) > 0.5 && frac(v) < 0.68 && frac(lx / 0.09 + 0.5 * Math.floor(v)) < 0.25) return 10;
            return undefined;
          }
        },
        SHL = OP([-0.33, 0.72, 0]),
        SHR = OP([0.33, 0.72, 0]);
      S.ball(OP([0, 0.45, 0]), [0.34 * OS, 0.4 * OS, 0.3 * OS], OWLM, oo('owl', { ax: OWLF }));
      S.ball(OP([0, 0.42, 0.13]), [0.25 * OS, 0.3 * OS, 0.2 * OS], BELLY, oo('owl', { ax: OWLF }));
      S.ball(OP([0, 0.92, 0]), [0.33 * OS, 0.27 * OS, 0.29 * OS], OWLM, oo('owl', { ax: OWLF }));
      S.ball(OP([0, 0.9, 0.16]), [0.29 * OS, 0.21 * OS, 0.13 * OS], { r: [5, 6, 7, 8], g: [5] }, oo('owl', { ax: OWLF }));
      const fwd = OWLF[2];
      for (const s of [-1, 1]) {
        const e = OP([s * 0.13, 0.93, 0.27]);
        S.torus(e, 0.1 * OS, 0.024 * OS, { r: [21, 22, 23, 24], g: [21], gloss: { c: 26, at: 0.92 } }, oo('owl', { ax: frameY(fwd) }));
        S.ball(e, 0.085 * OS, { r: [25, 26], em: true, v: 0.95 }, oo('owl'));
        // ear tufts
        S.tube([OP([s * 0.2, 1.1, 0]), OP([s * 0.3, 1.33, -0.03])], 0.065 * OS, 0.012, OWLM, oo('owl'));
        // feet
        S.box(OP([s * 0.11, 0.03, 0.12]), [0.06 * OS, 0.03 * OS, 0.07 * OS], { r: [22, 23, 24] }, oo('owl', { ax: OWLF, rd: 0.01 }));
      }
      S.lathe(OP([0, 0.87, 0.3]), 0.1 * OS, t => 0.04 * (1 - t) + 0.006, { r: [22, 23, 24, 25] }, oo('owl', { ax: frameY(add(mad([0, 0, 0], fwd, 0.6), [0, -0.8, 0])) }));
      // the flower crown: a ring of green with flowers round it
      S.torus(OP([0, 1.14, 0]), 0.25 * OS, 0.032 * OS, { r: GRASS }, oo('owl'));
      for (let k = 0; k < 9; k++) {
        const a = (k / 9) * TAU + 0.2;
        S.ball(OP([Math.cos(a) * 0.25, 1.17, Math.sin(a) * 0.25]), 0.055 * OS, { r: [[18, 19, 20], [46, 47], [39, 40, 41]][k % 3], g: [17] }, oo('owl'));
      }
      // the wings, each with three long feathers at its end, for fingers
      for (const s of [-1, 1]) {
        const tag = s < 0 ? 'owlL' : 'owlR';
        S.ball(OP([s * 0.37, 0.46, 0]), [0.085 * OS, 0.3 * OS, 0.2 * OS], OWLM, oo(tag, { ax: OWLF }));
        for (const dz of [-0.08, 0, 0.08]) S.tube([OP([s * 0.38, 0.24, dz]), OP([s * 0.41, 0.06, dz * 1.4])], 0.04 * OS, 0.018 * OS, OWLM, oo(tag));
      }
      // the frog, listening by the fire
      const FROGF = yawF(Math.atan2(fx - FROG[0], fz - FROG[1])),
        FS = 1.5,
        FP = placer(FROGF, FROG[0], gy(FROG[0], FROG[1]) - 0.01, FROG[1], FS),
        FROGM = { r: GRASS.concat([31]), g: [27], gloss: { c: 31, at: 0.93 } },
        fo = extra => Object.assign({ res: 0.025, tag: 'frog', whole: true }, extra || {});
      S.ball(FP([0, 0.13, 0]), [0.19 * FS, 0.13 * FS, 0.23 * FS], FROGM, fo({ ax: FROGF }));
      S.ball(FP([0, 0.17, 0.17]), [0.17 * FS, 0.1 * FS, 0.12 * FS], FROGM, fo({ ax: FROGF }));
      S.ball(FP([0, 0.11, 0.22]), [0.11 * FS, 0.06 * FS, 0.07 * FS], { r: [30, 31, 41] }, fo({ ax: FROGF }));
      for (const s of [-1, 1]) {
        // eyes on top: a green bump, a gold eye, a black slit of a pupil
        const eye = B.norm([s * 0.6, 0.45, 0.65]),
          at = k => [s * 0.1 + eye[0] * k, 0.27 + eye[1] * k, 0.15 + eye[2] * k];
        S.ball(FP(at(0)), 0.065 * FS, FROGM, fo());
        S.ball(FP(at(0.032)), 0.048 * FS, { r: [24, 25, 26], gloss: { c: 26, at: 0.9 } }, fo());
        S.ball(FP(at(0.064)), [0.026 * FS, 0.016 * FS, 0.026 * FS], { r: [4] }, fo({ ax: FROGF }));
        S.ball(FP([s * 0.17, 0.09, -0.08]), [0.07 * FS, 0.07 * FS, 0.13 * FS], FROGM, fo({ ax: FROGF }));
        S.box(FP([s * 0.21, 0.02, 0.05]), [0.05 * FS, 0.015 * FS, 0.07 * FS], FROGM, fo({ ax: FROGF }));
        S.tube([FP([s * 0.1, 0.1, 0.2]), FP([s * 0.13, 0.0, 0.27])], 0.03 * FS, 0.025 * FS, FROGM, fo());
      }
      // the two robots listening, their heads moving
      const robots = [
        { at: ROBA, top: robATop, head: 'robAh' },
        { at: ROBB, top: robBTop, head: 'robBh' }
      ].map(r => {
        const F = yawF(Math.atan2(fx - r.at[0], fz - r.at[1])),
          P = placer(F, r.at[0], r.top, r.at[1], 1),
          shell = { r: [7, 8, 9, 10], g: [7], gloss: { c: 10, at: 0.93 } },
          paint = { r: PINK.slice(1), g: [16] },
          h = r.top - gy(r.at[0], r.at[1]);
        S.box(P([0, 0.3, 0]), [0.15, 0.17, 0.11], shell, { ax: F, rd: 0.05, res: 0.025 });
        S.box(P([0, 0.31, 0.105]), [0.08, 0.06, 0.012], paint, { ax: F, rd: 0.01, res: 0.02 });
        S.box(P([0, 0.1, 0]), [0.12, 0.05, 0.1], STEELM, { ax: F, rd: 0.02, res: 0.025 });
        for (const s of [-1, 1]) {
          S.tube([P([s * 0.07, 0.1, 0]), P([s * 0.07, 0.1, 0.24]), P([s * 0.07, 0.05 - h, 0.28])], 0.038, 0.033, STEELM, { res: 0.022 });
          S.box(P([s * 0.07, 0.03 - h, 0.32]), [0.045, 0.03, 0.07], paint, { ax: F, rd: 0.01, res: 0.02 });
          S.tube([P([s * 0.18, 0.42, 0]), P([s * 0.17, 0.26, 0.1]), P([s * 0.11, 0.17, 0.2])], 0.03, 0.026, STEELM, { res: 0.02 });
          S.ball(P([s * 0.11, 0.16, 0.21]), 0.035, paint, { res: 0.02 });
        }
        S.tube([P([0, 0.46, 0]), P([0, 0.54, 0])], 0.03, 0.03, STEELM, { res: 0.02 });
        const ho = { res: 0.022, tag: r.head, whole: true };
        S.ball(P([0, 0.64, 0]), [0.13, 0.11, 0.12], shell, Object.assign({ ax: F }, ho));
        S.box(P([0, 0.65, 0.105]), [0.09, 0.03, 0.02], CYANGLOW, Object.assign({ ax: F, rd: 0.01 }, ho));
        S.tube([P([0.05, 0.73, 0]), P([0.07, 0.86, 0])], 0.009, 0.007, STEELM, ho);
        S.ball(P([0.07, 0.88, 0]), 0.025, { r: [19, 20], em: true, v: 0.8 }, ho);
        return { F, neck: P([0, 0.54, 0]) };
      });
      /* the Power Glove, standing up on its plinth like a trophy and turning slowly: a grey gauntlet with its keypad, a hand with its
         fingers up. In its own frame x runs across the hand, y out of its back (the keypad side) and z from the cuff to the fingertips */
      const GS = 1.5,
        GC = [GLOVE[0], gTop + 0.36 * GS, GLOVE[1]],
        GF = [
          [-Math.cos(HY), 0, Math.sin(HY)],
          [Math.sin(HY), 0, Math.cos(HY)],
          [0, 1, 0]
        ],
        GP = l => [0, 1, 2].map(i => GC[i] + (GF[0][i] * l[0] + GF[1][i] * l[1] + GF[2][i] * l[2]) * GS),
        go = extra => Object.assign({ res: 0.02, tag: 'glove', whole: true }, extra || {});
      {
        const GLV = { r: [6, 7, 8, 9, 10], g: [6], gloss: { c: 10, at: 0.92 } };
        S.box(GP([0, 0, -0.16]), [0.1 * GS, 0.075 * GS, 0.17 * GS], GLV, go({ ax: GF, rd: 0.04 }));
        S.box(GP([0, 0.078, -0.17]), [0.075 * GS, 0.012 * GS, 0.12 * GS], DARKM, go({ ax: GF }));
        S.box(GP([0, 0, -0.33]), [0.11 * GS, 0.085 * GS, 0.02 * GS], DARKM, go({ ax: GF }));
        S.box(GP([0, -0.005, 0.1]), [0.095 * GS, 0.055 * GS, 0.09 * GS], GLV, go({ ax: GF, rd: 0.03 }));
        S.box(GP([0, 0.05, 0.13]), [0.08 * GS, 0.012 * GS, 0.06 * GS], DARKM, go({ ax: GF }));
        for (let k = 0; k < 4; k++) {
          const x = -0.066 + k * 0.044,
            len = [0.33, 0.37, 0.36, 0.31][k];
          S.tube([GP([x, 0, 0.18]), GP([x * 1.25, 0.005, 0.27]), GP([x * 1.5, -0.025, len])], 0.022 * GS, 0.019 * GS, GLV, go());
          // the black strip down the back of each finger
          S.tube([GP([x, 0.02, 0.19]), GP([x * 1.25, 0.024, 0.27])], 0.008 * GS, 0.008 * GS, DARKM, go());
        }
        S.tube([GP([0.1, -0.01, 0.06]), GP([0.15, 0, 0.14]), GP([0.16, -0.01, 0.2])], 0.026 * GS, 0.022 * GS, GLV, go());
      }
      // the marble run's moving parts: the lift's wheels, the seesaw, the hammer, the bell, three marbles
      const wheel = (c, tag) => {
        const o = { tag, whole: true, res: 0.02 },
          WF = frameY([0, 0, 1]);
        S.torus(c, 0.18, 0.022, STEELM, Object.assign({ ax: WF }, o));
        S.lathe(add(c, [0, 0, -0.05]), 0.1, 0.04, { r: PINK.slice(1) }, Object.assign({ ax: WF }, o));
        for (let k = 0; k < 4; k++) {
          const a = (k / 4) * TAU;
          S.tube([c, add(c, [Math.cos(a) * 0.17, Math.sin(a) * 0.17, 0])], 0.012, 0.012, STEELM, o);
        }
      };
      wheel(WT, 'liftT');
      wheel(WB, 'liftB');
      {
        const o = { tag: 'seesaw', whole: true, res: 0.02 };
        S.box(SP, [0.42, 0.018, 0.045], { r: [16, 17, 18, 19], g: [16] }, o);
        S.lathe(add(SP, [-0.36, 0.0, 0]), 0.06, t => 0.03 + 0.06 * t, STEELM, o);
        S.box(add(SP, [0.38, 0.04, 0.12]), [0.03, 0.03, 0.14], STEELM, o);
        S.tube([add(SP, [0, 0, -0.06]), add(SP, [0, 0, 0.06])], 0.02, 0.02, STEELM, o);
      }
      {
        const o = { tag: 'hammer', whole: true, res: 0.02 };
        S.tube([HPV, add(HPV, [0, -0.36, 0])], 0.014, 0.014, WOODM, o);
        S.box(add(HPV, [0, -0.38, 0]), [0.05, 0.035, 0.035], { r: [21, 22, 23, 24] }, o);
      }
      {
        const o = { tag: 'bell', whole: true, res: 0.02 };
        S.tube([BELL, add(BELL, [0, -0.06, 0])], 0.01, 0.01, STEELM, o);
        S.lathe(add(BELL, [0, -0.2, 0]), 0.15, t => 0.1 * Math.pow(1 - t, 0.6) + 0.015, { r: [22, 23, 24, 25, 26], gloss: { c: 26, at: 0.9 } }, o);
      }
      const BALLS = [0, 1, 2].map(k => {
        const rest = ballAt(k / 3, 0),
          tag = 'ball' + k;
        S.ball(rest, 0.09, { r: [[18, 19, 20], [13, 14, 15], [24, 25, 26]][k], em: true, v: 0.8, gloss: { c: 35, at: 0.9 } }, { tag, whole: true, res: 0.018 });
        return { rest, tag, k };
      });
      // the fish in the tank
      const FISH = [
        { tag: 'fish0', c: 1, ph: 0, y: 0.02, cols: [23, 24, 25] },
        { tag: 'fish1', c: -2, ph: 2.0, y: -0.08, cols: [18, 19, 20] }
      ].map(f => {
        const rest = add(TANK, [0, f.y, 0]),
          o = { tag: f.tag, whole: true, res: 0.015 },
          U = AQF[0];
        S.ball(rest, [0.07, 0.045, 0.03], { r: f.cols, em: true, v: 0.75 }, Object.assign({ ax: AQF }, o));
        S.ball(mad(rest, U, -0.085), [0.035, 0.04, 0.01], { r: f.cols.slice(1), em: true, v: 0.75 }, Object.assign({ ax: AQF }, o));
        S.ball(add(mad(rest, U, 0.035), [0, 0.012, 0]), 0.009, { r: [4] }, o);
        return Object.assign(f, { rest });
      });
      // the traffic light's lamps: lit when they are out at the lens, put away inside the housing when they are not
      const LAMPS = [];
      for (const side of [1, -1]) {
        const W = TLF[2].map(v => v * side);
        for (const lp of TLAMPS) {
          const tag = 'tl' + lp.k + (side > 0 ? 'f' : 'b');
          S.ball(add(mad(TLH, W, 0.115), [0, lp.dy, 0]), [0.072, 0.072, 0.03], { r: lp.lit, em: true, v: 0.9 }, { ax: TLF, tag, whole: true, res: 0.014 });
          LAMPS.push({ tag, k: lp.k, W });
        }
      }

      S.bake();

      // ---------------- drawn by hand on the parts that move
      rig.own('owl', () => {
        for (const s of [-1, 1]) {
          const e = OP([s * 0.13, 0.93, 0.3]);
          B.iso(e[0], e[1], e[2], 0.035, B.P[4], 3);
          B.iso(e[0] + 0.02 * s, e[1] + 0.03, e[2], 0.014, B.P[26], 3, { em: true });
          B.iso(e[0], e[1], e[2], 0.17, B.P[25], 0.35, { em: true, nd: true, k: 7, ph: 0, sp: (TAU * 2) / L });
        }
        const c = OP([0, 0.55, 0.36]);
        B.iso(c[0], c[1], c[2], 0.025, B.P[14], 3, { em: true, k: 4, ph: 1, sp: (TAU * 2) / L });
        for (let k = 0; k < 9; k++) {
          const a = (k / 9) * TAU + 0.2,
            p = OP([Math.cos(a) * 0.25, 1.22, Math.sin(a) * 0.25]);
          B.iso(p[0], p[1], p[2], 0.022, B.P[25], 3);
        }
      });
      rig.own('glove', () => {
        for (let i = 0; i < 3; i++)
          for (let j = 0; j < 3; j++) {
            const p = GP([-0.04 + i * 0.04, 0.095, -0.24 + j * 0.04]);
            B.iso(p[0], p[1], p[2], 0.012, B.P[10], 3);
          }
        for (const [x, z, c] of [
          [-0.03, -0.1, 43],
          [0.03, -0.1, 43],
          [0.0, -0.06, 14]
        ]) {
          const p = GP([x, 0.095, z]);
          B.iso(p[0], p[1], p[2], 0.016, B.P[c], 3, { em: true });
        }
      });
      // the sky: a rainbow behind the island, a band of light low round the horizon, and snow falling through
      const RN = [Math.sin(HY), 0, Math.cos(HY)],
        RH = [Math.cos(HY), 0, -Math.sin(HY)],
        RC = [-6.5 * RN[0], -3.0, -6.5 * RN[2]];
      [43, 24, 25, 30, 14, 33, 47].forEach((c, k) => {
        const R = 9.6 - k * 0.16;
        for (let a = 0.02; a < Math.PI - 0.02; a += 0.08 / R) {
          // the bands fade out at their feet in a few steps (each strength is a style of its own in the baked file)
          const ends = Math.ceil(Math.min(1, Math.min(a, Math.PI - a) / 0.45) * 5) / 5,
            p = add(mad(RC, RH, Math.cos(a) * R), [0, Math.sin(a) * R, 0]),
            tg = B.norm(add(mad([0, 0, 0], RH, -Math.sin(a)), [0, Math.cos(a), 0]));
          B.stick(p[0], p[1], p[2], tg, 0.09, 0.085, B.P[c], 0.8 * ends, { em: true, nd: true });
        }
      });
      for (let i = 0; i < 160; i++) {
        const a = B.rr(0, TAU),
          r = B.rr(36, 42);
        B.iso(Math.cos(a) * r, B.rr(-1, 4), Math.sin(a) * r, B.rr(1.2, 2.4), B.P[B.pick([2, 2, 46])], 0.22, { em: true, nd: true });
      }
      for (let i = 0; i < 700; i++) {
        const a = B.rr(0, TAU),
          q = Math.sqrt(B.R()) * 6.5;
        B.iso(Math.cos(a) * q, B.rr(1.0, 5.6), Math.sin(a) * q, 0.034, B.P[B.pick([34, 35, 35])], 3, { em: true, nd: true, k: 2, ph: B.R(), sp: 5 / L, rg: 5, ex: 0 });
      }

      const W = B.finish({
        cam: { target: [0, -0.3, 0], dist: 22, pitch: HP, yaw: HY },
        detail: 19.4,
        dither: 0.6,
        radius: 10,
        palName: 'Rain Neon',
        fog: { c: 0, start: 0.8, max: 0.2 },
        outline: { c: 4, edge: 0.7 },
        ao: { k: 0.4, range: 0.5 }
      });
      FI.loopable(W, L);
      const st = K.stage(W);
      rig.bind(st);
      // every motion comes round in L seconds: the island bobs once; the owl sways and gestures; the frog hops twice; the robots nod;
      // the glove turns once; three marbles go round the run once each; the fish swim; the traffic light goes green, amber, red once
      const I = M.id(),
        Ry = a => M.rot([0, 1, 0], a),
        Rz = a => M.rot([0, 0, 1], a),
        heading = v => Math.atan2(-v[2], v[0]),
        ownFeet = OP([0, 0, 0]),
        frogFeet = FP([0, 0, 0]),
        lampOn = (k, t) => {
          const win = [
              [0, 3.4],
              [3.4, 4.4],
              [4.4, 8]
            ][k],
            e = 0.06,
            bump = u => smooth(win[0] - e, win[0] + e, u) * (1 - smooth(win[1] - e, win[1] + e, u)),
            u = frac(t / L) * L;
          return Math.max(bump(u), bump(u - L), bump(u + L));
        };
      st.add({
        update(dt, t) {
          const w = (TAU * t) / L,
            bob = 0.12 * Math.sin(w),
            lift = p => [p[0], p[1] + bob, p[2]];
          rig.set('island', I, [0, 0, 0], [0, bob, 0]);
          // the storyteller: the body sways and leans in, the wings open wide and reach toward the listeners in turn
          const of = OWLF[2],
            orr = OWLF[0];
          rig.set('owl', M.mul(M.rot(of, 0.06 * Math.sin(2 * w)), M.rot(orr, -0.06 * Math.sin(4 * w + 1))), ownFeet, lift(ownFeet));
          rig.child('owlL', 'owl', M.mul(M.rot(of, -(0.8 + 0.5 * Math.sin(2 * w))), M.rot(orr, -(0.45 + 0.35 * Math.sin(4 * w)))), SHL);
          rig.child('owlR', 'owl', M.mul(M.rot(of, 0.6 + 0.6 * Math.sin(2 * w + 2.2)), M.rot(orr, -(0.55 + 0.35 * Math.sin(4 * w + 1.5)))), SHR);
          // the frog hops twice, nose up
          const hv = Math.max(0, Math.sin(2 * w));
          rig.set('frog', M.rot(FROGF[0], -0.3 * hv), frogFeet, lift(add(frogFeet, [0, 0.2 * hv, 0])));
          // the robots: one nods along, one tilts its head
          rig.set('robAh', M.rot(robots[0].F[0], 0.15 * Math.sin(4 * w)), robots[0].neck, lift(robots[0].neck));
          rig.set('robBh', M.rot(robots[1].F[2], 0.14 * Math.sin(2 * w + 1)), robots[1].neck, lift(robots[1].neck));
          rig.set('glove', Ry(w), GC, lift(GC));
          // the marble run
          rig.set('liftT', Rz(5 * w), WT, lift(WT));
          rig.set('liftB', Rz(5 * w), WB, lift(WB));
          rig.set('seesaw', Rz(seesawAt(t)), SP, lift(SP));
          rig.set('hammer', Rz(hammerAt(t)), HPV, lift(HPV));
          rig.set('bell', Rz(bellAt(t)), BELL, lift(BELL));
          for (const b of BALLS) rig.set(b.tag, I, b.rest, lift(ballAt(frac(t / L + b.k / 3), t)));
          // the fish swim round the tank, one each way
          for (const f of FISH) {
            const th = f.c * w + f.ph,
              sg = Math.sign(f.c),
              p = add(add(mad([0, 0, 0], AQF[0], 0.27 * Math.cos(th)), mad([0, 0, 0], AQF[2], 0.09 * Math.sin(th))), [0, f.y + 0.03 * Math.sin(2 * th), 0]),
              v = add(mad([0, 0, 0], AQF[0], -0.27 * Math.sin(th) * sg), mad([0, 0, 0], AQF[2], 0.09 * Math.cos(th) * sg));
            rig.set(f.tag, Ry(heading(v) - heading(AQF[0])), f.rest, lift(add(TANK, p)));
          }
          // the traffic light
          for (const lp of LAMPS) rig.set(lp.tag, I, [0, 0, 0], lift(mad([0, 0, 0], lp.W, -0.13 * (1 - lampOn(lp.k, t)))));
          rig.apply();
        }
      });
      return W;
    }
  };
};
