/* Loads the ink-studio toolkit from the checkout INK_STUDIO names, and moves a built world through time. The toolkit is only
   called, never copied. */
const path = require('node:path');

const INK = process.env.INK_STUDIO;
if (!INK) throw new Error('INK_STUDIO is not set: point it at an ink-studio checkout (SKILL.md, Setup)');

const render = require(path.join(INK, 'cli/render.js'));
const png = require(path.join(INK, 'cli/png.js'));
const toolkit = () => require(path.join(INK, 'index.js')).load();

// walks a world forward to time t, a sixtieth of a second at a time (its stage remembers what came before, so time only goes forward)
function pose(world, t) {
  while (world.clock < t - 1e-9) {
    const dt = Math.min(1 / 60, t - world.clock);
    world.clock += dt;
    world.anim.update(dt, world.clock);
  }
  world.clock = t;
}

// walks a world to the first moment from now that is `seconds` into a loop
const at = (world, seconds) => pose(world, Math.ceil((world.clock - seconds) / world.loop - 1e-9) * world.loop + seconds);

module.exports = { INK, render, png, toolkit, pose, at };
