/* A solarpunk robot factory on a floating island at dusk: a workshop hall with a sawtooth roof of glass, sedum and solar panels, a
   brick chimney, copper and brass tanks, a water wheel fed by a flume, two wind turbines, a solar field, an assembly line with two robot
   arms, robots at work, a tree, planters, string lights and a flag; underneath, bedded rock with roots and stalactites, and the brass
   engine that holds it all up, with its propeller, side fans and lanterns on chains. Seeded: it builds the same way every time. */
const FI = require('./floating-island.cjs');

const L = 8; // seconds in one full turn of the loop: every repeating motion comes round in this time

// 48 colours, each ramp shifting hue as it goes from dark to light
const PAL = [
  0x2b2850, 0x3d3766, 0x5e5288, 0x8f7aa8, // 0-3   dusk sky, bokeh, cloud
  0x0f1f1f, 0x16302a, 0x1f4532, 0x2c5e38, 0x3f7a3c, 0x5f9641, 0x8bb24a, 0xc2d064, // 4-11  greens, teal to yellow
  0x1e1416, 0x34201e, 0x55322a, 0x7a4a32, // 12-15 bark and timber
  0x1a1a2e, 0x2e2a46, 0x4e4558, 0x76646a, 0x9e8c80, // 16-20 rock and steel, blue-violet to warm grey
  0x3c1c1e, 0x70361e, 0xa2602a, 0xcf8c3a, 0xe9b85c, 0xf6e3a0, // 21-26 brass and copper, maroon to straw
  0x0f3438, 0x1b5a5a, 0x2f8a80, 0x5cbfa8, 0xa8e8d0, // 27-31 teal glass and patina
  0x645a66, 0xab8f7f, 0xd8c6a2, 0xf4ecd0, // 32-35 cream, mauve to ivory
  0x5a1e14, 0xa8381c, 0xe8642a, 0xff9a3c, 0xffd070, // 36-40 tangerine and lamp light
  0x141d3a, 0x23386a, 0x4a6cb0, // 41-43 solar cells
  0x2a6f9a, 0x7cc8e0, // 44-45 water
  0xe0709a, 0xb8a0e8 // 46-47 flowers
];

// each ramp dark to light; *_SUN is the same thing where the low sun reaches it, warmer; *_LAMP where a lamp is the main light
const GRASS = [4, 5, 6, 7, 8],
  GRASS_SUN = [7, 8, 9, 10, 11],
  GRASS_LAMP = [9, 10, 11, 25],
  LEAF = [4, 5, 6, 7, 8, 9],
  LEAF_SUN = [7, 8, 9, 10, 11],
  LEAF_LAMP = [9, 10, 11, 25],
  BARK = [12, 13, 14, 15],
  BARK_SUN = [13, 14, 15, 23],
  ROCK = [16, 17, 18, 19],
  ROCK_SUN = [17, 18, 19, 20, 33],
  ROCK_LAMP = [18, 19, 23, 24],
  SANDSTONE = [17, 32, 19, 20, 33],
  RUST = [16, 21, 18, 32, 19],
  BRASS = [21, 22, 23, 24],
  BRASS_SUN = [22, 23, 24, 25, 26],
  COPPER = [12, 36, 22, 37],
  COPPER_SUN = [36, 37, 23, 38, 24],
  PATINA = [27, 28, 29, 30],
  PATINA_SUN = [28, 29, 30, 31],
  CREAM = [32, 33, 34],
  CREAM_SUN = [33, 34, 35],
  CREAM_LAMP = [33, 25, 35],
  BRICK = [12, 36, 22, 37],
  BRICK_SUN = [36, 22, 37, 23, 38],
  PAINT = [36, 37, 38],
  PAINT_SUN = [37, 38, 39, 40],
  STEEL = [16, 17, 18, 19],
  STEEL_SUN = [17, 18, 19, 20],
  SOIL = [12, 13, 14, 22],
  STONE = [17, 18, 32, 19, 33],
  GLOW = [39, 40, 35];

module.exports = kit => {
  const { makeBuilder, makeSculpt, KIT: K, courses } = kit;
  return {
    id: 'factory',
    name: 'Robot factory',
    seed: 23,
    loop: L,
    build(seed) {
      const B = makeBuilder(seed, PAL),
        S = K.sculpt(makeSculpt(B)),
        rig = K.rig(B, S),
        M = K.M,
        { clamp, TAU } = FI;
      const ISL = rig.part('island');
      // tagged solids are parts that move; everything else rides the island
      rig.resolve = pr => (pr.tag ? undefined : ISL);
      S.sun = B.norm([0.72, 0.34, 0.5]);
      S.amb = 0.16;
      S.sky = 0.22;
      S.sunK = 0.75;
      S.res = 0.08;
      S.view = B.norm([Math.sin(0.45) * Math.cos(0.22), Math.sin(0.22), Math.cos(0.45) * Math.cos(0.22)]);

      // ---------------- small vector helpers
      const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]],
        sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]],
        mad = (a, b, s) => [a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s],
        cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]],
        // a frame for o.ax whose y runs along dir
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
        hash = (i, j, k) => {
          const v = Math.sin(i * 127.1 + j * 311.7 + k * 74.7) * 43758.5453;
          return v - Math.floor(v);
        };

      // ---------------- where things stand
      const HALL = { x: 0, z: -1.5, hx: 2.3, hz: 1.15, top: 1.45 },
        CZ = 0.42, // the assembly line runs along x here
        YB = 0.55, // its belt's top
        PLANTER = [0.9, 2.75], // the round planter the walking robot goes round
        TREE = [-3.5, 2.55],
        T1 = [2.4, -3.35], // the tall copper tank
        T2 = [3.65, -2.45], // the brass tank
        TURB = [-4.0, -2.35],
        TURB2 = [1.2, -4.6],
        CHIM = [-1.5, -3.05],
        SOLAR_O = [3.7, 2.25],
        FLAG = [0.9, 4.35],
        BED = [-1.15, 4.2],
        BED2 = [-4.35, 0.35],
        AW = 0.05; // the water wheel's direction from the middle

      // ---------------- the land: nearly level, a knoll for the tree, a trodden ring round the planter
      const mud = K.form.mud({ scale: 0.32, crack: 0.035, curl: 0.015, depth: 0.025, seed: 4 });
      const ringD = (x, z) => Math.abs(Math.hypot(x - PLANTER[0], z - PLANTER[1]) - 1.25);
      const ground = (x, z) =>
        0.06 * (B.fbm(x * 0.35 + 3, 1.7, z * 0.35, 2) - 0.5) +
        0.28 * Math.exp(-((x - TREE[0]) ** 2 + (z - TREE[1]) ** 2) / 2.2) +
        (ringD(x, z) < 0.26 ? mud.h(x, z) : 0);
      const plaza = (x, z) => x > -2.95 && x < 2.95 && z > -0.42 && z < 1.08;
      const doorYard = (x, z) => x > 2.3 && x < 3.45 && z > -2.0 && z < -0.42;

      // ---------------- materials
      const TURF = {
        r: [12, 13, 13, 14],
        mod: (x, y, z) => 0.16 * (B.n3(x * 2.6, y * 4.1, z * 2.6) - 0.5) + 0.08,
        tex: (x, y, z, ny, t) => {
          const s = B.n3(x * 5.5, y * 5.5, z * 5.5);
          if (s > 0.8) return ROCK[clamp(Math.floor(t * ROCK.length + 1.5), 0, ROCK.length - 1)];
          if (s < 0.12) return BARK[clamp(Math.floor(t * BARK.length + 1), 0, BARK.length - 1)];
          return undefined;
        },
        top: {
          min: 0.5,
          r: GRASS,
          s: GRASS_SUN,
          g: GRASS_LAMP,
          blade: { h: 0.09, w: 0.022 },
          tex: (x, y, z, ny, t) => {
            // flagstones in front of the hall, laid in courses with dark joints
            if (plaza(x, z) || doorYard(x, z)) {
              const row = Math.floor(z / 0.27),
                u = x / 0.36 + row * 0.5 + 0.2 * hash(row, 3, 1),
                col = Math.floor(u),
                fu = u - col,
                fv = z / 0.27 - row;
              if (fu < 0.08 || fv < 0.1) return 16;
              return S.pick(STONE, t + 0.35 * (hash(col, row, 7) - 0.5));
            }
            // a ring of bare earth worn by the walking robot, cracked as it dries
            const rd = ringD(x, z);
            if (rd < 0.22 + 0.04 * B.n3(x * 3, z * 3, 1.3)) {
              if (mud.crack(x, z) > 0.5) return 12;
              return S.pick(SOIL, t + 0.2);
            }
            return undefined;
          }
        }
      };
      let isle = null;
      const ROCKMAT = {
        r: ROCK,
        s: ROCK_SUN,
        g: ROCK_LAMP,
        b: 0.1,
        mod: (x, y, z) => {
          const bd = isle ? isle.bed(y) : { i: 0, hard: 0.5 };
          return 0.26 * (B.n3(bd.i * 3.1, 0.5, 1.7) - 0.5) + 0.14 * (B.n3(x * 2.2, y * 5.5, z * 2.2) - 0.5);
        },
        // each bed is its own stone: warm sandstone, the grey-violet, or a rusty red, with a few flecks of copper ore
        tex: (x, y, z, ny, t) => {
          const bd = isle ? isle.bed(y) : { i: 0, hard: 0.5 },
            kind = B.n3(bd.i * 1.9 + 0.4, 4.2, 2.3);
          if (B.n3(x * 7.5, y * 7.5, z * 7.5) > 0.9) return S.pick(PATINA, t);
          if (kind > 0.58) return S.pick(SANDSTONE, t);
          if (kind < 0.36) return S.pick(RUST, t);
          return undefined;
        }
      };
      const CREAMM = { r: CREAM, s: CREAM_SUN, g: CREAM_LAMP, mod: (x, y, z) => 0.08 * (B.n3(x * 6, y * 6, z * 6) - 0.5) },
        PAINTM = { r: PAINT, s: PAINT_SUN, wear: { t: 0.25 } },
        BRASSM = { r: BRASS, s: BRASS_SUN, gloss: { c: 26, at: 0.93, c2: 25, at2: 0.88 } },
        COPPERM = { r: COPPER, s: COPPER_SUN, gloss: { c: 26, at: 0.93, c2: 25, at2: 0.88 } },
        PATINAM = { r: PATINA, s: PATINA_SUN, wear: { t: 0.25 } },
        STEELM = { r: STEEL, s: STEEL_SUN },
        TIMBER = { r: BARK, s: BARK_SUN, mod: (x, y, z) => 0.1 * (B.n3(x * 9, y * 3, z * 9) - 0.5) },
        BRICKM = { r: BRICK, s: BRICK_SUN, mod: courses(0.2, 0.09, B.n3, 0.14) },
        GLOWM = { r: GLOW, em: true, v: 0.6 },
        VISOR = { r: [30, 31], em: true, v: 0.6 },
        BUSH = { r: LEAF, s: LEAF_SUN, g: LEAF_LAMP, leaf: {} },
        SOILM = { r: SOIL, mod: (x, y, z) => 0.2 * (B.n3(x * 12, y * 12, z * 12) - 0.5) };

      // ---------------- the island itself
      isle = FI.body(K, B, S, {
        R: 6.2,
        thick: 0.75,
        depth: 4.4,
        ground,
        turf: TURF,
        rock: ROCKMAT,
        lumps: 14,
        seed: 8,
        res: 0.1
      });
      const gy = (x, z) => isle.h(x, z);
      // what stands where, so the flowers keep off it
      const busy = [];
      // parts that move are queued here and made in a bake of their own, so nothing still is cut where they stood
      const moving = [];
      const free = (x, z, pad) => {
        for (const [bx, bz, br] of busy) if (Math.hypot(x - bx, z - bz) < br + (pad || 0)) return false;
        return true;
      };

      // ---------------- the hall: brick plinth, cream walls with arched windows lit from within, a door on the east end
      const hx = HALL.hx,
        hz = HALL.hz,
        cxH = HALL.x,
        czH = HALL.z;
      const winTex = (x, y, z, ny, t, nx, nz) => {
        if (Math.abs(ny) > 0.5) return undefined;
        const onZ = Math.abs(nz) > 0.7,
          onX = Math.abs(nx) > 0.7;
        if (!onZ && !onX) return undefined;
        const u = onZ ? x - cxH : z - czH,
          pitch = 0.62,
          k = Math.round(u / pitch),
          du = u - k * pitch,
          face = onZ ? (nz > 0 ? 0 : 1) : nx > 0 ? 2 : 3;
        if (onZ ? Math.abs(k) > 3 : Math.abs(k) > 1) return undefined;
        if (face === 2 && k === 0) return undefined; // the door
        const hw = 0.165,
          y0 = 0.52,
          y1 = 1.2,
          top = y1 - hw + Math.sqrt(Math.max(0, hw * hw - du * du));
        if (Math.abs(du) > hw + 0.04 || y < y0 - 0.05 || y > top + 0.045) return undefined;
        if (Math.abs(du) > hw || y < y0 || y > top) return y < y0 ? 33 : 23; // a stone sill, a brass frame
        if (Math.abs(du) < 0.014 || Math.abs(y - 0.86) < 0.014) return 22; // glazing bars
        const lit = hash(k, face, 2) > 0.28;
        if (!lit) return y > 0.95 && du < 0 ? 29 : 28;
        return y > 0.86 ? 40 : 39;
      };
      const wall = S.box([cxH, 0.65, czH], [hx, 0.8, hz], Object.assign({ tex: winTex }, CREAMM), { hold: true, res: 0.045 });
      const doorBox = S.box([cxH + hx, 0.62, czH], [0.14, 0.32, 0.31], CREAMM, { hold: true }),
        doorArch = S.lathe([cxH + hx - 0.14, 0.94, czH], 0.28, 0.31, CREAMM, { hold: true, ax: S.AX });
      // the doorway is carved out of the wall, and its sides take the lamplight from inside
      S.join('cut', wall, [doorBox, doorArch], { r: 0.02, inner: GLOW, res: 0.04 });
      S.box([cxH + hx - 0.135, 0.78, czH], [0.012, 0.47, 0.3], GLOWM, { res: 0.035 });
      S.box([cxH, 0.08, czH], [hx + 0.04, 0.23, hz + 0.04], BRICKM, { res: 0.045 });
      // a brass cornice round the top of the walls
      for (const s of [-1, 1]) {
        S.box([cxH, 1.47, czH + s * hz], [hx + 0.06, 0.035, 0.06], BRASSM, { res: 0.04 });
        S.box([cxH + s * hx, 1.47, czH], [0.06, 0.035, hz + 0.06], BRASSM, { res: 0.04 });
      }
      for (const sx of [-1, 1])
        for (const sz of [-1, 1]) S.box([cxH + sx * (hx + 0.02), 0.7, czH + sz * (hz + 0.02)], [0.07, 0.76, 0.07], BRICKM, { res: 0.04 });
      // steps up to the door, and a gear over it
      K.form.steps(S, { r: STONE }, { at: [cxH + hx + 0.42, gy(cxH + hx + 0.42, czH) - 0.05, czH], dir: [-1, 0, 0], n: 2, rise: 0.17, run: 0.18, width: 0.8, res: 0.035, seed: 5 });
      S.extrude(K.poly2.gear(10, 0.2, 0.05), [cxH + hx + 0.03, 1.27, czH], 0.05, BRASSM, {
        ax: [
          [0, 0, -1],
          [0, 1, 0],
          [1, 0, 0]
        ],
        res: 0.025
      });
      S.lights.push({ p: [cxH + hx + 0.7, 0.75, czH], r: 2.6, s: 0.9, sh: true });
      // lamplight from the windows onto the yard
      for (let k = -3; k <= 3; k += 2) {
        S.lights.push({ p: [cxH + k * 0.62, 0.8, czH + hz + 0.45], r: 1.6, s: 0.35 });
        S.lights.push({ p: [cxH + k * 0.62, 0.8, czH - hz - 0.45], r: 1.6, s: 0.35 });
      }

      // the roof: four teeth, each a slope (sedum or solar) to the sun and a face of glass behind it
      const teeth = 4,
        tw = (2 * hx) / teeth,
        th = 0.64,
        ty = 1.5,
        tl = Math.hypot(th / tw, 1);
      const glassTex = (x, y, z, ny, t, nx) => {
        if (nx > -0.7) return undefined;
        const v = (y - ty) / 0.155,
          u = (z - czH) / 0.205,
          fu = u - Math.floor(u),
          fv = v - Math.floor(v);
        if (fu < 0.12 || fv < 0.14 || y < ty + 0.04) return 23;
        const lit = hash(Math.floor(u), Math.floor(v), Math.round(x * 3)) > 0.42;
        return lit ? (fv > 0.6 ? 40 : 39) : fv > 0.7 ? 30 : 29;
      };
      const sedum = {
        r: CREAM,
        s: CREAM_SUN,
        tex: glassTex,
        top: {
          min: 0.4,
          r: GRASS,
          s: GRASS_SUN,
          tex: (x, y, z) => {
            const q = B.n3(x * 7, y * 7, z * 7);
            if (q > 0.82) return B.n3(x * 2, 5, z * 2) > 0.5 ? 46 : 47;
            if (q < 0.18) return 11;
            return undefined;
          }
        }
      };
      const solarTop = {
        r: CREAM,
        s: CREAM_SUN,
        tex: glassTex,
        top: {
          min: 0.4,
          r: [41, 42, 42, 43],
          tex: (x, y, z, ny, t) => {
            const u = (z - czH) / 0.2,
              v = (x + 9) / 0.19,
              fu = u - Math.floor(u),
              fv = v - Math.floor(v);
            if (Math.abs(z - czH) > hz - 0.02) return 23;
            if (fu < 0.08 || fv < 0.1) return 43;
            return S.pick([41, 41, 42, 42], t);
          }
        }
      };
      for (let i = 0; i < teeth; i++) {
        const x0 = cxH - hx + i * tw;
        S.convex(
          [x0, ty, czH],
          [
            { n: [0, -1, 0], d: 0 },
            { n: [-1, 0, 0], d: 0 },
            { n: [th / tw / tl, 1 / tl, 0], d: th / tl },
            { n: [0, 0, 1], d: hz + 0.07 },
            { n: [0, 0, -1], d: hz + 0.07 }
          ],
          i % 2 ? solarTop : sedum,
          { res: 0.05 }
        );
        // a ridge cap along the top of the glass, a gutter in the valley
        S.tube([[x0, ty + th + 0.01, czH - hz - 0.08], [x0, ty + th + 0.01, czH + hz + 0.08]], 0.024, 0.024, BRASSM, { res: 0.03 });
        S.tube([[x0 + tw - 0.02, ty + 0.02, czH - hz - 0.12], [x0 + tw - 0.02, ty + 0.02, czH + hz + 0.12]], 0.035, 0.035, BRASSM, { res: 0.03 });
        // vents on the green slopes
        if (i % 2 === 0)
          for (const dz of [-0.55, 0.45]) {
            const vx = x0 + tw * 0.62,
              vy = ty + th * (1 - 0.62);
            S.lathe([vx, vy - 0.06, czH + dz], 0.24, t => (t > 0.78 ? 0.085 : 0.055), STEELM, { res: 0.025 });
          }
      }
      // downpipes at the back corners
      for (const sx of [-1, 1])
        S.tube([[cxH + sx * (hx - 0.02), ty + 0.02, czH - hz - 0.14], [cxH + sx * (hx - 0.02), 1.3, czH - hz - 0.14], [cxH + sx * (hx - 0.02), 0.05, czH - hz - 0.14]], 0.03, 0.03, BRASSM, { res: 0.03 });
      busy.push([cxH, czH, 2.6], [cxH - 1.6, czH, 1.4], [cxH + 1.6, czH, 1.4]);

      // ---------------- the greenhouse leaning on the west end
      const GH = { x0: cxH - hx - 0.95, x1: cxH - hx - 0.01, z0: czH - 0.8, z1: czH + 0.8, y0: 0.32, yH: 1.32, yL: 0.92 };
      {
        const sl = (GH.yH - GH.yL) / (GH.x1 - GH.x0),
          nl = Math.hypot(sl, 1),
          c = [GH.x1, GH.y0, czH];
        S.convex(
          c,
          [
            { n: [0, -1, 0], d: 0 },
            { n: [1, 0, 0], d: 0 },
            { n: [-1, 0, 0], d: GH.x1 - GH.x0 },
            { n: [0, 0, 1], d: 0.8 },
            { n: [0, 0, -1], d: 0.8 },
            { n: [-sl / nl, 1 / nl, 0], d: (GH.yH - GH.y0) / nl }
          ],
          K.look.glass([28, 29, 30, 31], { a: 0.32 }),
          { res: 0.05, ghost: true }
        );
        // its brass frame
        const yAt = x => GH.yL + ((x - GH.x0) / (GH.x1 - GH.x0)) * (GH.yH - GH.yL);
        for (const z of [GH.z0, czH - 0.27, czH + 0.27, GH.z1]) {
          S.tube([[GH.x0, GH.y0 - 0.3, z], [GH.x0, yAt(GH.x0), z], [GH.x1, yAt(GH.x1), z]], 0.018, 0.018, BRASSM, { res: 0.025 });
        }
        S.tube([[GH.x0, yAt(GH.x0), GH.z0], [GH.x0, yAt(GH.x0), GH.z1]], 0.018, 0.018, BRASSM, { res: 0.025 });
        S.tube([[GH.x0, 0.62, GH.z0], [GH.x0, 0.62, GH.z1]], 0.014, 0.014, BRASSM, { res: 0.025 });
        // a low wall it stands on, and plants inside
        S.box([(GH.x0 + GH.x1) / 2, 0.12, czH], [(GH.x1 - GH.x0) / 2, 0.22, 0.82], BRICKM, { res: 0.04 });
        for (let k = 0; k < 7; k++) {
          const x = GH.x0 + 0.22 + (k % 2) * 0.45,
            z = czH - 0.6 + k * 0.2,
            G = Object.assign(S.grp(0.05), { res: 0.035 });
          S.lathe([x, 0.33, z], 0.12, [0.07, 0.09], { r: [36, 37, 22] }, { res: 0.025 });
          S.ball([x, 0.52, z], [0.12, 0.1 + 0.06 * hash(k, 2, 2), 0.12], BUSH, G);
          S.ball([x + 0.05, 0.62, z - 0.03], 0.07, BUSH, G);
        }
        S.lights.push({ p: [(GH.x0 + GH.x1) / 2, 0.9, czH], r: 1.6, s: 0.4 });
      }
      busy.push([GH.x0 + 0.45, czH, 1.0]);

      // ---------------- the chimney, brick with brass bands
      const chy = gy(CHIM[0], CHIM[1]) - 0.1;
      S.lathe([CHIM[0], chy, CHIM[1]], 4.1, t => 0.31 - 0.08 * t + (t > 0.95 ? 0.05 : 0), BRICKM, { res: 0.04 });
      for (const y of [1.6, 2.9, 3.95]) S.torus([CHIM[0], chy + y, CHIM[1]], 0.3 - 0.08 * (y / 4.1) + 0.01, 0.025, BRASSM, { res: 0.025 });
      S.tube([[CHIM[0], 0.55, CHIM[1] + 0.2], [CHIM[0], 0.55, czH - hz]], 0.07, 0.07, COPPERM, { res: 0.03 });
      busy.push([CHIM[0], CHIM[1], 0.5]);

      // ---------------- the tanks: tall copper, squat brass, patina domes, bands, a ladder and a walkway
      const tank = (p, r, h, mat, bands) => {
        const y = gy(p[0], p[1]) - 0.05;
        S.lathe([p[0], y - 0.1, p[1]], 0.22, r + 0.1, { r: STONE }, { res: 0.04 });
        S.lathe([p[0], y + 0.1, p[1]], h, t => r * (t < 0.04 ? 0.92 + 2 * t : 1), mat, { res: 0.04 });
        S.lathe([p[0], y + 0.1 + h - 0.01, p[1]], r * 0.55, t => r * Math.sqrt(Math.max(0, 1 - t * t)) + 0.01, PATINAM, { res: 0.035 });
        for (const b of bands) S.torus([p[0], y + 0.1 + h * b, p[1]], r + 0.01, 0.022, BRASSM, { res: 0.025 });
        busy.push([p[0], p[1], r + 0.3]);
        return y + 0.1;
      };
      const t1y = tank(T1, 0.55, 1.9, COPPERM, [0.15, 0.5, 0.85]),
        t2y = tank(T2, 0.45, 1.45, BRASSM, [0.2, 0.75]);
      // a ladder up the copper tank, and a walkway round its top
      {
        const a = 0.55 * Math.PI,
          d = [Math.cos(a), 0, Math.sin(a)],
          sd = [-d[2], 0, d[0]],
          base = [T1[0] + d[0] * 0.62, t1y, T1[1] + d[2] * 0.62];
        for (const s of [-1, 1]) S.tube([mad(base, sd, s * 0.13), mad(add(base, [0, 2.0, 0]), sd, s * 0.13)], 0.014, 0.014, STEELM, { res: 0.022 });
        for (let k = 1; k < 10; k++) S.tube([mad(add(base, [0, k * 0.2, 0]), sd, -0.13), mad(add(base, [0, k * 0.2, 0]), sd, 0.13)], 0.01, 0.01, STEELM, { res: 0.022 });
        S.torus([T1[0], t1y + 1.92, T1[1]], 0.72, 0.02, BRASSM, { res: 0.025 });
        S.torus([T1[0], t1y + 2.15, T1[1]], 0.72, 0.016, BRASSM, { res: 0.025 });
        for (let k = 0; k < 10; k++) {
          const b = (k / 10) * TAU;
          S.tube([[T1[0] + Math.cos(b) * 0.72, t1y + 1.9, T1[1] + Math.sin(b) * 0.72], [T1[0] + Math.cos(b) * 0.72, t1y + 2.15, T1[1] + Math.sin(b) * 0.72]], 0.012, 0.012, BRASSM, { res: 0.022 });
        }
        S.torus([T1[0], t1y + 1.9, T1[1]], 0.64, 0.07, { r: STEEL }, { res: 0.03 });
      }
      // pipes: tank to tank, and from the copper tank along the back of the hall, with valve wheels
      const valve = (p, axis) => {
        S.torus(p, 0.075, 0.014, PAINTM, { res: 0.02, ax: frameY(axis) });
        S.lathe(mad(p, axis, -0.05), 0.08, 0.025, BRASSM, { res: 0.02, ax: frameY(axis) });
      };
      S.tube([[T2[0] - 0.4, t2y + 0.5, T2[1] - 0.12], [T1[0] + 0.5, t1y + 0.5, T1[1] + 0.2]], 0.05, 0.05, COPPERM, { res: 0.03 });
      valve([(T2[0] + T1[0]) / 2 + 0.1, t2y + 0.6, (T2[1] + T1[1]) / 2 + 0.05], B.norm([0.6, 0, -0.8]));
      S.tube(
        [
          [T1[0] - 0.5, t1y + 0.4, T1[1] + 0.1],
          [T1[0] - 0.8, t1y + 0.4, czH - hz - 0.22],
          [cxH - 0.6, 0.5, czH - hz - 0.22],
          [CHIM[0] + 0.32, 0.5, czH - hz - 0.22]
        ],
        0.045,
        0.045,
        BRASSM,
        { res: 0.028 }
      );
      for (const x of [1.2, 0.1, -0.7]) S.torus([x, 0.5, czH - hz - 0.22], 0.055, 0.015, COPPERM, { res: 0.02, ax: frameY([1, 0, 0]) });
      valve([0.55, 0.5, czH - hz - 0.3], [0, 0, -1]);
      // a gauge on the copper tank
      {
        const a = 0.25 * Math.PI,
          p = [T1[0] + Math.cos(a) * 0.57, t1y + 0.95, T1[1] + Math.sin(a) * 0.57];
        S.lathe(p, 0.05, 0.1, { r: CREAM }, { res: 0.02, ax: frameY([Math.cos(a), 0, Math.sin(a)]) });
        S.torus(mad(p, [Math.cos(a), 0, Math.sin(a)], 0.05), 0.1, 0.014, BRASSM, { res: 0.02, ax: frameY([Math.cos(a), 0, Math.sin(a)]) });
      }

      // ---------------- the water wheel at the east rim, and the flume that feeds it from the brass tank
      const eW = isle.rim(AW),
        WO = [Math.cos(AW), 0, Math.sin(AW)], // out from the middle
        WAX = [-Math.sin(AW), 0, Math.cos(AW)], // the axle
        WR = 0.85,
        WC = [WO[0] * (eW + 0.05), 0.95, WO[2] * (eW + 0.05)];
      for (const s of [-1, 1]) {
        const top = mad(WC, WAX, s * 0.34);
        for (const back of [0.95, 0.15]) {
          const foot = mad(mad(WC, WO, -back), WAX, s * 0.42);
          foot[1] = gy(foot[0], foot[2]) - 0.08;
          S.tube([foot, top], 0.045, 0.04, TIMBER, { res: 0.03 });
        }
        S.lathe(mad(top, WAX, s > 0 ? -0.06 : -0.06), 0.12, 0.075, BRASSM, { res: 0.022, ax: frameY(WAX) });
      }
      // the flume: a trough on stilts, falling gently from the tank to above the wheel
      const F0 = [T2[0] + 0.45, 2.05, T2[1] + 0.38],
        F1 = add(mad(WC, WO, -0.12), [0, WR + 0.2, 0]),
        FD = B.norm(sub(F1, F0)),
        FL = Math.hypot(...sub(F1, F0)),
        FA = B.norm(cross(FD, [0, 1, 0])),
        FU = cross(FA, FD),
        Ff = [FD, FU, FA],
        Fm = mad(F0, FD, FL / 2);
      S.box(Fm, [FL / 2, 0.016, 0.13], TIMBER, { ax: Ff, res: 0.03 });
      for (const s of [-1, 1]) S.box(mad(mad(Fm, FA, s * 0.13), FU, 0.055), [FL / 2, 0.07, 0.016], TIMBER, { ax: Ff, res: 0.03 });
      for (const k of [1, 3]) {
        const p = mad(F0, FD, (FL * k) / 4);
        for (const s of [-1, 1]) {
          const q = mad(p, FA, s * 0.12);
          S.tube([[q[0], gy(q[0], q[2]) - 0.05, q[2]], [q[0], q[1] - 0.02, q[2]]], 0.025, 0.022, TIMBER, { res: 0.025 });
        }
        S.box(add(p, [0, -0.03, 0]), [0.03, 0.03, 0.16], BRASSM, { ax: Ff, res: 0.022 });
      }
      // the pipe from the tank that spills into it (a hollow pipe, open at its end)
      K.build.pipe(S, [[T2[0] + 0.3, t2y + 1.2, T2[1] + 0.22], [F0[0] - 0.12, t2y + 1.2, F0[2] - 0.12], [F0[0], F0[1] + 0.22, F0[2]]], { r: 0.075, wall: 0.022, collar: 0.08, mats: { metal: COPPERM } });
      busy.push([WC[0] - 0.5, WC[2], 0.9]);

      // ---------------- the wind turbines
      const turbine = (p, h, len, F, tag) => {
        const y = gy(p[0], p[1]) - 0.08;
        S.lathe([p[0], y - 0.15, p[1]], 0.3, [0.34, 0.3], { r: STONE }, { res: 0.04 });
        S.lathe([p[0], y, p[1]], h, t => 0.15 - 0.07 * t, { r: CREAM, s: CREAM_SUN, tex: (x, yy, z, ny, t) => (yy > y + h - 0.35 || Math.abs(yy - y - h * 0.45) < 0.08 ? S.pick(PAINT_SUN, t) : undefined) }, { res: 0.035 });
        S.box([p[0], y + 0.25, p[1]], [0.07, 0.15, 0.13], { r: [16, 17, 32] }, { res: 0.025, ax: yawF(Math.atan2(F[0], F[2])) });
        const top = [p[0], y + h + 0.06, p[1]],
          Fr = frameY(F);
        S.lathe(mad(top, F, -0.3), 0.62, t => 0.12 * Math.sin(Math.PI * (0.15 + 0.7 * t)) + 0.03, { r: CREAM, s: CREAM_SUN }, { res: 0.028, ax: Fr });
        const H = mad(top, F, 0.36),
          side = B.norm(cross(F, [0, 1, 0]));
        moving.push(() => {
        S.lathe(mad(H, F, -0.05), 0.2, t => 0.085 * Math.sqrt(1 - t * t) + 0.01, PAINTM, { res: 0.022, ax: Fr, tag, whole: true });
        const bladeMat = { r: CREAM, s: CREAM_SUN, tex: (x, yy, z, ny, t) => (Math.hypot(x - H[0], yy - H[1], z - H[2]) > len * 0.78 ? S.pick(PAINT_SUN, t) : undefined) };
        for (let k = 0; k < 3; k++) {
          const a = (k / 3) * TAU + 0.3,
            d = add([0, Math.cos(a), 0], [side[0] * Math.sin(a), 0, side[2] * Math.sin(a)]);
          K.sweep(
            S,
            [mad(H, d, 0.06), mad(mad(H, d, len * 0.5), F, 0.03), mad(mad(H, d, len), F, 0.07)],
            { w: t => 0.1 * (1 - 0.72 * t) * (t < 0.1 ? 0.55 + 4.5 * t : 1) + 0.012, h: 0.016, shape: 'flat', twist: 0.08 },
            bladeMat,
            { up: F, res: 0.028, tag, whole: true }
          );
        }
        });
        busy.push([p[0], p[1], 0.5]);
        return H;
      };
      const F1d = B.norm([0.45, 0, 0.9]),
        F2d = B.norm([0.3, 0, 1]),
        HUB1 = turbine(TURB, 4.3, 1.55, F1d, 'rotor'),
        HUB2 = turbine(TURB2, 3.1, 1.05, F2d, 'rotor2');

      // ---------------- the assembly line: a belt between a press and a packer, legs, rails
      {
        const y = YB;
        S.box([0, y - 0.05, CZ], [2.02, 0.05, 0.25], { r: [16, 17], tex: (x, yy, z, ny) => (ny > 0.5 ? ((x + 9) / 0.14) % 1 < 0.18 ? 16 : 17 : undefined) }, { res: 0.03 });
        S.box([0, y - 0.16, CZ], [2.02, 0.05, 0.29], STEELM, { res: 0.035 });
        for (const s of [-1, 1]) S.tube([[-2.0, y + 0.03, CZ + s * 0.28], [2.0, y + 0.03, CZ + s * 0.28]], 0.022, 0.022, BRASSM, { res: 0.025 });
        for (let x = -1.65; x <= 1.7; x += 0.66)
          for (const s of [-1, 1]) S.box([x, (y - 0.2) / 2 - 0.05, CZ + s * 0.24], [0.03, (y - 0.2) / 2 + 0.06, 0.03], STEELM, { res: 0.025 });
        for (let x = -1.65; x < 1.6; x += 1.32) S.tube([[x, 0.05, CZ - 0.24], [x + 0.66, y - 0.22, CZ - 0.24]], 0.014, 0.014, STEELM, { res: 0.022 });
        // the press, its gantry over the belt
        const PX = -2.42;
        S.box([PX, 0.5, CZ], [0.42, 0.55, 0.42], CREAMM, { res: 0.04 });
        S.box([PX, 1.08, CZ], [0.45, 0.04, 0.45], PAINTM, { res: 0.035 });
        S.box([PX, 0.14, CZ], [0.44, 0.17, 0.44], PAINTM, { res: 0.035 });
        for (const sx of [-1, 1]) for (const sz of [-1, 1]) S.tube([[PX + sx * 0.42, 0.05, CZ + sz * 0.42], [PX + sx * 0.42, 1.08, CZ + sz * 0.42]], 0.02, 0.02, BRASSM, { res: 0.025 });
        S.box([PX + 0.425, y + 0.09, CZ], [0.012, 0.11, 0.27], GLOWM, { res: 0.025 });
        S.lathe([PX, 1.1, CZ], 0.32, [0.13, 0.11], BRASSM, { res: 0.03 });
        S.lathe([PX - 0.15, 1.42, CZ + 0.1], 0.22, 0.045, COPPERM, { res: 0.025 });
        S.lathe([PX, y - 0.25, CZ + 0.425], 0.04, 0.09, { r: CREAM }, { res: 0.02, ax: frameY([0, 0, 1]) });
        S.lathe([PX + 0.22, y - 0.25, CZ + 0.425], 0.04, 0.07, { r: CREAM }, { res: 0.02, ax: frameY([0, 0, 1]) });
        const GX = -1.55;
        for (const s of [-1, 1]) S.box([GX, 0.72, CZ + s * 0.34], [0.04, 0.68, 0.04], PAINTM, { res: 0.025 });
        S.box([GX, 1.42, CZ], [0.06, 0.05, 0.4], PAINTM, { res: 0.025 });
        S.lathe([GX, 1.08, CZ], 0.3, 0.075, BRASSM, { res: 0.025 });
        // the packer at the other end, a hopper on top
        const QX = 2.42;
        S.box([QX, 0.5, CZ], [0.42, 0.55, 0.42], PATINAM, { res: 0.04 });
        S.box([QX, 1.08, CZ], [0.45, 0.04, 0.45], BRASSM, { res: 0.035 });
        S.box([QX, 0.14, CZ], [0.44, 0.17, 0.44], { r: CREAM }, { res: 0.035 });
        S.box([QX - 0.425, y + 0.09, CZ], [0.012, 0.11, 0.27], GLOWM, { res: 0.025 });
        S.lathe([QX, 1.1, CZ], 0.45, t => 0.1 + 0.22 * t, COPPERM, { res: 0.03 });
        S.torus([QX, 1.55, CZ], 0.32, 0.02, BRASSM, { res: 0.022 });
        for (const sx of [-1, 1]) for (const sz of [-1, 1]) S.tube([[QX + sx * 0.42, 0.05, CZ + sz * 0.42], [QX + sx * 0.42, 1.08, CZ + sz * 0.42]], 0.02, 0.02, BRASSM, { res: 0.025 });
        busy.push([-2.42, CZ, 0.7], [2.42, CZ, 0.7], [0, CZ, 1.0], [-1.2, CZ, 1.0], [1.2, CZ, 1.0]);
      }
      // the robot arms' pedestals (the arms themselves move, below): x, z is where each one works, px, pz where it stands, off to the
      // side so it reaches across the view and shows its shape
      const ARMS = [
        { x: -0.75, z: CZ - 0.52, px: 0.0, pz: CZ - 0.5, tool: 'weld' },
        { x: 0.85, z: CZ - 0.52, px: 1.6, pz: CZ - 0.5, tool: 'grip' }
      ];
      for (const a of ARMS) {
        S.lathe([a.px, -0.05, a.pz], 0.24, [0.23, 0.21], STEELM, { res: 0.025 });
        S.torus([a.px, 0.17, a.pz], 0.21, 0.02, BRASSM, { res: 0.02 });
      }

      // ---------------- the solar field: six panels on posts, tilted to the low sun
      const sunH = B.norm([S.sun[0], 0, S.sun[2]]),
        across = [-sunH[2], 0, sunH[0]],
        tilt = 0.55,
        PN = B.norm([Math.sin(tilt) * sunH[0], Math.cos(tilt), Math.sin(tilt) * sunH[2]]),
        PV = B.norm(cross(PN, across));
      for (let j = 0; j < 2; j++)
        for (let k = 0; k < 3; k++) {
          const cx = SOLAR_O[0] + across[0] * (k - 1) * 0.92 + sunH[0] * (j - 0.5) * 0.95,
            cz = SOLAR_O[1] + across[2] * (k - 1) * 0.92 + sunH[2] * (j - 0.5) * 0.95,
            c = [cx, gy(cx, cz) + 0.55, cz];
          S.convex(
            c,
            [
              { n: PN, d: 0.018 },
              { n: [-PN[0], -PN[1], -PN[2]], d: 0.018 },
              { n: across, d: 0.42 },
              { n: [-across[0], 0, -across[2]], d: 0.42 },
              { n: PV, d: 0.29 },
              { n: [-PV[0], -PV[1], -PV[2]], d: 0.29 }
            ],
            {
              r: STEEL,
              tex: (x, y, z, ny, t, nx, nz) => {
                if (nx * PN[0] + ny * PN[1] + nz * PN[2] < 0.7) return undefined;
                const d = [x - c[0], y - c[1], z - c[2]],
                  a = d[0] * across[0] + d[2] * across[2],
                  b = d[0] * PV[0] + d[1] * PV[1] + d[2] * PV[2];
                if (Math.abs(a) > 0.39 || Math.abs(b) > 0.26) return 33;
                const fa = (a + 9) / 0.13 - Math.floor((a + 9) / 0.13),
                  fb = (b + 9) / 0.13 - Math.floor((b + 9) / 0.13);
                if (fa < 0.1 || fb < 0.1) return 43;
                return S.pick([41, 41, 42, 42, 43], t);
              }
            },
            { res: 0.035 }
          );
          for (const s of [-1, 1]) {
            const top = mad(mad(c, across, s * 0.3), PN, -0.03);
            S.tube([[top[0], gy(top[0], top[2]) - 0.05, top[2]], top], 0.022, 0.022, STEELM, { res: 0.025 });
          }
          S.box([cx, gy(cx, cz) + 0.12, cz], [0.06, 0.08, 0.04], BRASSM, { res: 0.022, ax: yawF(Math.atan2(sunH[0], sunH[2])) });
          busy.push([cx, cz, 0.5]);
        }
      // the cable from the field to the hall, lying in the grass
      S.tube(K.curve.bezier([SOLAR_O[0] - 0.9, 0.04, SOLAR_O[1] - 0.6], [2.6, 0.02, 1.2], [3.1, 0.02, 0.3], [2.85, 0.05, -0.35], 12).map(p => [p[0], gy(p[0], p[2]) + 0.015, p[2]]), 0.018, 0.018, { r: [16, 17] }, { res: 0.022 });

      // ---------------- the tree on its knoll, with a bench
      rig.own('island', () => FI.clumpyTree(B, S, 0.19, TREE[0], gy(TREE[0], TREE[1]) - 0.05, TREE[1], {
        h: 2.3,
        r: 0.18,
        spread: 1.6,
        nb: 7,
        lean: [0.06, -0.04],
        roots: 5,
        bark: { r: BARK, s: BARK_SUN, mod: (x, y, z) => 0.12 * (B.n3(x * 9, y * 2, z * 9) - 0.5) },
        leaf: { r: LEAF, s: LEAF_SUN, g: LEAF_LAMP },
        leaves: 8000,
        ls: 0.46,
        res: 0.055
      }));
      busy.push([TREE[0], TREE[1], 0.6]);
      {
        const bx = TREE[0] + 0.85,
          bz = TREE[1] + 0.55,
          by = gy(bx, bz),
          bf = yawF(-0.6);
        S.box([bx, by + 0.3, bz], [0.42, 0.025, 0.12], TIMBER, { ax: bf, res: 0.025 });
        S.box(mad([bx, by + 0.48, bz], bf[2], -0.1), [0.42, 0.08, 0.02], TIMBER, { ax: bf, res: 0.025 });
        for (const s of [-1, 1]) S.box(mad([bx, by + 0.15, bz], bf[0], s * 0.36), [0.025, 0.17, 0.11], BRASSM, { ax: bf, res: 0.022 });
        busy.push([bx, bz, 0.5]);
      }

      // ---------------- planters: a round one in the yard with a sundial among flowers, a bed by the gardener, a bed with bean poles
      {
        const [px, pz] = PLANTER,
          py = gy(px, pz) - 0.05;
        S.lathe([px, py, pz], 0.32, [0.52, 0.5], BRICKM, { res: 0.04 });
        S.torus([px, py + 0.32, pz], 0.5, 0.035, { r: STONE }, { res: 0.025 });
        S.lathe([px, py + 0.25, pz], 0.06, 0.47, SOILM, { res: 0.035 });
        S.lathe([px, py + 0.3, pz], 0.42, t => 0.06 - 0.025 * t + (t > 0.9 ? 0.04 : 0), { r: STONE }, { res: 0.025 });
        S.lathe([px, py + 0.72, pz], 0.025, 0.15, BRASSM, { res: 0.02 });
        S.convex([px, py + 0.745, pz], [{ n: [0, -1, 0], d: 0 }, { n: [1, 0, 0], d: 0.006 }, { n: [-1, 0, 0], d: 0.006 }, { n: [0, 0.6, 0.8], d: 0.06 }, { n: [0, 0, -1], d: 0.1 }], BRASSM, { res: 0.015 });
        const G = Object.assign(S.grp(0.05), { res: 0.03 });
        for (let k = 0; k < 6; k++) {
          const a = (k / 6) * TAU + 0.3;
          S.ball([px + Math.cos(a) * 0.32, py + 0.34, pz + Math.sin(a) * 0.32], [0.08, 0.06, 0.08], BUSH, G);
        }
        busy.push([px, pz, 0.7]);
      }
      const bed = (c, half, yaw, plants) => {
        const y = gy(c[0], c[1]) - 0.04,
          f = yawF(yaw);
        S.box([c[0], y + 0.15, c[1]], [half[0], 0.17, half[1]], { r: BARK, s: BARK_SUN, mod: (x, yy) => (((yy - y) / 0.085) % 1 < 0.15 ? -0.25 : 0) }, { ax: f, res: 0.03 });
        S.box([c[0], y + 0.3, c[1]], [half[0] - 0.04, 0.03, half[1] - 0.04], SOILM, { ax: f, res: 0.03 });
        const P = (u, v) => [c[0] + f[0][0] * u + f[2][0] * v, y + 0.33, c[1] + f[0][2] * u + f[2][2] * v];
        plants(P, y + 0.33);
        busy.push([c[0], c[1], Math.max(half[0], half[1]) + 0.2]);
      };
      bed(BED, [0.6, 0.22], 0, (P, y) => {
        for (let k = 0; k < 4; k++) {
          const p = P(-0.45 + k * 0.3, 0);
          if (k % 2)
            K.form.ribbed(S, [[p[0], y, p[2]], [p[0], y + 0.17, p[2]]], t => 0.11 * Math.sin(Math.PI * (0.08 + 0.84 * t)) + 0.01, { r: [36, 37, 38, 39], s: [37, 38, 39, 40] }, { ribs: 9, depth: 0.2, res: 0.025 });
          else K.form.rosette(S, [p[0], y, p[2]], { r: [5, 6, 7, 8, 9], s: [7, 8, 9, 10, 11] }, { n: 12, r: 0.15 });
        }
      });
      bed(BED2, [0.25, 0.65], 0.3, (P, y) => {
        // bean poles in a row of tents, leaves climbing them
        for (let k = 0; k < 3; k++) {
          const a = P(-0.12, -0.42 + k * 0.42),
            b = P(0.12, -0.42 + k * 0.42),
            top = add(P(0, -0.42 + k * 0.42), [0, 1.0, 0]);
          S.tube([[a[0], y - 0.05, a[2]], top], 0.012, 0.01, TIMBER, { res: 0.022 });
          S.tube([[b[0], y - 0.05, b[2]], top], 0.012, 0.01, TIMBER, { res: 0.022 });
          const G = Object.assign(S.grp(0.04), { res: 0.03 });
          for (let j = 0; j < 5; j++) {
            const u = 0.15 + j * 0.17,
              q = mad([a[0], y, a[2]], sub(top, [a[0], y, a[2]]), u);
            S.ball(add(q, [0.02 * (j % 2), 0, 0]), 0.07 - j * 0.008, BUSH, G);
            const q2 = mad([b[0], y, b[2]], sub(top, [b[0], y, b[2]]), u + 0.08);
            S.ball(q2, 0.065 - j * 0.008, BUSH, G);
          }
        }
      });

      // ---------------- rocks, mossy on top, and bushes in the open grass
      const MOSSROCK = { r: ROCK, s: ROCK_SUN, b: 0.08, wear: { t: 0.3 }, top: { min: 0.78, r: GRASS, s: GRASS_SUN } };
      [
        [1.7, 5.0, 0.38, 3],
        [2.05, 4.75, 0.18, 4],
        [-1.9, 5.0, 0.3, 5],
        [4.3, 3.5, 0.26, 6],
        [5.1, -1.6, 0.34, 7],
        [-5.2, -0.8, 0.3, 8],
        [-2.2, -4.9, 0.36, 9],
        [3.6, -4.3, 0.28, 10],
        [-4.6, 3.3, 0.22, 11]
      ].forEach(([x, z, r, sd]) => {
        if (!free(x, z, r)) return;
        K.grow.rock(S, [x, gy(x, z) + r * 0.25, z], r, MOSSROCK, { facets: 8, chip: 0.3, beds: { n: 3 }, seed: sd, res: Math.max(0.03, r * 0.12) });
        busy.push([x, z, r + 0.1]);
      });
      [
        [2.5, 4.4, 0.32],
        [-2.7, 4.5, 0.36],
        [4.8, 2.6, 0.3],
        [5.0, 0.95, 0.28],
        [-4.95, -3.0, 0.34],
        [-0.9, -4.7, 0.3],
        [-5.0, 1.6, 0.3]
      ].forEach(([x, z, r], i) => {
        if (!free(x, z, r)) return;
        const G = Object.assign(S.grp(0.08), { res: 0.05 }),
          y = gy(x, z);
        S.ball([x, y + r * 0.35, z], [r * 0.8, r * 0.55, r * 0.75], BUSH, G);
        for (let k = 0; k < 4; k++) {
          const a = k * 1.9 + i,
            q = r * 0.42;
          S.ball([x + Math.cos(a) * q, y + r * (0.3 + 0.25 * (k % 2)), z + Math.sin(a) * q], r * (0.42 + 0.12 * B.n3(i, k, 2)), BUSH, G);
        }
        busy.push([x, z, r + 0.1]);
      });

      // ---------------- crates and barrels by the door, and by the press
      const crate = (x, z, y, s, yaw) => {
        const c = [x, (y === undefined ? gy(x, z) - 0.02 : y) + s, z];
        S.box(c, [s, s, s], { r: BARK, s: BARK_SUN, mod: (xx, yy) => (((yy - c[1] + s) / (s * 0.5)) % 1 < 0.12 ? -0.3 : 0.05 * (B.n3(xx * 9, yy * 2, 1) - 0.5)) }, { ax: yawF(yaw || 0), res: 0.025, rd: 0.01 });
        for (const dy of [-0.7, 0.7]) S.box(add(c, [0, dy * s, 0]), [s + 0.008, 0.012, s + 0.008], BRASSM, { ax: yawF(yaw || 0), res: 0.02 });
        return c[1] + s;
      };
      const barrel = (x, z, h, r) => {
        const y = gy(x, z) - 0.02;
        // staves: a darker line every so far round
        S.lathe([x, y, z], h, t => r * (0.86 + 0.14 * Math.sin(Math.PI * t)), { r: BARK, s: BARK_SUN, mod: (xx, yy, zz) => (((Math.atan2(zz - z, xx - x) + 9) / 0.4) % 1 < 0.15 ? -0.2 : 0) }, { res: 0.025 });
        for (const b of [0.18, 0.82]) S.torus([x, y + h * b, z], r * (0.86 + 0.14 * Math.sin(Math.PI * b)) + 0.008, 0.012, BRASSM, { res: 0.02 });
      };
      {
        let top = crate(3.1, -0.7, undefined, 0.15, 0.2);
        crate(3.12, -0.72, top, 0.11, 0.6);
        crate(3.5, -1.0, undefined, 0.13, -0.3);
        crate(3.45, -0.35, undefined, 0.1, 0.9);
        barrel(2.95, -2.15, 0.42, 0.16);
        barrel(3.25, -2.25, 0.42, 0.16);
        crate(-3.15, 1.15, undefined, 0.14, 0.4);
        top = crate(-3.4, 0.82, undefined, 0.12, -0.2);
        barrel(-3.05, 0.55, 0.38, 0.14);
        busy.push([3.3, -0.7, 0.55], [3.1, -2.2, 0.4], [-3.2, 0.85, 0.55]);
      }

      // ---------------- lamp posts, the flagpole and the cables of string lights between them
      const POLES = [
        [-3.05, 1.35, 2.0],
        [2.85, 1.25, 2.0],
        [FLAG[0], FLAG[1], 2.85]
      ];
      const poleTop = [];
      for (const [x, z, h] of POLES) {
        const y = gy(x, z) - 0.05;
        S.lathe([x, y, z], 0.16, [0.08, 0.06], { r: STONE }, { res: 0.025 });
        S.tube([[x, y, z], [x, y + h, z]], 0.032, 0.022, BRASSM, { res: 0.025 });
        S.ball([x, y + h + 0.03, z], 0.045, BRASSM, { res: 0.02 });
        if (h < 2.5) {
          S.box([x, y + h - 0.2, z], [0.06, 0.08, 0.06], GLOWM, { res: 0.02 });
          S.box([x, y + h - 0.1, z], [0.08, 0.018, 0.08], PAINTM, { res: 0.02 });
          S.lights.push({ p: [x, y + h - 0.3, z], r: 2.2, s: 0.75, sh: true });
        }
        poleTop.push([x, y + h - 0.05, z]);
        busy.push([x, z, 0.2]);
      }
      const corner = s => [cxH + s * (hx + 0.02), 1.5, czH + hz + 0.03];
      const CABLES = [
        [corner(-1), poleTop[0], 0.25],
        [corner(1), poleTop[1], 0.25],
        [poleTop[0], poleTop[1], 0.45],
        [poleTop[0], poleTop[2], 0.5],
        [poleTop[1], poleTop[2], 0.5]
      ];
      const sagPts = (a, b, sag, n) => {
        const out = [];
        for (let i = 0; i <= n; i++) {
          const u = i / n;
          out.push([a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u - sag * 4 * u * (1 - u), a[2] + (b[2] - a[2]) * u]);
        }
        return out;
      };
      for (const [a, b, sag] of CABLES) S.tube(sagPts(a, b, sag, 10), 0.008, 0.008, { r: [12, 16] }, { res: 0.02 });

      // ---------------- the hanging machinery under the island: the engine and its propeller, two side fans, chains with lanterns
      const yBot = isle.yBot,
        ENG = [0, yBot - 1.5, 0],
        ENG_H = 2.1,
        engR = t => 0.24 + 0.56 * Math.pow(Math.sin(Math.PI * (0.12 + 0.8 * t)), 0.7);
      S.lathe(ENG, ENG_H, engR, BRASSM, { res: 0.04 });
      for (const b of [0.22, 0.36, 0.7, 0.86]) S.torus([0, ENG[1] + ENG_H * b, 0], engR(b) + 0.01, 0.04, COPPERM, { res: 0.03 });
      S.lathe([0, ENG[1] - 0.3, 0], 0.34, [0.07, 0.2], PATINAM, { res: 0.03 });
      S.tube([[0, ENG[1] - 0.25, 0], [0, ENG[1] - 0.5, 0]], 0.05, 0.05, STEELM, { res: 0.025 });
      S.lights.push({ p: [0, ENG[1] - 1.0, 0], r: 3.6, s: 0.8 });
      S.lights.push({ p: [0.5, yBot - 4.0, 2.5], r: 10, s: 0.4 });
      const PROP = [0, ENG[1] - 0.52, 0];
      moving.push(() => {
      S.ball(PROP, 0.12, PAINTM, { res: 0.022, tag: 'prop', whole: true });
      for (let k = 0; k < 4; k++) {
        const a = (k / 4) * TAU,
          d = [Math.cos(a), 0, Math.sin(a)];
        K.sweep(S, [mad(PROP, d, 0.08), mad(add(PROP, [0, -0.03, 0]), d, 0.8), mad(add(PROP, [0, -0.06, 0]), d, 1.5)], { w: t => 0.16 * (1 - 0.55 * t) + 0.025, h: 0.02, shape: 'flat', twist: 0.12 }, { r: CREAM, s: CREAM_SUN, tex: (x, y, z, ny, t) => (Math.hypot(x, z) > 1.22 ? S.pick(PAINT, t + 0.3) : undefined) }, { up: [0, 1, 0], res: 0.035, tag: 'prop', whole: true });
      }
      });
      // pipes running down the rock to the engine
      for (const a of [0.9, 2.9]) {
        const pts = [];
        for (let y = -0.9; y > yBot + 0.6; y -= 0.45) {
          const r = isle.rockR(y, a) + 0.07;
          pts.push([Math.cos(a) * r, y, Math.sin(a) * r]);
        }
        pts.push([Math.cos(a) * 0.62, ENG[1] + ENG_H * 0.78, Math.sin(a) * 0.62]);
        S.tube(pts, 0.05, 0.05, COPPERM, { res: 0.028 });
        for (let i = 1; i < pts.length - 1; i += 2) S.torus(pts[i], 0.065, 0.016, BRASSM, { res: 0.02, ax: frameY(sub(pts[i + 1], pts[i - 1])) });
      }
      // side fans on struts, a nozzle glowing behind each
      const FANS = [
        { a: 2.5, y: -2.4 },
        { a: -0.75, y: -2.9 }
      ].map((f, k) => {
        const out = [Math.cos(f.a), 0, Math.sin(f.a)],
          T = [-Math.sin(f.a), 0, Math.cos(f.a)],
          r = isle.rockR(f.y, f.a),
          C = add(mad([0, f.y, 0], out, r + 0.5), [0, -0.1, 0]),
          Fr = frameY(T);
        S.tube([mad(C, out, -0.12), mad([0, f.y + 0.1, 0], out, r - 0.15)], 0.05, 0.06, STEELM, { res: 0.025 });
        S.lathe(mad(C, T, -0.45), 0.9, t => 0.11 + 0.12 * Math.pow(Math.sin(Math.PI * (0.1 + 0.8 * t)), 0.6), BRASSM, { res: 0.03, ax: Fr });
        S.torus(mad(C, T, 0.47), 0.21, 0.025, COPPERM, { res: 0.022, ax: Fr });
        S.torus(mad(C, T, -0.47), 0.1, 0.03, { r: GLOW, em: true, v: 0.6 }, { res: 0.02, ax: Fr });
        S.lights.push({ p: mad(C, T, -0.9), r: 1.3, s: 0.6 });
        const hub = mad(C, T, 0.5),
          tag = 'fan' + k;
        moving.push(() => {
        S.ball(hub, 0.05, PAINTM, { res: 0.02, tag, whole: true });
        for (let j = 0; j < 5; j++) {
          const b = (j / 5) * TAU,
            d = add(mad([0, 0, 0], Fr[0], Math.cos(b)), mad([0, 0, 0], Fr[2], Math.sin(b)));
          S.box(mad(hub, d, 0.11), [0.02, 0.09, 0.008], { r: CREAM, s: CREAM_SUN }, { res: 0.02, tag, whole: true, ax: [T, d, cross(T, d)] });
        }
        });
        return { hub, T, tag };
      });
      // chains hanging from the rock, a lantern on each
      const chain = (a, y, n) => {
        const r = isle.rockR(y, a) - 0.05,
          top = [Math.cos(a) * r, y, Math.sin(a) * r];
        for (let k = 0; k < n; k++) S.torus(add(top, [0, -k * 0.075, 0]), 0.04, 0.011, STEELM, { res: 0.02, ax: frameY(k % 2 ? [1, 0, 0] : [0, 0, 1]) });
        const lp = add(top, [0, -n * 0.075 - 0.08, 0]);
        S.box(lp, [0.055, 0.075, 0.055], GLOWM, { res: 0.02 });
        S.box(add(lp, [0, 0.085, 0]), [0.075, 0.016, 0.075], BRASSM, { res: 0.02 });
        S.box(add(lp, [0, -0.085, 0]), [0.06, 0.012, 0.06], BRASSM, { res: 0.02 });
        S.lights.push({ p: lp, r: 1.5, s: 0.6 });
        return lp;
      };
      const LANTERNS = [chain(1.7, -2.0, 12), chain(4.3, -3.2, 9), chain(0.1, -1.6, 8)];

      // roots, stalactites and vines under the rim, kept clear of the waterfall
      const away = (a, b, w) => Math.abs(Math.atan2(Math.sin(a - b), Math.cos(a - b))) < w;
      FI.roots(K, B, S, isle, { r: BARK.slice(0, 3), mod: () => 0.1 }, { n: 11, len: 0.6, seed: 41, skip: a => away(a, AW, 0.55) });
      S.ready();
      K.form.drips(S, { box: [-4.0, 4.0, -4.0, 4.0], y: isle.yBot - 0.5, n: 70, gap: 0.45, len: [0.4, 1.3], r: 0.18, mites: false, mat: ROCKMAT, seed: 12, res: 0.04 });
      for (let k = 0; k < 6; k++) {
        const a = (k / 6) * TAU + 0.9,
          y = isle.yTop - 0.5,
          r = isle.rockR(y, a);
        if (away(a, AW, 0.5)) continue;
        const grown = K.grow.creep(S, { from: [Math.cos(a) * r, y, Math.sin(a) * r], dir: [0, -1, 0], steps: 30, step: 0.12, wander: 0.5, branch: 0.08, seed: 80 + k });
        K.grow.vine(S, grown, { r: [5, 6, 7] }, { r: LEAF }, { r: 0.02, size: 0.13, leaves: 0.9, seed: 90 + k });
      }

      rig.own('island', () => S.bake());

      // ---------------- drawn by hand after the bake: water, sparks, steam, flowers, lights, the hanging grass
      rig.own('island', () => {
        // water in the flume, with a few winking glints
        for (let u = 0; u < FL; u += 0.035)
          for (const s of [-0.07, 0, 0.07]) {
            const p = mad(mad(mad(F0, FD, u), FA, s + B.rr(-0.015, 0.015)), FU, 0.03),
              glint = B.R() < 0.08;
            B.disc(p[0], p[1], p[2], FU, 0.04, 0.01, B.P[glint ? 31 : B.pick([44, 44, 45, 29])], 3, glint ? { em: true, k: 4, ph: B.rr(0, 6), sp: B.rr(2, 4) } : { em: true });
          }
        // it spills from the flume onto the wheel, and from the wheel's far side off the edge of the island
        for (let i = 0; i < 160; i++) {
          const s = B.rr(-0.1, 0.1);
          B.stick(F1[0] + FD[0] * 0.05 + WAX[0] * s, F1[1] - 0.05, F1[2] + FD[2] * 0.05 + WAX[2] * s, B.UP, 0.04, 0.02, B.P[B.pick([44, 45, 45, 31])], 3, { em: true, k: 2, ph: B.R(), sp: 0.4, rg: 0.22, ex: 0.5 });
        }
        const fall = 6.6;
        for (let i = 0; i < 1300; i++) {
          const s = B.rr(-0.2, 0.2),
            out = WR + 0.08 + B.rr(0, 0.12) + (B.R() < 0.2 ? B.rr(0, 0.2) : 0),
            p = mad(mad(WC, WO, out), WAX, s);
          B.stick(p[0], WC[1] + 0.2, p[2], B.UP, 0.07 + 0.06 * B.R(), 0.022, B.P[B.pick([44, 45, 45, 31, 31, 35])], 3, { em: true, k: 2, ph: B.R(), sp: fall / 2, rg: fall, ex: 1.6 });
        }
        for (let i = 0; i < 40; i++) {
          const p = mad(mad(WC, WO, WR * 0.7 + B.rr(-0.2, 0.3)), WAX, B.rr(-0.25, 0.25));
          B.iso(p[0], WC[1] + B.rr(0.4, 0.95), p[2], 0.02, B.P[B.pick([45, 31, 35])], 3, { em: true, k: 1, ph: B.rr(0, 6), sp: B.rr(4, 8) });
        }
        // welding sparks under the first arm's torch
        const wa = ARMS[0],
          torch = [wa.x, 0.8, wa.z + 0.5];
        for (let i = 0; i < 90; i++)
          B.iso(torch[0] + B.rr(-0.05, 0.05), torch[1], torch[2] + B.rr(-0.05, 0.05), 0.014, B.P[B.pick([38, 39, 40, 40, 35])], 3, { em: true, nd: true, k: 2, ph: B.R(), sp: 0.5, rg: B.rr(0.15, 0.3), ex: 0.3 });
        // steam from the chimney and the roof vents
        for (let i = 0; i < 60; i++)
          B.iso(CHIM[0] + B.rr(-0.08, 0.08), chy + 4.15, CHIM[1] + B.rr(-0.08, 0.08), 0.11, B.P[B.pick([33, 34, 35, 3])], 0.6, { nd: true, k: 3, ph: B.R(), sp: 0.5, rg: 2.4, ex: 2.4 });
        for (let i = 0; i < 2; i++) {
          const vx = cxH - hx + i * 2 * tw + tw * 0.62,
            vy = ty + th * (1 - 0.62) + 0.2;
          for (let j = 0; j < 18; j++) B.iso(vx + B.rr(-0.03, 0.03), vy, czH - 0.55 + B.rr(-0.03, 0.03), 0.06, B.P[B.pick([34, 35, 3])], 0.5, { nd: true, k: 3, ph: B.R(), sp: 0.4, rg: 0.9, ex: 1.5 });
        }
        // string lights along the cables, pulsing a little
        for (const [a, b, sag] of CABLES) {
          const pts = sagPts(a, b, sag, 60);
          for (let i = 3; i < pts.length - 2; i += 5) {
            const p = pts[i];
            B.iso(p[0], p[1] - 0.04, p[2], 0.032, B.P[(i / 5) % 2 ? 40 : 39], 3, { em: true, k: 7, ph: i * 0.7, sp: 1.6, rg: 0.35 });
          }
        }
        // blinking lights on the machines
        const blinks = [
          [-2.42 + 0.25, 1.0, CZ + 0.43, 38],
          [-2.42 - 0.2, 1.0, CZ + 0.43, 30],
          [2.42 - 0.2, 0.95, CZ + 0.43, 40],
          [2.42 + 0.2, 0.95, CZ + 0.43, 30],
          [T1[0], t1y + 2.4, T1[1], 38],
          [HUB1[0], HUB1[1] + 0.18, HUB1[2], 38],
          [HUB2[0], HUB2[1] + 0.16, HUB2[2], 38]
        ];
        for (const [x, y, z, c] of blinks) B.iso(x, y, z, 0.035, B.P[c], 3, { em: true, k: 4, ph: B.rr(0, 6), sp: B.rr(1.5, 3) });
        // the engine's portholes
        for (let k = 0; k < 10; k++) {
          const a = (k / 10) * TAU,
            y = ENG[1] + ENG_H * 0.53,
            r = engR(0.53) + 0.012,
            n = [Math.cos(a), 0, Math.sin(a)];
          B.disc(n[0] * r, y, n[2] * r, n, 0.075, 0.01, B.P[k % 3 ? 40 : 39], 3, { em: true });
        }
        // flowers through the grass, in drifts, keeping off what stands there and the trodden places
        const FLOWER = [46, 47, 35, 40, 46, 11];
        let made = 0;
        for (let tries = 0; tries < 3000 && made < 300; tries++) {
          const a = B.rr(0, TAU),
            q = Math.sqrt(B.R()) * 5.8,
            x = Math.cos(a) * q,
            z = Math.sin(a) * q;
          if (q > isle.rim(a) - 0.35 || !free(x, z, 0.05) || plaza(x, z) || doorYard(x, z) || ringD(x, z) < 0.32) continue;
          if (B.n3(x * 0.9, z * 0.9, 5.5) < 0.42) continue;
          const y = gy(x, z),
            hgt = B.rr(0.1, 0.2),
            c = B.P[FLOWER[Math.floor(B.n3(x * 0.6, z * 0.6, 8.1) * FLOWER.length)]],
            sw = { k: 11, ph: B.rr(0, 6), sp: 1.9, rg: 0.012 };
          B.stick(x, y + hgt * 0.5, z, B.UP, hgt * 0.5, 0.012, B.P[7], 3, sw);
          B.iso(x, y + hgt, z, 0.034, c, 3, sw);
          made++;
        }
        // flowers in the round planter and on the bean poles
        for (let k = 0; k < 40; k++) {
          const a = B.rr(0, TAU),
            r = B.rr(0.2, 0.44),
            x = PLANTER[0] + Math.cos(a) * r,
            z = PLANTER[1] + Math.sin(a) * r,
            y = gy(PLANTER[0], PLANTER[1]) + 0.31,
            hgt = B.rr(0.06, 0.16);
          B.stick(x, y + hgt * 0.5, z, B.UP, hgt * 0.5, 0.011, B.P[8], 3);
          B.iso(x, y + hgt, z, 0.032, B.P[B.pick([46, 47, 40, 35])], 3);
        }
        // the grass that hangs over the rim, and moss in strands down the rock
        FI.skirt(B, isle, { ramp: [4, 5, 6, 7, 8, 9], sun: S.sun, len: 0.27, gap: 0.045 });
        for (let i = 0; i < 220; i++) {
          const a = B.rr(0, TAU),
            y = B.rr(isle.yBot + 1.0, isle.yTop - 0.3),
            r = isle.rockR(y, a) + 0.02;
          if (B.n3(Math.cos(a) * 2, y * 0.8, Math.sin(a) * 2) < 0.5) continue;
          const len = B.rr(0.12, 0.42);
          B.stick(Math.cos(a) * r, y - len * 0.5, Math.sin(a) * r, B.UP, len * 0.5, 0.02, B.P[B.pick([5, 6, 6, 7, 8])], 3, { k: 11, ph: B.rr(0, 6), sp: 1.9, rg: 0.015 });
        }
        // motes of light round the lanterns
        for (const lp of LANTERNS)
          for (let i = 0; i < 6; i++)
            B.iso(lp[0] + B.rr(-0.4, 0.4), lp[1] + B.rr(-0.4, 0.3), lp[2] + B.rr(-0.4, 0.4), 0.022, B.P[B.pick([39, 40])], 3, { em: true, nd: true, k: 6, ph: B.rr(0, 6), sp: B.rr(0.5, 1), rg: 0.1 });
      });

      // ---------------- what moves: made in a bake of its own so nothing still is cut where it stood
      for (const make of moving) make();
      // the water wheel: two rims, spokes, a hub and the buckets between the rims
      {
        const WF = frameY(WAX),
          o = { tag: 'wheel', whole: true };
        for (const s of [-1, 1]) S.torus(mad(WC, WAX, s * 0.19), WR, 0.035, TIMBER, Object.assign({ res: 0.03, ax: WF }, o));
        S.lathe(mad(WC, WAX, -0.3), 0.6, 0.1, BRASSM, Object.assign({ res: 0.03, ax: WF }, o));
        for (let k = 0; k < 8; k++) {
          const a = (k / 8) * TAU,
            d = add(mad([0, 0, 0], WO, Math.cos(a)), [0, Math.sin(a), 0]);
          for (const s of [-1, 1]) S.tube([mad(mad(WC, WAX, s * 0.19), d, 0.08), mad(mad(WC, WAX, s * 0.19), d, WR - 0.02)], 0.022, 0.02, TIMBER, Object.assign({ res: 0.03 }, o));
        }
        for (let k = 0; k < 14; k++) {
          const a = (k / 14) * TAU + 0.1,
            d = add(mad([0, 0, 0], WO, Math.cos(a)), [0, Math.sin(a), 0]),
            tn = cross(WAX, d);
          S.box(mad(WC, d, WR - 0.1), [0.11, 0.2, 0.016], { r: BARK, s: BARK_SUN }, Object.assign({ res: 0.03, ax: [d, WAX, tn] }, o));
        }
      }
      // the press's ram over the belt
      const PRESS = [-1.55, 0.95, CZ];
      S.lathe(add(PRESS, [0, -0.08, 0]), 0.26, 0.035, STEELM, { res: 0.02, tag: 'press', whole: true });
      S.box(add(PRESS, [0, -0.1, 0]), [0.12, 0.03, 0.14], PAINTM, { res: 0.02, tag: 'press', whole: true });
      // things riding the belt: crates, robot heads, canisters and gears
      const NI = 6,
        ITEMS = [];
      for (let k = 0; k < NI; k++) {
        const x = -2.2 + ((k + 0.5) * 4.4) / NI,
          tag = 'item' + k,
          o = { tag, whole: true, res: 0.025 },
          kind = k % 4;
        if (kind === 0) {
          S.box([x, YB + 0.1, CZ], [0.1, 0.1, 0.1], { r: BARK, s: BARK_SUN }, Object.assign({ rd: 0.008 }, o));
          for (const dy of [-0.06, 0.06]) S.box([x, YB + 0.1 + dy, CZ], [0.106, 0.01, 0.106], BRASSM, o);
        } else if (kind === 1) {
          S.ball([x, YB + 0.1, CZ], [0.11, 0.09, 0.1], CREAMM, o);
          S.box([x, YB + 0.11, CZ + 0.085], [0.075, 0.025, 0.02], VISOR, Object.assign({ rd: 0.01 }, o));
        } else if (kind === 2) {
          S.lathe([x, YB, CZ], 0.22, t => (t > 0.85 ? 0.06 : 0.08), COPPERM, o);
          S.torus([x, YB + 0.11, CZ], 0.083, 0.012, BRASSM, o);
        } else {
          S.extrude(K.poly2.gear(9, 0.11, 0.03), [x, YB + 0.115, CZ], 0.045, BRASSM, o);
          S.lathe([x, YB + 0.115 - 0.0, CZ - 0.03], 0.06, 0.03, STEELM, Object.assign({ ax: frameY([0, 0, 1]) }, o));
        }
        ITEMS.push({ x, tag });
      }
      // the two robot arms, big enough to read from across the island: a tangerine turret, then a tall box-section upper arm and a
      // forearm reaching down to the belt in dark steel, so they stand out against the lit windows behind, with tangerine joint caps;
      // the wrist stays where the work is, and the shoulder and elbow turn about the axis square to the arm's own reach
      const ARM_STEEL = { r: [16, 17, 18], s: [17, 18, 19] };
      for (let k = 0; k < ARMS.length; k++) {
        const a = ARMS[k],
          wr = [a.x, 0.98, a.z + 0.5],
          reach = B.norm([wr[0] - a.px, 0, wr[2] - a.pz]),
          axis = [reach[2], 0, -reach[0]],
          b = [a.px, 0.2, a.pz],
          sh = [a.px, 0.52, a.pz],
          el = [a.px + reach[0] * 0.2, 1.32, a.pz + reach[2] * 0.2],
          base = 'arm' + k,
          up = base + 'u',
          lo = base + 'l',
          seg = (p, q, w, d, tag) =>
            S.box([(p[0] + q[0]) / 2, (p[1] + q[1]) / 2, (p[2] + q[2]) / 2], [w, Math.hypot(q[0] - p[0], q[1] - p[1], q[2] - p[2]) / 2, d], ARM_STEEL, {
              res: 0.032,
              rd: 0.025,
              ax: frameY(sub(q, p)),
              tag,
              whole: true
            });
        a.parts = { base, up, lo, b, sh, el, wr, axis };
        S.lathe(b, 0.16, 0.17, PAINTM, { res: 0.032, tag: base, whole: true });
        S.box([a.px, 0.46, a.pz], [0.13, 0.11, 0.12], PAINTM, { res: 0.032, rd: 0.03, ax: yawF(Math.atan2(reach[0], reach[2])), tag: base, whole: true });
        S.lathe(mad(sh, axis, -0.17), 0.34, 0.11, PAINTM, { res: 0.028, ax: frameY(axis), tag: base, whole: true });
        seg(sh, el, 0.1, 0.09, up);
        S.lathe(mad(el, axis, -0.15), 0.3, 0.1, PAINTM, { res: 0.028, ax: frameY(axis), tag: up, whole: true });
        seg(el, wr, 0.075, 0.065, lo);
        S.ball(wr, 0.06, STEELM, { res: 0.02, tag: lo, whole: true });
        if (a.tool === 'weld') {
          S.lathe(add(wr, [0, -0.17, 0]), 0.15, t => 0.014 + 0.04 * t, BRASSM, { res: 0.02, tag: lo, whole: true });
        } else {
          for (const s of [-1, 1]) S.box(add(wr, [s * 0.05, -0.1, 0]), [0.018, 0.075, 0.04], STEELM, { res: 0.02, tag: lo, whole: true });
        }
      }
      // robots: a walker going round the planter, a gardener with a watering can, one by the tanks, one carrying a crate to the door
      const robot = (x, z, yaw, o) => {
        const s = o.s || 1,
          y0 = gy(x, z) - 0.01,
          F = yawF(yaw),
          tg = o.tags || {},
          opt = (part, extra) => Object.assign({ res: 0.025 }, extra || {}, tg[part] ? { tag: tg[part], whole: true } : {}),
          P = l => [x + (F[0][0] * l[0] + F[2][0] * l[2]) * s, y0 + l[1] * s, z + (F[0][2] * l[0] + F[2][2] * l[2]) * s],
          shell = o.shell || CREAMM,
          paint = o.paint || PAINTM;
        for (const sd of [-1, 1]) {
          const leg = sd < 0 ? 'legL' : 'legR';
          S.tube([P([sd * 0.075, 0.34, 0]), P([sd * 0.075, 0.06, 0])], 0.034 * s, 0.03 * s, STEELM, opt(leg));
          S.ball(P([sd * 0.075, 0.2, 0.0]), 0.042 * s, paint, opt(leg));
          S.box(P([sd * 0.075, 0.035, 0.03]), [0.045 * s, 0.035 * s, 0.075 * s], paint, opt(leg, { ax: F, rd: 0.015 * s }));
        }
        S.box(P([0, 0.36, 0]), [0.12 * s, 0.04 * s, 0.075 * s], STEELM, opt('body', { ax: F, rd: 0.02 * s }));
        S.box(P([0, 0.52, 0]), [0.145 * s, 0.135 * s, 0.105 * s], shell, opt('body', { ax: F, rd: 0.05 * s }));
        S.box(P([0, 0.53, 0.1]), [0.085 * s, 0.06 * s, 0.015 * s], paint, opt('body', { ax: F, rd: 0.01 * s }));
        S.box(P([0, 0.54, -0.125]), [0.095 * s, 0.095 * s, 0.035 * s], BRASSM, opt('body', { ax: F, rd: 0.015 * s }));
        S.convex(P([0, 0.66, -0.13]), [{ n: [0, 1, 0], d: 0.012 * s }, { n: [0, -1, 0], d: 0.012 * s }, { n: F[0], d: 0.1 * s }, { n: F[0].map(v => -v), d: 0.1 * s }, { n: F[2], d: 0.06 * s }, { n: F[2].map(v => -v), d: 0.06 * s }], { r: [41, 42, 43] }, opt('body'));
        S.tube([P([0, 0.64, 0]), P([0, 0.7, 0])], 0.03 * s, 0.03 * s, STEELM, opt('body'));
        S.ball(P([0, 0.77, 0]), [0.12 * s, 0.095 * s, 0.105 * s], shell, opt('body', { ax: F }));
        S.box(P([0, 0.78, 0.088]), [0.085 * s, 0.03 * s, 0.025 * s], VISOR, opt('body', { ax: F, rd: 0.012 * s }));
        S.lathe(P([-0.135, 0.77, 0]), 0.27 * s, 0.032 * s, BRASSM, opt('body', { ax: [[0, -1, 0], F[0], F[2]] }));
        S.tube([P([0.05, 0.85, 0]), P([0.07, 0.97, 0])], 0.008 * s, 0.006 * s, STEELM, opt('body'));
        for (const sd of [-1, 1]) {
          const arm = sd < 0 ? 'armL' : 'armR',
            hand = (o.hands && o.hands[sd < 0 ? 0 : 1]) || [sd * 0.2, 0.36, 0.03];
          S.ball(P([sd * 0.17, 0.6, 0]), 0.048 * s, paint, opt(arm));
          S.tube([P([sd * 0.17, 0.6, 0]), P(hand)], 0.03 * s, 0.026 * s, STEELM, opt(arm));
          S.ball(P(hand), 0.036 * s, BRASSM, opt(arm));
        }
        return { P, s, F };
      };
      const WALK_R = 1.25,
        walker = robot(PLANTER[0] + WALK_R, PLANTER[1], 0, { tags: { body: 'walker', legL: 'wlegL', legR: 'wlegR', armL: 'warmL', armR: 'warmR' } }),
        gardener = robot(BED[0], BED[1] - 0.55, 0, { hands: [[-0.2, 0.36, 0.03], [0.2, 0.5, 0.28]], tags: { armR: 'garm' }, paint: PATINAM }),
        tanker = robot(3.05, -3.05, -2.2, { hands: [[-0.2, 0.36, 0.03], [0.17, 0.7, 0.24]], paint: { r: [41, 42, 43] } }),
        carrier = robot(3.0, -0.95, -Math.PI / 2 + 0.25, { hands: [[-0.12, 0.5, 0.22], [0.12, 0.5, 0.22]], s: 0.9 });
      busy.push([PLANTER[0] + WALK_R, PLANTER[1], 0.3], [BED[0], BED[1] - 0.55, 0.3], [3.05, -3.05, 0.3], [3.0, -0.95, 0.3]);
      // the gardener's watering can, and the crate in the carrier's hands
      {
        const P = gardener.P,
          o = { tag: 'garm', whole: true, res: 0.022 };
        S.box(P([0.2, 0.47, 0.34]), [0.06, 0.06, 0.08], BRASSM, Object.assign({ rd: 0.015 }, o));
        S.tube([P([0.2, 0.47, 0.4]), P([0.2, 0.42, 0.52])], 0.012, 0.009, BRASSM, o);
        const held = carrier.P([0, 0.5, 0.2]);
        crate(held[0], held[2], held[1] - 0.06, 0.1, -Math.PI / 2 + 0.25);
      }
      // the drone that circles the yard, a parcel slung under it
      const DRONE_C = [0.3, 0.6],
        DRONE_R = 2.2,
        DY = 3.05,
        D0 = [DRONE_C[0] + DRONE_R, DY, DRONE_C[1]];
      {
        const o = { tag: 'drone', whole: true, res: 0.025 };
        S.ball(D0, [0.15, 0.065, 0.15], CREAMM, o);
        S.box(add(D0, [0, 0, 0.12]), [0.06, 0.025, 0.03], VISOR, Object.assign({ rd: 0.01 }, o));
        for (const [sx, sz] of [[1, 1], [1, -1], [-1, 1], [-1, -1]]) {
          const tip = add(D0, [sx * 0.2, 0.02, sz * 0.2]);
          S.tube([D0, tip], 0.018, 0.016, STEELM, o);
          S.lathe(add(tip, [0, -0.04, 0]), 0.07, 0.03, PAINTM, o);
        }
        S.tube([add(D0, [0, -0.06, 0]), add(D0, [0, -0.32, 0])], 0.005, 0.005, { r: [12, 16] }, o);
        S.box(add(D0, [0, -0.4, 0]), [0.08, 0.08, 0.08], { r: BARK, s: BARK_SUN }, Object.assign({ rd: 0.008 }, o));
        S.box(add(D0, [0, -0.4, 0]), [0.083, 0.012, 0.083], PAINTM, o);
      }

      S.bake();

      // ---------------- drawn by hand on the parts that move
      rig.own('arm0l', () => {
        const wr = ARMS[0].parts.wr;
        B.iso(wr[0], wr[1] - 0.19, wr[2], 0.05, B.P[40], 0.7, { em: true, nd: true, k: 1, ph: 0, sp: 9 });
        B.iso(wr[0], wr[1] - 0.18, wr[2], 0.022, B.P[35], 3, { em: true });
      });
      rig.own('walker', () => {
        const p = walker.P([0.07, 0.98, 0]);
        B.iso(p[0], p[1], p[2], 0.026, B.P[38], 3, { em: true, k: 4, ph: 0, sp: 3 });
        const c = walker.P([0, 0.53, 0.118]);
        B.iso(c[0], c[1], c[2], 0.02, B.P[30], 3, { em: true });
      });
      rig.own('island', () => {
        for (const r of [gardener, tanker, carrier]) {
          const p = r.P([0.07, 0.98, 0]);
          B.iso(p[0], p[1], p[2], 0.024, B.P[38], 3, { em: true, k: 4, ph: B.rr(0, 6), sp: 2.5 });
        }
        // water from the can into the bed
        const sp = gardener.P([0.2, 0.41, 0.54]);
        for (let i = 0; i < 40; i++) B.iso(sp[0] + B.rr(-0.02, 0.02), sp[1], sp[2] + B.rr(-0.02, 0.02), 0.012, B.P[B.pick([44, 45, 31])], 3, { em: true, k: 2, ph: B.R(), sp: 0.6, rg: 0.12, ex: 0.4 });
      });
      rig.own('drone', () => {
        for (const [sx, sz] of [[1, 1], [1, -1], [-1, 1], [-1, -1]]) {
          const tip = add(D0, [sx * 0.2, 0.04, sz * 0.2]);
          B.disc(tip[0], tip[1], tip[2], B.UP, 0.1, 0.006, B.P[19], 0.45, { k: 1, ph: B.rr(0, 6), sp: 12 });
        }
        B.iso(D0[0], D0[1] + 0.07, D0[2], 0.025, B.P[38], 3, { em: true, k: 4, ph: 0, sp: 4 });
        B.iso(D0[0], D0[1] - 0.07, D0[2], 0.04, B.P[40], 0.6, { em: true, nd: true });
      });

      // ---------------- the flag, a cloth that flies in a wind that comes round every turn
      const FLAGP = poleTop[2],
        bobY = t => 0.12 * Math.sin((TAU * t) / L);
      const flag = K.cloth(B, {
        at: [FLAGP[0] - 0.03, FLAGP[1] - 0.02, FLAGP[2]],
        u: [-0.95, 0, 0.12],
        v: [0, -0.58, 0],
        nu: 16,
        nv: 10,
        pins: i => i === 0,
        pinAt: (i, j, p0, t) => [p0[0], p0[1] + bobY(t), p0[2]],
        wind: (x, y, z, t) => {
          const w = (TAU * t) / L;
          return [-2.6 * (1 + 0.35 * Math.sin(2 * w + x * 0.6)), 0.3 * Math.sin(3 * w), 0.5 + 0.4 * Math.sin(w + 1)];
        },
        damp: 1.4,
        sun: S.sun,
        pattern: (u, v) => {
          const d = Math.hypot((u - 0.42) * 1.6, v - 0.5);
          if (v < 0.1 || v > 0.9) return [22, 23, 24, 25];
          if (d > 0.17 && d < 0.27) return [32, 33, 34, 35];
          return [36, 37, 38, 39];
        }
      });

      // ---------------- the sky: a few stars, soft lights, clouds below, and birds wheeling round
      FI.backdrop(B, {
        stars: 70,
        starCols: [3, 35, 31],
        bokeh: 60,
        bokehCols: [1, 2, 2, 3],
        clouds: [
          { p: [-7.5, -4.8, 3.5], r: [1.8, 0.4, 1.0], n: 70, cols: [1, 2, 3, 46], a: 0.2 },
          { p: [7.8, -5.8, -2.5], r: [2.0, 0.45, 1.1], n: 80, cols: [1, 2, 3, 46], a: 0.2 },
          { p: [2.5, -7.4, 7.5], r: [2.2, 0.5, 1.2], n: 80, cols: [1, 2, 3, 46], a: 0.2 },
          { p: [-3.0, -7.0, -7.5], r: [2.2, 0.45, 1.2], n: 80, cols: [1, 2, 3, 46], a: 0.2 }
        ]
      });
      for (let b = 0; b < 6; b++) {
        const a = (b / 6) * TAU + B.rr(-0.3, 0.3),
          r = B.rr(7.4, 8.8),
          y = B.rr(3.0, 5.5),
          x = Math.cos(a) * r,
          z = Math.sin(a) * r,
          fw = [-Math.sin(a), 0, Math.cos(a)],
          side = [Math.cos(a), 0, Math.sin(a)],
          fly = { nd: true, k: 5, ph: 0, sp: -TAU / L };
        for (const sg of [-1, 1])
          B.stick(x + side[0] * sg * 0.1, y + 0.03, z + side[2] * sg * 0.1, B.norm([side[0] * sg, 0.35, side[2] * sg]), 0.11, 0.022, B.P[12], 3, fly);
        B.stick(x, y, z, fw, 0.06, 0.03, B.P[12], 3, fly);
      }

      const W = B.finish({
        cam: { target: [0, -0.4, 0], dist: 22, pitch: 0.22, yaw: 0.45 },
        detail: 19.4,
        dither: 0.3,
        radius: 10,
        palName: 'Factory',
        fog: { c: 0, start: 0.8, max: 0.2 },
        outline: { c: 12, edge: 0.7 },
        ao: { k: 0.4, range: 0.5 }
      });
      FI.loopable(W, L);
      // the flag writes depth like any solid, so no outline of what is behind it is drawn across it
      for (let i = flag.first; i < flag.first + flag.count; i++) if (W.data[i * 16 + 11] & 16) W.data[i * 16 + 11] -= 16;
      const st = K.stage(W);
      rig.bind(st);
      // every motion comes round in L seconds: the island bobs, the wheel turns once, rotors and fans turn whole times,
      // the belt moves its things one full length, the arms work, the walker goes round once, the drone circles once
      const Ry = a => M.rot([0, 1, 0], a),
        Rx = a => M.rot([1, 0, 0], a),
        I = M.id();
      st.add({
        update(dt, t) {
          const w = (TAU * t) / L,
            bob = bobY(t),
            lift = p => [p[0], p[1] + bob, p[2]];
          rig.set('island', I, [0, 0, 0], [0, bob, 0]);
          rig.set('rotor', M.rot(F1d, 2 * w), HUB1, lift(HUB1));
          rig.set('rotor2', M.rot(F2d, 3 * w + 0.7), HUB2, lift(HUB2));
          rig.set('wheel', M.rot(WAX, -w), WC, lift(WC));
          rig.set('prop', Ry(4 * w), PROP, lift(PROP));
          for (const f of FANS) rig.set(f.tag, M.rot(f.T, 6 * w), f.hub, lift(f.hub));
          rig.set('press', I, PRESS, lift(add(PRESS, [0, -0.09 * (0.5 - 0.5 * Math.cos(4 * w)), 0])));
          for (const it of ITEMS) {
            const x = -2.2 + ((((it.x + 2.2 + (4.4 * t) / L) % 4.4) + 4.4) % 4.4);
            rig.set(it.tag, I, [it.x, YB, CZ], lift([x, YB, CZ]));
          }
          const [a0, a1] = ARMS.map(a => a.parts);
          rig.set(a0.base, Ry(0.1 * Math.sin(4 * w)), a0.b, lift(a0.b));
          rig.child(a0.up, a0.base, M.rot(a0.axis, 0.05 * Math.sin(4 * w + 1)), a0.sh);
          rig.child(a0.lo, a0.up, M.rot(a0.axis, 0.08 * Math.sin(4 * w + 2)), a0.el);
          rig.set(a1.base, Ry(0.4 * Math.sin(2 * w)), a1.b, lift(a1.b));
          rig.child(a1.up, a1.base, M.rot(a1.axis, 0.12 * Math.sin(2 * w + Math.PI / 2)), a1.sh);
          rig.child(a1.lo, a1.up, M.rot(a1.axis, 0.22 * Math.sin(2 * w)), a1.el);
          const step = 0.42 * Math.sin(16 * w),
            hop = 0.012 * (0.5 - 0.5 * Math.cos(32 * w));
          rig.set('walker', Ry(-w), [PLANTER[0], 0, PLANTER[1]], [PLANTER[0], bob + hop, PLANTER[1]]);
          rig.child('wlegL', 'walker', Rx(step), walker.P([-0.075, 0.34, 0]));
          rig.child('wlegR', 'walker', Rx(-step), walker.P([0.075, 0.34, 0]));
          rig.child('warmL', 'walker', Rx(-0.6 * step), walker.P([-0.17, 0.6, 0]));
          rig.child('warmR', 'walker', Rx(0.6 * step), walker.P([0.17, 0.6, 0]));
          rig.set('garm', Rx(0.16 * Math.sin(2 * w)), gardener.P([0.17, 0.6, 0]), lift(gardener.P([0.17, 0.6, 0])));
          rig.set('drone', Ry(-w), [DRONE_C[0], 0, DRONE_C[1]], [DRONE_C[0], bob + 0.05 * Math.sin(4 * w), DRONE_C[1]]);
          rig.apply();
        }
      });
      st.add(flag);
      return W;
    }
  };
};
