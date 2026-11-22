/* Proves a baked file draws what the toolkit draws. It builds the live scene with the toolkit, reads the baked file back with
   decode.cjs, and has the toolkit's own renderer draw both from six views (four quarter turns, nearly straight above, nearly straight
   below) at three moments of the loop, then counts the art pixels that differ, how many of them are lone, their longest run on a row
   and their biggest clump. The toolkit's pictures are kept as the reference a
   painter is checked against, at their art-pixel size and blown up as a stage shows them, with reference.json beside them. Beside each
   view is a third picture, _differ.png: the toolkit's picture faded to a dark grey with every art pixel that differs in magenta.

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

// the art pixels that differ; how many of them are lone (no differing neighbour above, below or to either side); the longest run of
// them on one row; the biggest clump (differing art pixels joined edge to edge)
const differing = (a, b) => {
  const { w, h } = a,
    d = new Uint8Array(w * h),
    seen = new Uint8Array(w * h);
  let n = 0,
    lone = 0,
    run = 0,
    clump = 0;
  for (let i = 0, p = 0; i < w * h; i++, p += 3)
    if (a.rgb[p] !== b.rgb[p] || a.rgb[p + 1] !== b.rgb[p + 1] || a.rgb[p + 2] !== b.rgb[p + 2]) (d[i] = 1), n++;
  for (let y = 0; y < h; y++)
    for (let x = 0, along = 0; x < w; x++) {
      const i = y * w + x;
      along = d[i] ? along + 1 : 0;
      run = Math.max(run, along);
      if (d[i] && !(x && d[i - 1]) && !(x < w - 1 && d[i + 1]) && !(y && d[i - w]) && !(y < h - 1 && d[i + w])) lone++;
    }
  for (let s = 0; s < w * h; s++) {
    if (!d[s] || seen[s]) continue;
    const stack = [s];
    let size = 0;
    seen[s] = 1;
    while (stack.length) {
      const i = stack.pop(),
        x = i % w;
      size++;
      for (const j of [x ? i - 1 : -1, x < w - 1 ? i + 1 : -1, i - w, i + w])
        if (j >= 0 && j < w * h && d[j] && !seen[j]) (seen[j] = 1), stack.push(j);
    }
    clump = Math.max(clump, size);
  }
  return { n, lone, run, clump, d };
};

// the toolkit's picture faded to a dark grey, with every differing art pixel in magenta, blown up as a stage shows it
const marked = (a, d) => {
  const rgb = new Uint8Array(a.w * a.h * 3);
  for (let i = 0, p = 0; i < a.w * a.h; i++, p += 3)
    if (d[i]) (rgb[p] = 255), (rgb[p + 2] = 255);
    else rgb[p] = rgb[p + 1] = rgb[p + 2] = (0.299 * a.rgb[p] + 0.587 * a.rgb[p + 1] + 0.114 * a.rgb[p + 2]) / 3;
  return kit.render.upscale({ w: a.w, h: a.h, rgb }, a.px);
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
      { n: diff, lone, run, clump, d } = differing(a, b),
      name = `${id}_yaw${deg(yaw)}_pitch${deg(pitch)}_t${tau.toFixed(2)}`,
      big = kit.render.upscale(a, a.px),
      differ = marked(a, d);
    worst = Math.max(worst, diff / (a.w * a.h));
    kit.png.write(path.join(out, name + '.png'), a.w, a.h, a.rgb);
    kit.png.write(path.join(out, `${name}_x${a.px}.png`), big.w, big.h, big.rgb);
    kit.png.write(path.join(out, `${name}_differ.png`), differ.w, differ.h, differ.rgb);
    entry.pictures.push({
      native: name + '.png',
      upscaled: `${name}_x${a.px}.png`,
      differ: `${name}_differ.png`,
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
    console.log(
      `  ${name}: ${a.w}x${a.h} art pixels of ${a.px}, ${diff} differ, ${lone} lone, longest run on a row ${run}, biggest clump ${clump}`
    );
  }
}
fs.writeFileSync(
  path.join(out, 'reference.json'),
  JSON.stringify({ canvas: CANVAS, fovDegrees: Number(deg(kit.render.FOV)), scene: entry }, null, 2) + '\n'
);
console.log(`${id}: at most ${(worst * 100).toFixed(3)}% of a view's art pixels differ between the live scene and the baked file`);
