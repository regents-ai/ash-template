/* Pool: still water in a ring of mossy stones, lily pads resting on it, ripples lifting it and glints winking on it, and reeds
   swaying at its back. The water is flat dabs laid on a grid; the stones are the toolkit's bumpy rocks. */
const WATER = 0.012, // the spacing of the water's dabs
  RES = 0.021; // the stones' splat spacing

module.exports = {
  kind: 'thing',
  size: 'medium',
  build({ B, S, pal, TAU, L }, place) {
    const [cx, cy, cz] = place.at,
      R = place.r * 0.72,
      UP = [0, 1, 0],
      water = pal.ramp('water'),
      stone = { r: pal.ramp('stone', 0, 3), s: pal.ramp('stone', 1), top: { min: 0.75, r: pal.ramp('leaf', 0, 3) } };

    // the water: flat dabs, darker toward the middle; a few lift with slow ripples, a few wink as glints
    for (let x = -R; x < R; x += WATER)
      for (let z = -R; z < R; z += WATER) {
        const d = Math.hypot(x, z) / R;
        if (d > 1) continue;
        const shade = water[Math.min(3, Math.floor((d + 0.4 * B.n3(x * 4 + cx, z * 4, 2)) * 3))],
          roll = B.R(),
          an = roll < 0.15 ? { k: 6, ph: (Math.hypot(x, z) * 9) % TAU, sp: (2 * TAU) / L, rg: 0.006 } : roll < 0.17 ? { k: 4, ph: B.rr(0, TAU), sp: (3 * TAU) / L } : undefined;
        B.dab(cx + x, cy + 0.03, cz + z, UP, [1, 0, 0], WATER * 0.8, WATER * 0.8, 0.003, B.P[shade], 3, an);
      }
    // lily pads, each with a flower on one
    for (let k = 0; k < 5; k++) {
      const a = (k / 5) * TAU + B.rr(0, 0.6),
        q = R * B.rr(0.3, 0.75),
        p = [cx + Math.cos(a) * q, cy + 0.045, cz + Math.sin(a) * q];
      S.ball(p, [0.09, 0.012, 0.09], { r: pal.ramp('leaf', 1, 4) }, { res: RES * 0.6 });
      if (k === 2) B.iso(p[0], p[1] + 0.04, p[2], 0.035, B.P[pal.c('light', -1)], 3);
    }
    // the ring of stones, half sunk in the turf
    for (let k = 0; k < 16; k++) {
      const a = (k / 16) * TAU + B.rr(-0.08, 0.08),
        r = B.rr(0.11, 0.16),
        q = R + r * 0.55;
      S.rock([cx + Math.cos(a) * q, cy + r * 0.25, cz + Math.sin(a) * q], r, stone, { res: RES });
    }
    // reeds at the back, swaying ten times a loop
    for (let k = 0; k < 24; k++) {
      const a = place.turn + Math.PI + B.rr(-0.9, 0.9),
        q = R * B.rr(0.85, 1.05),
        h = B.rr(0.35, 0.6),
        lean = B.norm([B.rr(-0.15, 0.15), 1, B.rr(-0.15, 0.15)]),
        foot = [cx + Math.sin(a) * q, cy, cz + Math.cos(a) * q],
        an = { k: 11, ph: B.rr(0, 1), sp: (10 * TAU) / L, rg: 0.02 };
      B.stick(foot[0] + (lean[0] * h) / 2, cy + h / 2, foot[2] + (lean[2] * h) / 2, lean, h / 2, 0.012, B.P[pal.c('leaf', B.pick([2, 3]))], 3, an);
      if (k % 3 === 0) B.stick(foot[0] + lean[0] * h, cy + h, foot[2] + lean[2] * h, lean, 0.04, 0.02, B.P[pal.c('wood', 1)], 3, an);
    }
  }
};
