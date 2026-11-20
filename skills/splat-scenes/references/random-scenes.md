# Scenes from a seed

A scene file can make a different scene for each seed: `build(seed)` gets the seed, and every choice in it comes from the builder's
seeded randomness, never `Math.random`. The same seed always gives the same scene and so the same baked bytes.

```js
build(seed) {
  const B = makeBuilder(seed, PALETTE);
  const S = K.sculpt(makeSculpt(B));
  const trees = Math.round(B.rr(3, 7));                 // how many
  const roof = B.pick(['flat', 'gable', 'dome']);       // which
  for (let i = 0; i < trees; i++) tree(S, B.rr(-4, 4), B.rr(-4, 4), B.rr(0.8, 1.4)); // where and how big
  // ...
}
```

- **Pick, then build.** Make the big choices (layout, counts, which variant of a part) first and the small ones (jitter, sizes) as each
  thing is built, so changing a detail does not shift every choice after it.
- **Keep the frame.** Choose within ranges that keep the scene inside its `radius` and in front of its camera; check several seeds
  before trusting the ranges.
- **Look at many at once.** ink-studio's command line (references/ink-studio.md, 2.7) draws any one seed with `render scene.js --seed 7`,
  and `variants scene.js --seeds 3,7,12,19` draws up to 48 seeds on one sheet, ranked, when the world publishes numbers to rank by: set
  `W.variant = { silhouette, openness, wear }` (numbers of your own choosing) on the finished world. The baker carries `variant`
  through without effect.
- **Bake one seed.** The kit builds a scene with its own `seed`. To bake another, a one-line file beside it picks the seed:

  ```js
  module.exports = kit => ({ ...require('./my-scene.js')(kit), id: 'my-scene-7', seed: 7 });
  ```

  then bake that file as usual. Several seeds: a script file that bakes each in turn (an agent's shell may not keep variables or run
  loops typed straight in).
- **Motion still loops.** Seeded speeds go through `loopable` like any others (SKILL.md, The loop).
