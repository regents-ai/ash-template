/* Puts one scene together from the pieces its scene file lists (references/contract.md): the ground, the things on its places and
   the character on its stage, the camera fitted to them, then the weather and the sky, with every motion made to come round in the
   loop. A piece that breaks the contract stops the build with an error naming it. One over or under its share, or outside its
   place, is named in the world's faults. */
const fs = require('node:fs');
const path = require('node:path');
const F = require('./format.cjs');
const { render } = require('./ink.cjs');
const { classify } = require('./look.cjs');

const L = 8; // the loop, in seconds
const TAU = Math.PI * 2;
const STAGE_HEIGHT = 960; // the screen height a camera's pixel size is given for
const GLASS_BEND = 6; // how far glass splats bend what lies behind them, in art pixels

const KINDS = ['palette', 'light', 'camera', 'finish', 'ground', 'sky', 'thing', 'character', 'weather'];
const ONE = ['palette', 'light', 'camera', 'finish', 'ground']; // a scene has exactly one of each
const AT_MOST_ONE = ['sky', 'character'];
const STAGED = new Set(['ground', 'thing', 'character']); // what the camera frames

// the colour roles, in the order their colours sit in the 48: the first sky colour is the backdrop, ink is the outline
const ROLES = [
  ['sky', 5], ['ink', 1], ['ground', 4], ['stone', 4], ['wood', 4], ['leaf', 5], ['water', 4],
  ['metal', 4], ['flesh', 4], ['warm', 4], ['gold', 3], ['cool', 4], ['light', 2]
];

// every place of a size: r, how far from its middle a piece may reach; h, how tall it may stand. The stage is the character's.
const SIZES = { large: { r: 1.3, h: 3.2 }, medium: { r: 0.8, h: 2.2 }, small: { r: 0.42, h: 1.4 }, stage: { r: 1.6, h: 4.0 } };
const FIT = { reach: 1.15, height: 1.1 };

// each piece's share of a scene: splats, styles, motions, moving parts; a thing's share is its size's. A share is a ceiling, and a
// piece that makes anything uses at least FLOOR of its splats.
const SHARES = {
  ground: [60000, 16, 12, 2],
  sky: [12000, 8, 10, 0],
  character: [40000, 16, 10, 8],
  weather: [10000, 6, 10, 2],
  large: [40000, 14, 12, 4],
  medium: [25000, 12, 10, 3],
  small: [10000, 8, 6, 2]
};
const FLOOR = 0.7;
const MOST = { splats: 340000, styles: 256, motions: 256 }; // what a scene file holds

// ---------------- what each kind exports, and what a ground hands back
const SLOT = { at: 'pair', turn: 'number' };
const EXPORTS = {
  palette: { kind: 'string', name: 'string', ramps: Object.fromEntries(ROLES.map(([role, n]) => [role, ['colour', n]])) },
  light: { kind: 'string', sun: 'point', amb: 'number', sky: 'number', sunK: 'number' },
  camera: { kind: 'string', yaw: 'number', pitch: 'number', dist: 'number', rise: 'number', pixel: 'number' },
  finish: { kind: 'string', outline: 'number', dither: 'number', shade: { k: 'number', range: 'number' }, grain: 'number' },
  ground: { kind: 'string', places: { stage: 'pair', large: [SLOT], medium: [SLOT], small: [SLOT] }, build: 'function' },
  sky: { kind: 'string', build: 'function' },
  thing: { kind: 'string', size: 'size', build: 'function' },
  character: { kind: 'string', build: 'function' },
  weather: { kind: 'string', build: 'function' }
};
const GROUND_HANDS_BACK = { top: 'function', radius: 'number', air: { r: 'number', y0: 'number', y1: 'number' } };

// checks a value against a shape: a type name, an object of exact keys, [shape] (a list of any length) or [shape, count]
function check(v, s, at) {
  const fail = what => {
    throw new Error(at + ' ' + what);
  };
  const num = x => typeof x === 'number' && Number.isFinite(x);
  if (Array.isArray(s)) {
    if (!Array.isArray(v) || (s[1] !== undefined && v.length !== s[1])) fail('should be a list' + (s[1] ? ' of ' + s[1] : ''));
    v.forEach((x, i) => check(x, s[0], at + '[' + i + ']'));
  } else if (typeof s === 'object') {
    if (!v || typeof v !== 'object' || Array.isArray(v)) fail('should be an object with ' + Object.keys(s).join(', '));
    for (const k of Object.keys(s)) if (!(k in v)) fail('is missing ' + k);
    for (const k of Object.keys(v)) if (!(k in s)) fail('has ' + k + ', which the contract does not have');
    for (const k of Object.keys(s)) check(v[k], s[k], at + '.' + k);
  } else if (
    s === 'number' ? !num(v)
    : s === 'point' ? !(Array.isArray(v) && v.length === 3 && v.every(num))
    : s === 'pair' ? !(Array.isArray(v) && v.length === 2 && v.every(num))
    : s === 'colour' ? !(Number.isInteger(v) && v >= 0 && v <= 0xffffff)
    : s === 'size' ? !['large', 'medium', 'small'].includes(v)
    : typeof v !== s
  )
    fail('should be ' + (s === 'size' ? "'large', 'medium' or 'small'" : 'a ' + s));
}

const fnv = str => {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) h = Math.imul(h ^ str.charCodeAt(i), 16777619) >>> 0;
  return h;
};
const add = (a, b, s = 1) => [a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const luma = c => 0.3 * ((c >> 16) & 255) + 0.55 * ((c >> 8) & 255) + 0.15 * (c & 255);

// loads one piece file, named as the scene lists it (relative to the scene file's folder), and checks what it exports
function load(dir, name) {
  const file = path.resolve(dir, name);
  if (!fs.existsSync(file)) throw new Error(name + ': no piece file at ' + file);
  const mod = require(file);
  if (!KINDS.includes(mod.kind)) throw new Error(name + ': its kind is ' + JSON.stringify(mod.kind) + '; a piece is one of ' + KINDS.join(', '));
  const who = mod.kind + ' ' + name;
  check(mod, EXPORTS[mod.kind], who + ': its exports');
  return { name, who, kind: mod.kind, mod, share: SHARES[mod.kind === 'thing' ? mod.size : mod.kind] };
}

// a place: where it stands on the ground, how big a piece on it may be ({ r, h }) and which way it faces (turn 0 faces +z)
function placeAt({ r, h }, slot, top) {
  const [x, z] = slot.at,
    y = top(x, z),
    c = Math.cos(slot.turn),
    s = Math.sin(slot.turn),
    left = [c, 0, -s],
    up = [0, 1, 0],
    forward = [s, 0, c];
  return {
    at: [x, y, z],
    r,
    h,
    turn: slot.turn,
    left,
    up,
    forward,
    ax: [left, up, forward],
    to: l => [x + left[0] * l[0] + forward[0] * l[2], y + l[1], z + left[2] * l[0] + forward[2] * l[2]],
    dir: l => {
      const d = [left[0] * l[0] + forward[0] * l[2], l[1], left[2] * l[0] + forward[2] * l[2]],
        n = Math.hypot(...d);
      return [d[0] / n, d[1] / n, d[2] / n];
    }
  };
}

// the ground's places: each on the ground and level (its height within 0.08 of its middle's at twelve points round its edge), and
// no two overlapping by more than 0.05
function checkPlaces(ground, places, top) {
  const all = [{ name: 'the stage', at: places.stage, r: SIZES.stage.r }];
  for (const size of ['large', 'medium', 'small'])
    places[size].forEach((s, k) => all.push({ name: 'the ' + size + ' place ' + (k + 1), at: s.at, r: SIZES[size].r }));
  for (const s of all) {
    const y = top(...s.at);
    for (let k = 0; k < 12; k++) {
      const a = (k / 12) * TAU;
      if (!(Math.abs(top(s.at[0] + Math.cos(a) * s.r, s.at[1] + Math.sin(a) * s.r) - y) < 0.08))
        throw new Error(ground.who + ': ' + s.name + ' is not level, or not wholly on the ground');
    }
  }
  for (let i = 0; i < all.length; i++)
    for (let j = i + 1; j < all.length; j++) {
      const gap = Math.hypot(all[i].at[0] - all[j].at[0], all[i].at[1] - all[j].at[1]) - all[i].r - all[j].r;
      if (gap < -0.05) throw new Error(ground.who + ': ' + all[i].name + ' and ' + all[j].name + ' overlap by ' + (-gap).toFixed(2));
    }
}

/* The camera's framing: it looks at the middle of the stage's box across, and up and down at the height from which it can stand
   nearest, raised by `rise` of the stage's height; it stands where the stage fills FILL of the frame at whichever of TURNS turns
   round the scene it fills most, times the camera's `dist`. */
const FILL = 0.9,
  ASPECT = 1.5,
  TURNS = 8,
  EVERY = 5; // one splat in this many is measured
function frameStage(data, count, staged, cam) {
  const lo = [Infinity, Infinity, Infinity],
    hi = [-Infinity, -Infinity, -Infinity],
    pts = [];
  for (let i = 0; i < count; i += EVERY)
    if (staged(i)) {
      const p = data.subarray(i * 16, i * 16 + 3);
      for (let k = 0; k < 3; k++) ((lo[k] = Math.min(lo[k], p[k])), (hi[k] = Math.max(hi[k], p[k])));
      pts.push([p[0], p[1], p[2]]);
    }
  const t = FILL * Math.tan(render.FOV / 2),
    n = pts.length;
  const turns = Array.from({ length: TURNS }, (_, k) => {
    const yaw = cam.yaw + (k / TURNS) * TAU,
      { pitch } = cam,
      axes = [
        [Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), Math.cos(yaw) * Math.cos(pitch)],
        [-Math.sin(yaw) * Math.sin(pitch), Math.cos(pitch), -Math.cos(yaw) * Math.sin(pitch)],
        [Math.cos(yaw), 0, -Math.sin(yaw)]
      ];
    return { axes, along: axes.map(a => Float64Array.from(pts, p => dot(a, p))) };
  });
  const fit = target => {
    let need = 0;
    for (const { axes, along } of turns) {
      const [tv, tu, tr] = axes.map(a => dot(a, target)),
        [v, u, r] = along;
      for (let i = 0; i < n; i++) need = Math.max(need, v[i] - tv + Math.max(Math.abs(u[i] - tu) / t, Math.abs(r[i] - tr) / (t * ASPECT)));
    }
    return need;
  };
  // the need is convex in the height looked at, so it is narrowed in by thirds
  const at = y => [(lo[0] + hi[0]) / 2, y, (lo[2] + hi[2]) / 2];
  let a = lo[1],
    b = hi[1];
  for (let k = 0; k < 30; k++) {
    const p = a + (b - a) / 3,
      q = b - (b - a) / 3;
    if (fit(at(p)) < fit(at(q))) b = q;
    else a = p;
  }
  const target = at((a + b) / 2 + cam.rise * (hi[1] - lo[1]));
  return { target, dist: cam.dist * fit(target) };
}

/* The hero view, as the pieces built after the framing are handed it (ctx.hero): see(p) is where p shows in the hero picture,
   [across, up] each -1 to 1 from edge to edge, and its distance in front of the camera; at([across, up], d) is the point that shows
   there at distance d. */
function heroView(cam, target, dist) {
  const view = [Math.sin(cam.yaw) * Math.cos(cam.pitch), Math.sin(cam.pitch), Math.cos(cam.yaw) * Math.cos(cam.pitch)],
    up = [-Math.sin(cam.yaw) * Math.sin(cam.pitch), Math.cos(cam.pitch), -Math.cos(cam.yaw) * Math.sin(cam.pitch)],
    right = [Math.cos(cam.yaw), 0, -Math.sin(cam.yaw)],
    eye = add(target, view, dist),
    half = Math.tan(render.FOV / 2);
  return {
    view,
    up,
    right,
    fov: render.FOV,
    aspect: ASPECT,
    target,
    dist,
    see: p => {
      const d = sub(p, eye),
        z = -dot(d, view);
      return [dot(d, right) / (z * half * ASPECT), dot(d, up) / (z * half), z];
    },
    at: ([a, b], d) => add(add(add(eye, view, -d), right, a * d * half * ASPECT), up, b * d * half)
  };
}

// every motion made to come round a whole number of times a loop: each speed snapped to its nearest whole count of cycles
function loopable(W) {
  const d = W.data;
  for (let i = 0; i < W.count; i++) {
    const q = i * 16,
      kind = Math.round(d[q + 11]) % 16,
      sp = d[q + 13],
      rg = d[q + 14];
    if (!kind || !sp) continue;
    if (F.FRACTION_KINDS.has(kind)) {
      if (rg) d[q + 13] = (rg * Math.max(1, Math.round((L * sp) / rg))) / L;
    } else d[q + 13] = (Math.sign(sp) * Math.max(1, Math.round((Math.abs(sp) * L) / TAU)) * TAU) / L;
  }
}

function compose(kit, spec, dir) {
  check(spec, { seed: 'number', pieces: ['string'] }, 'the scene');
  if (new Set(spec.pieces).size !== spec.pieces.length) throw new Error('the scene lists a piece twice');
  const all = spec.pieces.map(name => load(dir, name)),
    of = kind => all.filter(p => p.kind === kind);
  for (const k of ONE) if (of(k).length !== 1) throw new Error('a scene has exactly one ' + k + ' piece, not ' + of(k).length);
  for (const k of AT_MOST_ONE) if (of(k).length > 1) throw new Error('a scene has at most one ' + k + ' piece, not ' + of(k).length);
  const [palette, light, camera, finish, ground] = ONE.map(k => of(k)[0]),
    [sky] = of('sky'),
    [character] = of('character'),
    things = of('thing'),
    weather = of('weather'),
    cam = camera.mod,
    faults = [];
  const { makeBuilder, makeSculpt, KIT: K } = kit;

  // ---------------- the 48 colours, laid out role by role
  const hex = [],
    idx = {};
  for (const [role, n] of ROLES) {
    idx[role] = Array.from({ length: n }, (_, k) => hex.length + k);
    palette.mod.ramps[role].forEach((c, k, ramp) => {
      if (k && luma(c) <= luma(ramp[k - 1])) throw new Error(palette.who + ': its ' + role + ' ramp does not run from dark to light');
      hex.push(c);
    });
  }
  if (new Set(hex).size !== hex.length) throw new Error(palette.who + ': two of its 48 colours are the same');
  const B = makeBuilder(spec.seed, hex),
    S = K.sculpt(makeSculpt(B)),
    M = K.M;
  const pal = {
    ramp: (role, from, to) => {
      if (!idx[role]) throw new Error("there is no colour role '" + role + "'");
      return idx[role].slice(from, to);
    },
    c: (role, k = 0) => {
      const r = pal.ramp(role),
        i = r[k < 0 ? r.length + k : k];
      if (i === undefined) throw new Error('the ' + role + ' ramp has no colour ' + k);
      return i;
    },
    rgb: (role, k) => B.P[pal.c(role, k)],
    mat: (role, extra) => {
      const r = pal.ramp(role);
      return Object.assign(r.length > 2 ? { r: r.slice(0, -1), s: r.slice(1) } : { r }, extra);
    }
  };

  // ---------------- who made which splat: a piece's dabs are counted as it builds, its solids by their group numbers when baked
  const who = [],
    spans = [];
  let last = null;
  S.emit = (pr, n0, n1) => {
    if (!last || pr.g < last.g0 || pr.g >= last.g1) last = spans.find(s => pr.g >= s.g0 && pr.g < s.g1);
    if (!last) throw new Error('a solid that no piece made was baked');
    for (let i = n0; i < n1; i++) who[i] = last.p;
  };
  const rig = K.rig(B, S);
  let bakingPart = 0;
  rig.resolve = () => bakingPart;
  // runs a piece's drawing (its build, then each of its parts), its randomness seeded by the scene's seed, the piece and the run
  const run = (p, fn) => {
    B.reseed(fnv(spec.seed + ' ' + p.name + ' ' + spans.filter(s => s.p === p).length));
    const g0 = S.grp(0).g,
      n0 = B.count();
    let out;
    try {
      out = fn();
    } catch (e) {
      if (!e.message.startsWith(p.who)) e.message = p.who + ': ' + e.message;
      throw e;
    }
    for (let i = n0; i < B.count(); i++) who[i] = p;
    spans.push({ p, g0, g1: S.grp(0).g });
    return out;
  };

  // ---------------- moving parts: built after the still world is baked, each baked on its own, moved by a turn about its pivot
  const ZERO = [0, 0, 0],
    handles = [],
    loops = [];
  const makePart = (p, name, build, o) => {
    check(o, o && o.parent ? { pivot: 'point', parent: 'object' } : { pivot: 'point' }, p.who + ": part '" + name + "' options");
    if (o.parent && !handles.includes(o.parent)) throw new Error(p.who + ": part '" + name + "' has a parent that is not a part");
    const h = {
      p,
      id: rig.part(p.name + ' ' + name),
      parent: o.parent || null,
      pivot: o.pivot,
      build,
      A: M.id(),
      s: ZERO,
      set(A, shift = ZERO) {
        h.A = A;
        h.s = shift;
      }
    };
    handles.push(h);
    return h;
  };
  let hero = null;
  const ctxFor = (p, extra) =>
    Object.assign(
      {
        K,
        B,
        S,
        M,
        TAU,
        L,
        pal,
        share: { splats: p.share[0], styles: p.share[1], motions: p.share[2], parts: p.share[3] },
        view: S.view,
        along: d => {
          const v = K.V.norm(d),
            u = K.V.perp(v);
          return [u, v, K.V.cross(u, v)];
        },
        part: (name, build, o) => makePart(p, name, build, o),
        loop: fn => loops.push({ p, fn })
      },
      hero && { hero },
      extra
    );
  const build = (p, args, extra) => run(p, () => p.mod.build(ctxFor(p, extra), ...args));
  let baked = 0;
  const bakeAll = () => {
    bakingPart = 0;
    S.bake();
    for (; baked < handles.length; baked++) {
      const h = handles[baked];
      run(h.p, () => rig.own(h.id, h.build));
      bakingPart = h.id;
      S.bake();
    }
  };

  // ---------------- light, finish and the camera's direction, before anything is baked
  S.sun = B.norm(light.mod.sun);
  S.amb = light.mod.amb;
  S.sky = light.mod.sky;
  S.sunK = light.mod.sunK;
  S.wob = finish.mod.grain;
  S.view = [Math.sin(cam.yaw) * Math.cos(cam.pitch), Math.sin(cam.pitch), Math.cos(cam.yaw) * Math.cos(cam.pitch)];

  // ---------------- the stage: the ground, each thing on the next free place of its size, the character on the stage
  const places = ground.mod.places,
    free = { large: places.large.slice(), medium: places.medium.slice(), small: places.small.slice() },
    slots = things.map(p => {
      const slot = free[p.mod.size].shift();
      if (!slot) throw new Error(p.who + ': no ' + p.mod.size + ' place is left for it; the ground has ' + places[p.mod.size].length);
      return slot;
    }),
    stage = { at: places.stage, turn: cam.yaw },
    // where a thing stands, its place's whole reach; the stage stays open ground, which the character walks through
    taken = (x, z) => things.some((p, k) => Math.hypot(x - slots[k].at[0], z - slots[k].at[1]) < SIZES[p.mod.size].r);
  const g = build(ground, [], { taken });
  check(g, GROUND_HANDS_BACK, ground.who + ': what it hands back');
  checkPlaces(ground, places, g.top);
  things.forEach((p, k) => {
    p.place = placeAt(SIZES[p.mod.size], slots[k], g.top);
    build(p, [p.place]);
  });
  if (character) {
    character.place = placeAt(SIZES.stage, stage, g.top);
    build(character, [character.place]);
  }
  bakeAll();

  // ---------------- the hero camera, fitted to the stage; then the weather and the sky, handed its view
  const sofar = B.finish({}),
    { target, dist } = frameStage(sofar.data, sofar.count, i => STAGED.has(who[i].kind), cam);
  hero = heroView(cam, target, dist);
  for (const p of weather) build(p, [g.air]);
  bakeAll();
  let fog = { c: idx.sky[0], start: 1, max: 0 };
  if (sky) {
    build(sky, [{ r0: 30, r1: 46, sun: S.sun, sunK: S.sunK }], { fog: (k, start, max) => (fog = { c: pal.c('sky', k), start, max }) });
    bakeAll();
  }

  // ---------------- the finished world: its art pixels a fixed size on the stage, every motion closing in the loop
  const W = B.finish({
    dither: finish.mod.dither,
    radius: g.radius * 1.7,
    palName: palette.mod.name,
    fog,
    outline: { c: idx.ink[0], edge: finish.mod.outline },
    ao: finish.mod.shade,
    refract: GLASS_BEND
  });
  W.loop = L;
  W.cam = { target, dist, pitch: cam.pitch, yaw: cam.yaw };
  W.detail = STAGE_HEIGHT / (2 * Math.tan(render.FOV / 2) * cam.pixel * dist);
  W.who = who.slice(0, W.count);
  W.groups = classify(W.data, W.count, W.who, g.top, taken, cam.yaw);
  loopable(W);
  const st = K.stage(W);
  rig.bind(st);

  // ---------------- the loop: every piece sets the turns of its parts, then the parts are carried, parents first
  const reset = () => {
    for (const h of handles) {
      h.A = M.id();
      h.s = ZERO;
    }
  };
  const frame = t => {
    reset();
    for (const l of loops) l.fn(t, (TAU * t) / L);
    for (const h of handles) {
      if (!h.parent) rig.set(h.id, h.A, h.pivot, add(h.pivot, h.s));
      else {
        const k = h.parent.id * 12;
        rig.set(h.id, M.mul(Array.from(rig.M.subarray(k, k + 9)), h.A), h.pivot, rig.at(h.parent.id, add(h.pivot, h.s)));
      }
    }
    rig.apply();
  };
  for (const l of loops) {
    const pose = t => {
      reset();
      l.fn(t, (TAU * t) / L);
      return handles.flatMap(h => h.A.concat(h.s));
    };
    const a = pose(1.37),
      b = pose(1.37 + L);
    if (a.some((v, i) => !(Math.abs(v - b[i]) < 1e-6))) throw new Error(l.p.who + ': a part it moves is not back where it began after ' + L + ' seconds');
  }
  st.add({ update: (dt, t) => frame(t) });

  W.usage = measure(W, rig, all, handles, faults);
  W.pieces = all;
  W.faults = faults;
  W.clock = 0;
  st.update(0, 0);
  return W;
}

/* What each piece costs against its share, checked splat by splat: a splat the scene file cannot carry stops the build, naming its
   piece. A piece over its share, under its floor or outside its place is a fault, and so is a scene past what a file holds. */
function measure(W, rig, all, handles, faults) {
  const D = W.data,
    use = new Map(all.map(p => [p, { splats: 0, styles: new Set(), motions: new Set(), lo: [Infinity, Infinity, Infinity], hi: [-Infinity, -Infinity, -Infinity], reach: 0 }]));
  for (let i = 0; i < W.count; i++) {
    const p = W.who[i];
    if (!p) throw new Error('splat ' + i + ' was made by no piece');
    const u = use.get(p),
      o = i * 16,
      kraw = Math.round(D[o + 11]),
      kind = kraw % 16,
      [ph, sp, rg, ex] = D.subarray(o + 12, o + 16),
      fail = what => {
        throw new Error(p.who + ': ' + what);
      };
    if (kraw & ~F.KRAW_KNOWN || !F.KINDS.has(kind)) fail('makes a splat with a kind or flag the scene file cannot carry (' + kraw + ')');
    if (D[o + 1] < -30) fail('makes a splat below y -30, where the toolkit hides splats');
    u.splats++;
    for (let k = 0; k < 3; k++) ((u.lo[k] = Math.min(u.lo[k], D[o + k])), (u.hi[k] = Math.max(u.hi[k], D[o + k])));
    if (p.place) u.reach = Math.max(u.reach, Math.hypot(D[o] - p.place.at[0], D[o + 2] - p.place.at[2]));
    u.styles.add(D[o + 3] + ' ' + kraw + ' ' + rig.bid[i]);
    if (kind) {
      const cycles = Math.round(F.FRACTION_KINDS.has(kind) ? (sp * L) / rg : (sp * L) / TAU);
      if (Math.fround(F.speed(kind, cycles, rg, L)) !== sp) fail('makes a splat whose motion is not a whole number of cycles a loop');
      if (kind === 11 && cycles % 10) fail('makes a swaying splat with ' + cycles + ' cycles a loop; a sway closes only at a multiple of 10');
      if (F.FRACTION_KINDS.has(kind) && !(ph >= 0 && ph < 1)) fail('makes a falling or rising splat whose phase is outside 0 to 1');
      u.motions.add(rg + ' ' + ex);
    }
  }
  const KEYS = ['splats', 'styles', 'motions', 'parts'],
    n = x => x.toLocaleString('en');
  const rows = all.map(p => {
    const u = use.get(p),
      row = {
        piece: p.name,
        kind: p.kind,
        box: u.splats ? { lo: u.lo, hi: u.hi } : null,
        splats: u.splats,
        styles: u.styles.size,
        motions: u.motions.size,
        parts: handles.filter(h => h.p === p).length,
        share: p.share
      };
    if (!p.share) return row;
    const over = KEYS.filter((k, j) => row[k] > p.share[j]);
    if (over.length) faults.push(p.who + ': over its share in ' + over.map(k => k + ' (' + n(row[k]) + ' of ' + n(p.share[KEYS.indexOf(k)]) + ')').join(', '));
    if (row.splats < FLOOR * p.share[0]) faults.push(p.who + ': uses ' + n(row.splats) + ' of its ' + n(p.share[0]) + ' splats, under ' + FLOOR * 100 + '%');
    if (p.place && row.splats) {
      if (u.reach > FIT.reach * p.place.r) faults.push(p.who + ': reaches ' + u.reach.toFixed(2) + ' from the middle of its place, whose reach is ' + p.place.r);
      if (u.hi[1] - p.place.at[1] > FIT.height * p.place.h) faults.push(p.who + ': stands ' + (u.hi[1] - p.place.at[1]).toFixed(2) + ' tall on its place, whose height is ' + p.place.h);
    }
    return row;
  });
  const values = [...use.values()],
    total = {
      splats: W.count,
      styles: new Set(values.flatMap(u => [...u.styles])).size,
      motions: new Set(values.flatMap(u => [...u.motions])).size,
      parts: handles.length
    };
  for (const k of Object.keys(MOST)) if (total[k] > MOST[k]) faults.push('the scene has ' + n(total[k]) + ' ' + k + '; a scene file holds at most ' + n(MOST[k]));
  return { rows, total };
}

module.exports = { compose, KINDS, ONE, AT_MOST_ONE, SIZES };
