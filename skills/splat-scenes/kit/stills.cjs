/* The still pictures of a baked scene, drawn by the toolkit's renderer from the decoded file:

     still.png    the opening view at the start of the loop for a 1440 by 960 stage, one pixel per art pixel: the player's picture until
                  its first frame and without WebGPU (the browser scales it up in squares)
     sheet.png    six views at the start of the loop, three across: the opening view, the other three quarter turns, nearly straight
                  above and nearly straight below, each a 720 by 480 stage with every art pixel a square of screen pixels
     moments.png  the opening view at eight moments an eighth of the loop apart, four across

     env INK_STUDIO=<ink-studio folder> node kit/stills.cjs <baked .bin> <folder> */
const fs = require('node:fs');
const path = require('node:path');
const { render: R, png } = require('./toolkit.cjs');
const decode = require('./decode.cjs');

const STAGE = { w: 1440, h: 960 };
const TILE = { w: 720, h: 480 };
const ABOVE = 1.45; // radians of pitch, a little short of straight up or down

const [binFile, out] = process.argv.slice(2);
if (!binFile || !out) throw new Error('usage: node kit/stills.cjs <baked .bin> <folder>');
fs.mkdirSync(out, { recursive: true });

const scene = decode.open(binFile),
  { camYaw: yaw, camPitch: pitch, frames } = scene.h,
  draw = (world, o) => R.render(world, Object.assign({ t: world.clock }, o)),
  big = im => R.upscale(im, im.px),
  write = (name, im) => {
    png.write(path.join(out, name), im.w, im.h, im.rgb);
    console.log(`${path.join(out, name)}: ${im.w}x${im.h}`);
  };

const start = decode.world(scene, 0),
  still = draw(start, Object.assign({ yaw, pitch }, STAGE));
write('still.png', still);
console.log(`  ${still.w}x${still.h} art pixels, each ${still.px} screen pixels on a ${STAGE.w} by ${STAGE.h} stage`);

const views = [0, 1, 2, 3].map(k => [yaw + (k * Math.PI) / 2, pitch]).concat([[yaw, ABOVE], [yaw, -ABOVE]]);
write('sheet.png', R.grid(views.map(([y, p]) => big(draw(start, Object.assign({ yaw: y, pitch: p }, TILE)))), 3));

const moments = [];
for (let k = 0; k < 8; k++) moments.push(big(draw(decode.world(scene, Math.round((k * frames) / 8)), Object.assign({ yaw, pitch }, TILE))));
write('moments.png', R.grid(moments, 4));
