/* The offline pictures of a built world, drawn by ink-studio's own renderer and scaled up so one art pixel is a square of screen
   pixels: the seven stills and their sheet, the eight moments of the loop, and a stand's sheet for one piece. */
const fs = require('node:fs');
const path = require('node:path');
const { render: R, png, at } = require('./ink.cjs');
const { views, SIZE } = require('./look.cjs');

const TAU = Math.PI * 2;
const draw = (world, o) => {
  const im = R.render(world, Object.assign({ t: world.clock }, o));
  return R.upscale(im, im.px);
};
const write = (file, im) => png.write(file, im.w, im.h, im.rgb);

// the seven views at the start of the loop, one file each, and sheet.png: the hero view, the three other quarter turns, above, below
function stills(world, dir) {
  fs.mkdirSync(dir, { recursive: true });
  at(world, 0);
  const pics = Object.entries(views(world.cam)).map(([name, [yaw, pitch]]) => {
    const im = draw(world, Object.assign({ yaw, pitch }, SIZE));
    write(path.join(dir, name + '.png'), im);
    return [name, im];
  });
  write(path.join(dir, 'sheet.png'), R.grid(pics.filter(([name]) => name !== '000').map(([, im]) => im), 3));
}

// the hero view at eight moments an eighth of the loop apart, four across
function moments(world, file) {
  const pics = [];
  for (let k = 0; k < 8; k++) {
    at(world, (k * world.loop) / 8);
    pics.push(draw(world, { w: 720, h: 480 }));
  }
  write(file, R.grid(pics, 4));
}

/* A stand's sheet for one piece: a piece smaller than the ground is seen first from the hero camera, then close up on what it made
   from the front, behind and the side at 2 seconds, then from the front at 4 and 6 seconds; a wider piece gets the whole scene from
   the front, behind, the side and above, then from the front at 4 and 6 seconds. */
function standSheet(world, box, ground, file) {
  const { yaw, pitch } = world.cam,
    size = Math.max(...box.hi.map((v, k) => v - box.lo[k])),
    close = size < ground.hi[0] - ground.lo[0] && { target: box.lo.map((v, k) => (v + box.hi[k]) / 2), dist: Math.max(size, 1.2) * 2.4 },
    view = (y, p) => draw(world, Object.assign({ yaw: y, pitch: p, w: 720, h: 480 }, close)),
    pics = [];
  at(world, 2);
  if (close) pics.push(draw(world, { yaw, pitch, w: 720, h: 480 }));
  for (const [y, p] of [[yaw, pitch], [yaw + TAU / 2, pitch], [yaw + TAU / 4, pitch]].concat(close ? [] : [[yaw, 1.12]])) pics.push(view(y, p));
  for (const t of [4, 6]) {
    at(world, t);
    pics.push(view(yaw, pitch));
  }
  write(file, R.grid(pics, 3));
}

module.exports = { stills, moments, standSheet };
