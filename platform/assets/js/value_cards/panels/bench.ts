import type {ValuePanel} from "../panel"

/** Patchbay, Wallet Bench: the nine panel. */
export const bench: ValuePanel = {
  colours: ["#5a1a5a", "#ff6b9d", "#ffe9c7"],
  pitch: [8, 8],
  stillAt: 5.6,
  body: /* wgsl */ `
  let tq = g.at * 3.0;
  let ti = min(floor(tq), vec2f(2.0));
  let tf = tq - ti;
  let pad = 0.09;
  let inTile = step(pad, tf.x) * step(tf.x, 1.0 - pad) * step(pad, tf.y) * step(tf.y, 1.0 - pad);
  let k = ti.x + (2.0 - ti.y) * 3.0;
  let cursor = fract(t * 0.085) * 11.0;
  let pk = min(floor(p.x * 3.0), 2.0) + (2.0 - min(floor(p.y * 3.0), 2.0)) * 3.0;
  let over = p.z * (1.0 - step(0.5, abs(k - pk)));
  let done = step(k + 1.0, cursor);
  let running = step(k, cursor) * (1.0 - done);
  let fill = step((tf.y - pad) / (1.0 - 2.0 * pad), fract(cursor));
  let result = 0.45 + 0.55 * hash(vec2f(k, 4.0));
  var amount = 0.2 * dith(g.id, 0.3);
  amount = mix(amount, 0.16 + 0.8 * fill, running);
  amount = mix(amount, 0.22 + 0.7 * dith(g.id, result), done);
  amount = max(amount, over * 0.96);
  var tone = mix(0.1, 0.2 + 0.5 * result, done);
  tone = mix(tone, 0.5 + 0.4 * fill, running);
  tone = mix(tone, 1.0, over);
  return emit(g, mix(9.0, sdBox(g.local, vec2f(3.1, 3.1), 0.6), inTile), ramp(tone), amount);
`,
}
