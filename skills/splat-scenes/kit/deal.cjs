/* Deals a random scene from a library of interchangeable pieces: one of each kind a scene must have, a sky and a character when the
   library has any, no weather or one, and a thing for each place the dealt ground has, of that place's size. The same seed deals the
   same scene. */
const fs = require('node:fs');
const path = require('node:path');
const { ONE, KINDS } = require('./compose.cjs');

// mulberry32: a small seeded random number generator
const random = seed => {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
};

const filesIn = dir => fs.readdirSync(dir, { withFileTypes: true }).flatMap(e => (e.isDirectory() ? filesIn(path.join(dir, e.name)) : e.name.endsWith('.cjs') ? [path.join(dir, e.name)] : []));

function deal(folder, seed, out) {
  const rand = random(seed),
    pick = list => list[Math.floor(rand() * list.length)],
    shuffle = list => {
      const a = list.slice();
      for (let i = a.length - 1; i > 0; i--) {
        const j = Math.floor(rand() * (i + 1));
        [a[i], a[j]] = [a[j], a[i]];
      }
      return a;
    },
    library = filesIn(path.resolve(folder)).map(file => ({ file, mod: require(file) })),
    of = kind => library.filter(p => p.mod.kind === kind);
  for (const p of library) if (!KINDS.includes(p.mod.kind)) throw new Error(p.file + ': its kind is ' + JSON.stringify(p.mod.kind));
  const dealt = ONE.map(kind => {
    if (!of(kind).length) throw new Error('the library has no ' + kind + ' piece');
    return pick(of(kind));
  });
  for (const kind of ['sky', 'character']) if (of(kind).length) dealt.push(pick(of(kind)));
  const weather = pick([null, ...of('weather')]);
  if (weather) dealt.push(weather);
  const places = dealt.find(p => p.mod.kind === 'ground').mod.places;
  for (const size of ['large', 'medium', 'small'])
    dealt.push(...shuffle(of('thing').filter(p => p.mod.size === size)).slice(0, places[size].length));
  const dir = path.dirname(path.resolve(out)),
    scene = { seed, pieces: dealt.map(p => path.relative(dir, p.file).split(path.sep).join('/')) };
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(out, JSON.stringify(scene, null, 2) + '\n');
  return scene;
}

module.exports = { deal };
