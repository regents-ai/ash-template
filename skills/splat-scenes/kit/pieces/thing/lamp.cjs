/* Lamp: an iron lamp post on a stone foot, its lantern glowing and flickering, a soft halo breathing round it, and a stone planter
   with a flowering bush beside it. RES is the splat spacing that spends about its share. */
const RES = 0.0155;

module.exports = {
  kind: 'thing',
  size: 'medium',
  build({ B, S, pal, TAU, L, along }, place) {
    const P = l => place.to(l),
      up = along(place.up),
      iron = { r: pal.ramp('metal', 0, 2), s: pal.ramp('metal', 1, 3) },
      stone = { r: pal.ramp('stone', 0, 3), s: pal.ramp('stone', 1) },
      o = extra => Object.assign({ ax: up, res: RES }, extra);

    // the post: a stone foot, an iron column narrowing upward, a ring under the lantern
    S.lathe(P([0, 0, 0]), 0.2, [0.22, 0.15], stone, o());
    S.lathe(P([0, 0.2, 0]), 1.55, u => 0.065 - 0.025 * u, iron, o());
    S.torus(P([0, 1.74, 0]), 0.1, 0.025, iron, o());
    // the lantern: glowing panes under an iron roof, flickering five times a loop, and a halo breathing twice a loop
    S.lathe(P([0, 1.74, 0]), 0.03, 0.15, iron, o());
    S.box(P([0, 1.9, 0]), [0.12, 0.14, 0.12], { r: pal.ramp('light'), em: true, fl: { em: true, k: 1, ph: 0, sp: (5 * TAU) / L } }, o({ ax: place.ax }));
    S.lathe(P([0, 2.03, 0]), 0.16, [0.2, 0.02], iron, o());
    B.iso(...P([0, 1.9, 0]), 0.42, B.P[pal.c('gold', -1)], 0.25, { em: true, nd: true, k: 7, ph: 0, sp: (2 * TAU) / L });

    // the planter beside it, and a bush in flower
    const pot = P([0.45, 0, 0.12]);
    S.lathe(pot, 0.32, [0.2, 0.27], stone, o({ bump: [0.01, 12] }));
    const bush = P([0.45, 0.52, 0.12]);
    S.ball(bush, [0.3, 0.26, 0.3], { r: pal.ramp('leaf', 0, 3), s: pal.ramp('leaf', 2), mod: (x, y, z) => 0.2 * (B.n3(x * 14, y * 14, z * 14) - 0.5) }, { res: RES, bump: [0.03, 9] });
    const petals = [pal.c('warm', 2), pal.c('light', -1), pal.c('cool', 3)];
    for (let k = 0; k < 40; k++) {
      const d = B.randDir();
      if (d[1] < 0) continue;
      B.iso(bush[0] + d[0] * 0.31, bush[1] + d[1] * 0.27, bush[2] + d[2] * 0.31, 0.03, B.P[petals[k % 3]], 3);
    }
  }
};
