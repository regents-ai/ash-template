/* Rain: a soft grey cloud hangs over the back of the scene as the camera first sees it, pale on top and darker underneath, and a
   drizzle falls from it onto the ground, each streak five times a loop. The cloud is lowered until its top shows in the hero picture. */
const DROPS = 1400;

module.exports = {
  kind: 'weather',
  build({ B, K, pal, L, hero, share }, air) {
    const { V } = K,
      UP = [0, 1, 0],
      back = V.norm([-hero.view[0], 0, -hero.view[2]]), // away from the camera, along the ground
      side = V.cross(back, UP),
      W = air.r * 0.4, // half the cloud's length, across the picture
      off = air.r * 0.45, // how far behind the middle it hangs
      flecks = Math.floor(0.85 * share.splats - DROPS),
      shades = [pal.c('metal', 1), pal.c('metal', 2), pal.c('metal', 3)];

    // the cloud's puffs in a row across the picture, their bottoms on one flat underside at height 0 for now
    const puffs = Array.from({ length: 7 }, (_, k) => {
      const r = W * B.rr(0.2, 0.3) * (1 - 0.35 * Math.abs(k / 3 - 1)),
        at = V.add(V.mul(side, (k / 3 - 1) * W * 0.8), V.mul(back, off + B.rr(-0.15, 0.15) * W));
      return { c: [at[0], r * 0.55, at[2]], r };
    });
    const points = Array.from({ length: flecks }, (_, i) => {
      const p = puffs[i % puffs.length],
        d = B.randDir(),
        u = Math.cbrt(B.R());
      return [p.c[0] + d[0] * u * p.r, Math.max(0, p.c[1] + d[1] * u * p.r * 0.7), p.c[2] + d[2] * u * p.r];
    });
    // the underside's height: the top of the air, lowered until the cloud's top is well inside the hero picture
    const highest = y => points.reduce((m, p) => Math.max(m, hero.see([p[0], p[1] + y, p[2]])[1]), -1);
    let base = air.y1;
    while (highest(base) > 0.8 && base > air.y0 + 1) base -= 0.1;
    const thick = Math.max(...puffs.map(p => p.c[1] + 0.7 * p.r));
    for (const p of points) B.iso(p[0], p[1] + base, p[2], 0.16, B.P[shades[Math.min(2, Math.floor((p[1] / thick) * 3))]], 0.7);

    // the drizzle: thin streaks falling from the underside to the top of the ground, most under the cloud
    const rg = base - air.y0,
      fall = V.norm([0.06 * side[0], -1, 0.06 * side[2]]);
    for (let i = 0; i < DROPS; i++) {
      const p = i % 5 < 3 ? V.add(V.mul(side, B.rr(-0.85, 0.85) * W), V.mul(back, off + B.rr(-0.25, 0.25) * W)) : V.mul(B.norm([B.rr(-1, 1), 0, B.rr(-1, 1)]), air.r * 0.85 * Math.sqrt(B.R()));
      B.stick(p[0], base, p[2], fall, 0.1, 0.016, B.P[pal.c('cool', -1)], 0.5, { nd: true, k: 2, ph: B.R(), sp: (rg * 5) / L, rg, ex: 0 });
    }
  }
};
