/* A 1994 drive-in inside a snow globe at midnight, with a missile circus round the glass.
   Inside the globe: a drive-in screen showing a jet-pack picture, two parked cars (a teal minivan and a pink sedan) with speaker posts,
   the projection booth and its beam, a CRT set and a stack of rental tapes, plain crates, a record player with a frog riding the
   record, a blossoming broadleaf tree with a pocket watch swinging from a branch, a striped lighthouse whose beam sweeps round, a radio
   dish that follows the flyer and sends out pulses, and the crew: three robot arms of shadow, each in a bowler hat and a VR headset.
   Petals and snow fall inside the glass. Outside: a jet-pack flyer dodging round the globe with a swarm of missiles on corkscrew smoke
   trails behind it, flak bursting where they miss, a red balloon, a neon grid to the horizon, stars, and the Regents crown drawn as a
   constellation. Underneath: a hanging garden of pots, trailing vines and wisteria.
   It only calls the ink-studio toolkit through the kit it is handed, and the template's shared helpers; no toolkit code is copied. */
const FI = require('./floating-island.cjs');

const L = 8; // seconds in one loop: every motion comes round in this time

// 48 colours, Trapper Keeper: each ramp shifts hue as it goes from dark to light
const PAL = [
  0x0b0820, // 0      the night itself
  0x1a1238, 0x2a1a55, 0x46307a, // 1-3    night sky, indigo to violet
  0x07050d, 0x14102a, 0x261a42, // 4-6    shadow, black with violet in it
  0x3a3f7a, 0x5f6fb0, 0x8fa6dc, 0xc4d8f0, 0xf2f6ff, // 7-11   snow, violet shade to white
  0x3a0838, 0x6e0f5e, 0xb0157f, 0xe8359f, 0xff79c6, 0xffc1e6, // 12-17  hot pink, plum to blush
  0x2b0d5c, 0x5320a8, 0x8a4ae0, 0xc39bff, // 18-21  violet to lilac
  0x062a4a, 0x0a5a7a, 0x10a0b8, 0x3fe0e0, 0xb0fff4, // 22-26  turquoise, navy to mint
  0x0e2e1e, 0x1c5a2a, 0x3c9a2c, 0x8ad41e, 0xd8f53c, // 27-31  lime, pine to yellow-green
  0x4a1a0a, 0x8a3410, 0xd8601a, 0xff9a1e, 0xffd23a, 0xfff3a0, // 32-37  sunshine, brown through orange to cream
  0x3a0612, 0x7a0c1e, 0xd01c2c, 0xff5a4a, // 38-41  balloon red, maroon to coral
  0x2a140e, 0x4e2a18, 0x7e4a26, 0xb07a3e, // 42-45  crate wood
  0x7c7c9c, 0xc8c8e0 // 46-47  chrome
];

const SNOW = [7, 8, 9, 10],
  SNOW_MOON = [8, 9, 10, 11],
  PINK = [12, 13, 14, 15, 16],
  PINK_MOON = [14, 15, 16, 17],
  VIOLET = [18, 19, 20, 21],
  CYAN = [22, 23, 24, 25],
  CYAN_MOON = [23, 24, 25, 26],
  LIME = [27, 28, 29, 30],
  LIME_MOON = [28, 29, 30, 31],
  SUN = [32, 33, 34, 35, 36],
  GOLD = [33, 34, 35, 36, 37],
  RED = [38, 39, 40, 41],
  WOOD = [42, 43, 44, 45],
  CHROME = [7, 46, 47, 11],
  RAINBOW = [25, 36, 30, 20, 16];

module.exports = kit => {
  const { makeBuilder, makeSculpt, KIT: K } = kit;
  return {
    id: 'missile-circus',
    name: 'Drive-in snow globe',
    seed: 31,
    loop: L,
    build(seed) {
      const B = makeBuilder(seed, PAL),
        S = K.sculpt(makeSculpt(B)),
        rig = K.rig(B, S),
        M = K.M,
        { clamp, TAU } = FI;
      const CAM = { target: [0, 1.7, 0], dist: 22, pitch: 0.22, yaw: 0.45 };
      S.sun = B.norm([0.45, 0.8, 0.4]); // the moon
      S.amb = 0.22;
      S.sky = 0.3;
      S.sunK = 0.55;
      S.res = 0.08;
      S.view = B.norm([Math.sin(CAM.yaw) * Math.cos(CAM.pitch), Math.sin(CAM.pitch), Math.cos(CAM.yaw) * Math.cos(CAM.pitch)]);

      // ---------------- small helpers
      const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]],
        sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]],
        mul = (a, s) => [a[0] * s, a[1] * s, a[2] * s],
        mad = (a, b, s) => [a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s],
        dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2],
        cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]],
        nrm = B.norm,
        UP = [0, 1, 0],
        // a frame whose y runs along dir (rows: where local x, y and z go)
        frameY = dir => {
          const V = nrm(dir),
            U = nrm(cross(Math.abs(V[1]) < 0.9 ? UP : [1, 0, 0], V));
          return [U, V, cross(U, V)];
        },
        // which way is azimuth a (0 is +z, a quarter turn is +x), and a frame turned to face it
        az = a => [Math.sin(a), 0, Math.cos(a)],
        yawAx = a => [[Math.cos(a), 0, -Math.sin(a)], UP, az(a)],
        hash = (i, j) => {
          const v = Math.sin(i * 127.1 + j * 311.7) * 43758.5453;
          return v - Math.floor(v);
        },
        own = (tag, fn) => rig.own(tag, fn);
      // rainbow leopard rosettes: a ring of shadow round a bright middle, on a ground of `ramp`; s is the size of a cell
      const spots = (x, y, z, t, ramp, s) => {
        const i = Math.floor(x / s),
          j = Math.floor(y / s),
          k = Math.floor(z / s),
          cx = (i + 0.3 + 0.4 * hash(i + 0.13 * k, j)) * s,
          cy = (j + 0.3 + 0.4 * hash(j + 0.17 * i, k + 3)) * s,
          cz = (k + 0.3 + 0.4 * hash(k + 0.11 * j, i + 7)) * s,
          d = Math.hypot(x - cx, y - cy, z - cz) / s;
        if (d < 0.2) return RAINBOW[Math.floor(hash(i * 3 + k, j * 5) * RAINBOW.length)];
        if (d < 0.34 && B.n3((x * 7) / s, (y * 7) / s, (z * 7) / s) > 0.28) return 4;
        return S.pick(ramp, t);
      };

      // ---------------- materials
      const SHADOWM ={ r: [4, 4, 5, 6] },
        JOINTM = { r: [5, 18, 19, 20], s: [18, 19, 20, 21] },
        HATM = { r: [4, 5, 6, 18], s: [5, 6, 18, 19] },
        PINKM = { r: PINK, s: PINK_MOON, g: [15, 16, 17], gloss: { c: 17, at: 0.94, c2: 16, at2: 0.9 } },
        CYANM = { r: CYAN, s: CYAN_MOON, g: [24, 25, 26], gloss: { c: 26, at: 0.94, c2: 25, at2: 0.9 } },
        VIOLETM = { r: VIOLET, s: [19, 20, 21], g: [20, 21, 17] },
        STEELM = { r: [5, 18, 19, 46], s: [18, 19, 46, 47] },
        WOODM = { r: WOOD, s: [43, 44, 45], g: [44, 45, 37], mod: (x, y, z) => 0.1 * (B.n3(x * 9, y * 2.5, z * 9) - 0.5) },
        GOLDM = { r: SUN, s: GOLD, gloss: { c: 37, at: 0.92, c2: 36, at2: 0.86 } },
        CHROMEM = { r: CHROME, s: [46, 47, 11], gloss: { c: 11, at: 0.9, c2: 47, at2: 0.84 } },
        REDM = { r: RED, s: [39, 40, 41, 17], gloss: { c: 17, at: 0.93, c2: 41, at2: 0.88 } },
        LIMEM = { r: LIME, s: LIME_MOON, g: [30, 31, 37] },
        TIRE = { r: [4, 5, 6] },
        WINDOW = { r: [22, 23, 3], g: [23, 24, 25] },
        GLOWGOLD = { r: [35, 36, 37], em: true, v: 0.7 },
        GLOWCYAN = { r: [24, 25, 26], em: true, v: 0.7 },
        GLOWRED = { r: [40, 41, 17], em: true, v: 0.5 },
        BEAT = { em: true, k: 4, ph: 0, sp: (4 * TAU) / L }, // the record's beat: four times a loop
        GLOWPINK = { r: [15, 16, 17], em: true, v: 0.6, fl: BEAT },
        GLASSM = K.look.glass([22, 23, 24, 26], { a: 0.06 });

      // ---------------- the snow globe: a plinth banded in rainbow leopard, a snowy floor, a dome of glass
      const GC = [0, 1.4, 0],
        GR = 5.19, // the glass sphere: it meets the floor (y 0) at radius 5.0
        BASE_Y = -1.4;
      const PLINTH = {
        r: PINK,
        s: PINK_MOON,
        tex: (x, y, z, ny, t) => {
          if (ny < -0.5) return S.pick(VIOLET, t * 0.8);
          if (y > -0.24) return S.pick(GOLD, t + 0.15); // a gilt lip
          if (y < -1.16) return S.pick(VIOLET, t); // the foot
          return spots(x, y, z, t, [13, 14, 15, 16], 0.5);
        },
        top: { min: 0.5, r: SNOW, s: SNOW_MOON, g: [9, 10, 11] }
      };
      const plinthR = t => (t < 0.1 ? 5.55 : t < 0.2 ? 5.55 - 3.2 * (t - 0.1) : t < 0.86 ? 5.23 : t < 0.93 ? 5.33 : 5.33 - 4 * (t - 0.93));
      const G = Object.assign(S.grp(0.3), { res: 0.075 });
      S.lathe([0, BASE_Y, 0], 1.4, plinthR, PLINTH, G);
      // drifts of snow, melted into the floor
      for (const [x, z, r] of [
        [3.9, 0.4, 0.6],
        [-4.0, 2.4, 0.5],
        [-1.6, -1.8, 0.55],
        [2.1, -3.6, 0.5],
        [-1.6, -4.3, 0.45],
        [4.15, -1.7, 0.42],
        [0.3, 4.3, 0.45]
      ])
        S.ball([x, -0.24 + r * 0.3, z], [r, r * 0.55, r], PLINTH, G);
      // the glass: one skin of a sphere, cut off at the floor
      S.solid(
        GC,
        GR + 0.2,
        (x, y, z) => Math.max(Math.hypot(x, y, z) - GR, -(y + GC[1]) - 0.05),
        (rs, f) => {
          const n = Math.ceil((4 * Math.PI * GR * GR) / (rs * rs * 0.87));
          for (let k = 0; k < n; k++) {
            const yy = 1 - (2 * (k + 0.5)) / n,
              rr = Math.sqrt(1 - yy * yy),
              a = k * 2.399963;
            if (yy * GR + GC[1] < 0.02) continue;
            f(Math.cos(a) * rr * GR, yy * GR, Math.sin(a) * rr * GR);
          }
        },
        GLASSM,
        { res: 0.13, ghost: true }
      );

      // ---------------- the drive-in screen, showing a jet-pack hero over a striped sun
      const SCR = [-0.3, 2.15, -3.25],
        SW = 1.7,
        SH = 0.95,
        syaw = 0.2,
        sf = az(syaw),
        sr = [Math.cos(syaw), 0, -Math.sin(syaw)],
        SAX = yawAx(syaw);
      const screenTex = (x, y, z, ny, t, nx, nz) => {
        if (nx * sf[0] + nz * sf[2] < 0.7) return undefined;
        const X = (x - SCR[0]) * sr[0] + (z - SCR[2]) * sr[2],
          Y = y - SCR[1];
        if (Math.abs(X) > SW - 0.07 || Math.abs(Y) > SH - 0.07) return 4;
        // the hero, rising to the right on a flame
        const hx = X + 0.78,
          hy = Y - 0.3,
          u = hx * 0.6 + hy * 0.8,
          v = -hx * 0.8 + hy * 0.6;
        if (Math.hypot(u - 0.22, v) < 0.07) return 4;
        if (Math.abs(v) < 0.06 && u > -0.2 && u < 0.16) return 4;
        if (Math.abs(v + 0.08) < 0.04 && u > -0.14 && u < 0.1) return 46;
        if (u < -0.2 && u > -0.55 && Math.abs(v + 0.06) < 0.025 + 0.12 * (-0.2 - u)) return u > -0.32 ? 37 : 36;
        // the striped sun on the horizon, the sky in bands
        const H0 = -0.22,
          sx = X - 0.62,
          sy = Y - H0;
        if (Y > H0 && Math.hypot(sx, sy) < 0.56) {
          if (sy < 0.32 && ((sy + 0.02) / 0.08) % 1 < 0.42 - sy) return 14;
          return sy > 0.4 ? 37 : sy > 0.24 ? 36 : sy > 0.1 ? 35 : 15;
        }
        if (Y > H0) return Y > 0.5 ? 19 : Y > 0.12 ? 13 : 14;
        // the grid running away to the horizon
        const depth = H0 - Y + 0.03,
          lane = X / depth,
          far = 1 / depth;
        if (Math.abs((((lane * 0.5) % 1) + 1) % 1 - 0.5) > 0.42) return 25;
        if ((far * 0.6) % 1 < 0.12) return 25;
        return 18;
      };
      S.box(SCR, [SW, SH, 0.04], { r: [5, 6], em: true, v: 0.8, tex: screenTex }, { ax: SAX, res: 0.035 });
      S.box(mad(SCR, sf, -0.1), [SW + 0.08, SH + 0.08, 0.05], { r: [12, 13, 14, 15], s: [13, 14, 15, 16], tex: (x, y, z, ny, t) => spots(x, y, z, t, [12, 13, 14, 15], 0.42) }, { ax: SAX, res: 0.04 });
      // a neon trim along its top, posts and a lattice behind
      S.tube([mad(mad(SCR, sr, -SW - 0.08), UP, SH + 0.12), mad(mad(SCR, sr, SW + 0.08), UP, SH + 0.12)], 0.035, 0.035, GLOWPINK, { res: 0.025 });
      for (const s of [-1.3, 1.3]) {
        const top = mad(mad(SCR, sr, s), sf, -0.17),
          foot = [top[0], -0.05, top[2]];
        S.tube([foot, add(top, [0, SH, 0])], 0.06, 0.05, STEELM, { res: 0.03 });
        S.tube([mad(foot, sf, -0.6), add(top, [0, 0.2, 0])], 0.035, 0.03, STEELM, { res: 0.03 });
      }
      for (const yy of [-0.5, 0.2, 0.75]) S.tube([mad(mad(add(SCR, [0, yy, 0]), sr, -1.3), sf, -0.17), mad(mad(add(SCR, [0, yy, 0]), sr, 1.3), sf, -0.17)], 0.025, 0.025, STEELM, { res: 0.03 });
      S.lights.push({ p: add(mad(SCR, sf, 1.8), [0, -0.9, 0]), r: 5.5, s: 1.0, c: [15, 16] });

      // ---------------- two 1994 cars facing the screen, and their speaker posts
      const car = (x, z, yaw, paint, van) => {
        const F = az(yaw),
          R = [Math.cos(yaw), 0, -Math.sin(yaw)],
          ax = yawAx(yaw),
          P = (a, b, c) => [x + R[0] * a + F[0] * c, b, z + R[2] * a + F[2] * c];
        S.box(P(0, 0.29, 0), [0.33, 0.14, 0.64], paint, { ax, rd: 0.07, res: 0.03 });
        if (van) {
          S.box(P(0, 0.57, -0.04), [0.31, 0.18, 0.55], paint, { ax, rd: 0.08, res: 0.03 });
          S.box(P(0, 0.62, -0.02), [0.318, 0.085, 0.565], WINDOW, { ax, rd: 0.05, res: 0.025 });
          S.box(P(0, 0.76, -0.1), [0.22, 0.015, 0.4], STEELM, { ax, res: 0.025 }); // a roof rack
        } else {
          S.box(P(0, 0.53, -0.1), [0.29, 0.12, 0.33], paint, { ax, rd: 0.07, res: 0.03 });
          S.box(P(0, 0.55, -0.1), [0.298, 0.075, 0.345], WINDOW, { ax, rd: 0.04, res: 0.025 });
        }
        for (const sa of [-1, 1])
          for (const sc of [-0.4, 0.4]) {
            const hub = P(sa * 0.27, 0.15, sc),
              out = mul(R, sa);
            S.lathe(hub, 0.1, 0.14, TIRE, { ax: frameY(out), res: 0.022 });
            S.lathe(mad(hub, out, 0.05), 0.06, 0.07, CHROMEM, { ax: frameY(out), res: 0.02 });
          }
        // lights: red behind (toward the camera), gold in front, a bumper in chrome
        for (const sa of [-1, 1]) {
          S.box(P(sa * 0.23, 0.33, -0.645), [0.07, 0.035, 0.012], GLOWRED, { ax, res: 0.015 });
          S.box(P(sa * 0.23, 0.33, 0.645), [0.06, 0.03, 0.012], GLOWGOLD, { ax, res: 0.015 });
        }
        S.box(P(0, 0.19, -0.66), [0.32, 0.03, 0.02], CHROMEM, { ax, res: 0.018 });
        S.box(P(0, 0.19, 0.66), [0.32, 0.03, 0.02], CHROMEM, { ax, res: 0.018 });
        S.lights.push({ p: P(0, 0.35, -1.0), r: 1.0, s: 0.45, c: [40, 41] });
      };
      car(-1.15, 0.0, Math.PI + 0.05, CYANM, true);
      car(1.0, 0.45, Math.PI - 0.12, PINKM, false);
      for (const [x, z] of [
        [-0.28, 0.2],
        [1.78, 0.55]
      ]) {
        S.tube([[x, -0.05, z], [x, 0.78, z]], 0.025, 0.02, CHROMEM, { res: 0.02 });
        S.box([x, 0.72, z], [0.07, 0.07, 0.05], SHADOWM, { res: 0.02, rd: 0.015 });
        S.box([x, 0.72, z + 0.051], [0.045, 0.045, 0.004], { r: [6, 19] }, { res: 0.015 });
      }

      // ---------------- the projection booth, its beam to the screen
      const BO = [-3.05, 0, 1.5],
        bf = nrm(sub([SCR[0], 0, SCR[2]], BO)),
        byaw = Math.atan2(bf[0], bf[2]),
        bax = yawAx(byaw),
        bR = bax[0],
        BP = (a, b, c) => [BO[0] + bR[0] * a + bf[0] * c, b, BO[2] + bR[2] * a + bf[2] * c];
      S.box(BP(0, 0.5, 0), [0.55, 0.5, 0.5], VIOLETM, { ax: bax, rd: 0.02, res: 0.04 });
      S.box(BP(0, 1.04, 0), [0.64, 0.05, 0.6], PINKM, { ax: bax, res: 0.035 });
      S.box(BP(0, 0.06, 0), [0.57, 0.07, 0.52], PINKM, { ax: bax, res: 0.035 });
      S.box(BP(0.18, 0.72, 0.5), [0.2, 0.12, 0.02], GLOWCYAN, { ax: bax, res: 0.02 });
      S.box(BP(-0.2, 0.42, -0.505), [0.15, 0.3, 0.012], PINKM, { ax: bax, res: 0.02 }); // the door at the back
      S.ball(BP(-0.1, 0.42, -0.53), 0.025, GOLDM, { res: 0.012 });
      const LENS = BP(0.18, 0.72, 0.62);
      S.lathe(BP(0.18, 0.72, 0.45), 0.17, 0.065, CHROMEM, { ax: frameY(bf), res: 0.018 });
      S.lights.push({ p: mad(LENS, bf, 0.3), r: 2.0, s: 0.6, c: [25, 26] });

      // ---------------- the rental corner: a CRT set on a crate with a VCR, and a stack of tapes
      const crate = (x, z, y0, s, yaw) => {
        const c = [x, y0 + s, z];
        S.box(c, [s, s, s], Object.assign({}, WOODM, { mod: (xx, yy) => (((yy - y0) / (s * 0.5)) % 1 < 0.12 ? -0.3 : 0.05 * (B.n3(xx * 9, yy * 2, 1) - 0.5)) }), { ax: yawAx(yaw || 0), res: 0.025, rd: 0.01 });
        return y0 + 2 * s;
      };
      const tvTop = crate(-3.45, 2.75, 0, 0.24, 0.6),
        tvF = az(0.6),
        tvAx = yawAx(0.6),
        TV = [-3.45, tvTop + 0.05 + 0.23, 2.75];
      S.box([TV[0], tvTop + 0.045, TV[2]], [0.25, 0.045, 0.2], SHADOWM, { ax: tvAx, rd: 0.01, res: 0.018 });
      S.box(TV, [0.27, 0.23, 0.24], { r: [5, 6, 46], s: [6, 46, 47] }, { ax: tvAx, rd: 0.05, res: 0.025 });
      S.box(mad(TV, tvF, 0.235), [0.2, 0.16, 0.012], GLOWCYAN, { ax: tvAx, res: 0.015 });
      for (const s of [-1, 1]) S.tube([add(TV, [0, 0.22, 0]), add(TV, [s * 0.2, 0.55, -0.05])], 0.008, 0.006, CHROMEM, { res: 0.012 });
      S.lights.push({ p: mad(TV, tvF, 0.5), r: 1.6, s: 0.6, c: [24, 25] });
      const tapeTop = crate(-2.75, 3.1, 0, 0.2, 0.2);
      for (let k = 0; k < 5; k++) {
        const ax = yawAx(0.45 + 0.25 * (hash(k, 2) - 0.5)),
          c = [-2.75 + 0.02 * (hash(k, 4) - 0.5), tapeTop + 0.022 + k * 0.044, 3.1];
        S.box(c, [0.1, 0.02, 0.18], SHADOWM, { ax, res: 0.012 });
        S.box(mad(c, ax[0], 0.101), [0.002, 0.012, 0.15], { r: [RAINBOW[k]], em: true, v: 0.5 }, { ax, res: 0.01 });
      }

      // ---------------- plain crates, stacked by the lighthouse
      crate(1.45, 3.45, 0, 0.26, 0.2);
      const ct = crate(2.05, 3.15, 0, 0.24, -0.15);
      crate(2.0, 3.12, ct, 0.17, 0.35);
      crate(1.1, 3.95, 0, 0.18, 0.6);

      // ---------------- the record player on its crate (its platter and the frog riding it move, below)
      const RPC = [-1.6, 0, 3.15],
        rpYaw = 0.3,
        rpAx = yawAx(rpYaw),
        rpTop = crate(RPC[0], RPC[2], 0, 0.36, rpYaw),
        RPP = (a, b, c) => [RPC[0] + rpAx[0][0] * a + rpAx[2][0] * c, rpTop + b, RPC[2] + rpAx[0][2] * a + rpAx[2][2] * c];
      S.box(RPP(0, 0.08, 0), [0.46, 0.08, 0.37], { r: [13, 14, 15], s: [14, 15, 16], tex: (x, y, z, ny, t) => spots(x, y, z, t, [14, 15, 16], 0.2) }, { ax: rpAx, rd: 0.03, res: 0.02 });
      const PC = RPP(-0.08, 0.165, 0);
      // the tone arm, resting on the record
      S.lathe(RPP(0.33, 0.16, -0.25), 0.07, 0.04, CHROMEM, { res: 0.012 });
      S.tube([RPP(0.33, 0.22, -0.25), RPP(0.3, 0.22, 0.05), RPP(0.12, 0.2, 0.18)], 0.012, 0.01, CHROMEM, { res: 0.012 });
      S.box(RPP(0.33, 0.22, -0.33), [0.03, 0.03, 0.04], CHROMEM, { ax: rpAx, res: 0.012 });
      for (const k of [0, 1]) S.ball(RPP(0.36 - k * 0.08, 0.17, 0.3), 0.025, { r: [35, 36, 37] }, { res: 0.01 });

      // ---------------- the lighthouse, striped pink and white (its beam turns, below)
      const LH = [2.75, 0, 2.45],
        LHH = 2.3,
        LHC = [LH[0], LHH + 0.2, LH[2]];
      S.lathe([LH[0], -0.05, LH[2]], LHH + 0.05, t => 0.34 - 0.13 * t, { r: PINK, s: PINK_MOON, tex: (x, y, z, ny, t) => (Math.floor(y / 0.38) % 2 ? S.pick([9, 10, 11], t) : S.pick([13, 14, 15, 16], t)) }, { res: 0.035 });
      S.lathe([LH[0], LHH - 0.02, LH[2]], 0.05, 0.32, VIOLETM, { res: 0.025 });
      S.torus([LH[0], LHH + 0.18, LH[2]], 0.3, 0.015, CHROMEM, { res: 0.015 });
      for (let k = 0; k < 8; k++) {
        const a = (k / 8) * TAU;
        S.tube([[LH[0] + Math.cos(a) * 0.3, LHH, LH[2] + Math.sin(a) * 0.3], [LH[0] + Math.cos(a) * 0.3, LHH + 0.18, LH[2] + Math.sin(a) * 0.3]], 0.01, 0.01, CHROMEM, { res: 0.012 });
      }
      S.lathe([LH[0], LHH + 0.03, LH[2]], 0.34, 0.17, Object.assign({}, GLOWGOLD, { fl: BEAT }), { res: 0.025 });
      S.lathe([LH[0], LHH + 0.37, LH[2]], 0.3, t => 0.24 * (1 - t) + 0.01, REDM, { res: 0.022 });
      S.ball([LH[0], LHH + 0.69, LH[2]], 0.04, GOLDM, { res: 0.012 });
      S.lights.push({ p: LHC, r: 2.8, s: 0.9, c: [36, 37] });

      // ---------------- the radio dish's tower (the dish turns, below)
      const DS = [3.05, 0, -1.25],
        DTOP = 1.3,
        DP = [DS[0], 2.1, DS[2]];
      for (const sx of [-1, 1])
        for (const sz of [-1, 1]) S.tube([[DS[0] + sx * 0.5, -0.05, DS[2] + sz * 0.5], [DS[0] + sx * 0.15, DTOP, DS[2] + sz * 0.15]], 0.035, 0.028, STEELM, { res: 0.025 });
      for (const [h, q] of [
        [0.35, 0.4],
        [0.85, 0.27]
      ])
        for (let k = 0; k < 4; k++) {
          const a = (k / 4) * TAU + Math.PI / 4,
            b = a + TAU / 4,
            r = q * Math.SQRT2;
          S.tube([[DS[0] + Math.cos(a) * r, h, DS[2] + Math.sin(a) * r], [DS[0] + Math.cos(b) * r, h, DS[2] + Math.sin(b) * r]], 0.018, 0.018, STEELM, { res: 0.02 });
        }
      S.lathe([DS[0], DTOP - 0.04, DS[2]], 0.06, 0.24, STEELM, { res: 0.025 });

      // ---------------- the broadleaf tree, in blossom, and the branch the pocket watch hangs from
      const TR = [-3.0, 0, -1.5];
      FI.clumpyTree(B, S, 0.16, TR[0], -0.05, TR[2], {
        h: 2.5,
        r: 0.15,
        spread: 1.1,
        nb: 7,
        lean: [0.05, 0.08],
        roots: 4,
        bark: WOODM,
        leaf: { r: LIME, s: LIME_MOON, g: [29, 30, 31], tex: (x, y, z) => (B.n3(x * 4.1, y * 4.1, z * 4.1) > 0.72 ? B.pick([15, 16, 17]) : undefined) },
        leaves: 6000,
        ls: 0.4,
        res: 0.05
      });
      const HANG = [-2.15, 1.9, -0.85];
      S.tube([[TR[0] + 0.04, 1.4, TR[2] + 0.03], [-2.6, 1.75, -1.15], HANG], t => 0.055 * (1 - t) + 0.025, 0, WOODM, { res: 0.025 });
      S.tube([HANG, [-2.0, 2.05, -0.75]], 0.022, 0.015, WOODM, { res: 0.02 });

      // ---------------- pedestals for the crew
      const CREW = [
        { id: 'a', b: [-0.45, 0, 3.5], yaw: Math.atan2(-1.15, -0.4), e: [1.0, 0.0, -0.6] }, // the DJ, over the record player
        { id: 'b', b: [0.95, 0, -1.85], yaw: 0, e: [1.25, 0.7, 0.45] }, // the lookout, following the flyer
        { id: 'c', b: [0.7, 0, 2.9], yaw: Math.atan2(-0.9, -6.0), e: [1.2, 0.2, 0.05] } // the one watching the film
      ];
      for (const a of CREW) S.lathe([a.b[0], -0.05, a.b[2]], 0.1, [0.27, 0.24], SHADOWM, { res: 0.025 });

      S.bake();

      // ---------------- drawn by hand, still: the projector beam, the set's static, the screen's grain, petals and snow in the globe
      {
        const corners = [[0, 0]];
        for (const u of [-0.92, 0.92]) for (const v of [-0.88, 0.88]) corners.push([u, v]);
        for (const [u, v] of corners) {
          const d = sub(add(add(mad(SCR, sr, u * SW), [0, v * SH, 0]), mul(sf, 0.08)), LENS),
            len = Math.hypot(...d),
            dir = mul(d, 1 / len),
            n = 30;
          for (let k = 1; k < n; k++) {
            const s = k / n,
              p = mad(LENS, dir, len * s);
            B.stick(p[0], p[1], p[2], dir, (len / n) * 0.6, 0.012 + 0.03 * s, B.P[s < 0.3 ? 26 : 25], 0.07, { em: true, nd: true, k: 7, ph: 0, sp: (2 * TAU) / L, rg: 0 });
          }
        }
      }
      for (let i = 0; i < 36; i++) {
        const p = add(mad(TV, tvF, 0.25), add(mul(tvAx[0], B.rr(-0.18, 0.18)), [0, B.rr(-0.14, 0.14), 0]));
        B.iso(p[0], p[1], p[2], 0.016, B.P[B.pick([26, 11, 23])], 3, { em: true, k: 1, ph: B.rr(0, 6), sp: B.rr(9, 14) });
      }
      B.iso(...add(TV, [0.18, -0.23, 0]).map((v, i) => (i === 1 ? tvTop + 0.05 : v) + (i === 0 ? tvF[0] * 0.21 : i === 2 ? tvF[2] * 0.21 : 0)), 0.018, B.P[30], 3, { em: true, k: 4, ph: 0, sp: TAU / 2 });
      for (let i = 0; i < 40; i++) {
        const p = add(add(mad(SCR, sr, B.rr(-1.55, 1.55)), [0, B.rr(-0.82, 0.82), 0]), mul(sf, 0.05));
        B.iso(p[0], p[1], p[2], 0.018, B.P[B.pick([11, 37, 17])], 3, { em: true, nd: true, k: 1, ph: B.rr(0, 6), sp: B.rr(10, 16) });
      }
      {
        const domeTop = (x, z) => GC[1] + Math.sqrt(Math.max(0, GR * GR - x * x - z * z)) - 0.3;
        let made = 0;
        for (let tries = 0; made < 440 && tries < 6000; tries++) {
          const a = B.rr(0, TAU),
            q = Math.sqrt(B.R()) * 4.7,
            x = Math.cos(a) * q,
            z = Math.sin(a) * q,
            rg = B.pick([2.5, 3.5, 4.5]),
            y = B.rr(0.2, 0.7) + rg;
          if (y > domeTop(x, z)) continue;
          const fall = { k: 2, ph: B.R(), sp: rg / L, rg, ex: 0 };
          if (made % 2 === 0) B.disc(x, y, z, B.randDir(), 0.055, 0.012, B.P[B.pick([15, 16, 17, 16])], 3, fall);
          else B.iso(x, y, z, 0.026, B.P[B.pick([11, 10, 11])], 3, fall);
          made++;
        }
      }
      // the lighthouse lamp's glow, swelling on the beat
      for (const [s, a] of [
        [0.5, 0.3],
        [0.9, 0.14]
      ])
        B.iso(LHC[0], LHC[1], LHC[2], s, B.P[37], a, { em: true, nd: true, k: 7, ph: 0, sp: (4 * TAU) / L });
      // a few strokes of light on the glass
      for (const [a, e, len] of [
        [CAM.yaw - 0.55, 0.75, 0.9],
        [CAM.yaw - 0.42, 0.62, 0.5],
        [CAM.yaw + 0.5, 0.35, 0.6]
      ]) {
        const d = [Math.sin(a) * Math.cos(e), Math.sin(e), Math.cos(a) * Math.cos(e)],
          p = mad(GC, d, GR + 0.02),
          t = nrm(cross(d, [Math.cos(a), 0, -Math.sin(a)]));
        K.glint(B, p, t, len * 0.5, 26);
      }

      // ---------------- the hanging garden under the plinth
      {
        const POTS = [PINKM, CYANM, VIOLETM, GOLDM],
          FLOWERS = [16, 17, 21, 36, 25, 31],
          sway = () => ({ k: 11, ph: B.rr(0, 6), sp: 1.9, rg: 0.015 }),
          strand = (x, y, z, len, leafy) => {
            const sw = sway(),
              n = Math.max(2, Math.round(len / 0.11)),
              lean = [B.rr(-0.06, 0.06), -1, B.rr(-0.06, 0.06)];
            for (let k = 0; k < n; k++) {
              const p = mad([x, y, z], nrm(lean), (k + 0.5) * 0.11);
              B.stick(p[0], p[1], p[2], nrm(lean), 0.06, 0.016, B.P[B.pick([27, 28, 28, 29])], 3, sw);
              if (leafy && k % 2) B.disc(p[0] + B.rr(-0.04, 0.04), p[1], p[2] + B.rr(-0.04, 0.04), B.randDir(), 0.04, 0.01, B.P[B.pick([28, 29, 30])], 3, sw);
              if (k % 3 === 2) B.iso(p[0], p[1] - 0.03, p[2], 0.032, B.P[B.pick(FLOWERS)], 3, sw);
            }
          };
        const pot = (p, r, mat, chains) => {
          S.lathe([p[0], p[1] - r * 0.7, p[2]], r * 0.7, t => r * (0.45 + 0.55 * Math.sin((t * Math.PI) / 2)), mat, { res: 0.03 });
          S.torus([p[0], p[1], p[2]], r, 0.025, GOLDM, { res: 0.02 });
          const Gp = Object.assign(S.grp(0.06), { res: 0.035 });
          for (let k = 0; k < 6; k++) {
            const a = (k / 6) * TAU + p[0];
            S.ball([p[0] + Math.cos(a) * r * 0.5, p[1] + 0.06, p[2] + Math.sin(a) * r * 0.5], r * 0.42, LIMEM, Gp);
          }
          for (let k = 0; k < chains; k++) {
            const a = (k / chains) * TAU + 0.4,
              rim = [p[0] + Math.cos(a) * r, p[1], p[2] + Math.sin(a) * r];
            S.tube([rim, [p[0] + Math.cos(a) * r * 0.4, BASE_Y + 0.02, p[2] + Math.sin(a) * r * 0.4]], 0.01, 0.01, GOLDM, { res: 0.015 });
          }
          return () => {
            for (let k = 0; k < 14; k++) {
              const a = B.rr(0, TAU);
              strand(p[0] + Math.cos(a) * r * 0.95, p[1] + 0.02, p[2] + Math.sin(a) * r * 0.95, B.rr(0.4, 1.1) * (r / 0.35), true);
            }
            for (let k = 0; k < 10; k++) {
              const a = B.rr(0, TAU),
                q = B.rr(0, r * 0.8);
              B.iso(p[0] + Math.cos(a) * q, p[1] + 0.15 + B.rr(0, 0.1), p[2] + Math.sin(a) * q, 0.04, B.P[B.pick(FLOWERS)], 3);
            }
          };
        };
        const trails = [pot([0, -2.75, 0], 0.6, POTS[0], 4)];
        for (let k = 0; k < 6; k++) {
          const a = (k / 6) * TAU + 0.35,
            r = 3.1;
          trails.push(pot([Math.cos(a) * r, -2.1 - 0.35 * (k % 2), Math.sin(a) * r], 0.32, POTS[(k + 1) % POTS.length], 3));
        }
        S.lights.push({ p: [0.5, -5.6, 2.5], r: 9, s: 0.5 });
        S.bake();
        for (const t of trails) t();
        // vines straight from the plinth's underside, and wisteria round its edge
        for (let i = 0; i < 150; i++) {
          const a = B.rr(0, TAU),
            q = Math.sqrt(B.rr(0.04, 1)) * 5.2;
          strand(Math.cos(a) * q, BASE_Y - 0.01, Math.sin(a) * q, B.rr(0.25, 1.3) * (0.5 + 0.5 * (q / 5.2)), B.R() < 0.6);
        }
        for (let i = 0; i < 16; i++) {
          const a = (i / 16) * TAU + B.rr(-0.1, 0.1),
            q = B.rr(4.4, 5.1),
            x = Math.cos(a) * q,
            z = Math.sin(a) * q,
            len = B.rr(0.5, 0.9),
            sw = sway();
          for (let k = 0; k < 30; k++) {
            const f = B.R(),
              rr = 0.16 * (1 - f) + 0.02,
              b = B.rr(0, TAU);
            B.iso(x + Math.cos(b) * rr, BASE_Y - 0.05 - f * len, z + Math.sin(b) * rr, 0.035, B.P[f < 0.6 ? B.pick([20, 21, 21]) : B.pick([16, 17])], 3, sw);
          }
        }
      }

      // ---------------- the sky: a neon grid to the horizon, its glow, stars, and the crown as a constellation
      const GY = -15;
      for (let k = -15; k <= 15; k++)
        for (let s = -46; s <= 46; s += 0.7)
          for (const along of [0, 1]) {
            const x = along ? s : k * 3,
              z = along ? k * 3 : s,
              r = Math.hypot(x, z);
            if (r < 13 || r > 46) continue;
            B.stick(x, GY, z, along ? [1, 0, 0] : [0, 0, 1], 0.36, 0.05, B.P[r < 24 ? 15 : r < 34 ? 14 : 13], 3, { em: true, nd: true });
          }
      for (let i = 0; i < 200; i++) {
        const d = B.randDir();
        if (d[1] < 0.02) continue;
        const r = B.rr(40, 48);
        B.star(d[0] * r, d[1] * r * 0.7 + 1, d[2] * r, B.pick([0.12, 0.18, 0.24]), B.pick([21, 26, 11]), { em: true, nd: true, k: 4, ph: B.rr(0, 6), sp: B.rr(1.5, 3) });
      }
      {
        // the crown's thirteen squares as stars; lines trace its outline: the band, the sides, and the three points
        const ca = CAM.yaw + Math.PI - 0.55,
          cd = az(ca),
          across = [cd[2], 0, -cd[0]],
          step = 1.5,
          at = (i, j) => [cd[0] * 36 + across[0] * (i - 2) * step, 5.4 + j * step, cd[2] * 36 + across[2] * (i - 2) * step],
          on = (i, j) => j < 2 || i % 2 === 0;
        for (let i = 0; i < 5; i++)
          for (let j = 0; j < 3; j++) {
            if (!on(i, j)) continue;
            const p = at(i, j);
            B.star(p[0], p[1], p[2], j === 2 ? 0.5 : 0.26, j === 2 ? 37 : 11, { em: true, nd: true });
            B.iso(p[0], p[1], p[2], 0.25, B.P[36], 0.35, { em: true, nd: true });
          }
        const outline = [
          [0, 0], [1, 0], [2, 0], [3, 0], [4, 0], [4, 1], [4, 2], [3, 1], [2, 2], [1, 1], [0, 2], [0, 1], [0, 0]
        ];
        for (let s = 0; s + 1 < outline.length; s++) {
          const p = at(...outline[s]),
            q = at(...outline[s + 1]);
          for (let k = 2; k < 9; k++) {
            const m = add(p, mul(sub(q, p), k / 10));
            B.iso(m[0], m[1], m[2], 0.07, B.P[21], 0.7, { em: true, nd: true });
          }
        }
      }

      // ---------------- the missile circus: one flyer and a swarm of missiles, each round its own orbit of the globe once a loop,
      // the other way from the page's turn, so on the turning page they cross the view twice a loop
      const OC = [0, 2.4, 0],
        orbit = (n, r, azim) => {
          const a = az(azim),
            e1 = nrm(sub(a, mul(n, dot(a, n)))),
            p = mad(OC, e1, r);
          return { n, r, p, rad: e1, fwd: nrm(cross(sub(p, OC), n)) };
        },
        azF = CAM.yaw + 0.35,
        FLY = orbit(nrm([0.12, 1, -0.18]), 7.0, azF),
        MISSILES = [];
      for (let i = 0; i < 12; i++) {
        const tilt = 0.12 + 0.33 * B.R(),
          ta = B.rr(0, TAU),
          n = nrm([Math.sin(tilt) * Math.sin(ta), Math.cos(tilt), Math.sin(tilt) * Math.cos(ta)]);
        MISSILES.push(Object.assign(orbit(n, 6.3 + 1.5 * B.R(), azF + 0.42 + i * 0.13 + 0.08 * B.R()), { tag: 'm' + i, coil: B.rr(0, TAU) }));
      }

      // ---------------- the red balloon
      const BAL = [-2.5, 6.2, 9.7];

      // ---------------- what moves: made in a bake of its own, so nothing still is cut where it stood
      const whole = (tag, extra) => Object.assign({ tag, whole: true, res: 0.022 }, extra || {});
      // the record's platter, and the frog riding it
      S.lathe(sub(PC, [0, 0.035, 0]), 0.035, 0.3, { r: [4, 5, 6], gloss: { c: 21, at: 0.95, c2: 20, at2: 0.9 }, mod: (x, y, z) => (Math.hypot(x - PC[0], z - PC[2]) % 0.04 < 0.012 ? -0.2 : 0) }, whole('platter', { res: 0.018 }));
      S.lathe(PC, 0.006, 0.095, { r: [15, 16, 17] }, whole('platter', { res: 0.012 }));
      const FROG = mad(PC, rpAx[2], 0.15),
        ff = rpAx[0],
        fside = rpAx[2],
        FP = (a, b, c) => [FROG[0] + fside[0] * a + ff[0] * c, FROG[1] + b, FROG[2] + fside[2] * a + ff[2] * c];
      {
        const o = whole('frog', { res: 0.014 }),
          fax = [fside, UP, ff];
        S.ball(FP(0, 0.075, -0.02), [0.1, 0.07, 0.12], LIMEM, Object.assign({ ax: fax }, o));
        S.ball(FP(0, 0.1, 0.08), [0.085, 0.055, 0.07], LIMEM, Object.assign({ ax: fax }, o));
        S.ball(FP(0, 0.07, 0.11), [0.06, 0.03, 0.04], { r: [30, 31, 37] }, Object.assign({ ax: fax }, o));
        for (const s of [-1, 1]) {
          S.ball(FP(s * 0.05, 0.155, 0.09), 0.035, { r: [30, 31, 37] }, o);
          S.ball(FP(s * 0.055, 0.03, -0.06), [0.04, 0.035, 0.07], LIMEM, Object.assign({ ax: fax }, o));
          S.tube([FP(s * 0.05, 0.06, 0.08), FP(s * 0.065, 0.0, 0.12)], 0.016, 0.014, LIMEM, o);
        }
      }
      // the radio dish: a yoke that turns to follow the flyer, and a bowl on it that tips up and down
      {
        const oy = whole('dishYaw', { res: 0.025 });
        S.lathe([DS[0], DTOP + 0.02, DS[2]], 0.14, 0.22, CHROMEM, oy);
        S.box([DS[0], DTOP + 0.18, DS[2]], [0.36, 0.035, 0.08], STEELM, oy);
        for (const s of [-1, 1]) S.box([DS[0] + s * 0.33, (DTOP + 0.18 + DP[1]) / 2, DS[2]], [0.03, (DP[1] - DTOP - 0.18) / 2 + 0.05, 0.07], STEELM, oy);
        const ot = whole('dishTilt', { res: 0.028 }),
          R0 = 1.05,
          depth = 0.38,
          f = (R0 * R0) / (4 * depth),
          V0 = DP[1] + 0.14,
          outer = [],
          inner = [];
        for (let k = 0; k <= 16; k++) {
          const r = (R0 * k) / 16;
          outer.push([r, (r * r) / (4 * f)]);
          inner.push([r, (r * r) / (4 * f) + 0.05]);
        }
        S.revolve([outer.concat(inner.reverse())], [DP[0], V0, DP[2]], { r: SNOW, s: SNOW_MOON, tex: (x, y, z, ny, t) => (Math.abs(Math.hypot(x - DP[0], z - DP[2]) - 0.8) < 0.035 ? 15 : undefined) }, ot);
        S.tube([[DP[0] - 0.3, DP[1], DP[2]], [DP[0] + 0.3, DP[1], DP[2]]], 0.05, 0.05, CHROMEM, ot);
        S.lathe([DP[0], DP[1] - 0.06, DP[2]], 0.22, 0.13, STEELM, ot);
        for (let k = 0; k < 3; k++) {
          const a = (k / 3) * TAU + 0.5;
          S.tube([[DP[0] + Math.cos(a) * R0 * 0.92, V0 + depth * 0.85, DP[2] + Math.sin(a) * R0 * 0.92], [DP[0], V0 + f - 0.08, DP[2]]], 0.014, 0.014, STEELM, ot);
        }
        S.lathe([DP[0], V0 + f - 0.12, DP[2]], 0.16, t => 0.07 - 0.04 * t, CHROMEM, ot);
      }
      // the pocket watch on its chain, and its minute hand
      const fN = az(CAM.yaw),
        fAx = frameY(fN),
        fUp = UP,
        fRt = cross(fUp, fN),
        WCt = add(HANG, [0, -0.86, 0]);
      {
        const o = whole('watch', { res: 0.016 });
        for (let k = 0; k < 6; k++) S.torus(add(HANG, [0, -0.04 - k * 0.065, 0]), 0.035, 0.01, GOLDM, Object.assign({ ax: frameY(k % 2 ? fRt : fN) }, o));
        S.torus(add(HANG, [0, -0.47, 0]), 0.065, 0.016, GOLDM, Object.assign({ ax: frameY(fN) }, o));
        S.lathe(add(HANG, [0, -0.6, 0]), 0.07, 0.035, GOLDM, o);
        S.lathe(mad(WCt, fN, -0.05), 0.1, 0.27, GOLDM, Object.assign({ ax: fAx }, o));
        S.torus(mad(WCt, fN, 0.05), 0.26, 0.025, GOLDM, Object.assign({ ax: fAx }, o));
        S.lathe(mad(WCt, fN, 0.045), 0.012, 0.235, { r: [10, 37, 11] }, Object.assign({ ax: fAx }, o));
        // the hour hand stays at four
        const hd = nrm(add(mul(fRt, -Math.sin(2 * Math.PI / 3)), mul(fUp, Math.cos(2 * Math.PI / 3))));
        S.box(mad(mad(WCt, fN, 0.065), hd, 0.065), [0.014, 0.065, 0.006], SHADOWM, Object.assign({ ax: [cross(hd, fN), hd, fN] }, o));
        S.ball(mad(WCt, fN, 0.07), 0.022, GOLDM, o);
        S.box(mad(mad(WCt, fN, 0.075), fUp, 0.09), [0.01, 0.1, 0.005], { r: [18, 19] }, Object.assign({ ax: [fRt, fUp, fN] }, whole('minute', { res: 0.012 })));
      }
      // the crew: robot arms of shadow, each with a bowler hat and a VR headset on its head
      for (const a of CREW) {
        const d = az(a.yaw),
          ax = [d[2], 0, -d[0]],
          dirAt = e => [d[0] * Math.cos(e), Math.sin(e), d[2] * Math.cos(e)],
          sh = add(a.b, [0, 0.42, 0]),
          el = mad(sh, dirAt(a.e[0]), 0.85),
          wr = mad(el, dirAt(a.e[1]), 0.75),
          hf = dirAt(a.e[2]),
          hu = cross(hf, ax),
          hAx = [ax, hu, hf],
          hs = 1.3,
          hc = mad(mad(wr, hf, 0.1 * hs), hu, 0.05 * hs),
          t0 = a.id + '0',
          t1 = a.id + '1',
          t2 = a.id + '2',
          t3 = a.id + '3',
          seg = (p, q, w, tag) => S.box(mul(add(p, q), 0.5), [w, Math.hypot(...sub(q, p)) / 2, w], SHADOWM, whole(tag, { ax: frameY(sub(q, p)), rd: 0.03, res: 0.03 }));
        Object.assign(a, { sh, el, wr, hc, hf, hu, ax, hAx, hs });
        S.lathe([a.b[0], 0.03, a.b[2]], 0.34, [0.21, 0.17], SHADOWM, whole(t0, { res: 0.03 }));
        S.lathe(mad(sh, ax, -0.14), 0.28, 0.1, JOINTM, whole(t0, { ax: frameY(ax), res: 0.025 }));
        seg(sh, el, 0.085, t1);
        S.lathe(mad(el, ax, -0.12), 0.24, 0.085, JOINTM, whole(t1, { ax: frameY(ax), res: 0.025 }));
        seg(el, wr, 0.07, t2);
        S.ball(wr, 0.075, JOINTM, whole(t2, { res: 0.022 }));
        const o3 = (extra) => whole(t3, Object.assign({ res: 0.018 }, extra));
        S.box(hc, [0.15 * hs, 0.11 * hs, 0.13 * hs], SHADOWM, o3({ ax: hAx, rd: 0.05 * hs }));
        S.box(mad(mad(hc, hf, 0.13 * hs), hu, 0.02 * hs), [0.145 * hs, 0.062 * hs, 0.045 * hs], { r: [18, 19, 20], s: [19, 20, 21] }, o3({ ax: hAx, rd: 0.025 * hs }));
        S.box(mad(hc, hu, 0.02 * hs), [0.158 * hs, 0.024 * hs, 0.138 * hs], { r: [14, 15, 16] }, o3({ ax: hAx, rd: 0.02 }));
        S.lathe(mad(hc, hu, 0.11 * hs), 0.02 * hs, 0.2 * hs, HATM, o3({ ax: frameY(hu) }));
        S.lathe(mad(hc, hu, 0.125 * hs), 0.15 * hs, t => 0.125 * hs * Math.sqrt(Math.max(0, 1 - Math.pow(t, 2.5))) + 0.004, HATM, o3({ ax: frameY(hu) }));
        S.torus(mad(hc, hu, 0.15 * hs), 0.122 * hs, 0.016 * hs, { r: [14, 15, 16] }, o3({ ax: frameY(hu) }));
      }
      // the jet-pack flyer: a gold finned helmet, a leather jacket, a chrome pack with two flames
      const fF = FLY.fwd,
        fY = FLY.n,
        fX = cross(fY, fF),
        hd = nrm(add(mul(fF, 0.85), mul(fY, 0.5))),
        cn = nrm(add(mul(fF, 0.5), mul(fY, -0.85))),
        bodyAx = [fX, hd, cross(fX, hd)],
        FP0 = FLY.p,
        JACKET = { r: WOOD, s: [43, 44, 45, 37] },
        JEANS = { r: [18, 19, 20], s: [19, 20, 21] };
      // (drawn 1.7 times life size against the rest, so it reads from the page's distance)
      const FZ = 1.7,
        FQ = (h, x, c) => add(FP0, add(add(mul(hd, h * FZ), mul(fX, x * FZ)), mul(cn, c * FZ)));
      {
        const o = extra => whole('flyer', Object.assign({ res: 0.025 }, extra));
        S.box(FP0, [0.14 * FZ, 0.21 * FZ, 0.09 * FZ], JACKET, o({ ax: bodyAx, rd: 0.05 * FZ }));
        S.ball(FQ(0.33, 0, 0), 0.12 * FZ, GOLDM, o());
        S.box(FQ(0.37, 0, -0.02), [0.012 * FZ, 0.09 * FZ, 0.1 * FZ], GOLDM, o({ ax: bodyAx }));
        S.box(FQ(0.32, 0, 0.1), [0.08 * FZ, 0.035 * FZ, 0.02 * FZ], { r: [4, 5], gloss: { c: 26, at: 0.9 } }, o({ ax: bodyAx }));
        for (const s of [-1, 1]) {
          S.tube([FQ(-0.18, s * 0.07, 0), FQ(-0.62, s * 0.09, 0.05)], 0.05 * FZ, 0.04 * FZ, JEANS, o());
          S.ball(FQ(-0.66, s * 0.09, 0.08), 0.05 * FZ, PINKM, o());
          S.tube([FQ(0.16, s * 0.16, 0), FQ(0.42, s * 0.22, 0.1)], 0.035 * FZ, 0.03 * FZ, JACKET, o());
          const can = FQ(0, s * 0.075, -0.16);
          S.lathe(mad(can, hd, -0.2 * FZ), 0.38 * FZ, t => (0.058 * (t > 0.85 ? 1 - (t - 0.85) * 4 : 1) + 0.006) * FZ, CHROMEM, o({ ax: frameY(hd) }));
          S.box(mad(mad(can, hd, -0.12 * FZ), fX, s * 0.07 * FZ), [0.06 * FZ, 0.08 * FZ, 0.01 * FZ], REDM, o({ ax: [fX, hd, cross(fX, hd)] }));
        }
      }
      // the missiles: white with a pink band, four fins
      for (const m of MISSILES) {
        const F = m.fwd,
          Fr = frameY(F),
          tail = mad(m.p, F, -0.34),
          mat = { r: [8, 9, 10, 11], s: [9, 10, 11, 17], tex: (x, y, z) => (Math.abs(dot(sub([x, y, z], m.p), F) - 0.12) < 0.035 ? 15 : undefined) };
        S.lathe(tail, 0.7, t => (t > 0.72 ? 0.07 * Math.sqrt(Math.max(0, (1 - t) / 0.28)) + 0.006 : 0.07), mat, whole(m.tag, { ax: Fr, res: 0.02 }));
        for (let k = 0; k < 4; k++) {
          const dd = add(mul(Fr[0], Math.cos((k * Math.PI) / 2)), mul(Fr[2], Math.sin((k * Math.PI) / 2)));
          S.box(mad(mad(tail, F, 0.08), dd, 0.1), [0.055, 0.08, 0.01], PINKM, whole(m.tag, { ax: [dd, F, cross(dd, F)], res: 0.015 }));
        }
      }
      // the balloon, and its knot
      S.ball(BAL, [0.5, 0.6, 0.5], REDM, whole('balloon', { res: 0.03 }));
      S.lathe(add(BAL, [0, -0.7, 0]), 0.12, t => 0.05 * t + 0.01, REDM, whole('balloon', { res: 0.015 }));

      S.bake();

      // ---------------- drawn by hand on the parts that move
      // the missiles' flames and their corkscrew trails of smoke, hot near the missile, fading to violet behind
      for (const m of MISSILES) {
        own(m.tag, () => {
          const F = m.fwd,
            tail = mad(m.p, F, -0.36);
          B.stick(...mad(tail, F, -0.08), F, 0.1, 0.035, B.P[37], 3, { em: true, k: 1, ph: B.rr(0, 6), sp: 11 });
          B.stick(...mad(tail, F, -0.14), F, 0.14, 0.055, B.P[35], 3, { em: true, nd: true, k: 1, ph: B.rr(0, 6), sp: 9 });
          B.iso(...mad(tail, F, -0.18), 0.16, B.P[35], 0.5, { em: true, nd: true });
          const span = 0.75,
            stepA = 0.06 / m.r;
          for (let s = stepA; s < span; s += stepA) {
            const q = add(OC, M.app(M.rot(m.n, s), sub(mad(m.p, F, -0.4), OC))),
              rad = nrm(sub(q, OC)),
              f = s / span,
              rho = 0.03 + 0.22 * f,
              ph = m.coil + (s * m.r * TAU) / 1.0,
              p = add(q, add(mul(m.n, rho * Math.cos(ph)), mul(rad, rho * Math.sin(ph)))),
              col = f < 0.05 ? 37 : f < 0.3 ? 11 : f < 0.6 ? 10 : f < 0.85 ? 9 : 21,
              alpha = f < 0.15 ? 0.8 : f < 0.4 ? 0.5 : f < 0.7 ? 0.3 : 0.16;
            B.iso(p[0], p[1], p[2], 0.045 + 0.07 * f, B.P[col], alpha, { nd: true, k: 6, ph: s * 9, sp: (3 * TAU) / L, rg: 0.05 });
          }
        });
      }
      // the flyer's flames, and a short trail of sparks and pink smoke
      own('flyer', () => {
        for (const s of [-1, 1]) {
          const noz = mad(FQ(0, s * 0.075, -0.16), hd, -0.22 * FZ);
          B.stick(...mad(noz, hd, -0.12 * FZ), hd, 0.13 * FZ, 0.04 * FZ, B.P[37], 3, { em: true, k: 1, ph: s, sp: 12 });
          B.stick(...mad(noz, hd, -0.2 * FZ), hd, 0.2 * FZ, 0.065 * FZ, B.P[35], 3, { em: true, nd: true, k: 1, ph: s + 1, sp: 10 });
          B.iso(...mad(noz, hd, -0.25 * FZ), 0.18 * FZ, B.P[36], 0.5, { em: true, nd: true });
        }
        const stepA = 0.07 / FLY.r;
        for (let s = stepA; s < 0.4; s += stepA) {
          const q = add(OC, M.app(M.rot(FLY.n, s), sub(mad(FP0, hd, -0.5 * FZ), OC))),
            f = s / 0.4;
          B.iso(q[0], q[1], q[2], 0.06 + 0.1 * f, B.P[f < 0.3 ? 37 : f < 0.6 ? 16 : 15], f < 0.5 ? 0.6 : 0.38, { nd: true, k: 6, ph: s * 11, sp: (3 * TAU) / L, rg: 0.05 });
          if (B.R() < 0.5) B.iso(q[0] + B.rr(-0.15, 0.15), q[1] + B.rr(-0.15, 0.15), q[2] + B.rr(-0.15, 0.15), 0.03, B.P[37], 3, { em: true, nd: true, k: 1, ph: B.rr(0, 6), sp: 13 });
        }
      });
      // the lighthouse beam: a long cone of light, and a shorter one behind it
      const beamAz = CAM.yaw + 0.9;
      own('beam', () => {
        for (const [dirAz, len] of [
          [beamAz, 6],
          [beamAz + Math.PI, 2.5]
        ]) {
          const dir = nrm(add(az(dirAz), [0, 0.05, 0])),
            side = az(dirAz + Math.PI / 2),
            n = Math.round(len / 0.12);
          for (let k = 1; k <= n; k++) {
            const f = k / n,
              c = mad(LHC, dir, 0.2 + len * f),
              rho = 0.05 + 0.06 * len * f,
              alpha = f < 0.2 ? 0.22 : f < 0.45 ? 0.14 : f < 0.7 ? 0.09 : 0.05,
              col = B.P[f < 0.3 ? 11 : 37];
            B.stick(c[0], c[1], c[2], dir, 0.09, 0.03 + rho * 0.15, col, alpha * 1.5, { em: true, nd: true });
            for (const u of [-1, 1]) B.stick(c[0] + side[0] * u * rho * 0.5, c[1], c[2] + side[2] * u * rho * 0.5, dir, 0.09, rho * 0.35, col, alpha, { em: true, nd: true });
          }
        }
      });
      // the dish's transmitter, and rings of signal that pulse out of it twice a loop
      own('dishTilt', () => {
        const R0 = 1.05,
          f = (R0 * R0) / (4 * 0.38),
          V0 = DP[1] + 0.14;
        B.iso(DP[0], V0 + f - 0.12, DP[2], 0.05, B.P[16], 3, { em: true, k: 7, ph: 0, sp: (2 * TAU) / L });
        for (let k = 1; k <= 5; k++) {
          const y = V0 + f + 0.1 + 0.3 * k,
            r = 0.3 + 0.13 * k,
            n = Math.ceil((TAU * r) / 0.1);
          for (let i = 0; i < n; i++) {
            const a = (i / n) * TAU;
            B.stick(DP[0] + Math.cos(a) * r, y, DP[2] + Math.sin(a) * r, [-Math.sin(a), 0, Math.cos(a)], 0.035, 0.016, B.P[14], 3, { em: true, nd: true, k: 4, ph: -0.9 * k, sp: (2 * TAU) / L });
          }
        }
      });
      // the crew's eyes: two lenses glowing in each headset
      for (const a of CREW)
        own(a.id + '3', () => {
          for (const s of [-1, 1]) {
            const p = mad(mad(mad(a.hc, a.hf, 0.178 * a.hs), a.hu, 0.02 * a.hs), a.ax, s * 0.065 * a.hs);
            B.disc(p[0], p[1], p[2], a.hf, 0.035 * a.hs, 0.006, B.P[26], 3, { em: true });
          }
        });
      // the watch's hour marks
      own('watch', () => {
        for (let k = 0; k < 12; k++) {
          const a = (k / 12) * TAU,
            p = mad(add(mad(WCt, fRt, Math.sin(a) * 0.19), mul(fUp, Math.cos(a) * 0.19)), fN, 0.06);
          B.iso(p[0], p[1], p[2], k % 3 ? 0.012 : 0.02, B.P[k % 3 ? 6 : 15], 3);
        }
      });
      // the balloon's string
      own('balloon', () => {
        for (let k = 0; k < 16; k++) {
          const p = add(BAL, [0.06 * Math.sin(k * 0.5), -0.82 - k * 0.1, 0.04 * Math.sin(k * 0.4)]);
          B.stick(p[0], p[1], p[2], UP, 0.055, 0.012, B.P[10], 3);
        }
      });

      const W = B.finish({
        cam: CAM,
        detail: 19.4,
        dither: 0.3,
        radius: 10,
        palName: 'Trapper Keeper',
        fog: { c: 0, start: 0.8, max: 0.2 },
        outline: { c: 4, edge: 1000 }, // no outline: no step in depth is ever this big
        ao: { k: 0.4, range: 0.5 }
      });
      FI.loopable(W, L);
      const st = K.stage(W);
      rig.bind(st);
      const Ry = a => M.rot(UP, a),
        flyerNow = w => {
          const RF = M.rot(FLY.n, -w),
            jink = add(mul(FLY.n, 0.9 * Math.sin(3 * w)), mul(FLY.rad, 0.6 * Math.sin(5 * w + 1)));
          return { RF, p: add(add(OC, M.app(RF, sub(FLY.p, OC))), M.app(RF, jink)) };
        },
        CB = CREW[1],
        yawTo = (from, p) => Math.atan2(p[0] - from[0], p[2] - from[2]);
      st.add({
        update(dt, t) {
          const w = (TAU * t) / L,
            fl = flyerNow(w);
          // the flyer goes round, jinking up and down and out and in, banking as it dodges
          rig.set('flyer', M.mul(fl.RF, M.rot(FLY.fwd, 0.8 * Math.sin(3 * w))), FLY.p, fl.p);
          // the missiles go round behind it, each on its own tilted orbit, so they weave across its path
          for (const m of MISSILES) rig.set(m.tag, M.rot(m.n, -w), OC, OC);
          // the dish follows the flyer round and tips with its height; the beam sweeps; the record turns with the frog hopping on it
          const dv = sub(fl.p, DP);
          rig.set('dishYaw', Ry(Math.atan2(dv[0], dv[2])), DS, DS);
          rig.child('dishTilt', 'dishYaw', M.rot([1, 0, 0], clamp(0.7 - 0.6 * Math.atan2(dv[1], Math.hypot(dv[0], dv[2])), 0.35, 0.95)), DP);
          rig.set('beam', Ry(-w), LHC, LHC);
          rig.set('platter', Ry(-2 * w), PC, PC);
          rig.set('frog', Ry(-2 * w), PC, add(PC, [0, 0.12 * Math.max(0, Math.sin(4 * w)) ** 2, 0]));
          // the watch swings from its branch, its minute hand going round once
          rig.set('watch', M.rot(fN, 0.32 * Math.sin(2 * w)), HANG, HANG);
          rig.child('minute', 'watch', M.rot(fN, -w), WCt);
          // the crew: the DJ nods on the beat, the lookout follows the flyer, the third watches the film and sways
          const arm = (a, yawA, s1, s2, s3) => {
            rig.set(a.id + '0', Ry(yawA), a.b, a.b);
            rig.child(a.id + '1', a.id + '0', M.rot(a.ax, s1), a.sh);
            rig.child(a.id + '2', a.id + '1', M.rot(a.ax, s2), a.el);
            rig.child(a.id + '3', a.id + '2', M.rot(a.ax, s3), a.wr);
          };
          arm(CREW[0], 0.12 * Math.sin(w), 0.05 * Math.sin(2 * w), 0.06 * Math.sin(2 * w + 1), 0.22 * Math.sin(4 * w));
          arm(CB, yawTo(CB.b, fl.p) - CB.yaw0, 0.08 * Math.sin(w), 0.1 * Math.sin(w + 0.5), 0.15 * Math.sin(3 * w));
          arm(CREW[2], 0.45 * Math.sin(w), 0.08 * Math.sin(2 * w), -0.12 * Math.sin(2 * w), 0.25 * Math.sin(2 * w + 0.5));
          // the balloon bobs and leans
          rig.set('balloon', M.rot([0, 0, 1], 0.06 * Math.sin(w)), BAL, add(BAL, [0, 0.25 * Math.sin(w), 0]));
          rig.apply();
        }
      });
      // the lookout's rest pose faces the flyer where the loop starts
      CB.yaw0 = yawTo(CB.b, flyerNow(0).p);
      return W;
    }
  };
};
