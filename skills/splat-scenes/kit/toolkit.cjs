/* Loads ink-studio from the folder INK_STUDIO names, builds a scene file written against it, and walks the built world through time.
   The toolkit is only called, never copied (SKILL.md, Setup). */
const path = require('node:path');

const INK = process.env.INK_STUDIO;
if (!INK) throw new Error('INK_STUDIO is not set: point it at an ink-studio folder (SKILL.md, Setup)');

const render = require(path.join(INK, 'cli/render.js'));
const png = require(path.join(INK, 'cli/png.js'));

/* Builds a scene file: a module that takes the toolkit and returns { id, name, seed, build(seed) }. A world with nothing moving comes
   back without a stage, so it is given one and every world walks the same way. */
function build(sceneFile) {
  const kit = require(path.join(INK, 'index.js')).load(),
    scene = require(path.resolve(sceneFile))(kit),
    t0 = Date.now(),
    world = scene.build(scene.seed);
  world.buildMs = Date.now() - t0;
  world.id = scene.id;
  if (!world.anim) kit.KIT.stage(world);
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
