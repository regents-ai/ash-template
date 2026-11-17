/* A floating island at night: a great tree on a knoll, two pines, a cottage with its garden, a campfire, a pond whose stream runs off
   the edge as a waterfall, flowers, rocks and mushrooms; underneath, bedded rock with roots, vines, stalactites and a glowing crystal
   cluster; round it, stars, soft lights, clouds and a few birds. Seeded: it builds the same way every time. */
const FI = require('./floating-island.cjs');

const L = 8; // seconds in one full turn of the loop: every repeating motion comes round in this time

// 48 colours, each ramp shifting hue as it goes from dark to light
const PAL = [
  0x101934, 0x1b2850, 0x2e4274, 0x5a72a8, // 0-3   night sky, bokeh, cloud
  0x0b1a1e, 0x11292a, 0x173a30, 0x1f4d36, 0x29623b, 0x3a7a3f, 0x578f42, 0x82ab4b, 0xb8cf62, // 4-12  greens, teal to yellow
  0x183f3c, 0x2c5f52, 0x4c8466, // 13-15 pine needles
  0x1a1014, 0x2c1a1a, 0x482820, 0x6b3c28, 0x93582e, // 16-20 bark and earth
  0x5e4632, 0x8a6a48, // 21-22 trodden path
  0x14182a, 0x22263c, 0x363852, 0x4f4c64, 0x706878, 0x958a8c, 0xb8b0a2, // 23-29 rock, blue-grey through mauve to warm grey
  0x0c2244, 0x133b6c, 0x1f5f96, 0x3d8fc1, 0x7cc6e0, 0xd8f4f8, // 30-35 water and crystal
  0x4a1410, 0xa52a14, 0xe8641e, 0xffa832, 0xffd86a, 0xfff4c4, // 36-41 fire
  0xd86a9c, 0x9a72d8, 0xe8e2d0, // 42-44 flowers, cream
  0xb49c78, // 45    plaster
  0x7a3030, 0xb04c38 // 46-47 roof tiles
];

// each ramp dark to light; *_MOON is the same thing where the moon reaches it, *_FIRE where the campfire or a window is the main light
const GRASS = [4, 5, 6, 7, 8, 9, 10],
  GRASS_MOON = [7, 8, 9, 10, 11, 12],
  GRASS_FIRE = [9, 11, 12, 40],
  LEAF = [4, 5, 6, 7, 8, 9, 10],
  LEAF_MOON = [6, 7, 8, 9, 10, 11, 12],
  LEAF_FIRE = [8, 10, 11, 12],
  NEEDLE = [4, 13, 14, 15],
  NEEDLE_MOON = [13, 14, 15, 11],
  BARK = [16, 17, 18, 19, 20],
  BARK_MOON = [17, 18, 19, 20],
  BARK_FIRE = [17, 19, 20, 39],
  ROCK = [23, 24, 25, 26, 27, 28],
  ROCK_MOON = [24, 25, 26, 27, 28, 29],
  ROCK_FIRE = [26, 27, 28, 39],
  MOSS = [6, 7, 8, 9, 10],
  PATH = [18, 21, 22, 45],
  WATER = [31, 32, 33, 34, 35],
  PLASTER = [18, 21, 45, 44],
  ROOF = [16, 36, 46, 47],
  ROOF_MOON = [36, 46, 47, 29],
  CRYSTAL = [31, 32, 33, 34, 35];

module.exports = kit => {
  const { makeBuilder, makeSculpt, KIT: K, flame } = kit;
  return {
    id: 'island',
    name: 'Floating island',
    seed: 11,
    loop: L,
    build(seed) {
      const B = makeBuilder(seed, PAL),
        S = K.sculpt(makeSculpt(B)),
        rig = K.rig(B, S),
        { clamp, smooth, TAU } = FI;
      const ISL = rig.part('island');
      rig.resolve = () => ISL;
      S.sun = B.norm([-0.55, 0.72, 0.42]);
      S.amb = 0.2;
      S.sky = 0.3;
      S.sunK = 0.9;
      S.res = 0.085;

      // ---------------- where things stand
      const TREE = [0.7, -0.6],
        FIRE = [-1.3, 1.65],
        POND = [3.55, 1.55],
        POND_R = [1.0, 0.75],
        STREAM = [
          [4.3, 2.0],
          [5.2, 2.45],
          [6.6, 3.0]
        ],
        HOUSE = [0.6, -3.75],
        GARDEN = [-1.25, -4.25],
        PATHPTS = [
          [0.6, -4.45],
          [1.5, -4.3],
          [2.25, -3.2],
          [2.45, -1.5],
          [2.0, 0.25],
          [0.8, 1.45],
          [-0.6, 1.95]
        ];
      const segDist = (pts, x, z) => {
        let d = 1e9;
        for (let i = 0; i < pts.length - 1; i++) {
          const a = pts[i],
            b = pts[i + 1],
            bx = b[0] - a[0],
            bz = b[1] - a[1],
            t = clamp(((x - a[0]) * bx + (z - a[1]) * bz) / (bx * bx + bz * bz), 0, 1);
          d = Math.min(d, Math.hypot(x - a[0] - bx * t, z - a[1] - bz * t));
        }
        return d;
      };
      const pondD = (x, z) => Math.hypot((x - POND[0]) / POND_R[0], (z - POND[1]) / POND_R[1]);
      const WL = -0.1; // the water's level
      const ground = (x, z) =>
        0.42 * Math.exp(-((x - TREE[0]) ** 2 + (z - TREE[1]) ** 2) / 3.2) +
        0.12 * (B.fbm(x * 0.35 + 3, 1.7, z * 0.35, 2) - 0.5) -
        0.34 * (1 - smooth(0.55, 1.12, pondD(x, z))) -
        0.2 * (1 - smooth(0.12, 0.3, segDist(STREAM, x, z))) -
        0.06 * (1 - smooth(0.3, 0.6, segDist(PATHPTS, x, z)));

      // ---------------- materials
      const pathW = (x, z) => 0.36 + 0.1 * (B.n3(x * 1.3, z * 1.3, 2.2) - 0.5);
      const TURF = {
        // a lighter, greyer earth than bark, so the rim reads as a thin lip of soil under the grass rather than a heavy brown band
        r: [19, 21, 22, 45],
        s: [21, 22, 45, 44],
        mod: (x, y, z) => 0.16 * (B.n3(x * 2.6, y * 4.1, z * 2.6) - 0.5) + 0.08,
        // stones and root ends showing in the earth of the rim
        tex: (x, y, z, ny, t) => {
          const s = B.n3(x * 5.5, y * 5.5, z * 5.5);
          if (s > 0.8) return ROCK[clamp(Math.floor(t * ROCK.length + 1.5), 0, ROCK.length - 1)];
          if (s < 0.12) return BARK[clamp(Math.floor(t * BARK.length + 1), 0, BARK.length - 1)];
          return undefined;
        },
        top: {
          min: 0.5,
          r: GRASS,
          s: GRASS_MOON,
          g: GRASS_FIRE,
          blade: { h: 0.1, w: 0.024 },
          tex: (x, y, z, ny, t) => {
            // under the water of the pond and the stream (the rim's lip also dips this low, and stays grass)
            if (y < WL + 0.02 && (pondD(x, z) < 1.3 || segDist(STREAM, x, z) < 0.45)) return PATH[0];
            const pd = segDist(PATHPTS, x, z);
            if (pd < pathW(x, z)) {
              const peb = B.n3(x * 9, z * 9, 1.1) > 0.78 ? 0.25 : 0;
              return PATH[clamp(Math.floor((t + peb + 0.15) * PATH.length), 0, PATH.length - 1)];
            }
            return undefined;
          }
        }
      };
      const ROCKMAT = {
        r: ROCK,
        s: ROCK_MOON,
        g: [25, 32, 33, 34],
        b: 0.1,
        mod: (x, y, z) => {
          const bd = isle ? isle.bed(y) : { i: 0, hard: 0.5 };
          return 0.26 * (B.n3(bd.i * 3.1, 0.5, 1.7) - 0.5) + 0.14 * (B.n3(x * 2.2, y * 5.5, z * 2.2) - 0.5);
        }
      };
      const MOSSROCK = { r: ROCK, s: ROCK_MOON, g: ROCK_FIRE, b: 0.08, wear: { t: 0.3 }, top: { min: 0.78, r: MOSS, s: GRASS_MOON, g: GRASS_FIRE } };
      const BARKM = { r: BARK, s: BARK_MOON, g: BARK_FIRE, mod: (x, y, z) => 0.12 * (B.n3(x * 9, y * 2, z * 9) - 0.5) };
      const BUSH = { r: LEAF, s: LEAF_MOON, g: LEAF_FIRE, leaf: {} };
      const PINE = { r: NEEDLE, s: NEEDLE_MOON, g: NEEDLE_MOON, leaf: { l: 0.065, w: 0.022, j: 1.4, lift: 0.7 } },
        PINE_CORE = { r: [4, 4, 13, 14], g: [4, 13, 14] };

      // ---------------- the island itself
      let isle = null;
      isle = FI.body(K, B, S, {
        R: 6,
        thick: 0.7,
        depth: 4.6,
        ground,
        turf: TURF,
        rock: ROCKMAT,
        lumps: 16,
        seed: 5,
        res: 0.085
      });
      const gy = (x, z) => isle.h(x, z);

      // ---------------- the great tree on its knoll
      // (a tree draws its leaves as it is made, and the bake lays copied leaves at its end: both are claimed for the island, so they bob with it)
      rig.own('island', () => FI.clumpyTree(B, S, 0.26, TREE[0], gy(TREE[0], TREE[1]) - 0.05, TREE[1], {
        h: 3.5,
        r: 0.3,
        spread: 3.0,
        nb: 8,
        lean: [0.1, 0.06],
        roots: 6,
        bark: BARKM,
        leaf: { r: LEAF_MOON, g: LEAF_FIRE },
        leaves: 30000,
        ls: 0.48,
        res: 0.06
      }));

      // ---------------- two pines on the left
      // a pine: a stack of drooping skirts of needles, each narrower than the one below, dark gaps between them
      const pine = (x, z, hgt, sd) => {
        const y = gy(x, z);
        S.tube(
          [
            [x, y - 0.1, z],
            [x, y + hgt * 0.97, z]
          ],
          0.1 * (hgt / 3),
          0.025,
          BARKM,
          { res: 0.04 }
        );
        const tiers = 7,
          G = S.grp(0.03);
        for (let i = 0; i < tiers; i++) {
          const f = i / (tiers - 1),
            rb = (0.85 - f * 0.66) * (hgt / 3.1),
            y0 = y + hgt * (0.2 + f * 0.7),
            n = Math.round(9 - f * 4);
          // a dark core, then fronds that reach out and droop at the tip
          S.lathe([x, y0 - rb * 0.3, z], rb * 0.55, t => rb * 0.42 * Math.pow(1 - t, 1.3) + 0.01, PINE_CORE, Object.assign({ res: 0.045 }, G));
          for (let k = 0; k < n; k++) {
            const a = (k / n) * TAU + i * 0.7 + sd,
              len = rb * (0.85 + 0.3 * B.n3(i * 2.1, k * 1.3, sd)),
              dx = Math.cos(a) * len,
              dz = Math.sin(a) * len;
            S.tube(
              [
                [x, y0, z],
                [x + dx * 0.55, y0 - len * 0.08, z + dz * 0.55],
                [x + dx, y0 - len * 0.36, z + dz]
              ],
              t => rb * 0.2 * (1 - t) + 0.02,
              0,
              PINE,
              Object.assign({ res: 0.04 }, G)
            );
          }
        }
      };
      pine(-3.4, -0.45, 3.3, 0);
      pine(-2.55, -2.15, 2.6, 1);
      pine(-4.2, -1.9, 1.9, 2);

      // ---------------- the cottage, door to the rim
      const hx = HOUSE[0],
        hz = HOUSE[1],
        hy = gy(hx, hz) - 0.05,
        W2 = 0.85,
        D2 = 0.6,
        WH = 1.0;
      const STONE = {
        r: ROCK,
        g: ROCK_FIRE,
        mod: kit.courses(0.22, 0.13, B.n3, 0.14)
      };
      S.box([hx, hy + 0.14, hz], [W2 + 0.05, 0.16, D2 + 0.05], STONE, { res: 0.05 });
      S.box([hx, hy + 0.3 + WH / 2, hz], [W2, WH / 2, D2], { r: PLASTER, mod: (x, y, z) => 0.1 * (B.n3(x * 5, y * 5, z * 5) - 0.5) }, { res: 0.05 });
      const TIMBER = { r: BARK, g: BARK_FIRE };
      for (const sx of [-1, 1])
        for (const sz of [-1, 1]) S.box([hx + sx * W2, hy + 0.3 + WH / 2, hz + sz * D2], [0.06, WH / 2 + 0.02, 0.06], TIMBER, { res: 0.035 });
      for (const sz of [-1, 1]) {
        S.box([hx, hy + 0.32, hz + sz * (D2 + 0.01)], [W2 + 0.04, 0.04, 0.04], TIMBER, { res: 0.035 });
        S.box([hx, hy + 0.3 + WH, hz + sz * (D2 + 0.01)], [W2 + 0.04, 0.045, 0.04], TIMBER, { res: 0.035 });
      }
      // the roof: a gable over the long side, tiles in courses
      const RH = 0.78,
        RD = D2 + 0.28,
        RL = W2 + 0.2,
        rl = Math.hypot(RD, RH);
      S.convex(
        [hx, hy + 0.3 + WH, hz],
        [
          { n: [0, -1, 0], d: 0 },
          { n: [0, RD / rl, RH / rl], d: (RH * RD) / rl },
          { n: [0, RD / rl, -RH / rl], d: (RH * RD) / rl },
          { n: [1, 0, 0], d: RL },
          { n: [-1, 0, 0], d: RL }
        ],
        { r: ROOF, s: ROOF_MOON, mod: (x, y, z) => (((y - hy) / 0.11) % 1 < 0.22 ? -0.18 : 0.07 * (B.n3(Math.floor(x / 0.16), Math.floor(y / 0.11), 3) - 0.5)) },
        { res: 0.045 }
      );
      // chimney
      S.box([hx + 0.45, hy + 0.3 + WH + 0.55, hz + 0.18], [0.13, 0.42, 0.13], STONE, { res: 0.04 });
      // door and windows, lit from within
      const GLOW = { r: [39, 40, 41], em: true, v: 0.55 };
      S.box([hx - 0.2, hy + 0.62, hz - D2 - 0.02], [0.2, 0.32, 0.03], { r: [16, 17, 18] }, { res: 0.03 });
      S.box([hx - 0.2, hy + 0.62, hz - D2 - 0.03], [0.012, 0.3, 0.03], TIMBER, { res: 0.02 });
      const windows = [
        [hx + 0.42, hy + 0.85, hz - D2 - 0.02, 'z'],
        [hx - 0.35, hy + 0.85, hz + D2 + 0.02, 'z'],
        [hx + 0.35, hy + 0.85, hz + D2 + 0.02, 'z'],
        [hx - W2 - 0.02, hy + 0.85, hz, 'x'],
        [hx + W2 + 0.02, hy + 0.85, hz, 'x']
      ];
      for (const w of windows) {
        const half = w[3] === 'z' ? [0.2, 0.2, 0.03] : [0.03, 0.2, 0.2];
        S.box([w[0], w[1], w[2]], half, GLOW, { res: 0.025 });
        S.box([w[0], w[1], w[2]], w[3] === 'z' ? [0.018, 0.21, 0.04] : [0.04, 0.21, 0.018], TIMBER, { res: 0.02 });
        S.box([w[0], w[1], w[2]], w[3] === 'z' ? [0.21, 0.018, 0.04] : [0.04, 0.018, 0.21], TIMBER, { res: 0.02 });
        const out = w[3] === 'z' ? [0, 0, Math.sign(w[2] - hz) * 0.5] : [Math.sign(w[0] - hx) * 0.5, 0, 0];
        S.lights.push({ p: [w[0] + out[0], w[1] - 0.2, w[2] + out[2]], r: 2.0, s: 0.75 });
      }
      // a lantern on a post by the door
      const lx = hx - 0.7,
        lz = hz - D2 - 0.35,
        ly = gy(lx, lz);
      S.tube(
        [
          [lx, ly - 0.05, lz],
          [lx, ly + 0.95, lz]
        ],
        0.03,
        0.025,
        TIMBER,
        { res: 0.025 }
      );
      S.box([lx, ly + 1.0, lz], [0.07, 0.09, 0.07], GLOW, { res: 0.02 });
      S.box([lx, ly + 1.11, lz], [0.09, 0.02, 0.09], { r: [16, 17, 25] }, { res: 0.02 });
      S.lights.push({ p: [lx, ly + 0.95, lz - 0.1], r: 2.4, s: 0.7, sh: true });
      // a log pile against the side wall
      for (let i = 0; i < 7; i++) {
        const row = i < 4 ? 0 : i < 6 ? 1 : 2,
          k = i < 4 ? i : i < 6 ? i - 4 : 0,
          x = hx + W2 + 0.2,
          y = hy + 0.1 + row * 0.17,
          z = hz - 0.27 + k * 0.18 + row * 0.09;
        S.tube(
          [
            [x - 0.12, y, z],
            [x + 0.12, y, z]
          ],
          0.085,
          0.085,
          { r: BARK, g: BARK_FIRE },
          { res: 0.03 }
        );
        S.lathe([x + 0.12, y, z], 0.01, 0.075, { r: [19, 20, 22, 45] }, { res: 0.02, ax: S.AX });
      }

      // ---------------- the vegetable garden, fenced
      const gx = GARDEN[0],
        gz = GARDEN[1],
        fpath = [
          [gx - 0.8, gz - 0.55],
          [gx + 0.8, gz - 0.55],
          [gx + 0.8, gz + 0.55],
          [gx - 0.8, gz + 0.55],
          [gx - 0.8, gz - 0.25]
        ].map(p => [p[0], gy(p[0], p[1]), p[1]]);
      K.form.fence(S, TIMBER, {
        path: fpath,
        gap: 0.4,
        h: 0.42,
        r: 0.028,
        rails: [0.16, 0.34],
        rr: 0.016,
        sag: 0.015,
        lean: 0.08,
        broken: 0.1,
        ground: gy,
        seed: 7,
        res: 0.025
      });
      for (let i = 0; i < 3; i++)
        for (let j = 0; j < 5; j++) {
          const x = gx - 0.55 + j * 0.27,
            z = gz - 0.3 + i * 0.3,
            y = gy(x, z);
          if (i === 1 && j % 2 === 0)
            K.form.ribbed(
              S,
              [
                [x, y + 0.02, z],
                [x, y + 0.2, z]
              ],
              t => 0.13 * Math.sin(Math.PI * (0.08 + 0.84 * t)) + 0.01,
              { r: [36, 37, 38, 39], g: [38, 39, 40] },
              { ribs: 9, depth: 0.2, res: 0.025 }
            );
          else S.ball([x, y + 0.08, z], [0.12, 0.09, 0.12], BUSH, { res: 0.05 });
        }

      // ---------------- the campfire, its ring of stones and two log seats
      const fx = FIRE[0],
        fz = FIRE[1],
        fy = gy(fx, fz);
      for (let k = 0; k < 9; k++) {
        const a = (k / 9) * TAU;
        S.rock([fx + Math.cos(a) * 0.34, fy + 0.04, fz + Math.sin(a) * 0.34], 0.1, { r: ROCK, g: ROCK_FIRE }, { res: 0.03 });
      }
      for (let k = 0; k < 3; k++) {
        const a = (k / 3) * TAU + 0.4;
        S.tube(
          [
            [fx + Math.cos(a) * 0.26, fy + 0.02, fz + Math.sin(a) * 0.26],
            [fx - Math.cos(a) * 0.05, fy + 0.2, fz - Math.sin(a) * 0.05]
          ],
          0.045,
          0.035,
          { r: [16, 17, 36, 37], g: [36, 37, 38] },
          { res: 0.025 }
        );
      }
      for (const [dx, dz, a] of [
        [-0.95, 0.15, 0.3],
        [0.35, 0.95, 1.9]
      ]) {
        const x = fx + dx,
          z = fz + dz,
          y = gy(x, z) + 0.1;
        S.tube(
          [
            [x - Math.cos(a) * 0.45, y, z - Math.sin(a) * 0.45],
            [x + Math.cos(a) * 0.45, y, z + Math.sin(a) * 0.45]
          ],
          0.12,
          0.11,
          { r: BARK, g: BARK_FIRE, mod: (x, y, z) => 0.1 * (B.n3(x * 12, y * 3, z * 12) - 0.5) },
          { res: 0.035 }
        );
      }
      S.lights.push({ p: [fx, fy + 0.45, fz], r: 4.4, s: 2.2, sh: true });

      // ---------------- rocks, mossy on top
      const rocks = [
        [-3.5, 2.3, 0.55, 3],
        [-3.0, 2.85, 0.28, 4],
        [2.0, 3.75, 0.42, 5],
        [2.55, 3.4, 0.22, 6],
        [4.6, -1.0, 0.35, 7],
        [-1.6, -2.4, 0.3, 8],
        [-4.6, 0.4, 0.25, 9],
        [3.0, 0.2, 0.2, 10],
        [4.35, 2.45, 0.2, 11],
        [3.0, 2.25, 0.16, 12]
      ];
      for (const [x, z, r, sd] of rocks)
        K.grow.rock(S, [x, gy(x, z) + r * 0.25, z], r, MOSSROCK, {
          facets: 8,
          chip: 0.3,
          beds: { n: 3 },
          seed: sd,
          res: Math.max(0.03, r * 0.12)
        });

      // ---------------- bushes
      const bushes = [
        [-0.3, 4.0, 0.5],
        [-4.3, 1.4, 0.45],
        [3.1, -2.3, 0.42],
        [1.0, 2.8, 0.3],
        [-2.2, 3.4, 0.32],
        [4.7, 0.3, 0.3],
        [-0.6, -5.0, 0.32],
        [2.0, -4.9, 0.36]
      ];
      // each bush a few lobes of leaves melted together
      bushes.forEach(([x, z, r], i) => {
        const G = Object.assign(S.grp(0.08), { res: 0.05 }),
          y = gy(x, z);
        S.ball([x, y + r * 0.35, z], [r * 0.8, r * 0.55, r * 0.75], BUSH, G);
        for (let k = 0; k < 4; k++) {
          const a = k * 1.9 + i,
            q = r * 0.42;
          S.ball(
            [x + Math.cos(a) * q, y + r * (0.3 + 0.25 * (k % 2)), z + Math.sin(a) * q],
            r * (0.42 + 0.12 * B.n3(i, k, 2)),
            BUSH,
            G
          );
        }
      });

      // ---------------- mushrooms by the pines
      const shrooms = [
        [-2.9, -1.2],
        [-2.8, -1.05],
        [-3.0, -1.0],
        [-3.9, -0.9],
        [-2.1, -1.6],
        [-4.0, 0.0]
      ];
      shrooms.forEach(([x, z], i) => {
        const y = gy(x, z),
          s = 0.6 + 0.5 * B.n3(i * 3.3, 1, 1);
        S.lathe([x, y - 0.02, z], 0.13 * s, [0.03 * s, 0.025 * s], { r: [21, 45, 44] }, { res: 0.018 });
        S.ball([x, y + 0.13 * s, z], [0.08 * s, 0.05 * s, 0.08 * s], { r: [36, 37, 47], g: [37, 47, 38] }, { res: 0.018 });
      });

      // ---------------- the glowing crystals and the life under the island
      const CRY = { r: CRYSTAL, g: CRYSTAL };
      const cryAt = [1.2, isle.yBot + 1.6, 1.0],
        crystals = [
          [0.75, isle.yBot + 1.5, 2.6],
          [-0.35, isle.yBot + 2.4, 1.9],
          [-0.9, isle.yBot + 1.1, -1.4]
        ];
      crystals.forEach(([a, y, s], i) => {
        const r = isle.rockR(y, a) - 0.1,
          p = [Math.cos(a) * r, y, Math.sin(a) * r];
        K.form.cluster(S, p, [Math.cos(a) * 0.5, -1, Math.sin(a) * 0.5], CRY, {
          n: 6 + i,
          len: [0.35, 0.95],
          spread: 0.55,
          seed: 3 + i,
          res: 0.03
        });
        S.lights.push({ p: [p[0] + Math.cos(a) * 0.5, y - 0.5, p[2] + Math.sin(a) * 0.5], r: 1.5, s: 0.65 });
        if (i === 0) cryAt.splice(0, 3, p[0] / 1.6, y - 0.3, p[2] / 1.6);
      });
      // a soft lift of light from below, so the underside keeps its shape
      S.lights.push({ p: [0.5, isle.yBot - 4.5, 2.5], r: 10, s: 0.45 });

      const fallA = Math.atan2(STREAM[2][1], STREAM[2][0]);
      FI.roots(K, B, S, isle, { r: BARK.slice(0, 4), mod: (x, y, z) => 0.1 }, {
        n: 16,
        seed: 40,
        skip: a => Math.abs(Math.atan2(Math.sin(a - fallA), Math.cos(a - fallA))) < 0.65
      });
      S.ready();
      K.form.drips(S, {
        box: [-4.2, 4.2, -4.2, 4.2],
        y: isle.yBot - 0.5,
        n: 90,
        gap: 0.42,
        len: [0.5, 1.5],
        r: 0.2,
        mites: false,
        mat: ROCKMAT,
        seed: 9,
        res: 0.04
      });
      for (let k = 0; k < 7; k++) {
        const a = (k / 7) * TAU + 0.6,
          y = isle.yTop - 0.5,
          r = isle.rockR(y, a);
        if (Math.abs(Math.atan2(Math.sin(a - fallA), Math.cos(a - fallA))) < 0.5) continue;
        const grown = K.grow.creep(S, {
          from: [Math.cos(a) * r, y, Math.sin(a) * r],
          dir: [0, -1, 0],
          steps: 34,
          step: 0.12,
          wander: 0.5,
          branch: 0.08,
          seed: 60 + k
        });
        K.grow.vine(S, grown, { r: [5, 6, 7] }, { r: LEAF }, { r: 0.02, size: 0.14, leaves: 0.9, seed: 70 + k });
      }

      rig.own('island', () => S.bake());

      // ---------------- what is drawn by hand after the bake: water, the waterfall, flowers, fire, smoke, fireflies
      rig.own('island', () => {
        // the pond and its stream, flat tones in soft patches, a pale line at the bank, a few glints that wink
        const step = 0.06;
        for (let x = POND[0] - 1.3; x < 6.8; x += step)
          for (let z = POND[1] - 1.1; z < 3.4; z += step * 0.87) {
            const xx = x + (Math.round((z - POND[1]) / (step * 0.87)) % 2) * step * 0.5,
              r = Math.hypot(xx, z);
            if (r > isle.rim(Math.atan2(z, xx)) + 0.02) continue;
            const g = ground(xx, z),
              inPond = pondD(xx, z) < 1.12,
              inStream = segDist(STREAM, xx, z) < 0.3;
            if (!(inPond || inStream) || g > WL - 0.005) continue;
            const y = Math.min(WL, isle.h(xx, z) + 0.05),
              shore = g > WL - 0.05,
              v = B.fbm(xx * 1.4 + 7, z * 1.4, 1.7, 2),
              // the moon's sheen lies in bands across the water
              c = shore ? WATER[3] : v > 0.6 ? WATER[3] : v > 0.47 ? WATER[2] : v < 0.36 ? WATER[0] : WATER[1],
              glint = !shore && Math.sin(z * 9 + 2 * Math.sin(xx * 2.1)) > 0.9 && B.n3(xx * 2, z * 2, 4) > 0.45;
            B.disc(xx, y, z, B.UP, step * 0.62, 0.012, B.P[glint ? WATER[4] : c], 3, glint ? { em: true, k: 4, ph: B.rr(0, 6), sp: B.rr(2, 4) } : { em: true });
          }
        // lily pads with a pink flower here and there
        for (let i = 0; i < 9; i++) {
          const a = B.rr(0, TAU),
            q = Math.sqrt(B.rr(0.05, 0.6)),
            x = POND[0] + Math.cos(a) * q * POND_R[0] * 0.8,
            z = POND[1] + Math.sin(a) * q * POND_R[1] * 0.8,
            s = B.rr(0.09, 0.15);
          for (let k = 0; k < 14; k++) {
            const t = B.rr(0, TAU),
              d = Math.sqrt(B.rr(0, 1)) * s;
            if (Math.abs(((t - a + 9.42) % 6.283) - 3.14) < 0.4) continue;
            B.disc(x + Math.cos(t) * d, WL + 0.01, z + Math.sin(t) * d, B.UP, 0.04, 0.01, B.P[d > s * 0.7 ? 8 : 9], 3);
          }
          if (i % 3 === 0) B.iso(x, WL + 0.04, z, 0.035, B.P[42], 3);
        }
        // reeds and bulrushes round the bank
        for (let i = 0; i < 70; i++) {
          const a = B.rr(0, TAU),
            q = B.rr(1.0, 1.22),
            x = POND[0] + Math.cos(a) * q * POND_R[0],
            z = POND[1] + Math.sin(a) * q * POND_R[1];
          if (segDist(STREAM, x, z) < 0.35 || B.n3(x * 2, z * 2, 3.3) < 0.35) continue;
          const y = Math.max(WL, gy(x, z)),
            hgt = B.rr(0.25, 0.55),
            lean = B.norm([B.rr(-0.15, 0.15), 1, B.rr(-0.15, 0.15)]),
            sw = { k: 11, ph: B.rr(0, 6), sp: 1.9, rg: 0.02 };
          B.stick(x + lean[0] * hgt * 0.5, y + hgt * 0.5, z + lean[2] * hgt * 0.5, lean, hgt * 0.5, 0.014, B.P[B.pick([7, 8, 9, 10])], 3, sw);
          if (i % 3 === 0) B.stick(x + lean[0] * hgt, y + hgt * 0.95, z + lean[2] * hgt, lean, 0.05, 0.024, B.P[B.pick([18, 19])], 3, sw);
        }
        // the waterfall: the stream bends over the lip, then falls as a sheet that thins into spray
        const ex = STREAM[STREAM.length - 1],
          aw = Math.atan2(ex[1], ex[0]),
          e = isle.rim(aw),
          ox = Math.cos(aw),
          oz = Math.sin(aw),
          tx = -oz,
          tz = ox;
        for (let i = 0; i < 26; i++) {
          const u = B.rr(-0.24, 0.24),
            b = B.rr(0, 1),
            ang = b * Math.PI * 0.5,
            out = 0.16 * Math.sin(ang),
            dy = -0.16 * (1 - Math.cos(ang));
          B.disc(ox * (e + out) + tx * u, WL + dy, oz * (e + out) + tz * u, B.norm([ox * Math.sin(ang), Math.cos(ang), oz * Math.sin(ang)]), 0.05, 0.012, B.P[B.pick([WATER[2], WATER[3]])], 3, { em: true });
        }
        const fall = 4.6;
        for (let i = 0; i < 2200; i++) {
          const u = B.rr(-0.3, 0.3) * (1 + 0.15 * B.R()),
            out = 0.17 + B.rr(0, 0.12),
            sz = B.R();
          B.stick(ox * (e + out) + tx * u, WL - 0.18, oz * (e + out) + tz * u, B.UP, 0.08 + 0.06 * sz, 0.024, B.P[B.pick([WATER[2], WATER[3], WATER[3], WATER[4], WATER[4], WATER[4]])], 3, {
            em: true,
            k: 2,
            ph: B.R(),
            sp: fall / 2,
            rg: fall,
            ex: 1.6
          });
        }
        // flowers through the grass, avoiding the path, the pond and what stands there
        const keepOut = (x, z) =>
          segDist(PATHPTS, x, z) < 0.45 ||
          pondD(x, z) < 1.25 ||
          segDist(STREAM, x, z) < 0.45 ||
          (Math.abs(x - hx) < W2 + 0.3 && Math.abs(z - hz) < D2 + 0.3) ||
          (Math.abs(x - gx) < 0.95 && Math.abs(z - gz) < 0.7) ||
          Math.hypot(x - fx, z - fz) < 0.6 ||
          Math.hypot(x - TREE[0], z - TREE[1]) < 0.55;
        const FLOWER = [42, 43, 44, 40, 42, 44];
        let made = 0;
        for (let tries = 0; tries < 2400 && made < 340; tries++) {
          const a = B.rr(0, TAU),
            q = Math.sqrt(B.R()) * 5.4,
            x = Math.cos(a) * q,
            z = Math.sin(a) * q;
          if (q > isle.rim(a) - 0.35 || keepOut(x, z)) continue;
          if (B.n3(x * 0.9, z * 0.9, 5.5) < 0.45) continue; // they grow in drifts
          const y = gy(x, z),
            hgt = B.rr(0.1, 0.2),
            c = B.P[FLOWER[Math.floor(B.n3(x * 0.6, z * 0.6, 8.1) * FLOWER.length)]],
            sw = { k: 11, ph: B.rr(0, 6), sp: 1.9, rg: 0.012 };
          B.stick(x, y + hgt * 0.5, z, B.UP, hgt * 0.5, 0.012, B.P[7], 3, sw);
          B.iso(x, y + hgt, z, 0.034, c, 3, sw);
          made++;
        }
        // berries on two of the bushes
        for (const [x, z, r] of bushes.slice(0, 3))
          for (let k = 0; k < 14; k++) {
            const d = B.randDir();
            if (d[1] < -0.2) continue;
            B.iso(x + d[0] * r * 0.98, gy(x, z) + r * 0.45 + d[1] * r * 0.7, z + d[2] * r * 0.88, 0.03, B.P[k % 2 ? 42 : 37], 3);
          }
        // white spots on the mushroom caps
        shrooms.forEach(([x, z], i) => {
          const s = 0.6 + 0.5 * B.n3(i * 3.3, 1, 1),
            y = gy(x, z) + 0.13 * s;
          for (let k = 0; k < 4; k++) {
            const a = k * 1.7 + i;
            B.iso(x + Math.cos(a) * 0.045 * s, y + 0.045 * s, z + Math.sin(a) * 0.045 * s, 0.014, B.P[44], 3);
          }
        });
        // the fire, its embers, and smoke from the chimney
        flame(B, fx, fy + 0.12, fz, 1.0, [38, 39, 41]);
        flame(B, fx + 0.08, fy + 0.1, fz - 0.05, 0.6, [37, 38, 40]);
        // hard-edged tongues inside the glow, so the fire reads as a shape from across the island: pale at the heart, orange outside
        for (let i = 0; i < 9; i++) {
          const a = (i / 9) * TAU + 0.3,
            q = i % 3 === 0 ? 0.02 : 0.11,
            h = i % 3 === 0 ? 0.58 : B.rr(0.32, 0.46),
            lean = B.norm([Math.cos(a) * 0.25, 1, Math.sin(a) * 0.25]),
            x = fx + Math.cos(a) * q,
            z = fz + Math.sin(a) * q;
          B.stick(x + lean[0] * h * 0.5, fy + 0.14 + h * 0.5, z + lean[2] * h * 0.5, lean, h * 0.5, i % 3 === 0 ? 0.06 : 0.08, B.P[i % 3 === 0 ? 41 : i % 2 ? 40 : 39], 3, {
            em: true,
            k: 1,
            ph: i * 1.7,
            sp: 9
          });
        }
        for (let i = 0; i < 70; i++)
          B.iso(fx + B.rr(-0.15, 0.15), fy + 0.25, fz + B.rr(-0.15, 0.15), 0.022, B.P[B.pick([38, 39, 40])], 3, {
            em: true,
            nd: true,
            k: 3,
            ph: B.R(),
            sp: B.rr(0.5, 0.9),
            rg: B.rr(1.2, 2.2),
            ex: 0
          });
        const cx = hx + 0.45,
          cz = hz + 0.18,
          cy = hy + 0.3 + WH + 1.0;
        for (let i = 0; i < 46; i++)
          B.iso(cx + B.rr(-0.05, 0.05), cy, cz + B.rr(-0.05, 0.05), 0.09, B.P[B.pick([1, 2, 2, 3])], 0.55, {
            nd: true,
            k: 3,
            ph: B.R(),
            sp: 0.5,
            rg: 2.0,
            ex: 2.2
          });
        // fireflies by the pines, the pond and the garden
        for (let i = 0; i < 46; i++) {
          const c = B.pick([
              [-3.2, -1.2],
              [3.4, 1.4],
              [-1.2, -4.0],
              [-2.0, 2.6]
            ]),
            x = c[0] + B.rr(-1.1, 1.1),
            z = c[1] + B.rr(-1.1, 1.1);
          B.iso(x, gy(x, z) + B.rr(0.25, 1.4), z, 0.028, B.P[B.pick([40, 41, 12])], 3, {
            em: true,
            nd: true,
            k: 6,
            ph: B.rr(0, 6),
            sp: B.rr(0.6, 1.3),
            rg: B.rr(0.08, 0.2)
          });
        }
        // the grass that hangs over the rim
        FI.skirt(B, isle, { ramp: [4, 5, 6, 7, 8, 9], sun: S.sun, len: 0.34, gap: 0.045 });
        // moss hanging in strands from the ledges of the rock
        for (let i = 0; i < 260; i++) {
          const a = B.rr(0, TAU),
            y = B.rr(isle.yBot + 1.0, isle.yTop - 0.3),
            r = isle.rockR(y, a) + 0.02;
          if (B.n3(Math.cos(a) * 2, y * 0.8, Math.sin(a) * 2) < 0.5) continue;
          const len = B.rr(0.12, 0.45),
            c = B.pick([5, 6, 6, 7, 8]);
          B.stick(Math.cos(a) * r, y - len * 0.5, Math.sin(a) * r, B.UP, len * 0.5, 0.02, B.P[c], 3, {
            k: 11,
            ph: B.rr(0, 6),
            sp: 1.9,
            rg: 0.015
          });
        }
        // the crystals' own glow, a few motes round them
        for (let i = 0; i < 14; i++)
          B.iso(cryAt[0] * 1.6 + B.rr(-0.6, 0.6), cryAt[1] + B.rr(-0.9, 0.2), cryAt[2] * 1.6 + B.rr(-0.6, 0.6), 0.025, B.P[B.pick([34, 35])], 3, {
            em: true,
            nd: true,
            k: 6,
            ph: B.rr(0, 6),
            sp: B.rr(0.5, 1),
            rg: 0.12
          });
      });

      // ---------------- the sky: stars, soft lights, clouds below, and birds wheeling the other way round
      FI.backdrop(B, {
        stars: 140,
        starCols: [3, 44, 35],
        bokeh: 60,
        bokehCols: [1, 2, 2, 3],
        clouds: [
          { p: [-7.5, -4.6, 3.5], r: [1.8, 0.4, 1.0], n: 70, cols: [2, 3, 3], a: 0.26 },
          { p: [7.6, -5.6, -2.5], r: [2.0, 0.45, 1.1], n: 80, cols: [2, 3, 3], a: 0.26 },
          { p: [2.5, -7.2, 7.5], r: [2.2, 0.5, 1.2], n: 80, cols: [2, 3, 3], a: 0.26 },
          { p: [-3.0, -6.8, -7.5], r: [2.2, 0.45, 1.2], n: 80, cols: [2, 3, 3], a: 0.26 }
        ]
      });
      for (let b = 0; b < 6; b++) {
        const a = (b / 6) * TAU + B.rr(-0.3, 0.3),
          r = B.rr(7.2, 8.6),
          y = B.rr(2.5, 5.0),
          x = Math.cos(a) * r,
          z = Math.sin(a) * r,
          fw = [-Math.sin(a), 0, Math.cos(a)],
          side = [Math.cos(a), 0, Math.sin(a)],
          fly = { nd: true, k: 5, ph: 0, sp: -TAU / L };
        for (const sg of [-1, 1])
          B.stick(x + side[0] * sg * 0.1, y + 0.03, z + side[2] * sg * 0.1, B.norm([side[0] * sg, 0.35, side[2] * sg]), 0.11, 0.022, B.P[3], 3, fly);
        B.stick(x, y, z, fw, 0.06, 0.03, B.P[3], 3, fly);
      }

      const W = B.finish({
        cam: { target: [0, -0.3, 0], dist: 22, pitch: 0.22, yaw: 0.45 },
        detail: 19.4,
        dither: 0.3,
        radius: 10,
        palName: 'Island',
        fog: { c: 0, start: 0.8, max: 0.2 },
        outline: { c: 4, edge: 0.7 },
        ao: { k: 0.4, range: 0.5 }
      });
      FI.loopable(W, L);
      const st = K.stage(W);
      rig.bind(st);
      FI.bob(K, st, rig, 'island', 0.12, L);
      return W;
    }
  };
};
