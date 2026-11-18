/* Meteor: a coral reef on a floating rock under a teal noon sky full of stars. A meteor falls out of the sky at
   a chrome, hooded Big Grey Neighbour standing on a 1977 light-up dance floor, who bats it back up into the sky at the last moment.
   Round it: an orange couch, a black slab, a bonsai, a pool of quicksand with a hat going under, a tape-reel computer, crates of fish
   with a black cat on top, a hut on chicken legs with an OPEN sign, a mirror ball; snow falls, bubbles rise, fish circle, and under
   the rock the Regents crown is carved in the cliff and jellyfish trail their tentacles. Seeded: it builds the same way every time. */
const FI = require('./floating-island.cjs');

const L = 8; // seconds in one loop: every repeating motion comes round in this time

// 48 colours, Punk Teal: the sky is the CryptoPunks background; each ramp shifts hue from dark to light
const PAL = [
  0x638596, // 0     the sky, punk teal
  0x0b141c, 0x182c38, 0x2a4652, 0x40636e, 0x8eb2b6, 0xcfe6e0, // 1-6   navy to mint (outline, chrome, cat)
  0x3a2c3a, 0x5e4648, 0x8a6a5a, 0xb8956e, 0xdcc08a, 0xf4e6b8, // 7-12  reef sand, plum to straw
  0x1c1a2e, 0x2e2c44, 0x4a4658, 0x6c6670, 0x948a88, // 13-17 floating rock, blue-violet to warm grey
  0x4a1430, 0x8a2448, 0xd04a5e, 0xf47e6e, 0xffb48a, 0xffe0b0, // 18-23 coral, plum to peach
  0x2c1848, 0x5a2e7a, 0x9050b0, 0xc890d8, // 24-27 violet coral and jellyfish
  0x0f2a24, 0x1c4a36, 0x2e7046, 0x5a9a4a, 0x9cc45a, // 28-32 kelp and leaves, teal-green to yellow-green
  0xff3ea5, 0xffa0e0, 0x2ee6e6, // 33-35 neon pink, its pale core, glitch cyan
  0x5a1a10, 0xb03a14, 0xf07a1e, 0xffc040, 0xfff2a0, // 36-40 meteor fire
  0x4a2414, 0x8a4a1e, 0xc8742a, 0xe8a040, // 41-44 1977 orange, wood
  0xe8dcc0, // 45    computer cream
  0x3a8ab0, // 46    glaze blue
  0xffffff // 47    white
];

const NAVY = [1, 2, 3, 4],
  SAND = [7, 8, 9, 10, 11],
  SAND_SUN = [9, 10, 11, 12],
  ROCK = [13, 14, 15, 16],
  ROCK_SUN = [14, 15, 16, 17],
  CORAL = [18, 19, 20, 21, 22],
  VIOLET = [24, 25, 26, 27],
  PEACH = [41, 43, 44, 22, 23],
  KELP = [28, 29, 30, 31, 32],
  WOOD = [41, 42, 43, 44];

module.exports = kit => {
  const { makeBuilder, makeSculpt, KIT: K } = kit;
  return {
    id: 'meteor',
    name: 'Meteor reef',
    seed: 5,
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

      // ---------------- isometric camera, noon sun straight overhead
      const CAM = { target: [0, -0.7, 0], dist: 21, pitch: 0.6155, yaw: Math.PI / 4 };
      S.sun = B.norm([0.22, 1, 0.3]);
      S.amb = 0.28;
      S.sky = 0.34;
      S.sunK = 0.95;
      S.res = 0.09;
      S.view = B.norm([Math.sin(CAM.yaw) * Math.cos(CAM.pitch), Math.sin(CAM.pitch), Math.cos(CAM.yaw) * Math.cos(CAM.pitch)]);

      // ---------------- small vector helpers
      const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]],
        sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]],
        mad = (a, b, s) => [a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s],
        dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2],
        cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]],
        lerp = (a, b, u) => [a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u],
        frac = v => v - Math.floor(v),
        hash = (i, j, k) => frac(Math.sin(i * 127.1 + j * 311.7 + k * 74.7) * 43758.5453),
        pickT = (ramp, t) => ramp[clamp(Math.floor(t * ramp.length), 0, ramp.length - 1)],
        // a frame whose y runs along dir
        frameY = dir => {
          const V = B.norm(dir),
            U = B.norm(cross(Math.abs(V[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0], V));
          return [U, V, cross(U, V)];
        },
        // a frame turned about the vertical: its z goes to (sin a, 0, cos a)
        yawF = a => [
          [Math.cos(a), 0, -Math.sin(a)],
          [0, 1, 0],
          [Math.sin(a), 0, Math.cos(a)]
        ],
        // a point given in a thing's own frame F, standing at c (x, z) with its floor at y0
        local = (c, F, y0) => l => [c[0] + F[0][0] * l[0] + F[2][0] * l[2], y0 + l[1], c[1] + F[0][2] * l[0] + F[2][2] * l[2]];

      // ---------------- where things stand (x, z)
      const RES = [0.9, 0.6], // the Big Grey Neighbour, on the dance floor
        COUCH = [-1.55, -0.55],
        SLAB = [-3.3, -1.3],
        HUT = [1.7, -3.1],
        CRATES = [0.4, -2.6],
        TAPE = [3.5, 0.4],
        POLE = [2.6, -1.1],
        BALLXZ = [1.75, -0.25],
        QS = [-0.9, 3.0],
        QS_R = 0.9,
        BON = [-3.6, 1.25];
      const busy = [
        [RES[0], RES[1], 1.35],
        [COUCH[0], COUCH[1], 1.15],
        [SLAB[0], SLAB[1], 1.0],
        [HUT[0], HUT[1], 1.0],
        [CRATES[0], CRATES[1], 0.8],
        [TAPE[0], TAPE[1], 1.0],
        [POLE[0], POLE[1], 0.35],
        [QS[0], QS[1], QS_R + 0.15],
        [BON[0], BON[1], 0.65]
      ];
      const free = (x, z, pad) => busy.every(([bx, bz, br]) => Math.hypot(x - bx, z - bz) > br + (pad || 0));

      // ---------------- the reef floor: nearly level sand, a bowl for the quicksand, a rise for the bonsai
      const ground = (x, z) =>
        0.1 * (B.fbm(x * 0.3 + 2, 1.3, z * 0.3, 2) - 0.5) -
        0.24 * (1 - smooth(0.75, 1.2, Math.hypot(x - QS[0], z - QS[1]) / QS_R)) +
        0.16 * Math.exp(-((x - BON[0]) ** 2 + (z - BON[1]) ** 2) / 1.4);
      const TURF = {
        r: [7, 8, 9, 15],
        mod: (x, y, z) => 0.16 * (B.n3(x * 2.6, y * 4.1, z * 2.6) - 0.5) + 0.05,
        top: {
          min: 0.5,
          r: SAND,
          s: SAND_SUN,
          // ripples in the sand, and patches of seagrass
          tex: (x, y, z, ny, t) => {
            if (B.n3(x * 0.8, z * 0.8, 6.1) > 0.74) return pickT([29, 30, 31], t);
            if (Math.sin(x * 5.5 + z * 2.2 + 3 * B.n3(x * 0.6, z * 0.6, 3.3)) > 0.86) return pickT(SAND_SUN, t - 0.2);
            return undefined;
          }
        }
      };
      let isle = null;
      const ROCKMAT = {
        r: ROCK,
        s: ROCK_SUN,
        b: 0.1,
        mod: (x, y, z) => {
          const bd = isle ? isle.bed(y) : { i: 0, hard: 0.5 };
          return 0.26 * (B.n3(bd.i * 3.1, 0.5, 1.7) - 0.5) + 0.14 * (B.n3(x * 2.2, y * 5.5, z * 2.2) - 0.5);
        },
        // coral crusting the rock here and there
        tex: (x, y, z, ny, t) => (B.n3(x * 5, y * 5, z * 5) > 0.84 ? pickT([18, 19, 20, 25], t) : undefined)
      };
      isle = FI.body(K, B, S, { R: 5.0, thick: 0.7, depth: 3.8, ground, turf: TURF, rock: ROCKMAT, lumps: 10, seed: 6, res: 0.09 });
      const gy = (x, z) => isle.h(x, z);

      // ---------------- the black slab (2001), its broad face to +z
      const slabY = gy(SLAB[0], SLAB[1]) - 0.15;
      S.box([SLAB[0], slabY + 2.03, SLAB[1]], [0.9, 2.03, 0.225], { r: [1, 2, 13, 3], gloss: { c: 5, at: 0.97, c2: 3, at2: 0.93 } }, { res: 0.05 });

      // ---------------- the couch, 1977 orange with stripes, facing +z
      {
        const F = yawF(0.25),
          P = local(COUCH, F, gy(COUCH[0], COUCH[1]) - 0.03),
          stripe = (x, y, z) => {
            const u = (x - COUCH[0]) * F[0][0] + (z - COUCH[1]) * F[0][2],
              b = Math.floor((u + 9) / 0.14) % 3;
            return b === 1 ? 0.28 : b === 2 ? -0.22 : 0;
          },
          UPH = { r: WOOD, s: [42, 43, 44, 23], mod: stripe },
          o = { ax: F, res: 0.035 };
        S.box(P([0, 0.3, 0.05]), [1.0, 0.13, 0.42], UPH, Object.assign({ rd: 0.06 }, o));
        S.box(P([0, 0.66, -0.31]), [1.0, 0.34, 0.13], UPH, Object.assign({ rd: 0.09 }, o));
        for (const s of [-1, 1]) {
          S.box(P([s * 1.04, 0.47, 0.0]), [0.15, 0.24, 0.47], UPH, Object.assign({ rd: 0.08 }, o));
          S.box(P([s * 0.49, 0.5, 0.1]), [0.47, 0.08, 0.35], { r: [42, 43, 44, 23], mod: stripe }, Object.assign({ rd: 0.07 }, o));
          for (const zz of [-0.32, 0.36]) S.lathe(P([s * 0.92, -0.02, zz]), 0.2, [0.035, 0.05], { r: [41, 42] }, { res: 0.02 });
        }
      }

      // ---------------- the dance floor's frame (its lit tiles are drawn after the bake)
      const floorY = gy(RES[0], RES[1]) + 0.09;
      S.box([RES[0], floorY - 0.14, RES[1]], [0.98, 0.14, 0.98], { r: NAVY }, { res: 0.04 });

      // ---------------- the mirror ball's stand (the ball itself turns, below)
      const poleY = gy(POLE[0], POLE[1]) - 0.05,
        CHROMEM = { r: [2, 3, 4, 5], gloss: { c: 47, at: 0.95, c2: 6, at2: 0.88 } },
        BALLY = poleY + 3.35,
        DB = [BALLXZ[0], BALLY, BALLXZ[1]];
      S.lathe([POLE[0], poleY, POLE[1]], 0.08, [0.3, 0.26], CHROMEM, { res: 0.03 });
      S.tube(
        [
          [POLE[0], poleY, POLE[1]],
          [POLE[0], poleY + 3.6, POLE[1]],
          [(POLE[0] + BALLXZ[0]) / 2, poleY + 4.0, (POLE[1] + BALLXZ[1]) / 2],
          [BALLXZ[0], poleY + 3.95, BALLXZ[1]]
        ],
        0.045,
        0.035,
        CHROMEM,
        { res: 0.025 }
      );
      S.tube([[BALLXZ[0], poleY + 3.95, BALLXZ[1]], [BALLXZ[0], BALLY + 0.28, BALLXZ[1]]], 0.012, 0.012, { r: [1, 2] }, { res: 0.02 });

      // ---------------- the tape-reel computer: two cream cabinets facing +x, each with a reel window and a dark panel below it
      const TF = yawF(Math.PI / 2),
        TP = local(TAPE, TF, gy(TAPE[0], TAPE[1]) - 0.05),
        TN = TF[2],
        REELS = [];
      for (const c of [-1, 1]) {
        S.box(TP([c * 0.42, 0.86, 0]), [0.38, 0.86, 0.28], { r: [15, 16, 17, 45], s: [16, 17, 45, 12], mod: (x, y) => (frac(y / 0.3) < 0.04 ? -0.2 : 0) }, { ax: TF, res: 0.035, rd: 0.02 });
        S.box(TP([c * 0.42, 1.2, 0.27]), [0.31, 0.42, 0.025], { r: [1, 2, 3] }, { ax: TF, res: 0.025 });
        S.box(TP([c * 0.42, 0.52, 0.27]), [0.31, 0.15, 0.02], { r: [13, 14] }, { ax: TF, res: 0.025 });
        for (const y of [1.4, 0.99]) REELS.push(TP([c * 0.42, y, 0.31]));
      }

      // ---------------- the fish crates, facing the camera: two open ones full of fish, two closed ones stacked behind
      const CRF = yawF(0.55),
        CRP = local(CRATES, CRF, gy(CRATES[0], CRATES[1]) - 0.03),
        CRATE = { r: WOOD, mod: (x, y) => (frac((y + 9) / 0.1) < 0.16 ? -0.35 : 0.06 * (B.n3(x * 9, y * 2, 1) - 0.5)) },
        CATCH = [
          { r: [3, 46, 5, 6], gloss: { c: 47, at: 0.94 } },
          { r: [19, 20, 21, 22], gloss: { c: 23, at: 0.94 } }
        ],
        fishAt = [];
      [-1, 1].forEach((s, i) => {
        S.box(CRP([s * 0.33, 0.2, 0.2]), [0.3, 0.2, 0.24], CRATE, { ax: CRF, res: 0.03, rd: 0.012 });
        for (let k = 0; k < 9; k++) {
          const p = CRP([s * 0.33 + B.rr(-0.17, 0.17), 0.42 + B.rr(0, 0.04), 0.2 + B.rr(-0.15, 0.15)]),
            a = B.rr(0, TAU);
          S.ball(p, [0.05, 0.04, 0.13], CATCH[i], { ax: yawF(a), res: 0.018 });
          fishAt.push([p, a]);
        }
      });
      for (const y of [0.2, 0.61]) S.box(CRP([0.02, y, -0.33]), [0.3, 0.2, 0.24], CRATE, { ax: CRF, res: 0.03, rd: 0.012 });
      const CATP = CRP([0.04, 0.81, -0.31]);

      // ---------------- the quicksand bowl's level, and the bonsai on its stone
      const QSY = gy(QS[0], QS[1]) + 0.12;
      {
        const by = gy(BON[0], BON[1]),
          x = BON[0],
          z = BON[1];
        S.box([x, by + 0.02, z], [0.56, 0.08, 0.42], { r: ROCK, s: ROCK_SUN }, { res: 0.035, rd: 0.04 });
        S.box([x, by + 0.2, z], [0.42, 0.09, 0.3], { r: [2, 3, 46, 5], gloss: { c: 6, at: 0.95 } }, { res: 0.025, rd: 0.03 });
        S.box([x, by + 0.3, z], [0.38, 0.02, 0.26], { r: [7, 8] }, { res: 0.025 });
        const BARK = { r: [41, 15, 16, 17], mod: (xx, yy, zz) => 0.15 * (B.n3(xx * 14, yy * 4, zz * 14) - 0.5) },
          LEAFM = { r: [28, 29, 30, 31], s: [30, 31, 32], leaf: { l: 0.05, w: 0.03 } },
          trunk = [
            [x, by + 0.3, z],
            [x + 0.14, by + 0.55, z + 0.05],
            [x - 0.1, by + 0.82, z - 0.02],
            [x + 0.06, by + 1.06, z + 0.03],
            [x + 0.16, by + 1.22, z]
          ];
        S.tube(trunk, t => 0.1 * (1 - 0.55 * t) + 0.02, 0, BARK, { res: 0.022 });
        const pads = [
          [x - 0.42, by + 0.86, z + 0.08, 0.34],
          [x + 0.42, by + 0.98, z - 0.05, 0.3],
          [x + 0.16, by + 1.34, z + 0.02, 0.28],
          [x - 0.2, by + 1.16, z - 0.16, 0.24]
        ];
        for (const [px, py, pz, r] of pads) {
          const from = trunk[py > by + 1.1 ? 3 : 2];
          S.tube([from, [(from[0] + px) / 2, py - 0.04, (from[2] + pz) / 2], [px, py - 0.03, pz]], 0.035, 0.022, BARK, { res: 0.02 });
          const G = Object.assign(S.grp(0.06), { res: 0.03 });
          S.ball([px, py, pz], [r, r * 0.38, r * 0.8], LEAFM, G);
          S.ball([px + r * 0.3, py + 0.05, pz - r * 0.2], [r * 0.6, r * 0.3, r * 0.5], LEAFM, G);
        }
      }

      // ---------------- the reef: brain corals, staghorn, sea fans, tube sponges, anemone bases, starfish
      const sources = []; // where bubbles stream up from
      const brain = (x, z, r, ramp) => {
        const y = gy(x, z);
        S.ball([x, y + r * 0.3, z], [r, r * 0.78, r * 0.95], {
          r: ramp,
          mod: (xx, yy, zz) => (Math.abs(Math.sin(xx * 15 + 4 * B.n3(xx * 2, yy * 2, zz * 2)) * Math.sin(zz * 15 + 4 * B.n3(zz * 2, xx * 2, yy * 2))) < 0.18 ? -0.45 : 0.05)
        }, { res: 0.028 });
        busy.push([x, z, r + 0.1]);
        sources.push([x, y + r, z]);
      };
      const stag = (x, z, s, ramp, sd) => {
        const y = gy(x, z);
        for (let k = 0; k < 3; k++) {
          const a = k * 2.1 + sd,
            grown = K.grow.branch({
              at: [x + Math.cos(a) * 0.12 * s, y - 0.05, z + Math.sin(a) * 0.12 * s],
              dir: [Math.cos(a) * 0.3, 1, Math.sin(a) * 0.3],
              len: B.rr(0.5, 0.75) * s,
              r: 0.055 * s,
              depth: 3,
              forks: 2,
              spread: 0.6,
              shrink: 0.74,
              segs: 5,
              light: [0, 1, 0],
              lean: 0.1,
              droop: 0,
              wobble: 0.5,
              seed: sd * 10 + k
            });
          K.grow.limbs(S, grown, { r: ramp, root: 0.35 }, { res: 0.025, melt: 0.025 });
        }
        busy.push([x, z, 0.55 * s]);
        sources.push([x, y + 0.9 * s, z]);
      };
      const fan = (x, z, h, a, ramp) => {
        const y = gy(x, z),
          F = yawF(a),
          c = [x, y + 0.12 + h, z];
        S.tube([[x, y - 0.05, z], [x, y + 0.2, z]], 0.04, 0.03, { r: ramp }, { res: 0.022 });
        S.ball(c, [h * 0.95, h, 0.03], {
          r: ramp,
          // a net: only the threads are kept
          tex: (xx, yy, zz) => {
            const u = (xx - c[0]) * F[0][0] + (zz - c[2]) * F[0][2],
              v = yy - c[1],
              rim = Math.hypot(u / (h * 0.95), v / h) > 0.9;
            return rim || frac((u + v * 0.55 + 9) / 0.1) < 0.3 || frac((u - v * 0.55 + 9) / 0.1) < 0.3 ? undefined : -1;
          }
        }, { ax: F, res: 0.02 });
        busy.push([x, z, 0.5]);
      };
      const tubes = [];
      const sponge = (x, z, s, ramp) => {
        const y = gy(x, z);
        for (let k = 0; k < 4; k++) {
          const a = k * 1.7 + x,
            q = k ? 0.17 * s : 0,
            px = x + Math.cos(a) * q,
            pz = z + Math.sin(a) * q,
            h = (k ? B.rr(0.35, 0.6) : 0.85) * s,
            r = (k ? 0.08 : 0.11) * s;
          S.lathe([px, y - 0.05, pz], h, t => r * (1 + 0.12 * Math.sin(t * 9)) + (t > 0.93 ? 0.015 : 0), { r: ramp }, { res: 0.022 });
          tubes.push([px, y - 0.05 + h, pz, r]);
          sources.push([px, y + h, pz]);
        }
        busy.push([x, z, 0.4 * s]);
      };
      const anemones = [];
      const anemone = (x, z, ramp, tips) => {
        const y = gy(x, z);
        S.lathe([x, y - 0.04, z], 0.16, [0.14, 0.12], { r: ramp }, { res: 0.022 });
        anemones.push([x, y + 0.12, z, ramp, tips]);
        busy.push([x, z, 0.35]);
        sources.push([x, y + 0.3, z]);
      };
      brain(2.4, 2.9, 0.45, CORAL);
      brain(-2.45, 2.35, 0.4, VIOLET);
      brain(4.1, -1.9, 0.38, PEACH);
      brain(-0.9, -3.4, 0.34, KELP.slice(1));
      stag(1.75, 3.55, 1.1, CORAL, 1);
      stag(3.4, 2.4, 0.9, VIOLET, 2);
      stag(-4.2, 0.0, 0.8, PEACH, 3);
      stag(-2.2, -3.0, 0.9, CORAL, 4);
      fan(-1.6, -3.9, 0.55, 0.3, VIOLET);
      fan(4.2, -0.9, 0.45, Math.PI / 2 - 0.3, CORAL);
      fan(-4.1, 2.2, 0.4, -0.5, [24, 25, 19, 20, 21]);
      sponge(0.9, 4.25, 1, PEACH);
      sponge(-3.0, 3.25, 0.9, VIOLET);
      sponge(3.2, -3.4, 0.9, CORAL);
      anemone(0.15, 4.2, CORAL, 23);
      anemone(-1.95, 1.4, KELP.slice(1), 34);
      anemone(2.75, 1.75, VIOLET, 22);
      anemone(-0.6, 1.9, CORAL, 35);
      for (const [x, z, a] of [
        [1.65, 2.45, 0.2],
        [-0.1, 2.75, 1.1],
        [3.9, 1.5, 2.0],
        [-2.7, 0.7, 0.6],
        [0.4, -1.3, 1.6]
      ]) {
        S.extrude(K.poly2.star(5, 0.2, 0.08, a), [x, gy(x, z) + 0.02, z], 0.05, { r: [19, 20, 21, 22] }, {
          ax: [
            [1, 0, 0],
            [0, 0, -1],
            [0, 1, 0]
          ],
          res: 0.018
        });
        busy.push([x, z, 0.25]);
      }

      // ---------------- the Regents crown, carved into a face of the floating rock that looks toward the camera
      {
        const aC = Math.PI / 4,
          yC = -3.05,
          out = [Math.cos(aC), 0, Math.sin(aC)],
          r0 = isle.rockR(yC, aC),
          PC = mad([0, yC, 0], out, r0 + 0.12),
          panel = S.box(PC, [1.02, 0.62, 0.3], { r: [15, 16, 17], mod: ROCKMAT.mod }, { ax: yawF(aC), res: 0.035, rd: 0.05 }),
          s = 0.31,
          g = 0.05,
          loops = [];
        for (let j = 0; j < 3; j++)
          for (let i = 0; i < 5; i++) {
            if (j === 2 && i % 2) continue;
            const cx = (i - 2) * (s + g),
              cy = (j - 1) * (s + g);
            loops.push([
              [cx - s / 2, cy - s / 2],
              [cx + s / 2, cy - s / 2],
              [cx + s / 2, cy + s / 2],
              [cx - s / 2, cy + s / 2]
            ]);
          }
        S.engrave(loops, { on: panel, at: mad(PC, out, 0.3), n: out, up: [0, 1, 0], depth: 0.11, mat: { r: [1, 13, 2] }, res: 0.025 });
      }

      // ---------------- under the rock: stalactites and hanging kelp
      S.ready();
      K.form.drips(S, { box: [-2.4, 2.4, -2.4, 2.4], y: isle.yBot - 0.5, n: 34, gap: 0.45, len: [0.4, 1.0], r: 0.16, mites: false, mat: ROCKMAT, seed: 9, res: 0.04 });
      for (let k = 0; k < 7; k++) {
        const a = (k / 7) * TAU + 1.1,
          y = isle.yTop - 0.5,
          r = isle.rockR(y, a);
        const grown = K.grow.creep(S, { from: [Math.cos(a) * r, y, Math.sin(a) * r], dir: [0, -1, 0], steps: 30, step: 0.12, wander: 0.5, branch: 0.08, seed: 60 + k });
        K.grow.vine(S, grown, { r: [28, 29, 30] }, { r: [29, 30, 31] }, { r: 0.02, size: 0.14, leaves: 0.9, seed: 70 + k });
      }

      rig.own('island', () => S.bake());

      // ---------------- drawn by hand on the island: the lit floor, quicksand, kelp, seagrass, anemones, bubbles, fish, glitches
      rig.own('island', () => {
        // the dance floor: sixteen tiles that flash in a travelling wave, grout left dark
        const TILE = [33, 35, 39, 26, 21, 46];
        for (let i = 0; i < 4; i++)
          for (let j = 0; j < 4; j++) {
            const cx = RES[0] - 0.69 + i * 0.46,
              cz = RES[1] - 0.69 + j * 0.46,
              c = TILE[(i * 2 + j * 3) % TILE.length],
              an = { em: true, k: 4, ph: (i + j) * 0.9, sp: (4 * TAU) / L };
            for (let u = -0.17; u <= 0.171; u += 0.068)
              for (let v = -0.17; v <= 0.171; v += 0.068) B.disc(cx + u, floorY + 0.004, cz + v, B.UP, 0.05, 0.01, B.P[c], 3, an);
          }
        // quicksand: wet sand in slow rings, darker toward the middle
        for (let x = QS[0] - QS_R * 1.2; x < QS[0] + QS_R * 1.2; x += 0.05)
          for (let z = QS[1] - QS_R * 1.2; z < QS[1] + QS_R * 1.2; z += 0.045) {
            const xx = x + (Math.round(z / 0.045) % 2) * 0.025,
              d = Math.hypot(xx - QS[0], z - QS[1]);
            if (gy(xx, z) > QSY - 0.005 || d > QS_R * 1.2) continue;
            const v = B.fbm(xx * 2.5, z * 2.5, 4.1, 2),
              ring = Math.sin(d * 16 - 2 * v) > 0.7,
              c = ring ? 10 : d < 0.3 ? 8 : v > 0.55 ? 10 : 9;
            B.disc(xx, QSY, z, B.UP, 0.045, 0.01, B.P[c], 3);
          }
        // mud bubbles that come up in the quicksand
        for (let i = 0; i < 14; i++) {
          const a = B.rr(0, TAU),
            q = Math.sqrt(B.R()) * QS_R * 0.7;
          B.iso(QS[0] + Math.cos(a) * q, QSY + 0.02, QS[1] + Math.sin(a) * q, 0.035, B.P[B.pick([9, 10, 11])], 3, { k: 3, ph: B.R(), sp: 0.3 / L, rg: 0.3, ex: 1.2 });
        }
        // kelp at the back of the reef: tall strands that wave
        const kelp = [
          [-1.0, -4.2, 5],
          [0.4, -4.4, 4],
          [-3.1, -2.7, 4],
          [4.3, -2.3, 4],
          [-4.5, -1.3, 3],
          [2.9, 3.6, 3]
        ];
        for (const [kx, kz, n] of kelp) {
          busy.push([kx, kz, 0.35]);
          for (let s = 0; s < n; s++) {
            const x0 = kx + B.rr(-0.25, 0.25),
              z0 = kz + B.rr(-0.25, 0.25),
              y0 = gy(x0, z0) - 0.03,
              H = B.rr(1.4, 2.5),
              ph = B.rr(0, 6),
              segs = 16;
            let prev = [x0, y0, z0];
            for (let k = 1; k <= segs; k++) {
              const u = k / segs,
                p = [x0 + 0.13 * Math.sin(u * 4.5 + ph) * u, y0 + u * H, z0 + 0.1 * Math.cos(u * 3.7 + ph) * u],
                d = sub(p, prev),
                len = Math.hypot(...d),
                sw = { k: 11, ph: ph + u * 2.5, sp: 1.9, rg: 0.02 + 0.05 * u },
                col = B.P[pickT(KELP.slice(1), u * 0.9 + 0.05)];
              B.stick((p[0] + prev[0]) / 2, (p[1] + prev[1]) / 2, (p[2] + prev[2]) / 2, B.norm(d), len * 0.6, 0.045 * (1 - 0.4 * u), col, 3, sw);
              if (k % 2 === 0) {
                const side = B.norm([Math.cos(k + ph), 0.5, Math.sin(k + ph)]);
                B.stick(p[0] + side[0] * 0.09, p[1] + side[1] * 0.09, p[2] + side[2] * 0.09, side, 0.1, 0.035, B.P[pickT(KELP.slice(2), u)], 3, sw);
              }
              prev = p;
            }
          }
        }
        // seagrass tufts over the open sand
        let made = 0;
        for (let tries = 0; tries < 2500 && made < 150; tries++) {
          const a = B.rr(0, TAU),
            q = Math.sqrt(B.R()) * 4.6,
            x = Math.cos(a) * q,
            z = Math.sin(a) * q;
          if (q > isle.rim(a) - 0.35 || !free(x, z, 0.1) || B.n3(x * 0.9, z * 0.9, 5.5) < 0.4) continue;
          const y = gy(x, z);
          for (let b = 0; b < 4; b++) {
            const h = B.rr(0.12, 0.26),
              lean = B.norm([B.rr(-0.3, 0.3), 1, B.rr(-0.3, 0.3)]);
            B.stick(x + lean[0] * h * 0.5, y + h * 0.5, z + lean[2] * h * 0.5, lean, h * 0.5, 0.016, B.P[B.pick([29, 30, 31, 32])], 3, { k: 11, ph: B.rr(0, 6), sp: 1.9, rg: 0.015 });
          }
          made++;
        }
        // anemone tentacles, swaying, pale at the tips
        for (const [x, y, z, ramp, tip] of anemones)
          for (let k = 0; k < 30; k++) {
            const a = (k / 30) * TAU + B.rr(-0.1, 0.1),
              rr = B.rr(0.02, 0.11),
              d = B.norm([Math.cos(a) * (0.4 + rr * 4), 1, Math.sin(a) * (0.4 + rr * 4)]),
              h = B.rr(0.14, 0.22),
              sw = { k: 11, ph: a * 2, sp: 1.9, rg: 0.02 };
            const bx = x + Math.cos(a) * rr,
              bz = z + Math.sin(a) * rr;
            B.stick(bx + d[0] * h * 0.5, y + d[1] * h * 0.5, bz + d[2] * h * 0.5, d, h * 0.5, 0.022, B.P[ramp[ramp.length - 2]], 3, sw);
            B.iso(bx + d[0] * h, y + d[1] * h, bz + d[2] * h, 0.026, B.P[tip], 3, sw);
          }
        // the dark mouths of the tube sponges
        for (const [x, y, z, r] of tubes) B.disc(x, y + 0.005, z, B.UP, r * 0.72, 0.01, B.P[B.pick([18, 24, 7])], 3);
        // fish eyes and tails in the open crates
        for (const [p, a] of fishAt) {
          const f = [Math.sin(a), 0, Math.cos(a)];
          B.iso(p[0] + f[0] * 0.09, p[1] + 0.03, p[2] + f[2] * 0.09, 0.016, B.P[47], 3);
          B.disc(p[0] - f[0] * 0.15, p[1] + 0.01, p[2] - f[2] * 0.15, B.norm([f[2], 0.4, -f[0]]), 0.05, 0.01, B.P[4], 3);
        }
        // bubbles: the loop's rise, streaming up from the corals and anemones
        for (const [x, y, z] of sources) {
          const n = 7 + Math.floor(B.R() * 5),
            rg = B.rr(2.6, 3.8);
          for (let i = 0; i < n; i++)
            B.iso(x + B.rr(-0.04, 0.04), y, z + B.rr(-0.04, 0.04), B.rr(0.028, 0.045), B.P[B.pick([5, 6, 6, 47])], 2.4, {
              em: true,
              nd: true,
              k: 3,
              ph: (i + B.R() * 0.5) / n,
              sp: (rg * 2) / L,
              rg,
              ex: 1.0
            });
        }
        // a school of reef fish going round the island
        for (let s = 0; s < 5; s++) {
          const a0 = (s / 5) * TAU + B.rr(-0.3, 0.3),
            rs = B.rr(5.6, 6.6),
            hy = B.rr(0.0, 2.2),
            dir = s % 2 ? 1 : -1,
            cols = [
              [39, 44],
              [46, 5],
              [21, 22],
              [35, 6],
              [33, 34]
            ][s];
          for (let f = 0; f < 9; f++) {
            const a = a0 + B.rr(-0.3, 0.3),
              r = rs + B.rr(-0.4, 0.4),
              y = hy + B.rr(-0.4, 0.4),
              p = [Math.cos(a) * r, y, Math.sin(a) * r],
              tg = [-Math.sin(a) * dir, 0, Math.cos(a) * dir],
              swim = { k: 5, sp: (-dir * TAU * (1 + (s % 2))) / L };
            // a slim body, and a tail fin standing up behind it
            B.stick(p[0], p[1], p[2], tg, 0.1, 0.032, B.P[cols[0]], 3, swim);
            B.stick(p[0] - tg[0] * 0.12, p[1], p[2] - tg[2] * 0.12, B.UP, 0.045, 0.018, B.P[cols[1]], 3, swim);
          }
        }
        // glitch bars across the black slab's face, flashing on and fading out of step with each other
        for (let k = 0; k < 16; k++) {
          const w = B.rr(0.25, 0.85),
            x = SLAB[0] + B.rr(-0.9 + w / 2, 0.9 - w / 2),
            y = slabY + B.rr(0.2, 3.95),
            c = Math.floor(B.rr(3, 12));
          B.stick(x, y, SLAB[1] + 0.24, [1, 0, 0], w / 2, 0.035, B.P[B.pick([33, 35, 47, 34])], 1.3, { em: true, nd: true, k: 2, ph: B.R(), sp: (0.01 * c) / L, rg: 0.01, ex: 0 });
        }
        // seaweed hanging over the rim, and strands and coral crust down the rock
        FI.skirt(B, isle, { ramp: [28, 29, 30, 31, 32], sun: S.sun, len: 0.36, gap: 0.05 });
        for (let i = 0; i < 240; i++) {
          const a = B.rr(0, TAU),
            y = B.rr(isle.yBot + 1.0, isle.yTop - 0.3),
            r = isle.rockR(y, a) + 0.02;
          if (B.n3(Math.cos(a) * 2, y * 0.8, Math.sin(a) * 2) < 0.48) continue;
          const len = B.rr(0.12, 0.45);
          B.stick(Math.cos(a) * r, y - len * 0.5, Math.sin(a) * r, B.UP, len * 0.5, 0.02, B.P[B.pick([28, 29, 29, 30, 19, 25])], 3, { k: 11, ph: B.rr(0, 6), sp: 1.9, rg: 0.015 });
        }
      });

      // ---------------- what moves: made in a bake of its own so nothing still is cut where it stood
      // The Big Grey Neighbour: chrome, hood up, plain eyes, facing +z; it swings a bat in its right paw (on its -x side)
      const BASE = [RES[0], floorY, RES[1]],
        RP = l => [RES[0] + l[0], floorY + l[1], RES[1] + l[2]],
        chrome = (x, y, z, ny, t, nx, nz) => {
          const lx = x - RES[0],
            ly = y - floorY;
          // the belly: a paler patch with the dark chevrons
          if (nz > 0.3 && (lx / 0.52) ** 2 + ((ly - 0.82) / 0.58) ** 2 < 1) {
            for (const [cx, cy] of [
              [-0.2, 1.16],
              [0, 1.18],
              [0.2, 1.16],
              [-0.1, 1.0],
              [0.1, 1.0]
            ]) {
              const dx = lx - cx;
              if (Math.abs(dx) < 0.075 && Math.abs(ly - (cy - 0.5 * Math.abs(dx))) < 0.028) return 3;
            }
            return t > 0.6 ? 47 : 6;
          }
          // the rest mirrors the world: sky above, a dark horizon, the sand below
          const v = ny + 0.14 * (B.n3(x * 2.2, y * 2.2, z * 2.2) - 0.5),
            dim = t < 0.3;
          if (v > 0.78) return dim ? 5 : t > 0.8 ? 47 : 6;
          if (v > 0.42) return dim ? 0 : 5;
          if (v > 0.1) return dim ? 4 : 0;
          if (v > -0.06) return 1;
          if (v > -0.32) return 9;
          if (v > -0.62) return 10;
          return 11;
        },
        CHROME = { r: [2, 3, 4, 5], tex: chrome },
        HOODM = { r: VIOLET, s: [25, 26, 27, 34] },
        TB = { tag: 'body', whole: true },
        G = Object.assign(S.grp(0.12), TB, { res: 0.032 });
      S.ball(RP([0, 0.98, 0]), [0.8, 0.98, 0.72], CHROME, G);
      S.ball(RP([0, 1.82, 0.04]), [0.6, 0.5, 0.56], CHROME, G);
      for (const s of [-1, 1]) S.ball(RP([s * 0.4, 0.07, 0.3]), [0.21, 0.1, 0.25], CHROME, G);
      S.ball(RP([0.74, 1.05, 0.1]), [0.15, 0.42, 0.17], CHROME, Object.assign({ ax: frameY([0.35, 1, 0.1]) }, G));
      for (const s of [-1, 1])
        S.lathe(RP([s * 0.3, 2.0, 0.0]), 0.95, t => 0.17 * Math.sqrt(1 - t) + 0.02, CHROME, Object.assign({ ax: frameY([s * 0.22, 1, -0.05]), res: 0.025 }, TB));
      // the hood, cut open round the face, with a drawstring
      {
        const hood = S.ball(RP([0, 1.86, -0.03]), [0.69, 0.61, 0.65], HOODM, { hold: true }),
          face = S.ball(RP([0, 1.8, 0.52]), [0.47, 0.42, 0.42], HOODM, { hold: true });
        S.join('cut', hood, face, Object.assign({ res: 0.03 }, TB));
        S.torus(RP([0, 1.48, 0.12]), 0.52, 0.06, HOODM, Object.assign({ res: 0.025, ax: frameY([0, 1, 0.3]) }, TB));
        for (const s of [-1, 1]) S.tube([RP([s * 0.13, 1.46, 0.62]), RP([s * 0.15, 1.18, 0.7])], 0.018, 0.018, { r: [45, 12] }, Object.assign({ res: 0.015 }, TB));
      }
      // plain eyes, a nose, whiskers
      for (const s of [-1, 1]) {
        S.ball(RP([s * 0.2, 1.88, 0.56]), [0.1, 0.1, 0.05], { r: [6, 47], em: true, v: 0.9 }, Object.assign({ res: 0.014 }, TB));
        S.ball(RP([s * 0.19, 1.87, 0.6]), [0.05, 0.055, 0.03], { r: [1], em: true }, Object.assign({ res: 0.012 }, TB));
        for (const dy of [-0.04, 0.03]) S.tube([RP([s * 0.3, 1.72 + dy, 0.5]), RP([s * 0.62, 1.76 + dy * 2, 0.46])], 0.012, 0.01, { r: [1, 2] }, Object.assign({ res: 0.012 }, TB));
      }
      S.ball(RP([0, 1.76, 0.6]), [0.07, 0.035, 0.04], { r: [1, 2] }, Object.assign({ res: 0.012 }, TB));

      // the bat arm: built where it meets the meteor
      const SH = RP([-0.62, 1.42, 0.1]),
        DIRC = B.norm([-0.82, 0.2, 0.52]),
        TILT = B.norm(cross(DIRC, [0, 1, 0])),
        TBAT = { tag: 'bat', whole: true },
        HBAT = mad(SH, DIRC, 1.7),
        VHIT = B.norm([-DIRC[2], 0, DIRC[0]]); // where the bat's sweet spot is going as it meets the meteor
      S.tube([SH, mad(SH, DIRC, 0.48)], 0.16, 0.13, CHROME, Object.assign({ res: 0.028 }, TBAT));
      S.ball(mad(SH, DIRC, 0.52), 0.14, CHROME, Object.assign({ res: 0.025 }, TBAT));
      S.lathe(mad(SH, DIRC, 0.36), 1.68, t => (t < 0.04 ? 0.07 : 0.045 + 0.07 * smooth(0.25, 0.85, t)) * (t > 0.95 ? 0.6 : 1), {
        r: [42, 43, 44, 23],
        tex: (x, y, z, ny, t) => (dot(sub([x, y, z], SH), DIRC) < 0.66 ? pickT([1, 2, 3], t) : undefined)
      }, Object.assign({ ax: frameY(DIRC), res: 0.022 }, TBAT));

      // the meteor, at the moment it is hit, its burning tail drawn back the way it came
      // offsets measured on the hero screen: a to the right, b up, d toward the camera
      const SR = [Math.cos(CAM.yaw), 0, -Math.sin(CAM.yaw)],
        SC = [Math.sin(CAM.yaw) * Math.cos(CAM.pitch), Math.sin(CAM.pitch), Math.cos(CAM.yaw) * Math.cos(CAM.pitch)],
        SU = cross(SC, SR),
        onScreen = (a, b, d) => mad(mad(mad([0, 0, 0], SR, a), SU, b), SC, d);
      const HM = mad(HBAT, VHIT, 0.62),
        A0 = add(HM, onScreen(-7, 6.5, 2)), // where it falls from: just out of the picture, top left
        C0 = add(HM, onScreen(9, 7, -1)), // where the hit sends it: out of the picture, top right
        DIN = B.norm(sub(HM, A0)),
        DOUT = B.norm(sub(C0, HM)),
        TURN = B.norm(cross(DIN, DOUT)),
        PHI = Math.acos(clamp(dot(DIN, DOUT), -1, 1));
      S.rock(HM, [0.44, 0.4, 0.42], {
        r: [13, 36, 14, 15],
        // lava in the cracks, and the face it falls on white hot
        tex: (x, y, z, ny, t, nx, nz) => {
          const cr = Math.abs(B.n3(x * 7, y * 7, z * 7) - 0.5),
            front = nx * DIN[0] + ny * DIN[1] + nz * DIN[2];
          if (front > 0.72) return t > 0.5 ? 40 : 39;
          if (front > 0.45 || cr < 0.045) return 38;
          if (cr < 0.08) return 37;
          return undefined;
        }
      }, { tag: 'meteor', whole: true, res: 0.03 });

      // the cat on the crates: body still, head and tail move
      // drawn in its own units, then made 1.4 times bigger so it reads at the hero distance
      const CK = 1.4,
        ck = v => (Array.isArray(v) ? v.map(q => q * CK) : v * CK),
        CF = yawF(0.6),
        CP = l => local([CATP[0], CATP[2]], CF, CATP[1])(ck(l)),
        FUR = { r: [1, 1, 2, 3], s: [1, 2, 3, 4] },
        CATN = CP([0, 0.3, 0.08]),
        TAILB = CP([0, 0.06, -0.17]);
      {
        const Gc = Object.assign(S.grp(0.05), { res: 0.02 });
        S.ball(CP([0, 0.17, -0.02]), ck([0.14, 0.17, 0.18]), FUR, Object.assign({ ax: CF }, Gc));
        for (const s of [-1, 1]) {
          S.ball(CP([s * 0.09, 0.1, -0.07]), ck([0.07, 0.1, 0.12]), FUR, Object.assign({ ax: CF }, Gc));
          S.tube([CP([s * 0.05, 0.22, 0.1]), CP([s * 0.05, 0.02, 0.13])], ck(0.035), ck(0.03), FUR, Gc);
        }
        const TH = { tag: 'cathead', whole: true, res: 0.018 };
        S.ball(CP([0, 0.41, 0.1]), ck([0.13, 0.11, 0.11]), FUR, Object.assign({ ax: CF }, TH));
        S.ball(CP([0, 0.37, 0.19]), ck([0.05, 0.035, 0.035]), { r: [3, 4] }, Object.assign({ ax: CF }, TH));
        for (const s of [-1, 1]) S.lathe(CP([s * 0.075, 0.47, 0.08]), ck(0.11), t => ck(0.05 * (1 - t) + 0.006), FUR, Object.assign({ ax: frameY(add(mad([0, 0, 0], CF[0], s * 0.35), [0, 1, 0])) }, TH));
        S.tube([TAILB, CP([0.04, 0.07, -0.32]), CP([0.12, 0.24, -0.37]), CP([0.1, 0.43, -0.31])], ck(0.034), ck(0.028), FUR, { tag: 'cattail', whole: true, res: 0.018 });
      }

      // the hut on chicken legs, parked and treading, an OPEN sign on its roof
      const HF = yawF(0),
        hutY = gy(HUT[0], HUT[1]),
        HP = local(HUT, HF, hutY),
        HUTB = HP([0, 0, 0]),
        HIPS = [HP([-0.32, 1.15, 0]), HP([0.32, 1.15, 0])];
      {
        const TH = { tag: 'hut', whole: true },
          LOGS = { r: WOOD, s: [42, 43, 44, 23], mod: (x, y) => (frac((y - hutY) / 0.13) < 0.18 ? -0.32 : 0.05 * (B.n3(x * 8, y * 3, 1) - 0.5)) };
        S.box(HP([0, 1.2, 0]), [0.7, 0.06, 0.62], { r: [41, 42] }, Object.assign({ ax: HF, res: 0.03 }, TH));
        S.box(HP([0, 1.74, 0]), [0.6, 0.5, 0.54], LOGS, Object.assign({ ax: HF, res: 0.03, rd: 0.03 }, TH));
        const RH = 0.62,
          RD = 0.72,
          rl = Math.hypot(RD, RH);
        S.convex(
          HP([0, 2.24, 0]),
          [
            { n: [0, -1, 0], d: 0 },
            { n: [0, RD / rl, RH / rl], d: (RH * RD) / rl },
            { n: [0, RD / rl, -RH / rl], d: (RH * RD) / rl },
            { n: [1, 0, 0], d: 0.74 },
            { n: [-1, 0, 0], d: 0.74 }
          ],
          { r: [2, 3, 4, 5], mod: (x, y) => (frac((y - hutY) / 0.1) < 0.22 ? -0.2 : 0.07 * (B.n3(Math.floor(x / 0.14), Math.floor(y / 0.1), 3) - 0.5)) },
          Object.assign({ res: 0.03 }, TH)
        );
        S.box(HP([0.38, 2.7, -0.22]), [0.1, 0.28, 0.1], { r: ROCK, s: ROCK_SUN }, Object.assign({ res: 0.025 }, TH));
        S.box(HP([-0.2, 1.58, 0.55]), [0.17, 0.33, 0.03], { r: [41, 1, 42] }, Object.assign({ ax: HF, res: 0.02 }, TH));
        S.box(HP([0.3, 1.82, 0.55]), [0.14, 0.14, 0.03], { r: [2, 3, 4] }, Object.assign({ ax: HF, res: 0.02 }, TH));
        S.box(HP([0.3, 1.82, 0.57]), [0.015, 0.15, 0.02], { r: [41, 42] }, Object.assign({ ax: HF, res: 0.015 }, TH));
        S.box(HP([0.3, 1.82, 0.57]), [0.15, 0.015, 0.02], { r: [41, 42] }, Object.assign({ ax: HF, res: 0.015 }, TH));
        // the sign: a dark board on two posts on the ridge, the word in pink neon
        const signC = HP([0, 3.22, 0.06]);
        for (const s of [-1, 1]) S.tube([HP([s * 0.55, 2.7, 0.0]), HP([s * 0.55, 3.0, 0.03])], 0.025, 0.025, { r: [1, 2] }, Object.assign({ res: 0.02 }, TH));
        S.box(signC, [0.84, 0.29, 0.03], { r: [1, 2] }, Object.assign({ ax: HF, res: 0.025 }, TH));
        S.strokes(K.poly2.text('OPEN', 0.42, { width: 0.085 }), mad(signC, HF[2], 0.05), 0.04, { r: [33, 33, 34], em: true, v: 0.4 }, Object.assign({ ax: [HF[0], [0, 1, 0], HF[2]], res: 0.016 }, TH));
        // two chicken legs, each its own part, turning at the hip
        HIPS.forEach((hip, k) => {
          const s = k ? 1 : -1,
            TL = { tag: k ? 'legR' : 'legL', whole: true },
            SKIN = { r: [42, 43, 44, 23], mod: (x, y, z) => 0.14 * (B.n3(x * 14, y * 14, z * 14) - 0.5) },
            knee = HP([s * 0.36, 0.66, 0.24]),
            ankle = HP([s * 0.36, 0.14, -0.04]);
          S.ball(hip, [0.22, 0.2, 0.22], { r: [17, 45, 12], leaf: { l: 0.06, w: 0.03 } }, Object.assign({ res: 0.03 }, TL));
          S.tube([hip, knee], 0.14, 0.09, SKIN, Object.assign({ res: 0.025 }, TL));
          S.tube([knee, ankle], 0.07, 0.055, SKIN, Object.assign({ res: 0.02 }, TL));
          for (const toe of [[-0.13, -0.11, 0.3], [0, -0.11, 0.36], [0.13, -0.11, 0.3], [0, -0.1, -0.2]])
            S.tube([ankle, add(ankle, toe)], 0.04, 0.025, SKIN, Object.assign({ res: 0.018 }, TL));
        });
      }

      // the reels of the tape computer
      REELS.forEach((c, k) => {
        const Fr = frameY(TN);
        S.lathe(mad(c, TN, -0.02), 0.04, 0.17, {
          r: [5, 6, 45],
          tex: (x, y, z) => {
            const d = sub([x, y, z], c),
              u = dot(d, TF[0]),
              v = d[1],
              r = Math.hypot(u, v),
              sector = frac((Math.atan2(v, u) * 3) / TAU + 1);
            if (r < 0.04) return 1;
            if (r < 0.13) return sector < 0.3 ? 1 : 41;
            return 47;
          }
        }, { ax: Fr, tag: 'reel' + k, whole: true, res: 0.012 });
      });

      // the mirror ball
      S.ball(DB, 0.3, {
        r: [2, 3, 4, 0, 5, 6, 47],
        tex: (x, y, z, ny, t) => {
          const d = sub([x, y, z], DB),
            lat = Math.asin(clamp(d[1] / 0.3, -1, 1)),
            lon = Math.atan2(d[2], d[0]),
            fi = lat / 0.2,
            fj = (lon * Math.cos(lat)) / 0.2;
          if (frac(fi) < 0.14 || frac(fj) < 0.14) return 2;
          return pickT([3, 4, 0, 5, 6, 47], t + 0.6 * (hash(Math.floor(fi), Math.floor(fj), 3) - 0.5));
        }
      }, { tag: 'disco', whole: true, res: 0.02 });

      // jellyfish under the rock: a glowing bell each, its own part, rising and sinking
      const JELLY = [];
      for (let k = 0; k < 6; k++) {
        const a = (k / 6) * TAU + Math.PI / 4 + Math.PI / 6, // two of them flank the carved crown, none hangs in front of it
          r = 2.55 + 0.45 * (k % 2),
          y = isle.yBot + 0.9 - 0.6 * (k % 3),
          c = [Math.cos(a) * r, y, Math.sin(a) * r],
          ramp = k % 2 ? [24, 25, 26, 27, 34] : [18, 19, 20, 21, 34],
          R0 = 0.36 + 0.08 * ((k * 7) % 3) / 2,
          tag = 'jelly' + k;
        S.lathe(c, R0 * 0.95, t => R0 * Math.sqrt(Math.max(0, 1 - t * t)) * (1 - 0.1 * t) + 0.012, {
          r: ramp,
          em: true,
          v: 0.55,
          tex: (x, yy, z) => {
            const h = (yy - c[1]) / (R0 * 0.95),
              ang = Math.atan2(z - c[2], x - c[0]);
            if (h > 0.72) return ramp[4];
            if (h < 0.1) return ramp[3];
            return Math.sin(ang * 8) > 0.55 ? ramp[3] : ramp[2];
          }
        }, { tag, whole: true, res: 0.025 });
        JELLY.push({ c, R0, ramp, tag, tilt: B.norm([Math.sin(a), 0, -Math.cos(a)]), n: 1 + (k % 2), ph: k * 1.3 });
      }

      // the pith helmet going under in the quicksand
      const HATP = [QS[0] + 0.22, QSY, QS[1] - 0.12];
      S.ball(add(HATP, [0, -0.02, 0]), [0.26, 0.24, 0.3], { r: [10, 11, 12, 45] }, { tag: 'hat', whole: true, res: 0.02 });
      S.ball(add(HATP, [0, 0.02, 0]), [0.42, 0.03, 0.46], { r: [10, 11, 12] }, { tag: 'hat', whole: true, res: 0.02 });
      S.torus(add(HATP, [0, 0.07, 0]), 0.26, 0.035, { r: [36, 37] }, { tag: 'hat', whole: true, res: 0.015 });

      S.bake();

      // ---------------- drawn by hand on the parts that move
      // the meteor's tail: white at the head, through orange to smoke, every flame flickering
      rig.own('meteor', () => {
        const back = [-DIN[0], -DIN[1], -DIN[2]],
          U = B.norm(cross(Math.abs(back[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0], back)),
          V = cross(back, U);
        for (let i = 0; i < 900; i++) {
          const s = Math.pow(B.R(), 0.85),
            dist = 0.2 + s * 3.0,
            spread = (0.4 * (1 - s) + 0.07) * Math.sqrt(B.R()),
            a = B.R() * TAU,
            p = mad(mad(mad(HM, back, dist), U, Math.cos(a) * spread), V, Math.sin(a) * spread),
            smoke = s > 0.78,
            c = s < 0.12 ? B.pick([40, 47]) : s < 0.3 ? 39 : s < 0.55 ? 38 : s < 0.78 ? 37 : B.pick([3, 2, 15]);
          B.stick(p[0], p[1], p[2], back, 0.1 + 0.08 * (1 - s), 0.06 * (1 - 0.5 * s), B.P[c], smoke ? 0.85 : 3, { em: !smoke, nd: true, k: 1, ph: B.rr(0, 6), sp: B.rr(10, 16) });
        }
        B.iso(HM[0], HM[1], HM[2], 0.72, B.P[39], 0.32, { em: true, nd: true, k: 7, ph: 0, sp: 14 });
        for (let i = 0; i < 40; i++) {
          const p = mad(mad(HM, back, B.rr(0.3, 2.6)), B.randDir(), B.rr(0.2, 0.6));
          B.iso(p[0], p[1], p[2], 0.03, B.P[B.pick([39, 40, 47])], 3, { em: true, nd: true, k: 1, ph: B.rr(0, 6), sp: B.rr(8, 14) });
        }
      });
      // the flash where bat meets rock, shown only for the instant of the hit (parked far above the rest of the loop)
      rig.own('pow', () => {
        for (let i = 0; i < 18; i++) {
          const d = B.randDir(),
            l = B.rr(0.25, 0.55);
          B.stick(HM[0] + d[0] * (0.5 + l), HM[1] + d[1] * (0.5 + l), HM[2] + d[2] * (0.5 + l), d, l, 0.05, B.P[i % 3 ? 40 : 47], 3, { em: true, nd: true });
        }
        for (let i = 0; i < 14; i++) {
          const d = B.randDir(),
            q = mad(HM, d, B.rr(0.8, 1.4));
          B.stick(q[0], q[1], q[2], [0.707, 0, -0.707], B.rr(0.15, 0.4), 0.04, B.P[B.pick([33, 35])], 3, { em: true, nd: true });
        }
        B.iso(HM[0], HM[1], HM[2], 0.55, B.P[47], 3, { em: true, nd: true });
      });
      rig.own('cathead', () => {
        for (const s of [-1, 1]) {
          const e = CP([s * 0.05, 0.43, 0.2]);
          B.iso(e[0], e[1], e[2], ck(0.03), B.P[32], 3, { em: true });
          B.stick(e[0] + CF[2][0] * 0.016, e[1], e[2] + CF[2][2] * 0.016, B.UP, ck(0.022), 0.012, B.P[1], 3);
        }
      });
      rig.own('disco', () => {
        for (let i = 0; i < 16; i++) {
          const d = B.randDir();
          B.star(DB[0] + d[0] * 0.31, DB[1] + d[1] * 0.31, DB[2] + d[2] * 0.31, 0.08, 47, { em: true, nd: true, k: 4, ph: B.rr(0, 6), sp: B.rr(2, 5) });
        }
      });
      rig.own('hut', () => {
        const top = HP([0.38, 3.0, -0.22]);
        for (let i = 0; i < 30; i++)
          B.iso(top[0] + B.rr(-0.05, 0.05), top[1], top[2] + B.rr(-0.05, 0.05), 0.09, B.P[B.pick([5, 6, 6, 0])], 0.6, { nd: true, k: 3, ph: B.R(), sp: 1.8 / L, rg: 1.8, ex: 2.0 });
      });
      for (const j of JELLY)
        rig.own(j.tag, () => {
          // tentacles trailing down, rippling
          for (let t = 0; t < 10; t++) {
            const a = (t / 10) * TAU,
              len = B.rr(1.4, 2.4),
              segs = 16;
            let prev = [j.c[0] + Math.cos(a) * j.R0 * 0.9, j.c[1], j.c[2] + Math.sin(a) * j.R0 * 0.9];
            for (let k = 1; k <= segs; k++) {
              const u = k / segs,
                p = [prev[0] + Math.cos(a) * 0.012 + 0.03 * Math.sin(u * 7 + t), j.c[1] - u * len, prev[2] + Math.sin(a) * 0.012 + 0.03 * Math.cos(u * 6 + t)],
                d = sub(p, prev);
              B.stick((p[0] + prev[0]) / 2, (p[1] + prev[1]) / 2, (p[2] + prev[2]) / 2, B.norm(d), Math.hypot(...d) * 0.62, 0.02, B.P[j.ramp[u < 0.5 ? 3 : 2]], 3, { k: 11, ph: t + u * 3, sp: 1.9, rg: 0.025 + 0.04 * u });
              prev = p;
            }
          }
          // four frilled arms from the middle
          for (let t = 0; t < 4; t++) {
            const a = (t / 4) * TAU + 0.4;
            for (let k = 0; k < 9; k++) {
              const u = k / 8;
              B.iso(j.c[0] + Math.cos(a) * 0.06 + 0.04 * Math.sin(u * 8 + t), j.c[1] - 0.05 - u * 1.0, j.c[2] + Math.sin(a) * 0.06, 0.05 - 0.02 * u, B.P[j.ramp[4]], 3, { em: true, k: 11, ph: t + u * 2, sp: 1.9, rg: 0.03 });
            }
          }
        });
      // the quicksand's slow swirl, turning about its middle
      rig.own('swirl', () => {
        for (let arm = 0; arm < 3; arm++)
          for (let s = 0; s < 1; s += 0.018) {
            const r = 0.08 + s * QS_R * 0.95,
              a = (arm / 3) * TAU + s * 4.2;
            B.disc(QS[0] + Math.cos(a) * r, QSY + 0.006, QS[1] + Math.sin(a) * r, B.UP, 0.04, 0.008, B.P[s < 0.5 ? 7 : 8], 3);
            B.disc(QS[0] + Math.cos(a + 0.35) * r, QSY + 0.006, QS[1] + Math.sin(a + 0.35) * r, B.UP, 0.03, 0.008, B.P[11], 3);
          }
      });

      // ---------------- what is not on the island: snow falling, glitch tears in the air, the stars
      for (let i = 0; i < 320; i++)
        B.iso(B.rr(-7, 7), 8.5, B.rr(-7, 7), B.rr(0.026, 0.046), B.P[B.pick([47, 47, 6])], 3, { em: true, nd: true, k: 2, ph: B.R(), sp: 12 / L, rg: 12, ex: 0 });
      for (let i = 0; i < 40; i++) {
        const c = Math.floor(B.rr(3, 12));
        B.stick(B.rr(-6, 6), B.rr(-4, 6), B.rr(-6, 6), [0.707, 0, -0.707], B.rr(0.15, 0.7), 0.035, B.P[B.pick([33, 35, 47])], 1.25, { em: true, nd: true, k: 2, ph: B.R(), sp: (0.01 * c) / L, rg: 0.01, ex: 0 });
      }
      FI.backdrop(B, { stars: 320, starCols: [6, 47, 5, 35], bokeh: 0, clouds: [] });

      const W = B.finish({
        cam: CAM,
        detail: 19.4,
        dither: 0.55,
        radius: 10,
        palName: 'Punk Teal',
        fog: { c: 0, start: 0.82, max: 0.15 },
        outline: { c: 1, edge: 0.6 },
        ao: { k: 0.4, range: 0.5 }
      });
      FI.loopable(W, L);
      const st = K.stage(W);
      rig.bind(st);

      // ---------------- the loop
      const HIT = 4.0,
        I = M.id(),
        Ry = a => M.rot([0, 1, 0], a),
        sm = (a, b, x) => smooth(a, b, x);
      // the meteor falls from A0 to the bat, is sent off toward C0, and goes round high above every view back to A0
      const meteorAt = tau => {
        if (tau < HIT) {
          const u = tau / HIT;
          return lerp(A0, HM, 0.6 * u + 0.4 * u * u);
        }
        if (tau < 6) {
          const v = (tau - HIT) / (6 - HIT);
          return lerp(HM, C0, 1.6 * v - 0.6 * v * v);
        }
        const s = (tau - 6) / 2,
          P1 = add(C0, [0, 30, 0]),
          P2 = add(A0, [0, 30, 0]),
          q = 1 - s;
        return [0, 1, 2].map(i => q * q * q * C0[i] + 3 * q * q * s * P1[i] + 3 * q * s * s * P2[i] + s * s * s * A0[i]);
      };
      // its tail swings round to trail behind it when it is hit, and back while it is out of sight
      const turnAt = tau => (tau < HIT ? 0 : tau < HIT + 0.12 ? PHI * sm(HIT, HIT + 0.12, tau) : tau < 6 ? PHI : PHI * (1 - sm(6, 8, tau)));
      // the swing: the bat held up over the shoulder, cocked, swung through the meteor, followed through, brought back
      const AR = 0.9,
        TR = 1.15;
      const batAt = tau => {
        if (tau < 3.4) {
          const wg = 0.07 * Math.sin((TAU * tau) / 1.7);
          return [AR + wg, TR + 0.5 * wg];
        }
        if (tau < 3.75) {
          const k = sm(3.4, 3.75, tau);
          return [AR + 0.35 * k, TR + 0.12 * k];
        }
        if (tau < HIT) {
          const u = (tau - 3.75) / (HIT - 3.75),
            k = u * u;
          return [(AR + 0.35) * (1 - k), (TR + 0.12) * (1 - k)];
        }
        if (tau < 4.35) {
          const u = (tau - HIT) / 0.35,
            k = 1 - (1 - u) * (1 - u);
          return [-1.75 * k, 0.45 * k];
        }
        if (tau < 7.2) {
          const k = sm(4.35, 7.2, tau);
          return [-1.75 + (AR + 1.75) * k, 0.45 + (TR - 0.45) * k];
        }
        return [AR, TR];
      };
      const wrap = a => Math.atan2(Math.sin(a), Math.cos(a)),
        catFace = Math.atan2(CF[2][0], CF[2][2]),
        POWV = S.view;
      st.add({
        update(dt, t) {
          const tau = ((t % L) + L) % L,
            w = (TAU * tau) / L,
            bob = 0.1 * Math.sin(w),
            lift = p => [p[0], p[1] + bob, p[2]];
          rig.set('island', I, [0, 0, 0], [0, bob, 0]);
          // the meteor, spinning twice a loop about the way it falls
          const mp = meteorAt(tau);
          rig.set('meteor', M.mul(M.rot(TURN, turnAt(tau)), M.rot(DIN, 2 * w)), HM, mp);
          rig.set('pow', M.rot(POWV, 3 * w), HM, tau >= HIT - 1e-4 && tau < HIT + 0.3 ? HM : add(HM, [0, 400, 0]));
          // the neighbour turns its body into the swing; the bat arm turns about the shoulder
          const [a, th] = batAt(tau),
            b = (0.2 * clamp(a, -1.75, 1.3)) / 1.3;
          rig.set('body', Ry(b), BASE, lift(BASE));
          rig.child('bat', 'body', M.mul(Ry(a), M.rot(TILT, th)), SH);
          // the cat follows the meteor with its head while it is near, and swishes its tail
          const md = sub(mp, CATN),
            wt = sm(0.5, 1.5, tau) * (1 - sm(5.2, 6.4, tau)),
            look = clamp(wrap(Math.atan2(md[0], md[2]) - catFace), -1.2, 1.2),
            up = clamp(Math.atan2(md[1], Math.hypot(md[0], md[2])), 0, 0.6);
          rig.set('cathead', M.mul(Ry(look * wt), M.rot(CF[0], -up * wt)), CATN, lift(CATN));
          rig.set('cattail', M.rot(CF[2], 0.45 * Math.sin(2 * w)), TAILB, lift(TAILB));
          // the hut treads: a foot up, then the other, twice each a loop
          const s2 = Math.sin(2 * w),
            hb = 0.05 * (1 + Math.cos(4 * w)) * 0.5;
          rig.set('hut', M.mul(Ry(0.07 * Math.sin(w)), M.rot(HF[2], 0.05 * s2)), HUTB, lift(add(HUTB, [0, hb, 0])));
          rig.child('legL', 'hut', M.rot(HF[0], -0.5 * Math.max(0, s2)), HIPS[0]);
          rig.child('legR', 'hut', M.rot(HF[0], -0.5 * Math.max(0, -s2)), HIPS[1]);
          // tape reels run and stop, the mirror ball turns, the jellyfish rise and sink, the quicksand swirls, the hat bobs
          REELS.forEach((c, k) => rig.set('reel' + k, M.rot(TN, (k % 2 ? 1 : -1) * (2 * w + 0.6 * Math.sin(2 * w + k))), c, lift(c)));
          rig.set('disco', Ry(2 * w), DB, lift(DB));
          for (const j of JELLY) {
            const s = Math.sin(j.n * w + j.ph);
            rig.set(j.tag, M.rot(j.tilt, 0.1 * s), j.c, lift(add(j.c, [0, 0.32 * s, 0])));
          }
          rig.set('swirl', Ry(-w), [QS[0], QSY, QS[1]], lift([QS[0], QSY, QS[1]]));
          rig.set('hat', M.rot([1, 0, 0], 0.15 * Math.sin(w)), HATP, lift(add(HATP, [0, 0.04 * Math.sin(2 * w) - 0.02, 0])));
          rig.apply();
        }
      });
      return W;
    }
  };
};
