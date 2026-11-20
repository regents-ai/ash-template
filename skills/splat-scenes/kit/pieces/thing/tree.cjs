/* Tree: a broad tree on spreading roots, its canopy of small leaves swaying in the wind, a few leaves drifting down from it each loop
   and more lying in the grass. Built by the toolkit's own tree, sized to its place. */
module.exports = {
  kind: 'thing',
  size: 'large',
  build({ B, S, pal, TAU, L }, place) {
    const [x, y, z] = place.at,
      h = place.h * 0.8,
      leaf = pal.ramp('leaf'),
      UP = [0, 1, 0];
    S.tree(x, y - 0.05, z, {
      h,
      r: h * 0.06,
      spread: place.r * 0.78,
      nb: 7,
      lean: [B.rr(-0.06, 0.06), B.rr(-0.06, 0.06)],
      roots: 5,
      bark: { r: pal.ramp('wood', 0, 3), s: pal.ramp('wood', 1), mod: (px, py, pz) => 0.12 * (B.n3(px * 9, py * 2, pz * 9) - 0.5) },
      // the canopy sways ten times a loop: a sway comes round exactly only at a multiple of ten
      leaf: { r: leaf.slice(0, 4), s: leaf.slice(1), fl: { k: 11, ph: 0, sp: (10 * TAU) / L, rg: 0.03 } },
      leaves: 26000,
      ls: 0.32,
      res: 0.035
    });

    // leaves lying in the grass under the canopy, and a few letting go and falling, each once a loop
    for (let i = 0; i < 40; i++) {
      const a = B.rr(0, TAU),
        q = B.rr(0.2, place.r),
        d = [Math.cos(a + 1), 0, Math.sin(a + 1)];
      B.dab(x + Math.cos(a) * q, y + 0.02, z + Math.sin(a) * q, UP, d, 0.05, 0.03, 0.006, B.P[leaf[B.pick([2, 3, 4])]], 3);
    }
    for (let i = 0; i < 6; i++) {
      const a = B.rr(0, TAU),
        q = B.rr(0.3, place.r * 0.8),
        fall = h * 0.8;
      B.dab(x + Math.cos(a) * q, y + fall, z + Math.sin(a) * q, B.norm([0.3, 1, 0.2]), B.norm([Math.cos(a), 0.4, Math.sin(a)]), 0.05, 0.03, 0.006, B.P[leaf[3]], 3, {
        k: 2,
        ph: i / 6,
        sp: fall / L,
        rg: fall
      });
    }
  }
};
