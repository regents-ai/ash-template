/* How a baked scene moves over its loop, worked on the processor: where a splat is at a moment, for ordering the few splats drawn far
   to near (order.js). The painter's vertex shader works the same rules on the graphics card for every splat. */
import { FRAME_RATE, restCentre } from './scene.js';

// the kinds of motion that move or fade a splat (blink only brightens it)
export const FLICKER = 1;
export const FALL = 2;
export const RISE = 3;
export const ORBIT = 5;
export const BOB = 6;
export const PULSE = 7;
export const SWAY = 11;

const TAU = Math.PI * 2;
const frac = x => x - Math.floor(x);

// the stored frame shown `seconds` into the loop
export const frameAt = (header, seconds) => Math.min(header.frames - 1, Math.floor(seconds * FRAME_RATE));

// a moving splat's centre moved by its kind at `seconds` into the loop (only the centre matters for ordering)
function moved(scene, n, [x, y, z], seconds) {
  const { blocks, header } = scene,
    kind = blocks.styleCode[blocks.style[n]] & 15,
    turns = (blocks.cycles[n] * seconds) / header.loop,
    phase = blocks.phase[n] / 65536,
    r = blocks.motionRange[blocks.motion[n]],
    angle = TAU * (turns + phase);
  switch (kind) {
    case FALL:
      return [x, y - frac(turns + phase) * r, z];
    case RISE: {
      const u = frac(turns + phase);
      return [x + 0.25 * u * Math.sin(7 * u + 50 * phase), y + u * r, z];
    }
    case ORBIT: {
      const turn = TAU * turns;
      return [x * Math.cos(turn) + z * Math.sin(turn), y, z * Math.cos(turn) - x * Math.sin(turn)];
    }
    case BOB:
      return [x, y + r * Math.sin(angle), z];
    case SWAY:
      return [x + r * Math.sin(angle + 1.3 * y + 0.9 * z), y + 0.6 * r * Math.sin(1.3 * TAU * turns + TAU * phase + 1.1 * x), z];
    default:
      return [x, y, z];
  }
}

// splat n's centre `seconds` into the loop: carried by its part, then moved by its kind
export function centreAt(scene, n, seconds) {
  const { header, blocks } = scene,
    [x, y, z] = restCentre(scene, n),
    a = blocks.track,
    o = (frameAt(header, seconds) * header.parts + blocks.stylePart[blocks.style[n]]) * 12,
    carried = [a[o] * x + a[o + 1] * y + a[o + 2] * z + a[o + 9], a[o + 3] * x + a[o + 4] * y + a[o + 5] * z + a[o + 10], a[o + 6] * x + a[o + 7] * y + a[o + 8] * z + a[o + 11]];
  return n < header.moving ? moved(scene, n, carried, seconds) : carried;
}
