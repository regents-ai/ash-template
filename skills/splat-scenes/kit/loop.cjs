/* The loop rule for a scene file: every splat that moves by its kind made to come round a whole number of times in `loop` seconds, so
   the baked loop plays on into itself without a jump. A scene calls it on its finished world before returning it:

     const loopable = require('<this skill>/kit/loop.cjs');
     ...
     return loopable(B.finish({ ... }), 8);

   It moves each speed to the nearest whole number of cycles a loop (at least one) and changes nothing else. A swaying splat (kind 11)
   also rises and falls at 1.3 times its speed, which never comes round exactly, so of the cycle counts either side of its own it takes
   the one that brings that second motion nearest a whole number. The rows are changed in the world and in its stage's rest copy, when
   it already has a stage. */
const TAU = Math.PI * 2;

const cyclesOf = (sp, loop) => Math.max(1, Math.round((Math.abs(sp) * loop) / TAU));
const turnSpeed = (sp, cycles, loop) => (Math.sign(sp) * cycles * TAU) / loop;

function swayCycles(sp, loop) {
  const m0 = cyclesOf(sp, loop);
  let best = m0,
    off = 1;
  for (let m = Math.max(1, m0 - 1); m <= m0 + 1; m++) {
    const o = Math.abs(1.3 * m - Math.round(1.3 * m));
    if (o < off) [off, best] = [o, m];
  }
  return best;
}

function snap(rows, count, loop) {
  for (let i = 0; i < count; i++) {
    const q = i * 16,
      kind = Math.round(rows[q + 11]) % 16,
      sp = rows[q + 13],
      rg = rows[q + 14];
    if (!kind || !sp) continue;
    // falling and rising cover their range once a cycle; every other kind turns once a cycle
    if (kind === 2 || kind === 3) rows[q + 13] = rg ? (rg * Math.max(1, Math.round((loop * sp) / rg))) / loop : sp;
    else rows[q + 13] = turnSpeed(sp, kind === 11 ? swayCycles(sp, loop) : cyclesOf(sp, loop), loop);
  }
}

module.exports = function loopable(world, loop) {
  snap(world.data, world.count, loop);
  if (world.anim && world.anim.base) snap(world.anim.base, world.count, loop);
  return world;
};
