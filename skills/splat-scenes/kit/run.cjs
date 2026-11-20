/* The kit's one runner: setup, stand, build, check and deal. Every command needs INK_STUDIO set to an ink-studio checkout; SKILL.md
   says what each one writes. */
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const USAGE = `usage (from the skill folder, with INK_STUDIO set):
  node kit/run.cjs setup
  node kit/run.cjs stand <piece.cjs> <out folder> [scene.json]
  node kit/run.cjs build <scene.json> <out folder>
  node kit/run.cjs check <scene.json> <out folder>
  node kit/run.cjs deal <pieces folder> <seed> <scene.json>`;
const EXAMPLE = path.join(__dirname, 'example.json');

const n = x => x.toLocaleString('en');
const pc = x => (x * 100).toFixed(1) + '%';
const readScene = file => ({ spec: JSON.parse(fs.readFileSync(file, 'utf8')), dir: path.dirname(path.resolve(file)) });
// runs one step, printing how long it took
const step = (name, fn) => {
  const t0 = Date.now(),
    out = fn();
  console.log(name.padEnd(9) + ((Date.now() - t0) / 1000).toFixed(1).padStart(7) + ' s');
  return out;
};
const compose = (spec, dir) => {
  const { toolkit } = require('./ink.cjs'),
    { compose } = require('./compose.cjs');
  return compose(toolkit(), spec, dir);
};

// what each piece costs against its share
const usageTable = world =>
  ['| Piece | Splats | Styles | Motions | Parts |', '| --- | --- | --- | --- | --- |']
    .concat(
      world.usage.rows.map(r => {
        const of = (v, k) => n(v) + (r.share ? ' of ' + n(r.share[k]) : '');
        return '| ' + r.kind + ' ' + r.piece + ' | ' + of(r.splats, 0) + ' | ' + of(r.styles, 1) + ' | ' + of(r.motions, 2) + ' | ' + of(r.parts, 3) + ' |';
      })
    )
    .concat(['| the scene | ' + n(world.usage.total.splats) + ' | ' + world.usage.total.styles + ' | ' + world.usage.total.motions + ' | ' + world.usage.total.parts + ' |']);

// the baked file read back against the world it came from
function fileFaults(world, file) {
  const F = require('./format.cjs');
  if (!fs.existsSync(file)) return ['there is no baked file at ' + file + '; build the scene'];
  const buf = fs.readFileSync(file),
    h = F.readHeader(buf),
    f = [];
  if (buf.toString('latin1', 0, 4) !== F.MAGIC) return [file + ' is not a scene file'];
  if (buf.length !== F.layout(h).pop().at) f.push(file + ' is ' + n(buf.length) + ' bytes; its header says ' + n(F.layout(h).pop().at));
  for (const [k, v] of [['splats', world.count], ['parts', world.anim.rig.names.length], ['loop', world.loop]])
    if (h[k] !== v) f.push(file + ' has ' + v + ' ' + k + ' in the scene but ' + h[k] + ' in the file; build the scene again');
  return f;
}

// the look check and the baked file's, written to look.md; fails, naming every fault, when there is one
function check(world, out) {
  const { look, breaches, LIMITS } = require('./look.cjs'),
    L = look(world),
    faults = world.faults.concat(breaches(L), fileFaults(world, path.join(out, 'scene.bin'))),
    lines = ['# Look', '', 'The hero view at the start of the loop, ' + L.w + ' by ' + L.h + ' art pixels.', '', '| Measure | Value | Limit |', '| --- | --- | --- |'];
  if (L.character)
    lines.push('| Character height | ' + pc(L.character.share) + ' | at least ' + pc(LIMITS.character) + ' |', '| Character showing | ' + pc(L.character.shows) + ' | at least ' + pc(LIMITS.shows) + ' |');
  lines.push('| Top and what stands on it | ' + pc(L.top) + ' | at least ' + pc(LIMITS.top) + ' |', '| Largest bare patch in the front third | ' + pc(L.bare) + ' | at most ' + pc(LIMITS.bare) + ' |');
  lines.push('', '| Piece | Art pixels it adds | View |', '| --- | --- | --- |', ...L.pieces.map(r => '| ' + r.piece.who + ' | ' + r.best + ' | ' + r.view + ' |'));
  lines.push('', ...usageTable(world), '', faults.length ? '## ' + faults.length + ' faults\n\n' + faults.map(f => '- ' + f).join('\n') : 'No faults.');
  fs.mkdirSync(out, { recursive: true });
  fs.writeFileSync(path.join(out, 'look.md'), lines.join('\n') + '\n');
  console.log(lines.join('\n'));
  return faults;
}

const commands = {
  // checks the ink-studio checkout loads and draws, and installs the player's two packages
  setup() {
    const { INK, toolkit, render } = require('./ink.cjs'),
      version = JSON.parse(fs.readFileSync(path.join(INK, 'package.json'), 'utf8')).version;
    toolkit();
    console.log('ink-studio ' + version + ' at ' + INK + ' loads; its camera sees ' + ((render.FOV * 180) / Math.PI).toFixed(0) + ' degrees');
    // the browser needs only the packages' files, so no install script runs
    const npm = spawnSync('npm', ['install', '--no-audit', '--no-fund', '--ignore-scripts'], { cwd: path.join(__dirname, '..', 'player'), stdio: 'inherit' });
    if (npm.status !== 0) throw new Error('npm install in player/ failed');
    console.log('the player is ready: node player/serve.mjs <scene.bin> <still.png>');
  },

  // one piece on a stand: the scene's palette, light, camera, finish and ground, with the piece in place of one of those of its kind
  stand(piece, out, scene = EXAMPLE) {
    if (!piece || !out) throw new Error(USAGE);
    const { standSheet } = require('./draw.cjs'),
      { look, breaches } = require('./look.cjs'),
      { ONE } = require('./compose.cjs'),
      { spec, dir } = readScene(scene),
      mod = require(path.resolve(piece)),
      rel = f => path.relative(path.resolve(out), f).split(path.sep).join('/'),
      kinds = file => require(file).kind,
      pieces = spec.pieces
        .map(p => path.resolve(dir, p))
        .filter(f => ONE.includes(kinds(f)) && kinds(f) !== mod.kind)
        .concat(path.resolve(piece))
        .map(rel),
      stand = { seed: spec.seed, pieces };
    fs.mkdirSync(out, { recursive: true });
    fs.writeFileSync(path.join(out, 'stand.json'), JSON.stringify(stand, null, 2) + '\n');
    const world = step('compose', () => compose(stand, path.resolve(out))),
      p = world.pieces.find(q => q.name === rel(path.resolve(piece))),
      row = world.usage.rows.find(r => r.piece === p.name),
      ground = world.usage.rows.find(r => r.kind === 'ground').box;
    step('sheet', () => standSheet(world, row.box || ground, ground, path.join(out, 'sheet.png')));
    const L = step('look', () => look(world)),
      mine = world.faults.concat(breaches(L)).filter(f => f.startsWith(p.who)),
      adds = L.pieces.find(r => r.piece === p);
    console.log(usageTable(world).join('\n'));
    if (adds) console.log(p.who + ' adds ' + adds.best + ' art pixels at its best view (' + adds.view + ')');
    if (L.character) console.log('the character stands ' + pc(L.character.share) + ' of the hero picture, ' + pc(L.character.shows) + ' of it showing');
    console.log('wrote ' + path.join(out, 'sheet.png'));
    if (mine.length) {
      console.log('\n' + mine.length + ' faults:\n' + mine.map(f => '- ' + f).join('\n'));
      process.exitCode = 1;
    } else console.log('\nno faults name the piece');
  },

  // compose, stills, moments, bake and check, in one process
  build(scene, out) {
    if (!scene || !out) throw new Error(USAGE);
    const { stills, moments } = require('./draw.cjs'),
      { bake } = require('./bake.cjs'),
      { spec, dir } = readScene(scene),
      world = step('compose', () => compose(spec, dir));
    console.log(n(world.count) + ' splats');
    step('stills', () => stills(world, path.join(out, 'stills')));
    step('moments', () => moments(world, path.join(out, 'moments.png')));
    const { buf } = step('bake', () => bake(world));
    fs.writeFileSync(path.join(out, 'scene.bin'), buf);
    console.log('scene.bin ' + (buf.length / 1e6).toFixed(2) + ' MB');
    const faults = step('check', () => check(world, out));
    if (faults.length) process.exitCode = 1;
  },

  check(scene, out) {
    if (!scene || !out) throw new Error(USAGE);
    const { spec, dir } = readScene(scene),
      world = step('compose', () => compose(spec, dir)),
      faults = step('check', () => check(world, out));
    if (faults.length) process.exitCode = 1;
  },

  deal(folder, seed, scene) {
    if (!folder || !Number.isInteger(Number(seed)) || !scene) throw new Error(USAGE);
    const { deal } = require('./deal.cjs');
    console.log(JSON.stringify(deal(folder, Number(seed), scene), null, 2));
  }
};

const [cmd, ...args] = process.argv.slice(2);
if (!commands[cmd]) {
  console.error(USAGE);
  process.exit(1);
}
try {
  commands[cmd](...args);
} catch (e) {
  console.error(e.message);
  process.exit(1);
}
