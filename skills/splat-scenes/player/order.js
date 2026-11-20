/* Which splats the painter draws far to near, and in what order. A solid splat whose density never changes hides what is behind it,
   so the depth test keeps the nearest and those are drawn unsorted. The rest are sorted every frame: soft splats, splats that write
   no depth, and those whose kind changes their density (flicker, fall, rise, pulse). */
import { centreAt, FALL, FLICKER, PULSE, RISE } from './motion.js';
import { NO_DEPTH } from './scene.js';

const FADING = new Set([FLICKER, FALL, RISE, PULSE]);

export function createOrder(scene) {
  const { header, blocks } = scene,
    solid = [],
    sorted = [];
  for (let n = 0; n < header.splats; n++) {
    const style = blocks.style[n],
      code = blocks.styleCode[style],
      fades = n < header.moving && FADING.has(code & 15);
    (blocks.styleDensity[style] < 1 || code & NO_DEPTH || fades ? sorted : solid).push(n);
  }
  const keys = new Float64Array(sorted.length),
    places = new Uint32Array(sorted.length),
    ids = new Uint32Array(sorted.length);
  return {
    solid: Uint32Array.from(solid),
    // the rest, farthest first `seconds` into the loop for a camera whose back axis is `back`; ties keep file order
    farToNear(back, seconds) {
      for (let i = 0; i < sorted.length; i++) {
        const [x, y, z] = centreAt(scene, sorted[i], seconds);
        keys[i] = back[0] * x + back[1] * y + back[2] * z;
        places[i] = i;
      }
      places.sort((a, b) => keys[a] - keys[b] || a - b);
      for (let i = 0; i < sorted.length; i++) ids[i] = sorted[places[i]];
      return ids;
    }
  };
}
