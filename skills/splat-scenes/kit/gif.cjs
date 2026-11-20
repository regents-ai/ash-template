/* The loop of a baked scene as an animated GIF that plays for ever. The camera goes once round at the resting tilt while everything in
   the scene plays its loop once, so the last frame runs on into the first. The toolkit's renderer draws the decoded file at every
   second stored frame (15 a second) on an 864 by 576 stage, each art pixel a square of screen pixels.

   Every pixel the renderer draws is one of the scene's palette colours, so the GIF's one colour table is the palette as it is, with one
   more entry for a pixel unchanged since the frame before (shown through from it). Nothing is matched to a colour again or dithered; a
   pixel off the palette is an error.

     env INK_STUDIO=<ink-studio folder> node kit/gif.cjs <baked .bin> <out .gif> */
const fs = require('node:fs');
const path = require('node:path');
const { render: R } = require('./toolkit.cjs');
const F = require('./format.cjs');
const decode = require('./decode.cjs');

const STAGE = { w: 864, h: 576 };
const STEP = 2; // stored frames from one GIF frame to the next

// one frame's colour indices, LZW-compressed into GIF sub-blocks
function lzw(ix, bits) {
  const clear = 1 << bits,
    stop = clear + 1,
    out = [],
    dict = new Map();
  let size = bits + 1,
    next = stop + 1,
    acc = 0,
    n = 0;
  const put = code => {
    acc |= code << n;
    n += size;
    while (n >= 8) {
      out.push(acc & 255);
      acc >>>= 8;
      n -= 8;
    }
  };
  put(clear);
  let w = ix[0];
  for (let i = 1; i < ix.length; i++) {
    const k = ix[i],
      key = w * 4096 + k;
    if (dict.has(key)) {
      w = dict.get(key);
      continue;
    }
    put(w);
    if (next < 4096) {
      dict.set(key, next++);
      if (next > 1 << size && size < 12) size++;
    } else {
      put(clear);
      dict.clear();
      size = bits + 1;
      next = stop + 1;
    }
    w = k;
  }
  put(w);
  put(stop);
  if (n) out.push(acc & 255);
  const blocks = [];
  for (let i = 0; i < out.length; i += 255) blocks.push(Math.min(255, out.length - i), ...out.slice(i, i + 255));
  return Buffer.from(blocks.concat(0));
}

/* writes a GIF of frames ({ w, h, rgb }, all one size) in palette (0xRRGGBB), frame i shown for delays[i] hundredths of a second;
   returns how many pixels changed between each frame and the next, the last frame to the first included */
function writeGif(file, frames, palette, delays) {
  const { w, h } = frames[0],
    index = new Map(Array.from(palette, (hex, i) => [hex, i])),
    unchanged = palette.length,
    bits = Math.max(2, Math.ceil(Math.log2(palette.length + 1))),
    table = Buffer.alloc(3 << bits),
    u16 = v => [v & 255, v >> 8];
  if (unchanged > 255) throw new Error('a GIF holds 255 colours and the unchanged entry; the palette has ' + palette.length);
  Array.from(palette).forEach((hex, i) => table.set([hex >> 16, (hex >> 8) & 255, hex & 255], i * 3));
  const indexed = frames.map((f, k) => {
    const ix = new Uint8Array(w * h);
    for (let p = 0; p < w * h; p++) {
      const found = index.get((f.rgb[p * 3] << 16) | (f.rgb[p * 3 + 1] << 8) | f.rgb[p * 3 + 2]);
      if (found === undefined) throw new Error(`frame ${k}, pixel ${p} is not one of the palette's colours`);
      ix[p] = found;
    }
    return ix;
  });
  const parts = [Buffer.from('GIF89a'), Buffer.from([...u16(w), ...u16(h), 0xf0 | (bits - 1), 0, 0]), table];
  parts.push(Buffer.from([0x21, 0xff, 11, ...Buffer.from('NETSCAPE2.0'), 3, 1, 0, 0, 0]));
  const changed = indexed.map((ix, k) => {
    const after = indexed[(k + 1) % indexed.length];
    let n = 0;
    for (let p = 0; p < ix.length; p++) if (ix[p] !== after[p]) n++;
    return n;
  });
  indexed.forEach((ix, k) => {
    const frame = k ? ix.map((v, p) => (v === indexed[k - 1][p] ? unchanged : v)) : ix;
    // graphic control: leave the frame in place under the next (dispose 1), the unchanged entry see-through
    parts.push(Buffer.from([0x21, 0xf9, 4, 0x05, ...u16(delays[k]), unchanged, 0]));
    parts.push(Buffer.from([0x2c, 0, 0, 0, 0, ...u16(w), ...u16(h), 0, bits]));
    parts.push(lzw(frame, bits));
  });
  parts.push(Buffer.from([0x3b]));
  fs.mkdirSync(path.dirname(path.resolve(file)), { recursive: true });
  fs.writeFileSync(file, Buffer.concat(parts));
  return changed;
}

const [binFile, out] = process.argv.slice(2);
if (!binFile || !out) throw new Error('usage: node kit/gif.cjs <baked .bin> <out .gif>');

const t0 = Date.now(),
  scene = decode.open(binFile),
  { h } = scene,
  stored = [];
for (let f = 0; f < h.frames; f += STEP) stored.push(f);
const at = k => (k < stored.length ? stored[k] / F.FRAME_RATE : h.loop),
  // each frame shown until the next one's moment, rounded so the whole loop lasts its own length
  delays = stored.map((_, k) => Math.round(100 * at(k + 1)) - Math.round(100 * at(k))),
  frames = stored.map(f => {
    const world = decode.world(scene, f),
      im = R.render(world, { t: world.clock, yaw: h.camYaw - (2 * Math.PI * f) / h.frames, pitch: h.camPitch, w: STAGE.w, h: STAGE.h });
    return R.upscale(im, im.px);
  }),
  changed = writeGif(out, frames, scene.A.palette, delays),
  between = changed.slice(0, -1);
console.log(
  `${out}: ${frames.length} frames of ${frames[0].w}x${frames[0].h}, ${(fs.statSync(out).size / 1e6).toFixed(2)} MB, ` +
    `${(delays.reduce((s, d) => s + d, 0) / 100).toFixed(2)} s a loop, made in ${((Date.now() - t0) / 1000).toFixed(1)} s`
);
console.log(
  `  seam: ${changed[changed.length - 1]} pixels change from the last frame to the first, against ` +
    `${Math.min(...between)} to ${Math.max(...between)} between neighbouring frames`
);
