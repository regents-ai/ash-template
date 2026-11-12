import type {ValuePanel} from "../panel"

/** WebMCP, Page scope: the pages panel. */
export const scope: ValuePanel = {
  colours: ["#3b1a00", "#ff8c42", "#fff0df"],
  pitch: [9, 9],
  stillAt: 2,
  body: /* wgsl */ `
  let tq = g.at * 2.0;
  let ti = min(floor(tq), vec2f(1.0));
  let tf = tq - ti;
  let pad = 0.08;
  let inTile = step(pad, tf.x) * step(tf.x, 1.0 - pad) * step(pad, tf.y) * step(tf.y, 1.0 - pad);
  let k = ti.x + ti.y * 2.0;
  let mine = min(floor(p.x * 2.0), 1.0) + min(floor(p.y * 2.0), 1.0) * 2.0;
  let front = select(floor(fract(t * 0.07) * 4.0), mine, p.z > 0.5);
  let live = 1.0 - step(0.5, abs(k - front));
  let wave = 0.5 + 0.5 * sin(length((tf - vec2f(0.5)) * aspect()) * 20.0 - t * 2.5);
  var d = sdBox(g.local, vec2f(3.2, 3.2), 0.5);
  if (k > 0.5) { d = length(g.local) - 3.4; }
  if (k > 1.5) { d = sdDiamond(g.local, 4.2); }
  if (k > 2.5) { d = sdPlus(g.local, 3.6, 1.0); }
  return emit(g, mix(9.0, d, inTile), ramp(mix(0.12, 0.35 + 0.65 * wave, live)), mix(0.22, 0.45 + 0.55 * wave, live));
`,
}
