/* The look check, counted on the pictures the stills draw: the same seven views, the same moment, 1440 by 960 screen pixels, in art
   pixels. A piece is lifted out by making its splats empty and drawing again; the art pixels that change are what it adds. classify
   marks, on the world at rest, which splats lie on the ground's top and which stand on it. */
const { render: R, at } = require('./ink.cjs');

const TAU = Math.PI * 2;
const SIZE = { w: 1440, h: 960 };
const EPS = 0.05; // a splat this close to the ground's top at its x, z lies on it; a blade of grass stands above it
const GLASS = 256; // the glass flag in a splat's kind-and-flags number
const STAGED = new Set(['ground', 'thing', 'character']);
const LIMITS = {
  character: 0.3, // the character's height, as a share of the hero picture's height, at least
  seen: 200, // art pixels a piece adds at its best view, at least
  top: 0.5, // the ground's top and what stands on it, as a share of the hero picture's height, at least
  bare: 0.07, // the side of the largest bare square in the front third of the top, as a share of the picture's height, at most
  shows: 0.7 // the share of the character's own pixels that show with every other piece in place, at least
};

/* skin: the ground's own splats within EPS of its top (not glass), outside the places things stand on (taken); front: the third of
   the skin nearest the hero camera, whose direction is yaw; ontop: every staged splat at or above the top where it stands (not glass). */
function classify(data, count, who, top, taken, yaw) {
  const skin = new Uint8Array(count),
    front = new Uint8Array(count),
    ontop = new Uint8Array(count),
    along = new Float32Array(count);
  let lo = Infinity,
    hi = -Infinity;
  for (let i = 0, o = 0; i < count; i++, o += 16) {
    const kind = who[i].kind;
    if (!STAGED.has(kind) || Math.round(data[o + 11]) & GLASS) continue;
    const t = top(data[o], data[o + 2]);
    if (!(t > -Infinity)) continue;
    const y = data[o + 1];
    if (y >= t - EPS) ontop[i] = 1;
    if (kind === 'ground' && Math.abs(y - t) <= EPS && !taken(data[o], data[o + 2])) {
      skin[i] = 1;
      along[i] = data[o] * Math.sin(yaw) + data[o + 2] * Math.cos(yaw);
      lo = Math.min(lo, along[i]);
      hi = Math.max(hi, along[i]);
    }
  }
  const cut = lo + ((hi - lo) * 2) / 3;
  for (let i = 0; i < count; i++) if (skin[i] && along[i] >= cut) front[i] = 1;
  return { skin, front, ontop };
}

// the seven views the stills draw, as [yaw, pitch]
const views = cam => ({
  hero: [cam.yaw, cam.pitch],
  '000': [0, cam.pitch],
  '090': [TAU / 4, cam.pitch],
  '180': [TAU / 2, cam.pitch],
  '270': [(TAU * 3) / 4, cam.pitch],
  above: [cam.yaw, 1.12],
  below: [cam.yaw, -0.55]
});

// draws one world again and again from a view, with only the splats keep(i) says (every splat when keep is left out)
function drawer(world) {
  const D = world.data,
    N = world.count,
    alpha = Float32Array.from({ length: N }, (_, i) => D[i * 16 + 3]),
    at = views(world.cam);
  return (view, keep) => {
    if (keep) for (let i = 0; i < N; i++) D[i * 16 + 3] = keep(i) ? alpha[i] : 0;
    const [yaw, pitch] = at[view],
      im = R.render(world, Object.assign({ yaw, pitch, t: world.clock }, SIZE));
    if (keep) for (let i = 0; i < N; i++) D[i * 16 + 3] = alpha[i];
    return im;
  };
}

// the art pixels that differ between two pictures of one view, as a mask
const differ = (a, b) => {
  const m = new Uint8Array(a.w * a.h);
  for (let p = 0, q = 0; p < m.length; p++, q += 3) m[p] = a.rgb[q] !== b.rgb[q] || a.rgb[q + 1] !== b.rgb[q + 1] || a.rgb[q + 2] !== b.rgb[q + 2] ? 1 : 0;
  return m;
};
const sum = m => m.reduce((a, v) => a + v, 0);
// the rows a mask spans, top to bottom, as a share of the picture's height
const rows = (m, w, h) => {
  let lo = h,
    hi = -1;
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++)
      if (m[y * w + x]) {
        lo = Math.min(lo, y);
        hi = y;
        break;
      }
  return hi < 0 ? 0 : (hi - lo + 1) / h;
};
// the side of the largest square whose every pixel is in the mask
const largestSquare = (m, w, h) => {
  const s = new Uint16Array(w * h);
  let best = 0;
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      const p = y * w + x;
      if (!m[p]) continue;
      s[p] = x && y ? 1 + Math.min(s[p - 1], s[p - w], s[p - w - 1]) : 1;
      best = Math.max(best, s[p]);
    }
  return best;
};

/* The look in the hero view: the character's height and how much of it shows (and, when too little does, who hides it), the share
   of the picture the ground's top and what stands on it take, the largest bare patch in the front third of the top, and what every
   piece adds, in the hero view or, under the limit there, at its best view. */
function look(world) {
  at(world, 0);
  const { who, pieces } = world,
    { skin, front, ontop } = world.groups,
    pic = drawer(world),
    full = pic('hero'),
    { w, h } = full,
    empty = pic('hero', () => false),
    alone = keep => differ(pic('hero', keep), empty),
    character = pieces.find(p => p.kind === 'character'),
    out = { w, h, ground: pieces.find(p => p.kind === 'ground'), pieces: [] };

  // a pixel of the character is hidden where the picture is what it would be without it, though it alone shows something else there
  if (character) {
    const mine = i => who[i] === character,
      solo = pic('hero', mine),
      own = differ(solo, empty),
      shown = differ(pic('hero', i => !mine(i)), full),
      apart = differ(solo, pic('hero', i => !mine(i))),
      ownN = sum(own);
    let shows = 0;
    for (let p = 0; p < own.length; p++) if (own[p] && (shown[p] || !apart[p])) shows++;
    out.character = { piece: character, share: rows(own, w, h), shows: ownN ? shows / ownN : 0, hiddenBy: [] };
    if (out.character.shows < LIMITS.shows)
      for (const p of pieces) {
        if (p === character) continue;
        const it = pic('hero', i => who[i] === p),
          adds = differ(pic('hero', i => mine(i) || who[i] === p), it),
          off = differ(solo, it);
        let n = 0;
        for (let q = 0; q < own.length; q++) if (own[q] && !adds[q] && off[q]) n++;
        if (n) out.character.hiddenBy.push({ piece: p, share: n / ownN });
      }
  }
  out.top = rows(alone(i => ontop[i]), w, h);
  const region = alone(i => front[i]),
    bare = differ(pic('hero', i => !skin[i]), full);
  for (let p = 0; p < bare.length; p++) bare[p] &= region[p];
  out.bare = largestSquare(bare, w, h) / h;

  const fulls = { hero: full },
    names = Object.keys(views(world.cam));
  for (const p of pieces) {
    if (!world.usage.rows.find(r => r.piece === p.name).splats) continue;
    const lifted = i => who[i] !== p,
      r = { piece: p, view: 'hero', best: sum(differ(pic('hero', lifted), full)) };
    for (const view of names.slice(1)) {
      if (r.best >= LIMITS.seen) break;
      const n = sum(differ(pic(view, lifted), (fulls[view] = fulls[view] || pic(view))));
      if (n > r.best) Object.assign(r, { view, best: n });
    }
    out.pieces.push(r);
  }
  return out;
}

// the rules a look breaks, one line each, naming the piece where there is one
function breaches(L) {
  const f = [],
    pc = x => Math.round(x * 100) + '%';
  if (L.character && L.character.share < LIMITS.character)
    f.push(L.character.piece.who + ": stands " + pc(L.character.share) + " of the hero picture's height, under " + pc(LIMITS.character));
  for (const r of L.pieces) if (r.best < LIMITS.seen) f.push(r.piece.who + ': adds ' + r.best + ' art pixels at its best view (' + r.view + '), under ' + LIMITS.seen);
  if (L.top < LIMITS.top) f.push(L.ground.who + ': its top and what stands on it take ' + pc(L.top) + " of the hero picture's height, under " + pc(LIMITS.top));
  if (L.bare > LIMITS.bare) f.push(L.ground.who + ': a bare patch ' + pc(L.bare) + " of the picture's height across in the front third of its top, over " + pc(LIMITS.bare));
  if (L.character && L.character.shows < LIMITS.shows)
    f.push(
      L.character.piece.who + ': ' + pc(L.character.shows) + ' of it shows, under ' + pc(LIMITS.shows) + '; hidden by ' +
        (L.character.hiddenBy.sort((a, b) => b.share - a.share).map(({ piece, share }) => piece.who + ' ' + pc(share)).join(', ') || 'nothing alone')
    );
  return f;
}

module.exports = { classify, views, look, breaches, LIMITS, SIZE };
