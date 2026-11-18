/* An orbital greenhouse on a black slab at golden hour, in smog.
   A long black slab, polished like the monolith from 2001, is the ground. On it: a geodesic glass dome growing a kelp forest, a hot
   spring with steam, a green dragon in a wizard hat fishing in the spring (a line in the water and a bite that never comes), the
   standing black monolith behind him (its polished face reflects a crown that is not there), three clone vats with a machine and a
   "24 HRS" sign, a stack of fireworks, a 2012 tripod floor lamp on a chevron rug. Feathers circle the world, a few drift down, and an
   anchor chain hangs from the slab's underside. The whole world is tilted, the scene's stand-in for a Dutch tilt.
   It only calls the ink-studio toolkit (handed in as `kit`) and the studio's shared helpers; no toolkit code is copied here. */
const FI = require('./floating-island.cjs');

const L = 8; // seconds in one loop: every motion comes round in exactly this time
const YAW = 0.45,
  PITCH = 0.4;
const TILT = 0.17; // the Dutch tilt: the whole world rolled about the hero line of sight

// 48 colours, Technicolor: each ramp shifts hue as it goes from dark to light
const PAL = [
  0x3b2430, 0x5a3332, 0x84503a, 0xb37845, 0xe0a85c, // 0-4   smog: maroon-brown to golden haze (0 is the empty sky)
  0x08070f, 0x141228, 0x252241, 0x3d375e, 0x6d5f8c, // 5-9   the black slab: blue-black to a violet sheen
  0x05261e, 0x0a4a2e, 0x11733b, 0x22a043, 0x62cc45, 0xc6ee62, // 10-15 emerald, teal-green to yellow-green
  0x3d0a24, 0x7c0f2a, 0xc4192e, 0xf24b36, 0xff8f5c, // 16-20 ruby, wine to coral
  0x4e2a10, 0x8f5416, 0xd6961c, 0xf7cf3c, 0xfff2a0, // 21-25 yellow brick, umber to cream-yellow
  0x0d1650, 0x17358f, 0x2a62cc, 0x4f9ff2, 0x9cd8ff, // 26-30 gingham blue, navy to sky
  0x2c0c40, 0x5c1872, 0x9b2ca8, 0xd862cf, 0xffa9ea, // 31-35 Glinda magenta, plum to pink
  0x083848, 0x10707a, 0x25b0a6, 0x7decd2, // 36-39 hot spring, deep teal to pale turquoise
  0x2a1f2e, 0x4b3a45, 0x7a6262, 0xa89080, 0xdccab0, // 40-44 stone, plum-grey to sand
  0xfff8ea, // 45    white: feathers, eyes, steam
  0xff7d86, // 46    coral (the 2012 chevron)
  0x9fe8c8 // 47    mint (the 2012 lamp shade)
];

const SLAB = [5, 6, 7],
  SLAB_SUN = [5, 6, 7, 8],
  EMER = [10, 11, 12, 13],
  EMER_SUN = [12, 13, 14, 15],
  RUBY = [16, 17, 18],
  RUBY_SUN = [17, 18, 19, 20],
  GOLD = [21, 22, 23],
  GOLD_SUN = [22, 23, 24, 25],
  BLUE = [26, 27, 28],
  BLUE_SUN = [27, 28, 29, 30],
  PINK = [31, 32, 33],
  PINK_SUN = [32, 33, 34, 35],
  STONE = [40, 41, 42, 43],
  STONE_SUN = [41, 42, 43, 44];

module.exports = kit => {
  const { makeBuilder, makeSculpt, KIT: K } = kit;
  return {
    id: 'fishing',
    name: 'Monolith greenhouse',
    seed: 4,
    loop: L,
    build(seed) {
      const B = makeBuilder(seed, PAL),
        S = K.sculpt(makeSculpt(B)),
        rig = K.rig(B, S),
        M = K.M,
        { TAU } = FI;
      const WORLD = rig.part('world');
      // tagged solids are the parts that move; everything else rides the world
      rig.resolve = pr => (pr.tag ? undefined : WORLD);
      // golden hour: a low warm sun from the front left
      S.sun = B.norm([-0.72, 0.32, 0.55]);
      S.amb = 0.2;
      S.sky = 0.3;
      S.sunK = 0.95;
      S.res = 0.07;
      S.view = [Math.sin(YAW) * Math.cos(PITCH), Math.sin(PITCH), Math.cos(YAW) * Math.cos(PITCH)];

      // ---------------- small vector helpers
      const add = (a, b, s = 1) => [a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s],
        sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]],
        cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]],
        lerp = (a, b, t) => add(a, sub(b, a), t),
        unit = B.norm,
        // a frame whose middle axis runs along d (lathes and rings are made about their middle axis)
        along = d => {
          const v = unit(d),
            u = unit(cross(Math.abs(v[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0], v));
          return [u, v, cross(u, v)];
        },
        // a frame turned about the upright: its third axis (forward) is (sin a, 0, cos a)
        yawFrame = a => [
          [Math.cos(a), 0, -Math.sin(a)],
          [0, 1, 0],
          [Math.sin(a), 0, Math.cos(a)]
        ],
        UP = [0, 1, 0];

      // ---------------- where things stand (the slab's top is y = 0)
      const SX = 5.4, // the slab's half-length (x), half-width (z) and thickness: 1 : 4 : 9 like the monolith
        SZ = 2.4,
        SH = 1.2,
        DPOS = [-0.5, 1.1], // the dragon, at the front, turned a little toward the hero view from side-on
        DIR = unit([Math.cos(YAW) + 0.35 * Math.sin(YAW), 0, -Math.sin(YAW) + 0.35 * Math.cos(YAW)]),
        DA = Math.atan2(DIR[0], DIR[2]),
        DS = 1.45,
        SEAT = 0.22,
        PO = [DPOS[0] + DIR[0] * 1.55, 0, DPOS[1] + DIR[2] * 1.55], // the hot spring, in front of him
        PR = [1.05, 0.78],
        WL = -0.1, // its water level
        BOB = [PO[0] + 0.16, WL, PO[2] - 0.03], // where his line meets the water
        MB = [-0.25, 0, -1.65], // the standing monolith
        MY = 0.3,
        GC = [-3.3, 0, 0], // the greenhouse dome
        GR = 2.0,
        VX = [2.75, 3.6, 4.45], // the clone vats
        VZ = -0.55,
        LAMP = [4.75, 0, 1.85],
        RUG = [0.0, 2.0],
        CT = [0.2, -SH, 0.1]; // where the anchor chain hangs from
      const pondD = (x, z) => Math.hypot((x - PO[0]) / PR[0], (z - PO[2]) / PR[1]);

      // the dragon's own frame: l = [to his left, up, forward], in his units
      const DF = yawFrame(DA),
        DP = l => [DPOS[0] + (DF[0][0] * l[0] + DF[2][0] * l[2]) * DS, SEAT + l[1] * DS, DPOS[1] + (DF[0][2] * l[0] + DF[2][2] * l[2]) * DS],
        DD = l => unit([DF[0][0] * l[0] + DF[2][0] * l[2], l[1], DF[0][2] * l[0] + DF[2][2] * l[2]]),
        DLEFT = DF[0];

      // ---------------- materials
      const SLABM = {
          r: SLAB,
          s: SLAB_SUN,
          gloss: { c: 4, at: 0.97, c2: 9, at2: 0.93 },
          mod: (x, y, z) => 0.08 * (B.n3(x * 0.9, y * 0.9 + 3, z * 0.9) - 0.5)
        },
        // the monolith's polished face catches a little more of the sky the higher it goes
        MONOM = { r: SLAB, s: SLAB_SUN, gloss: { c: 4, at: 0.97, c2: 9, at2: 0.93 }, mod: (x, y) => 0.14 * (y / 3.8) - 0.04 },
        STONEM = { r: STONE, s: STONE_SUN, b: 0.08 },
        SKIN = { r: EMER, s: EMER_SUN },
        BELLY = { r: GOLD, s: GOLD_SUN },
        RUBYM = { r: RUBY, s: RUBY_SUN },
        HATM = { r: BLUE, s: BLUE_SUN },
        BANDM = { r: [22, 23], s: [23, 24, 25] },
        HORNM = { r: [42, 43], s: [43, 44, 45] },
        EYEM = { r: [44, 45], s: [45] },
        METALM = { r: [6, 7, 8], s: [7, 8, 9, 42] },
        STRUTM = { r: [7, 8, 42], s: [42, 43, 44, 45] },
        WOODM = { r: [21, 22], s: [22, 23, 24] },
        MINTM = { r: [36, 37, 47], s: [37, 47, 45] },
        SHADEM = { r: [17, 18, 46], s: [18, 46, 20] },
        CREAMM = { r: [41, 42, 43], s: [43, 44, 45] },
        WHITEM = { r: [44, 45], s: [45] },
        DOME_GLASS = K.look.glass([29, 30, 45], { a: 0.06 }),
        VAT_GLASS = K.look.glass([37, 38, 39], { a: 0.07 });

      // ================================================================ the still world
      // ---------------- the black slab the world sits on, with the spring's basin cut into it
      S.box([0, -SH / 2, 0], [SX, SH / 2, SZ], SLABM, { res: 0.06, rd: 0.03 });
      S.ball([PO[0], 0.05, PO[2]], [PR[0], 0.42, PR[1]], SLABM, { neg: true, res: 0.05 });

      // ---------------- the standing monolith, 1 : 4 : 9
      const MF = yawFrame(MY);
      S.box([MB[0], 1.9, MB[2]], [0.85, 1.9, 0.21], MONOM, { ax: MF, res: 0.045, rd: 0.012 });

      // ---------------- the hot spring's ring of stones (left open where the dragon sits and on the near side, so the water shows)
      for (let k = 0; k < 18; k++) {
        const a = (k / 18) * TAU + 0.17 * Math.sin(k * 2.3),
          near = Math.sin(a) > 0.35, // the side towards the hero view
          r = near ? 0.1 + 0.05 * B.n3(k, 1, 2) : 0.17 + 0.14 * B.n3(k, 2, 3),
          q = 1.06 + 0.05 * B.n3(k, 3, 1),
          x = PO[0] + Math.cos(a) * PR[0] * q,
          z = PO[2] + Math.sin(a) * PR[1] * q;
        if (Math.hypot(x - DPOS[0], z - DPOS[1]) < 0.75) continue;
        K.grow.rock(S, [x, r * 0.2, z], r, STONEM, { facets: 8, chip: 0.3, seed: 10 + k, res: Math.max(0.025, r * 0.13) });
      }
      // the boulder the dragon sits on
      S.ball([DPOS[0], 0.0, DPOS[1]], [0.52, SEAT, 0.46], STONEM, { ax: DF, res: 0.035 });

      // ---------------- the dragon: emerald, plain skin, a yellow belly, ruby wings and spikes
      {
        const G = Object.assign(S.grp(0.07), { res: 0.028 }),
          ball = (l, r, mat, o) => S.ball(DP(l), r.map(v => v * DS), mat, Object.assign({ ax: DF }, G, o));
        ball([0, 0.48, 0], [0.36, 0.48, 0.32], SKIN);
        ball([0, 0.44, 0.16], [0.25, 0.38, 0.19], BELLY);
        for (const s of [-1, 1]) {
          ball([s * 0.27, 0.2, 0.04], [0.2, 0.19, 0.27], SKIN);
          ball([s * 0.24, 0.04, 0.32], [0.1, 0.06, 0.15], SKIN);
          for (let c = -1; c <= 1; c++) S.ball(DP([s * 0.24 + c * 0.05, 0.03, 0.47]), 0.028 * DS, HORNM, { res: 0.015 });
          // arms reaching forward to the rod
          S.tube([DP([s * 0.3, 0.74, 0.06]), DP([s * 0.29, 0.56, 0.22]), DP([s * 0.08, 0.56, 0.42])], 0.07 * DS, 0.055 * DS, SKIN, G);
          ball([s * 0.07, 0.56, 0.43], [0.065, 0.065, 0.065], SKIN);
          // folded wings on his back: a bone along the top and a ruby membrane
          S.tube([DP([s * 0.2, 0.86, -0.2]), DP([s * 0.36, 1.16, -0.36]), DP([s * 0.46, 1.3, -0.5])], 0.035 * DS, 0.018 * DS, SKIN, { res: 0.02 });
          S.ball(DP([s * 0.33, 0.92, -0.38]), [0.045 * DS, 0.34 * DS, 0.21 * DS], RUBYM, { ax: DF, res: 0.025 });
          // the wing's finger bones, fanning down from the wrist across the membrane
          for (const tip of [
            [s * 0.37, 0.62, -0.28],
            [s * 0.37, 0.64, -0.46],
            [s * 0.35, 0.76, -0.58]
          ])
            S.tube([DP([s * 0.43, 1.26, -0.46]), DP([s * 0.385, 0.95, (tip[2] - 0.42) / 2]), DP(tip)], 0.022 * DS, 0.012 * DS, SKIN, { res: 0.018 });
        }
        S.tube([DP([0, 0.82, 0.02]), DP([0, 0.98, 0.08]), DP([0, 1.08, 0.12])], 0.16 * DS, 0.13 * DS, SKIN, G);
        // ruby spikes down his back
        for (let k = 0; k < 6; k++) {
          const t = k / 5,
            y = 0.98 - 0.72 * t,
            back = -0.32 * Math.sqrt(Math.max(0.05, 1 - ((y - 0.48) / 0.5) ** 2)),
            p = DP([0, y, back + 0.02]);
          S.lathe(p, 0.13 * DS * (1 - 0.3 * t), t2 => 0.05 * DS * (1 - t2) + 0.004, RUBYM, { ax: along(DD([0, 0.5, -1])), res: 0.018 });
        }
      }

      // ---------------- the greenhouse: a geodesic dome of glass on the west end, growing a kelp forest in a round tank
      {
        // a frequency-two icosphere, its top half: the struts of a geodesic dome
        const V = [[0, 1, 0]],
          y0 = 1 / Math.sqrt(5),
          r0 = 2 / Math.sqrt(5);
        for (let k = 0; k < 5; k++) V.push([r0 * Math.cos((k * TAU) / 5), y0, r0 * Math.sin((k * TAU) / 5)]);
        for (let k = 0; k < 5; k++) V.push([r0 * Math.cos(((k + 0.5) * TAU) / 5), -y0, r0 * Math.sin(((k + 0.5) * TAU) / 5)]);
        V.push([0, -1, 0]);
        const faces = [];
        for (let k = 0; k < 5; k++) {
          const u = 1 + k,
            u2 = 1 + ((k + 1) % 5),
            l = 6 + k,
            l2 = 6 + ((k + 1) % 5);
          faces.push([0, u, u2], [u, l, u2], [u2, l, l2], [11, l2, l]);
        }
        const key = (a, b) => (a < b ? a + ',' + b : b + ',' + a),
          mids = {},
          mid = (a, b) => {
            const k = key(a, b);
            if (mids[k] === undefined) {
              mids[k] = V.length;
              V.push(unit(lerp(V[a], V[b], 0.5)));
            }
            return mids[k];
          },
          seen = new Set(),
          edges = [],
          edge = (a, b) => {
            const k = key(a, b);
            if (!seen.has(k)) {
              seen.add(k);
              edges.push([a, b]);
            }
          };
        for (const [a, b, c] of faces) {
          const ab = mid(a, b),
            bc = mid(b, c),
            ca = mid(c, a);
          for (const [p, q] of [[a, ab], [ab, b], [b, bc], [bc, c], [c, ca], [ca, a], [ab, bc], [bc, ca], [ca, ab]]) edge(p, q);
        }
        const at = v => [GC[0] + v[0] * GR, v[1] * GR, GC[2] + v[2] * GR];
        const used = new Set();
        for (const [a, b] of edges) {
          if (V[a][1] < -1e-6 || V[b][1] < -1e-6) continue;
          S.tube([at(V[a]), at(V[b])], 0.026, 0.026, STRUTM, { res: 0.03 });
          used.add(a);
          used.add(b);
        }
        for (const i of used) S.ball(at(V[i]), 0.045, METALM, { res: 0.02 });
        S.torus([GC[0], 0.05, GC[2]], GR, 0.06, METALM, { res: 0.035 });
        // the glass itself: a thin shell that tints and bends what is inside, and hides nothing
        S.solid(
          [GC[0], GR * 0.5, GC[2]],
          GR * 1.2,
          (x, y, z) => {
            const wy = y + GR * 0.5;
            return Math.max(Math.abs(Math.hypot(x, wy, z) - GR) - 0.012, -wy);
          },
          (res, f) => {
            const rows = Math.ceil((GR * Math.PI) / 2 / res);
            for (let j = 0; j < rows; j++) {
              const e = ((j + 0.5) / rows) * (Math.PI / 2),
                rr = GR * Math.cos(e),
                n = Math.max(3, Math.ceil((TAU * rr) / res));
              for (let k = 0; k < n; k++) {
                const a = ((k + 0.5 * j) / n) * TAU;
                f(Math.cos(a) * rr, GR * Math.sin(e) - GR * 0.5, Math.sin(a) * rr);
              }
            }
          },
          DOME_GLASS,
          { res: 0.06, ghost: true }
        );
        // the kelp tank: a low round tub the kelp grows from
        S.lathe([GC[0], 0, GC[2]], 0.2, 1.62, { r: [36, 37, 7], s: [37, 38, 8] }, { res: 0.04 });
        S.torus([GC[0], 0.2, GC[2]], 1.62, 0.05, STRUTM, { res: 0.025 });
        // the airlock, facing the spring
        const ad = unit([0.75, 0, 0.66]),
          aBase = add([GC[0], 0.5, GC[2]], ad, GR - 0.4);
        S.lathe(aBase, 0.85, 0.45, CREAMM, { ax: along(ad), res: 0.035 });
        S.torus(add(aBase, ad, 0.85), 0.45, 0.04, METALM, { ax: along(ad), res: 0.025 });
        S.lathe(add(aBase, ad, 0.84), 0.05, 0.36, RUBYM, { ax: along(ad), res: 0.025 });
        S.torus(add(aBase, ad, 0.92), 0.17, 0.025, BANDM, { ax: along(ad), res: 0.02 });
      }

      // ---------------- the clone vats on the east end, the machine that runs them, and the sign over it
      {
        S.box([3.6, 0.09, VZ], [1.35, 0.09, 0.55], METALM, { res: 0.04, rd: 0.02 });
        VX.forEach((x, k) => {
          S.lathe([x, 0.18, VZ], 0.12, 0.42, METALM, { res: 0.03 });
          S.lathe([x, 0.3, VZ], 1.35, 0.35, VAT_GLASS, { res: 0.045, ghost: true });
          S.lathe([x, 1.62, VZ], 0.16, [0.42, 0.36], METALM, { res: 0.03 });
          S.lathe([x, 1.77, VZ], 0.12, t => 0.3 * Math.sqrt(Math.max(0, 1 - t * t)) + 0.01, CREAMM, { res: 0.025 });
          for (const y of [0.32, 1.62]) S.torus([x, y, VZ], 0.38, 0.025, BANDM, { res: 0.02 });
          // a clone floating in each, curled up, bobbing in the fluid
          const CL = { r: [33, 34], s: [34, 35], fl: { k: 6, ph: k * 2.1, sp: (2 * TAU) / L, rg: 0.05 } },
            o = { res: 0.02 },
            cz = VZ + 0.02,
            lean = 0.06 * (k - 1);
          S.ball([x + lean, 1.2, cz], 0.105, CL, o);
          S.ball([x, 0.97, cz], [0.085, 0.15, 0.07], CL, o);
          for (const s of [-1, 1]) {
            S.tube([[x + s * 0.045, 0.86, cz], [x + s * 0.06, 0.74, cz + 0.12], [x + s * 0.05, 0.6, cz + 0.02]], 0.035, 0.028, CL, o);
            S.tube([[x + s * 0.09, 1.06, cz], [x + s * 0.12, 0.92, cz + 0.07], [x + s * 0.05, 0.84, cz + 0.12]], 0.025, 0.02, CL, o);
          }
          // a pipe from each cap back to the machine
          S.tube([[x, 1.85, VZ], [x, 1.95, VZ - 0.3], [x, 1.95, -1.4], [x, 1.2, -1.4]], 0.04, 0.04, BANDM, { res: 0.025 });
        });
        // the machine: a cream cabinet with a ruby base
        S.box([3.6, 0.62, -1.6], [1.25, 0.58, 0.35], CREAMM, { res: 0.04, rd: 0.03 });
        S.box([3.6, 0.07, -1.6], [1.28, 0.07, 0.38], RUBYM, { res: 0.035 });
        S.lathe([4.85, 0.65, -1.6], 0.16, 0.07, METALM, { ax: along([1, 0, 0]), res: 0.02 });
        // the sign on two posts over the machine, turned to face the hero view
        const SF = yawFrame(YAW),
          SC = [3.6, 2.48, -1.6];
        for (const s of [-1, 1]) {
          const p = add(SC, SF[0], s * 0.75);
          S.tube([[p[0], 1.18, p[2]], [p[0], SC[1] - 0.3, p[2]]], 0.04, 0.035, METALM, { res: 0.025 });
        }
        S.box(SC, [1.32, 0.36, 0.05], { r: [16, 17], s: [17, 18] }, { ax: SF, res: 0.03, rd: 0.015 });
        const corner = (u, v) => add(add(add(SC, SF[0], u), UP, v), SF[2], 0.06);
        S.tube([corner(-1.25, -0.29), corner(1.25, -0.29), corner(1.25, 0.29), corner(-1.25, 0.29), corner(-1.25, -0.29)], 0.022, 0.022, { r: [34, 35], s: [35] }, { res: 0.018 });
        S.strokes(K.poly2.text('24 HRS', 0.4, { width: 0.075 }), add(SC, SF[2], 0.07), 0.05, { r: [24, 25], s: [25] }, { ax: SF, res: 0.02 });
      }

      // ---------------- the fireworks: a crate of rockets and a pyramid of cakes, and two rockets left lying
      {
        const COLS = [RUBYM, { r: BLUE, s: BLUE_SUN }, { r: PINK, s: PINK_SUN }, BELLY],
          striped = m => Object.assign({}, m, { tex: (x, y) => (((y * 16) % 3) + 3) % 3 < 0.7 ? 45 : undefined }),
          CF = yawFrame(0.2),
          cc = [2.8, 0.2, 1.6];
        S.box(cc, [0.34, 0.2, 0.26], Object.assign({ mod: (x, y) => (((y + 0.02) / 0.1) % 1 < 0.15 ? -0.3 : 0) }, WOODM), { ax: CF, res: 0.03, rd: 0.01 });
        let n = 0;
        for (let i = -1; i <= 1; i++)
          for (const j of [-1, 1]) {
            const p = add(add([cc[0], 0.25, cc[2]], CF[0], i * 0.2), CF[2], j * 0.11),
              h = 0.5 + 0.07 * ((n * 7) % 3);
            S.lathe(p, h, 0.055, striped(COLS[n % 4]), { res: 0.02 });
            S.lathe([p[0], p[1] + h, p[2]], 0.14, t => 0.06 * (1 - t) + 0.003, COLS[(n + 1) % 4], { res: 0.018 });
            n++;
          }
        const cake = (x, y, z, k) => {
          S.lathe([x, y, z], 0.24, 0.17, Object.assign({}, COLS[k % 4], { tex: (xx, yy, zz) => (((Math.atan2(zz - z, xx - x) + 9) / 0.5) % 1 < 0.3 ? 45 : undefined) }), { res: 0.025 });
          S.tube([[x, y + 0.24, z], [x + 0.03, y + 0.33, z + 0.02]], 0.012, 0.01, { r: [5, 6] }, { res: 0.015 });
        };
        [3.45, 3.8, 4.15].forEach((x, k) => cake(x, 0, 1.7, k));
        [3.62, 3.98].forEach((x, k) => cake(x, 0.24, 1.7, k + 1));
        cake(3.8, 0.48, 1.7, 3);
        for (const [x, z, a, k] of [
          [2.4, 2.12, 0.3, 0],
          [3.35, 2.15, -0.5, 2]
        ]) {
          const d = [Math.cos(a), 0, Math.sin(a)],
            p = [x, 0.06, z];
          S.lathe(add(p, d, -0.22), 0.42, 0.055, striped(COLS[k]), { ax: along(d), res: 0.02 });
          S.lathe(add(p, d, 0.2), 0.14, t => 0.06 * (1 - t) + 0.003, COLS[k + 1], { ax: along(d), res: 0.018 });
          S.tube([add(p, d, -0.22), add(add(p, d, -0.9), UP, -0.03)], 0.012, 0.012, WOODM, { res: 0.015 });
        }
      }

      // ---------------- 2012: a tripod floor lamp with a mint drum shade (switched off: daylight only), a chevron rug, a mason jar
      {
        const top = [LAMP[0], 1.18, LAMP[2]];
        for (let k = 0; k < 3; k++) {
          const a = 0.4 + (k * TAU) / 3;
          S.tube([[LAMP[0] + Math.cos(a) * 0.34, 0, LAMP[2] + Math.sin(a) * 0.34], top], 0.025, 0.02, WOODM, { res: 0.018 });
        }
        S.tube([top, [LAMP[0], 1.55, LAMP[2]]], 0.018, 0.018, BANDM, { res: 0.015 });
        S.lathe([LAMP[0], 1.48, LAMP[2]], 0.36, [0.3, 0.27], SHADEM, { res: 0.025 });
        for (const y of [1.49, 1.83]) S.torus([LAMP[0], y, LAMP[2]], y < 1.6 ? 0.3 : 0.27, 0.018, MINTM, { res: 0.015 });
        S.ball([LAMP[0], 1.42, LAMP[2]], [0.05, 0.07, 0.05], { r: [23, 24] }, { res: 0.015 });
        const RF = yawFrame(0.25),
          rug = [RUG[0], 0.008, RUG[1]];
        S.box(rug, [0.5, 0.008, 0.36], {
          r: [41, 42],
          tex: (x, y, z, ny) => {
            if (ny < 0.5) return undefined;
            const dx = x - rug[0],
              dz = z - rug[2],
              u = dx * RF[0][0] + dz * RF[0][2],
              v = dx * RF[2][0] + dz * RF[2][2];
            if (Math.abs(u) > 0.45 || Math.abs(v) > 0.31) return 46;
            const zig = 0.1 * Math.abs(2 * (((u / 0.26) % 1) + 1 - Math.floor(((u / 0.26) % 1) + 1)) - 1),
              band = Math.floor((v + zig) / 0.1);
            return [46, 45, 47][((band % 3) + 3) % 3];
          }
        }, { ax: RF, res: 0.025 });
        const jar = add(DP([-0.55, 0, 0.35]), [0, -SEAT + 0.012, 0]);
        S.lathe(jar, 0.2, t => 0.075 * (t > 0.85 ? 0.85 : 1), { r: [47, 39], s: [39, 45] }, { res: 0.018 });
        S.lathe([jar[0], jar[1] + 0.2, jar[2]], 0.04, 0.068, BANDM, { res: 0.015 });
      }

      // ---------------- an orbital mast and its solar wing out of the slab's back, and four thrusters underneath
      {
        S.tube([[1.2, -0.6, -SZ], [1.2, -0.6, -SZ - 2.3]], 0.05, 0.05, METALM, { res: 0.025 });
        for (const s of [-1, 1]) {
          const PF = [
            [1, 0, 0],
            [0, 1, 0],
            [0, 0, 1]
          ];
          S.box([1.2 + s * 0.78, -0.6, -SZ - 1.5], [0.66, 0.018, 0.85], {
            r: [26, 27],
            tex: (x, y, z, ny) => {
              if (Math.abs(ny) < 0.5) return undefined;
              const u = (x + 9) / 0.165 - Math.floor((x + 9) / 0.165),
                v = (z + 9) / 0.2 - Math.floor((z + 9) / 0.2);
              return u < 0.12 || v < 0.1 ? 29 : ny > 0 ? 27 : 26;
            }
          }, { ax: PF, res: 0.035 });
          S.tube([[1.2, -0.6, -SZ - 1.5], [1.2 + s * 0.12, -0.6, -SZ - 1.5]], 0.03, 0.03, METALM, { res: 0.02 });
        }
        for (const sx of [-1, 1])
          for (const sz of [-1, 1]) {
            const x = sx * (SX - 0.7),
              z = sz * (SZ - 0.6);
            S.lathe([x, -SH - 0.5, z], 0.5, t => 0.13 + 0.2 * (1 - t) * (1 - t), METALM, { res: 0.03 });
            S.torus([x, -SH - 0.08, z], 0.15, 0.03, RUBYM, { res: 0.02 });
          }
        // the eye the anchor chain hangs from
        S.torus([CT[0], CT[1] - 0.02, CT[2]], 0.11, 0.035, METALM, { res: 0.02 });
      }

      rig.own('world', () => S.bake());

      // ================================================================ drawn by hand on the still world
      rig.own('world', () => {
        // the hot spring: milky turquoise, paler at the edge, glints that wink
        const step = 0.055;
        let row = 0;
        for (let z = PO[2] - PR[1]; z <= PO[2] + PR[1]; z += step * 0.87, row++)
          for (let x = PO[0] - PR[0] + (row % 2) * step * 0.5; x <= PO[0] + PR[0]; x += step) {
            const d = pondD(x, z);
            if (d > 0.95) continue;
            const v = B.fbm(x * 1.6 + 7, z * 1.6, 1.7, 2),
              c = d > 0.86 ? 39 : v > 0.62 ? 39 : v > 0.48 ? 38 : d < 0.5 && v < 0.4 ? 36 : 37,
              glint = d < 0.85 && Math.sin(z * 11 + 2 * Math.sin(x * 2.3)) > 0.93 && B.n3(x * 2, z * 2, 4) > 0.5;
            B.disc(x, WL, z, UP, step * 0.62, 0.012, B.P[glint ? 45 : c], 3, glint ? { em: true, k: 4, ph: B.rr(0, 6), sp: B.rr(2, 4) } : { em: true });
          }
        // ripples round the bobber: rings that brighten one after another, outward
        for (let k = 0; k < 3; k++) {
          const rr = 0.15 + k * 0.11,
            n = Math.ceil((TAU * rr) / 0.035);
          for (let i = 0; i < n; i++) {
            const a = (i / n) * TAU;
            B.disc(BOB[0] + Math.cos(a) * rr, WL + 0.006, BOB[2] + Math.sin(a) * rr * 0.9, UP, 0.026, 0.006, B.P[45], 3, { em: true, k: 4, ph: -k * 1.4, sp: (3 * TAU) / L });
          }
        }
        // steam off the spring
        for (let i = 0; i < 70; i++) {
          const a = B.rr(0, TAU),
            q = Math.sqrt(B.R()) * 0.82;
          B.iso(PO[0] + Math.cos(a) * q * PR[0], WL + 0.05, PO[2] + Math.sin(a) * q * PR[1], B.rr(0.05, 0.09), B.P[B.pick([44, 45, 45, 39])], 0.3, {
            nd: true,
            k: 3,
            ph: B.R(),
            sp: 1.8 / L,
            rg: 1.8,
            ex: 1.7
          });
        }
        // the kelp tank's water
        {
          let rw = 0;
          for (let z = -1.58; z <= 1.58; z += 0.06 * 0.87, rw++)
            for (let x = -1.58 + (rw % 2) * 0.03; x <= 1.58; x += 0.06) {
              const d = Math.hypot(x, z);
              if (d > 1.56) continue;
              const v = B.fbm(x * 1.4 + 2, z * 1.4, 3.3, 2);
              B.disc(GC[0] + x, 0.205, GC[2] + z, UP, 0.037, 0.01, B.P[v > 0.6 ? 38 : v > 0.45 ? 37 : 36], 3, { em: true });
            }
        }
        // the kelp forest: stalks from the tank toward the glass, gold floats and long blades, waving (the wave runs up each stalk)
        for (let s = 0; s < 13; s++) {
          const a = s * 2.4 + 0.3,
            rho = s === 0 ? 0.05 : 0.35 + 0.95 * ((s * 0.618) % 1),
            bx = GC[0] + Math.cos(a) * rho,
            bz = GC[2] + Math.sin(a) * rho,
            H = 0.8 * Math.sqrt(GR * GR - rho * rho) - 0.25,
            lean = [B.rr(-0.25, 0.25), B.rr(-0.25, 0.25)],
            ph = B.rr(0, TAU),
            at = t => [bx + lean[0] * t * t, 0.2 + H * t, bz + lean[1] * t * t],
            // the sway grows up the stalk in ten steps (the baked file holds at most 256 kinds of motion)
            sway = t => ({ k: 11, ph, sp: (10 * TAU) / L, rg: 0.012 + 0.009 * Math.round(t * t * 10) });
          const n = Math.ceil(H / 0.045);
          for (let i = 0; i < n; i++) {
            const t0 = i / n,
              t1 = (i + 1) / n,
              p = lerp(at(t0), at(t1), 0.5),
              d = unit(sub(at(t1), at(t0)));
            B.stick(p[0], p[1], p[2], d, 0.03, 0.022, B.P[t0 < 0.5 ? 22 : 23], 3, sway(t0));
          }
          for (let b = 0; b < 7; b++) {
            const t = 0.2 + b * 0.12;
            if (t > 1) break;
            const p = at(t),
              side = b * 2.1 + s,
              out = [Math.cos(side), 0, Math.sin(side)],
              d = unit([out[0], -0.35, out[2]]),
              len = 0.16 + 0.08 * B.R(),
              col = B.pick([11, 12, 13, 23, 12]);
            B.iso(p[0], p[1], p[2], 0.032, B.P[24], 3, sway(t));
            for (let j = 0; j < 4; j++) {
              const q = add(p, d, (j + 0.5) * len * 0.5);
              B.dab(q[0], q[1] - 0.01 * j, q[2], unit(cross(d, [-out[2], 0, out[0]])), d, len * 0.28, 0.045 - j * 0.006, 0.008, B.P[j > 2 ? 14 : col], 3, sway(t));
            }
          }
          // a crown of blades at the top
          const top = at(1);
          for (let j = 0; j < 4; j++) {
            const a2 = j * 1.57 + s,
              d = unit([Math.cos(a2), -0.2, Math.sin(a2)]);
            B.dab(top[0] + d[0] * 0.12, top[1], top[2] + d[2] * 0.12, unit(cross(d, [-d[2], 0, d[0]])), d, 0.13, 0.04, 0.008, B.P[j % 2 ? 13 : 23], 3, sway(1));
          }
        }
        // bubbles rising in the vats, and the fluid's surface
        VX.forEach((x, k) => {
          for (let i = 0; i < 9; i++)
            B.iso(x + B.rr(-0.24, 0.24), 0.36, VZ + B.rr(-0.24, 0.24), B.rr(0.018, 0.03), B.P[B.pick([39, 45, 39])], 3, {
              nd: true,
              k: 3,
              ph: B.R(),
              sp: (2 * 1.12) / L,
              rg: 1.12,
              ex: 0.6
            });
          for (let r = 0.05; r < 0.33; r += 0.05) {
            const n = Math.ceil((TAU * r) / 0.05);
            for (let i = 0; i < n; i++) {
              const a = (i / n) * TAU + r * 3;
              B.disc(x + Math.cos(a) * r, 1.5, VZ + Math.sin(a) * r, UP, 0.034, 0.01, B.P[r > 0.27 ? 39 : 38], 3, { em: true });
            }
          }
        });
        // on the machine's face: dials, blinking lights, and three instant photos stuck on with tape (2012)
        const FZ = -1.6 + 0.355,
          FACE = [0, 0, 1];
        for (const x of [3.18, 4.02]) {
          B.disc(x, 0.85, FZ, FACE, 0.09, 0.01, B.P[5], 3);
          B.disc(x, 0.85, FZ + 0.004, FACE, 0.07, 0.01, B.P[44], 3);
          B.stick(x + 0.025, 0.87, FZ + 0.01, unit([0.8, 0.6, 0]), 0.045, 0.01, B.P[18], 3);
        }
        [
          [2.55, 19],
          [2.7, 24],
          [2.85, 14],
          [4.6, 29],
          [4.75, 19]
        ].forEach(([x, c], i) => B.iso(x, 0.5, FZ + 0.01, 0.035, B.P[c], 3, { em: true, k: 4, ph: i * 1.3, sp: ((2 + (i % 3)) * TAU) / L }));
        [
          [2.62, 0.95, 46],
          [2.84, 0.9, 29],
          [4.62, 0.93, 34]
        ].forEach(([x, y, c], i) => {
          B.disc(x, y, FZ + 0.006, FACE, 0.085, 0.006, B.P[45], 3);
          B.disc(x, y + 0.015, FZ + 0.01, FACE, 0.058, 0.006, B.P[c], 3);
          B.stick(x, y + 0.1, FZ + 0.012, [1, 0, 0], 0.04, 0.012, B.P[47], 3);
        });
        // the crown, seen only in the monolith's polished face: a reflection with nothing in front of it to cast it
        {
          const MW = MF[2],
            MU = MF[0],
            face = (u, v) => add(add(add(MB, MU, u), UP, v), MW, 0.215),
            cs = 0.16,
            u0 = 0.2,
            v0 = 2.95;
          for (let j = 0; j < 3; j++)
            for (let i = 0; i < 5; i++) {
              if (j === 2 && i % 2) continue;
              for (let a = 0; a < 2; a++)
                for (let b = 0; b < 2; b++) {
                  const p = face(u0 + (i - 2) * cs + (a - 0.5) * cs * 0.44, v0 + (j - 1) * cs + (b - 0.5) * cs * 0.44);
                  B.disc(p[0], p[1], p[2], MW, cs * 0.24, 0.006, B.P[(i + j) % 3 ? 23 : 24], 3, { nd: true });
                }
            }
          // and the long streaks of a polished stone
          for (const [u, v, len] of [
            [-0.45, 2.3, 1.1],
            [0.35, 1.2, 0.8],
            [-0.1, 3.4, 0.6]
          ]) {
            const p = face(u, v),
              d = unit(add(MU, UP, 0.9));
            B.stick(p[0], p[1], p[2], d, len * 0.5, 0.012, B.P[8], 3, { nd: true });
          }
        }
        // the dragon's nostrils and a smile
        for (const s of [-1, 1]) {
          const p = DP([s * 0.055, 1.2, 0.585]);
          B.iso(p[0], p[1], p[2], 0.016, B.P[10], 3);
        }
        // feathers that have come loose and drift down past the spring
        for (let i = 0; i < 6; i++) {
          const p = [B.rr(-1.6, 2.8), 3.6, B.rr(-0.6, 1.9)],
            e = unit([B.rr(-1, 1), B.rr(-0.4, 0.4), B.rr(-1, 1)]),
            n = unit(cross(e, unit([B.rr(-1, 1), 1, B.rr(-1, 1)]))),
            an = { k: 2, ph: i / 6, sp: 3.5 / L, rg: 3.5, ex: 0 };
          feather(p, e, n, 0.4, [19, 24, 29, 34, 14][i % 5], an);
        }
        // the grass of the world is kelp; nothing else grows
      });

      // ================================================================ the parts that move, made in a bake of their own
      // ---------------- the dragon's head: wide eyes, horns, and the wizard hat
      const NECK = DP([0, 1.08, 0.12]);
      {
        const o = { tag: 'head', whole: true, res: 0.025, ax: DF },
          ball = (l, r, mat) => S.ball(DP(l), r.map(v => v * DS), mat, o);
        ball([0, 1.22, 0.16], [0.25, 0.22, 0.24], SKIN);
        ball([0, 1.13, 0.4], [0.15, 0.115, 0.2], SKIN);
        ball([0, 1.07, 0.33], [0.13, 0.06, 0.15], BELLY);
        for (const s of [-1, 1]) {
          ball([s * 0.12, 1.3, 0.33], [0.1, 0.11, 0.08], EYEM);
          S.lathe(DP([s * 0.17, 1.34, 0.04]), 0.24 * DS, t => 0.05 * DS * (1 - t) + 0.004, HORNM, { tag: 'head', whole: true, res: 0.018, ax: along(DD([s * 0.65, 0.55, -0.5])) });
          ball([s * 0.21, 1.2, 0.0], [0.03, 0.09, 0.07], RUBYM);
        }
        // the hat: a wide brim, a tall cone whose tip flops back, a gold band
        const tilt = DD([0, 1, -0.15]);
        S.lathe(DP([0, 1.39, 0.12]), 0.03 * DS, 0.37 * DS, HATM, { tag: 'head', whole: true, res: 0.02, ax: along(tilt) });
        S.tube([DP([0, 1.4, 0.11]), DP([0, 1.72, 0.07]), DP([0, 1.97, -0.03]), DP([-0.03, 2.12, -0.2]), DP([-0.05, 2.14, -0.32])], t => (0.25 * Math.pow(1 - t, 1.2) + 0.012) * DS, 0, HATM, {
          tag: 'head',
          whole: true,
          res: 0.02
        });
        S.torus(DP([0, 1.47, 0.105]), 0.225 * DS, 0.028 * DS, BANDM, { tag: 'head', whole: true, res: 0.018, ax: along(tilt) });
      }
      // ---------------- the tail, in two parts so it can swish, with a ruby spade at its end
      const T = [
        [0, 0.1, -0.3],
        [-0.1, 0.02, -0.62],
        [-0.34, -0.1, -0.78],
        [-0.58, -0.13, -0.62],
        [-0.69, -0.13, -0.32],
        [-0.67, -0.12, -0.06]
      ];
      S.tube(T.slice(0, 4).map(DP), t => (0.15 - 0.065 * t) * DS, 0, SKIN, { tag: 'tail', whole: true, res: 0.025 });
      S.tube(T.slice(3).map(DP), t => (0.085 - 0.04 * t) * DS, 0, SKIN, { tag: 'tailtip', whole: true, res: 0.02 });
      S.ball(DP([-0.66, -0.12, 0.02]), [0.1 * DS, 0.03 * DS, 0.12 * DS], RUBYM, { tag: 'tailtip', whole: true, res: 0.018, ax: DF });
      // ---------------- the rod, its line and the bobber, one rigid piece pivoting in his hands
      const HAND = DP([0, 0.56, 0.44]),
        hd = unit([BOB[0] - HAND[0], 0, BOB[2] - HAND[2]]),
        TIP = add(add(HAND, hd, 1.0), UP, 1.1),
        rodDir = unit(sub(TIP, HAND)),
        ROD_AX = unit(cross(hd, UP));
      {
        const o = { tag: 'rod', whole: true, res: 0.016 };
        S.tube([add(HAND, rodDir, -0.3), TIP], 0.042, 0.013, RUBYM, o);
        S.tube([add(HAND, rodDir, -0.3), add(HAND, rodDir, 0.12)], 0.05, 0.047, BANDM, o);
        S.lathe(add(add(HAND, rodDir, 0.24), UP, -0.11), 0.07, 0.065, METALM, Object.assign({ ax: along(ROD_AX) }, o));
        S.ball(add(BOB, [0, 0.07, 0]), 0.1, RUBYM, o);
        S.ball(add(BOB, [0, -0.0, 0]), [0.088, 0.07, 0.088], WHITEM, o);
        S.tube([add(BOB, [0, 0.16, 0]), add(BOB, [0, 0.26, 0])], 0.016, 0.012, BANDM, o);
      }
      // ---------------- the anchor chain under the slab, and its anchor
      const CHAIN_N = 22,
        AY = CT[1] - 0.1 - CHAIN_N * 0.115 - 0.95; // the anchor's crown
      {
        const o = { tag: 'chain', whole: true, res: 0.018 },
          IRON = { r: [6, 7, 8], s: [7, 8, 9, 42] };
        for (let k = 0; k < CHAIN_N; k++)
          S.torus([CT[0], CT[1] - 0.12 - k * 0.115, CT[2]], 0.075, 0.022, IRON, Object.assign({ ax: along(k % 2 ? [1, 0, 0] : [0, 0, 1]) }, o));
        const ay = AY;
        S.torus([CT[0], ay + 1.02, CT[2]], 0.1, 0.03, IRON, Object.assign({ ax: along([0, 0, 1]) }, o));
        S.lathe([CT[0], ay, CT[2]], 0.95, [0.065, 0.045], IRON, o);
        S.tube([[CT[0], ay + 0.82, CT[2] - 0.42], [CT[0], ay + 0.82, CT[2] + 0.42]], 0.035, 0.035, IRON, o);
        for (const s of [-1, 1]) S.ball([CT[0], ay + 0.82, CT[2] + s * 0.44], 0.05, IRON, o);
        S.tube(
          [
            [CT[0] - 0.5, ay + 0.34, CT[2]],
            [CT[0] - 0.36, ay + 0.07, CT[2]],
            [CT[0], ay - 0.03, CT[2]],
            [CT[0] + 0.36, ay + 0.07, CT[2]],
            [CT[0] + 0.5, ay + 0.34, CT[2]]
          ],
          0.05,
          0.05,
          IRON,
          o
        );
        for (const s of [-1, 1])
          S.lathe([CT[0] + s * 0.47, ay + 0.24, CT[2]], 0.26, t => 0.13 * (1 - t) + 0.01, IRON, Object.assign({ ax: along([s * 0.45, 1, 0]) }, o));
      }
      // ---------------- the machine's flywheel, turning
      const FLY = [5.02, 0.65, -1.6];
      {
        const o = { tag: 'fly', whole: true, res: 0.02 },
          FX = along([1, 0, 0]);
        S.torus(FLY, 0.4, 0.045, RUBYM, Object.assign({ ax: FX }, o));
        S.lathe(add(FLY, [-0.06, 0, 0]), 0.12, 0.08, METALM, Object.assign({ ax: FX }, o));
        for (let k = 0; k < 6; k++) {
          const a = (k / 6) * TAU,
            d = [0, Math.cos(a), Math.sin(a)];
          S.tube([add(FLY, d, 0.06), add(FLY, d, 0.38)], 0.022, 0.018, BANDM, o);
        }
      }

      S.bake();

      // ================================================================ drawn by hand on the parts that move
      rig.own('head', () => {
        // wide eyes: big whites, small pupils in the middle, a glint
        for (const s of [-1, 1]) {
          const p = DP([s * 0.18, 1.305, 0.395]),
            g = DP([s * 0.185, 1.335, 0.405]);
          B.iso(p[0], p[1], p[2], 0.036, B.P[5], 3);
          B.iso(g[0], g[1], g[2], 0.011, B.P[45], 3, { em: true });
        }
        // gold stars and a crescent on the hat, on the side that faces out
        const hat = (t, phi) => {
          const y = 1.42 + t * 0.62,
            r = (0.25 * Math.pow(1 - t, 1.2) + 0.012) * 1.04,
            zc = 0.11 - t * 0.12;
          return DP([-Math.sin(phi) * r, y, zc + Math.cos(phi) * r]);
        };
        [
          [0.12, 0.2],
          [0.3, 0.9],
          [0.45, 0.1],
          [0.2, 1.4],
          [0.58, 0.7]
        ].forEach(([t, phi], i) => {
          const p = hat(t, phi);
          B.star(p[0], p[1], p[2], 0.038, i % 2 ? 25 : 24, { k: 4, ph: i * 1.7, sp: (2 * TAU) / L });
        });
      });
      rig.own('rod', () => {
        // the line, from the rod's tip down to the bobber
        const top = add(BOB, [0, 0.26, 0]),
          len = Math.hypot(...sub(TIP, top)),
          d = unit(sub(top, TIP)),
          n = Math.ceil(len / 0.03);
        for (let i = 0; i < n; i++) {
          const p = add(TIP, d, (i + 0.5) * (len / n));
          B.stick(p[0], p[1], p[2], d, len / n / 2 + 0.004, 0.009, B.P[45], 3, { nd: true });
        }
      });
      // the feathers that go round the world, on two tilted rings turning opposite ways
      const RINGS = [
        { name: 'ringA', c: [0, 1.8, 0], ax: unit([0.22, 1, 0.12]), r: 6.4, n: 9, len: 0.85, dir: 1 },
        { name: 'ringB', c: [0, 3.9, 0], ax: unit([-0.12, 1, 0.2]), r: 4.7, n: 6, len: 0.65, dir: -1 }
      ];
      for (const R of RINGS)
        rig.own(R.name, () => {
          const e1 = unit(cross(R.ax, [0, 0, 1])),
            e2 = cross(R.ax, e1);
          for (let k = 0; k < R.n; k++) {
            const a = (k / R.n) * TAU + 0.3 * R.dir,
              rad = add([0, 0, 0], add(e1.map(v => v * Math.cos(a)), e2, Math.sin(a))),
              tg = add(e1.map(v => -v * Math.sin(a)), e2, Math.cos(a)),
              p = add(R.c, rad, R.r),
              e = unit(add(tg.map(v => v * R.dir), UP, 0.25 * Math.sin(k * 1.7)));
            feather(p, e, unit(rad), R.len, [19, 24, 29, 34, 14][k % 5]);
          }
        });

      // ---------------- the sky: smog, thick and warm toward the low sun, a few hazy lights in it
      const SUN_AZ = Math.atan2(S.sun[2], S.sun[0]);
      rig.own('sky', () => {
        FI.backdrop(B, { bokeh: 40, bokehCols: [2, 3, 4, 3] });
        for (let i = 0; i < 560; i++) {
          const a = B.rr(0, TAU),
            r = B.rr(30, 42),
            y = B.gauss() * 5 + 1,
            toward = Math.cos(a - SUN_AZ),
            c = toward > 0.55 && y > -3 ? B.pick([3, 4, 3]) : toward > 0 ? B.pick([1, 2, 3]) : B.pick([1, 1, 2]);
          B.iso(Math.cos(a) * r, y, Math.sin(a) * r, B.rr(1.4, 3.0), B.P[c], B.pick([0.24, 0.32, 0.4]), { em: true, nd: true });
        }
        // the sun low in the smog: a glow round a pale core
        const sd = S.sun,
          sp = [sd[0] * 40, sd[1] * 40, sd[2] * 40];
        for (let i = 0; i < 40; i++) {
          const g = B.randDir(),
            q = B.rr(0, 4.5);
          B.iso(sp[0] + g[0] * q, sp[1] + g[1] * q, sp[2] + g[2] * q, B.rr(1.2, 2.6), B.P[q < 2 ? 25 : 4], B.pick([0.3, 0.42]), { em: true, nd: true });
        }
        B.iso(sp[0], sp[1], sp[2], 1.6, B.P[25], 3, { em: true, nd: true });
      });

      const W = B.finish({
        cam: { target: [0.35, 0.45, 0.25], dist: 17, pitch: PITCH, yaw: YAW },
        detail: 19.4,
        dither: 0.3,
        radius: 10,
        palName: 'Technicolor',
        fog: { c: 2, start: 0.55, max: 0.3 },
        outline: { c: 5, edge: 0.7 },
        ao: { k: 0.4, range: 0.5 }
      });
      FI.loopable(W, L);
      const st = K.stage(W);
      rig.bind(st);

      // every motion comes round in L seconds: the world rocks in its tilt and bobs, the rod nods and twice twitches at a nibble
      // that comes to nothing, the head nods, the tail swishes, the chain swings, the flywheel turns three times, the feathers
      // go round the world once each way
      const HERO = [Math.sin(YAW), 0, Math.cos(YAW)];
      st.add({
        update(dt, t) {
          const w = (TAU * t) / L,
            A = M.rot(HERO, TILT + 0.03 * Math.sin(w));
          rig.set('world', A, [0, 0, 0], [0, 0.1 * Math.sin(w + 0.4), 0]);
          rig.set('sky', A, [0, 0, 0], [0, 0, 0]);
          const nib = Math.exp(6 * (Math.cos(w - 3.6) - 1)),
            look = Math.exp(4 * (Math.cos(w - 3.4) - 1));
          rig.child('rod', 'world', M.rot(ROD_AX, -(0.06 * (0.5 + 0.5 * Math.sin(2 * w)) + 0.2 * nib * (0.5 + 0.5 * Math.sin(12 * w)))), HAND);
          rig.child('head', 'world', M.mul(M.rot(UP, 0.08 * Math.sin(w + 1)), M.rot(DLEFT, 0.04 * Math.sin(2 * w) + 0.16 * look)), NECK);
          rig.child('tail', 'world', M.rot(UP, 0.2 * Math.sin(w)), DP(T[0]));
          rig.child('tailtip', 'tail', M.rot(UP, 0.32 * Math.sin(w - 1)), DP(T[3]));
          rig.child('chain', 'world', M.mul(M.rot([1, 0, 0], 0.05 * Math.sin(w + 1.3)), M.rot([0, 0, 1], 0.09 * Math.sin(w))), CT);
          rig.child('fly', 'world', M.rot([1, 0, 0], 3 * w), FLY);
          for (const R of RINGS) rig.child(R.name, 'world', M.rot(R.ax, R.dir * w), R.c);
          rig.apply();
        }
      });
      return W;

      // a feather: a bare white quill at its base, then a curved vane, wider on one side, white at the root and
      // shading through one of the Technicolor hues to a pale tip
      function feather(p, e, n, len, hue, an) {
        const side = unit(cross(n, e)),
          at = t => add(add(p, e, t * len), side, 0.16 * len * t * t), // the shaft, bending to one side
          VANE = [
            [-0.2, 0.05, 45],
            [-0.04, 0.085, hue - 1],
            [0.12, 0.09, hue],
            [0.27, 0.075, hue],
            [0.39, 0.045, hue + 1]
          ];
        for (let i = 0; i < 6; i++) {
          const t0 = -0.5 + (i * 0.95) / 6,
            t1 = t0 + 0.95 / 6,
            q = lerp(at(t0), at(t1), 0.5);
          B.stick(q[0], q[1], q[2], unit(sub(at(t1), at(t0))), len * 0.085, 0.009, B.P[45], 3, an);
        }
        for (const [t, wd, c] of VANE)
          for (const s of [-1, 1]) {
            const w = wd * len * (s > 0 ? 1 : 0.62),
              q = add(at(t), side, s * w * 0.85),
              d = unit(sub(at(t + 0.05), at(t - 0.05)));
            B.dab(q[0], q[1], q[2], n, d, len * 0.1, w, 0.008, B.P[c], 3, an);
          }
      }
    }
  };
};
