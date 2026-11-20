/* Isle: a flat disc of turf with a ragged rim, on a cone of bumpy stone hanging in the air. Grass tufts, pebbles and small
   flowers cover the turf, thickest on the side the camera sees, and never where a thing stands. The places are laid out so none
   overlap and all lie wholly on the flat top. */
const R = 5.2, // the turf's radius
  THICK = 0.5, // the turf's depth at the rim
  DEPTH = 2.4, // the stone cone's height under it
  BODY = 40000, // about what the turf and the cone bake to; tufts spend the rest of the share
  TUFT = 4; // the splats in a tuft, a pebble or a flower, on average
const slot = (x, z, turn) => ({ at: [x, z], turn });

module.exports = {
  kind: 'ground',
  places: {
    stage: [0.3, 1.6],
    large: [slot(-2.2, -1.6, 0.5), slot(2.1, -1.9, 0.2)],
    medium: [slot(-0.2, -2.8, 0.4), slot(2.9, 0.9, -0.3), slot(-2.9, 0.6, 0.6)],
    small: [slot(1.9, 3.0, 0.3), slot(-1.6, 3.0, 0.5), slot(0.4, -0.6, 0.4), slot(-4.0, -0.4, 0.6)]
  },
  build({ B, S, pal, TAU, L, share, view, taken }) {
    const rim = a => R * (1 + 0.04 * Math.sin(3 * a + 1) + 0.08 * (B.fbm(Math.cos(a) * 1.5 + 4, Math.sin(a) * 1.5, 0.7, 2) - 0.5)),
      height = (x, z) => 0.03 * (B.fbm(x * 0.4, 1.3, z * 0.4, 2) - 0.5),
      top = (x, z) => (Math.hypot(x, z) < rim(Math.atan2(z, x)) ? height(x, z) : -Infinity),
      G = S.grp(0.35),
      leaf = pal.ramp('leaf'),
      [s0, s1, s2, s3] = pal.ramp('stone');

    // the turf: a layer THICK deep under its top, inside its ragged rim; green on top, earth on its sides
    S.solid(
      [0, 0, 0],
      R * 1.1,
      (x, y, z) => Math.max(0.8 * (Math.hypot(x, z) - rim(Math.atan2(z, x))), y - height(x, z), -THICK - y),
      (res, f) => {
        for (let x = -R * 1.1; x < R * 1.1; x += res)
          for (let z = -R * 1.1; z < R * 1.1; z += res)
            if (top(x, z) > -Infinity) {
              f(x, height(x, z), z);
              if (Math.hypot(x, z) > R * 0.8) f(x, -THICK, z);
            }
        for (let a = 0; a < TAU; a += res / R) for (let y = -THICK; y < 0; y += res) f(Math.cos(a) * rim(a), y, Math.sin(a) * rim(a));
      },
      {
        r: pal.ramp('wood', 0, 3),
        s: pal.ramp('wood', 1),
        top: { min: 0.5, r: pal.ramp('ground', 0, 3), s: pal.ramp('ground', 1) }
      },
      Object.assign({ res: 0.07 }, G)
    );
    // the cone of stone hanging under it, bumpy and banded, narrowing to a point
    const strata = (x, y, z) => 0.25 * (B.n3(x * 0.7, y * 3.2, z * 0.7) - 0.5);
    S.lathe([0, -THICK - DEPTH, 0], DEPTH + 0.1, u => R * 0.8 * (0.06 + 0.94 * Math.pow(u, 1.3)), { r: [s0, s1, s2], s: [s1, s2, s3], mod: strata }, Object.assign({ res: 0.1, bump: [0.3, 1.1] }, G));

    // tufts, pebbles and flowers: as many as the share leaves after the body, more on the half the camera sees
    const toward = Math.atan2(view[2], view[0]),
      quiver = { k: 11, sp: (10 * TAU) / L, rg: 0.012 },
      petal = [pal.c('light', -1), pal.c('gold', -1), pal.c('warm', -1), pal.c('cool', -1)],
      items = Math.floor((0.95 * share.splats - BODY) / TUFT);
    for (let k = 0; k < items; ) {
      const a = B.rr(0, TAU),
        d = Math.sqrt(B.R()) * (rim(a) - 0.15),
        x = Math.cos(a) * d,
        z = Math.sin(a) * d,
        front = (x * Math.cos(toward) + z * Math.sin(toward)) / R;
      if (taken(x, z) || B.R() > 0.35 + 0.65 * Math.max(0, front + 0.3)) continue;
      k++;
      const y = top(x, z),
        roll = B.R();
      if (roll < 0.72) {
        // a tuft: a patch of turf lying flat, and blades leaning out of it
        const an = Object.assign({ ph: B.rr(0, TAU) }, quiver),
          b = B.rr(0, Math.PI);
        B.dab(x, y + 0.015, z, [0, 1, 0], [Math.cos(b), 0, Math.sin(b)], 0.12, 0.08, 0.01, B.P[leaf[B.pick([1, 2])]], 3);
        for (let j = 2 + Math.floor(B.R() * 3); j > 0; j--) {
          const len = B.pick([0.12, 0.16, 0.2]),
            lean = B.norm([B.rr(-0.3, 0.3), 1, B.rr(-0.3, 0.3)]);
          B.stick(x + lean[0] * len * 0.5, y + lean[1] * len * 0.5, z + lean[2] * len * 0.5, lean, len * 0.5, 0.02, B.P[leaf[B.pick([2, 3, 4])]], 3, an);
        }
      } else if (roll < 0.88) {
        // a pebble, half sunk
        const r = B.pick([0.05, 0.065, 0.08]);
        B.iso(x, y + r * 0.7, z, r, B.P[B.pick([s1, s2, s3])], 3);
        B.iso(x + r * 0.3, y + r * 1.1, z - r * 0.2, r * 0.45, B.P[s3], 3);
      } else {
        // a small flower on a stem
        const h = B.pick([0.14, 0.18]);
        B.stick(x, y + h / 2, z, [0, 1, 0], h / 2, 0.014, B.P[leaf[2]], 3);
        B.iso(x, y + h, z, 0.045, B.P[B.pick(petal)], 3);
        B.iso(x, y + h + 0.015, z, 0.018, B.P[pal.c('gold', -1)], 3);
      }
    }
    return { top, radius: R, air: { r: R + 0.6, y0: 0.3, y1: 4.6 } };
  }
};
