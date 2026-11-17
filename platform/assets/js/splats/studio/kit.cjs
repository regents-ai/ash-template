/* Loads the outside ink-studio toolkit from its own checkout, builds one of our scenes with it, and walks it to a moment.
   The toolkit is never part of this repository: INK_STUDIO names the folder it is in (see README.md). */
const path = require('node:path');

const INK = process.env.INK_STUDIO;
if (!INK) throw new Error('INK_STUDIO is not set: point it at a checkout of the ink-studio toolkit (see README.md)');

const render = require(path.join(INK, 'cli/render.js'));
const png = require(path.join(INK, 'cli/png.js'));

/* Builds a scene file. looks are the toolkit's build-time looks, which it reads from globals: fine (inked detail), bounce
   (light bounced between surfaces), follow (dabs laid along the form). The baked scenes use none of them. */
function build(scenePath, looks = {}) {
  globalThis.INK_FINE = !!looks.fine;
  globalThis.INK_BOUNCE = !!looks.bounce;
  globalThis.INK_FOLLOW = looks.follow ? {} : null;
  const kit = require(path.join(INK, 'index.js')).load(),
    scene = require(path.resolve(scenePath))(kit),
    t0 = Date.now(),
    world = scene.build(scene.seed);
  world.buildMs = Date.now() - t0;
  world.id = scene.id;
  world.loop = scene.loop;
  world.clock = 0;
  world.anim.update(0, 0);
  return world;
}

// walks a world forward to time t, a sixtieth of a second at a time (its stage remembers what came before, so t only goes forward)
function pose(world, t) {
  while (world.clock < t - 1e-9) {
    const dt = Math.min(1 / 60, t - world.clock);
    world.clock += dt;
    world.anim.update(dt, world.clock);
  }
  world.clock = t;
}

module.exports = { INK, render, png, build, pose };
