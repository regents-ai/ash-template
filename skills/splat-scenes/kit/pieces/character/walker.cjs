/* Walker: a figure with a backpack walking one lap of the stage each loop, six strides a lap, bobbing as it goes, legs and arms
   swinging. Its body is one moving part turning about the stage's middle and carrying its legs and arms, and it keeps to the stage,
   so it never meets a piece on another place. RES is the splat spacing that spends about its share. */
const RES = 0.0144,
  ORBIT = 0.8, // the lap's radius
  START = -0.7, // where on the lap it is at the start of the loop, in radians from straight toward the camera
  STRIDES = 6;

module.exports = {
  kind: 'character',
  build({ B, S, M, pal, part, loop }, place) {
    // a point on the figure: a along the way it walks, b up, c across toward the camera at the start of the loop
    const P = (a, b, c) => place.to([a, b, ORBIT + c]),
      o = { ax: place.ax, res: RES },
      mat = (role, from = 0) => ({ r: pal.ramp(role, from, from + 3), s: pal.ramp(role, from + 1) }),
      shirt = mat('warm'),
      trousers = mat('cool'),
      skin = mat('flesh'),
      hair = mat('wood', 0),
      pack = mat('gold', 0),
      shoes = { r: [pal.c('ink'), pal.c('metal', 0), pal.c('metal', 1)] };

    const body = part(
      'body',
      () => {
        S.ball(P(0, 1.6, 0), [0.24, 0.42, 0.3], shirt, o);
        S.ball(P(0, 1.2, 0), [0.22, 0.14, 0.27], trousers, o);
        S.box(P(-0.33, 1.65, 0), [0.1, 0.26, 0.2], pack, Object.assign({ rd: 0.05 }, o));
        S.tube([P(0, 1.95, 0), P(0.02, 2.12, 0)], 0.08, 0.08, skin, { res: RES });
        S.ball(P(0.03, 2.32, 0), 0.24, skin, o);
        S.ball(P(-0.03, 2.4, 0), [0.25, 0.2, 0.26], hair, o);
        S.ball(P(0.27, 2.3, 0), 0.05, skin, o);
        for (const c of [-0.09, 0.09]) B.iso(...P(0.24, 2.36, c), 0.025, pal.rgb('ink'), 3);
      },
      { pivot: place.at }
    );
    // a leg or an arm: a tube through [a, b] points at c across, ending in a shoe or a hand; it swings about its first point
    const limb = (name, c, pts, r, cloth, end, size, endMat) =>
      part(
        name,
        () => {
          S.tube(pts.map(([a, b]) => P(a, b, c)), r[0], r[1], cloth, { res: RES });
          S.ball(P(end[0], end[1], c), size, endMat, o);
        },
        { pivot: P(pts[0][0], pts[0][1], c), parent: body }
      );
    const legs = [-1, 1].map(s => limb(s < 0 ? 'left leg' : 'right leg', s * 0.13, [[0, 1.2], [0.03, 0.68], [0, 0.14]], [0.1, 0.07], trousers, [0.07, 0.06], [0.15, 0.06, 0.08], shoes));
    const arms = [-1, 1].map(s => limb(s < 0 ? 'left arm' : 'right arm', s * 0.34, [[0, 1.95], [0.03, 1.5], [0.06, 1.12]], [0.07, 0.055], shirt, [0.07, 1.06], 0.07, skin));

    // one lap a loop about the stage's middle, starting a little to the right so it first faces partly toward the camera; legs and
    // arms swing about the way across, one stride for each
    loop((t, w) => {
      const stride = Math.sin(STRIDES * w);
      body.set(M.rot(place.up, START + w), [0, 0.04 * Math.abs(Math.cos(STRIDES * w)), 0]);
      legs.forEach((leg, i) => leg.set(M.rot(place.forward, (i ? -1 : 1) * 0.45 * stride)));
      arms.forEach((arm, i) => arm.set(M.rot(place.forward, (i ? 1 : -1) * 0.35 * stride)));
    });
  }
};
