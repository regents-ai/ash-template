/* Proves a baked file draws what the toolkit draws. It builds the live scene with the toolkit, reads the baked file back with
   decode.cjs, and has the toolkit's own renderer draw both from six views (four quarter turns, nearly straight above, nearly straight
   below) at three moments of the loop, then counts the art pixels that differ. The toolkit's pictures are kept as the reference a
   painter is checked against, at their art-pixel size and blown up as a stage shows them, with reference.json beside them.

     env INK_STUDIO=<ink-studio folder> node kit/verify.cjs <scene file> <baked .bin> <reference folder> */
const fs = require('node:fs');
const path = require('node:path');
const kit = require('./toolkit.cjs');
const F = require('./format.cjs');
const decode = require('./decode.cjs');

const CANVAS = { w: 1440, h: 960 };
const MOMENTS = [0, 5 / 16, 11 / 16]; // fractions of the loop
const ABOVE = 1.45; // radians of pitch, a little short of straight up or down (where the camera has no sideways)

const [sceneFile, binFile, out] = process.argv.slice(2);
if (!sceneFile || !binFile || !out) throw new Error('usage: node kit/verify.cjs <scene file> <baked .bin> <reference folder>');
fs.mkdirSync(out, { recursive: true });

const deg = r => ((r * 180) / Math.PI).toFixed(1);
const covOf = (d, o) => [d[o + 4], d[o + 5], d[o + 6], d[o + 8], d[o + 9], d[o + 10]];
const frob = c => Math.hypot(c[0], c[3], c[5], Math.SQRT2 * c[1], Math.SQRT2 * c[2], Math.SQRT2 * c[4]);

// how far the decoded rows are from the toolkit's, field by field
function compareRows(live, dec, order, moving) {
  const r = { position: 0, shape: 0, density: 0, colour: 0, kind: 0, phase: 0, motion: 0 };
  order.forEach((i, n) => {
    const a = i * 16,
      b = n * 16;
    for (let k = 0; k < 3; k++) r.position = Math.max(r.position, Math.abs(live[a + k] - dec[b + k]));
    const ca = covOf(live, a);
    r.shape = Math.max(r.shape, frob(covOf(dec, b).map((v, k) => v - ca[k])) / frob(ca));
    if (live[a + 3] !== dec[b + 3]) r.density++;
    if (live[a + 7] !== dec[b + 7]) r.colour++;
    if (live[a + 11] !== dec[b + 11]) r.kind++;
    if (n < moving) {
      r.phase = Math.max(r.phase, 2 * Math.abs(Math.sin((live[a + 12] - dec[b + 12]) / 2)));
      for (let k = 13; k < 16; k++) if (live[a + k] !== dec[b + k]) r.motion++;
    }
  });
  return r;
}

const differing = (a, b) => {
  let n = 0;
  for (let p = 0; p < a.length; p += 3) if (a[p] !== b[p] || a[p + 1] !== b[p + 1] || a[p + 2] !== b[p + 2]) n++;
  return n;
};

const live = kit.build(sceneFile),
  scene = decode.open(binFile),
  { h } = scene,
  id = live.id,
  order = F.fileOrder(live.anim.base, live.count),
  cam = live.cam,
  views = [0, 1, 2, 3].map(k => [cam.yaw + (k * Math.PI) / 2, cam.pitch]).concat([[cam.yaw, ABOVE], [cam.yaw, -ABOVE]]),
  entry = { id, file: path.basename(binFile), loop: h.loop, clockStart: h.clockStart, rows: [], pictures: [] };
let worst = 0;
// (the live scene is walked to each moment frame by frame, as the bake walked it: a cloth remembers every step it took, so a different
//  walk would leave it a hair elsewhere)
let walked = 0;
for (const fraction of MOMENTS) {
  const frame = Math.round(fraction * h.frames),
    tau = frame / F.FRAME_RATE,
    dec = decode.world(scene, frame);
  for (; walked <= frame; walked++) kit.pose(live, h.clockStart + walked / F.FRAME_RATE);
  const rows = compareRows(live.data, dec.data, order, h.moving);
  entry.rows.push(Object.assign({ loopTime: tau }, rows));
  console.log(
    `${id} at ${tau.toFixed(2)}s: rows within ${rows.position.toExponential(2)} world units and ${(rows.shape * 100).toFixed(2)}% of shape, ` +
      `phases within ${rows.phase.toExponential(2)}; differing densities ${rows.density}, colours ${rows.colour}, kinds ${rows.kind}, motion numbers ${rows.motion}`
  );
  for (const [yaw, pitch] of views) {
    const o = Object.assign({ yaw, pitch }, CANVAS),
      a = kit.render.render(live, Object.assign({ t: live.clock }, o)),
      b = kit.render.render(dec, Object.assign({ t: dec.clock }, o)),
      diff = differing(a.rgb, b.rgb),
      name = `${id}_yaw${deg(yaw)}_pitch${deg(pitch)}_t${tau.toFixed(2)}`,
      big = kit.render.upscale(a, a.px);
    worst = Math.max(worst, diff / (a.w * a.h));
    kit.png.write(path.join(out, name + '.png'), a.w, a.h, a.rgb);
    kit.png.write(path.join(out, `${name}_x${a.px}.png`), big.w, big.h, big.rgb);
    entry.pictures.push({
      native: name + '.png',
      upscaled: `${name}_x${a.px}.png`,
      yaw,
      pitch,
      dist: cam.dist,
      target: cam.target,
      pixelSize: a.px,
      grid: [a.w, a.h],
      loopTime: tau,
      clock: live.clock,
      differingPixels: diff
    });
    console.log(`  ${name}: ${a.w}x${a.h} art pixels of ${a.px}, ${diff} differ`);
  }
}
fs.writeFileSync(
  path.join(out, 'reference.json'),
  JSON.stringify({ canvas: CANVAS, fovDegrees: Number(deg(kit.render.FOV)), scene: entry }, null, 2) + '\n'
);
console.log(`${id}: at most ${(worst * 100).toFixed(3)}% of a view's art pixels differ between the live scene and the baked file`);
