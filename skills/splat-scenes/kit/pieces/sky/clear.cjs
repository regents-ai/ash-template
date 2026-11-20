/* Clear: an open sky. Big soft splats on a sphere round the scene, palest at the horizon and under the sun, deepening above and
   below, and a little haze on the far side of the scene. They glow and stay out of the outline, so the light does not shade them. */
module.exports = {
  kind: 'sky',
  build({ B, pal, TAU, fog, share }, sky) {
    const [s0, s1, s2, s3, s4] = pal.ramp('sky'),
      sunAz = Math.atan2(sky.sun[2], sky.sun[0]),
      R = sky.r1 - 2, // the sphere the sky is laid on
      TOP = 7,
      BOTTOM = -28, // the lowest the camera looks past the scene; nothing may go below y -30
      STEP = 1.1,
      // the colours by height: [lowest height of the band, [away from the sun, across, toward it]]
      BANDS = [
        [4, [s2, s3, s3]],
        [1.5, [s2, s3, s4]],
        [-1.5, [s2, s3, s4]],
        [-5, [s2, s2, s3]],
        [-11, [s1, s2, s2]],
        [-18, [s0, s1, s2]],
        [-Infinity, [s0, s0, s1]]
      ],
      band = y => BANDS.findIndex(([h]) => y >= h),
      rows = [];
    for (let y = TOP; y >= BOTTOM; y -= STEP) rows.push([y, Math.sqrt(R * R - y * y)]);
    const gap = rows.reduce((n, [, r]) => n + TAU * r, 0) / (0.86 * share.splats); // the spacing round each row that spends the share
    for (const [y, r] of rows) {
      const n = Math.round((TAU * r) / gap);
      for (let i = 0; i < n; i++) {
        const a = ((i + B.R()) / n) * TAU,
          yy = y + B.gauss() * 0.25,
          lean = Math.cos(a - sunAz) + B.gauss() * 0.2,
          [away, across, toward] = BANDS[band(yy)][1],
          c = lean > 0.45 ? toward : lean > -0.35 ? across : away;
        B.iso(Math.cos(a) * r, yy, Math.sin(a) * r, 2.3, B.P[c], 0.24, { em: true, nd: true });
      }
    }
    fog(0, 0.82, 0.16);
  }
};
