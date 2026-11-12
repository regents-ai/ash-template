import type {ValuePanel} from "../panel"

/** Techtree, Signed bundles: the seal panel. */
export const seal: ValuePanel = {
  colours: ["#2a1466", "#c264ff", "#ffe1f4"],
  pitch: [9, 9],
  stillAt: 6.4,
  body: /* wgsl */ `
  let e = min(min(g.id.x, g.count.x - 1.0 - g.id.x), min(g.id.y, g.count.y - 1.0 - g.id.y));
  let ringNo = floor(e / 2.0);
  let visible = 1.0 - (e - ringNo * 2.0);
  let rings = floor((min(g.count.x, g.count.y) - 1.0) * 0.25) + 1.0;
  let q = (g.at - vec2f(0.5)) * aspect();
  let turn = fract(atan2(q.x, q.y) / TAU + 1.0);
  let towards = 1.0 - max(abs(p.x - 0.5), abs(p.y - 0.5)) * 2.0;
  let prog = mix(fract(t * 0.07) * (rings + 1.6), towards * (rings + 0.6) + 0.4, p.z);
  let sealed = step(ringNo + 1.0, prog);
  let drawing = step(ringNo, prog) * (1.0 - sealed) * step(turn, fract(prog));
  let tip = drawing * exp(-sq((fract(prog) - turn) * 9.0));
  let all = step(rings, prog);
  let tone = 0.1 + 0.55 * ringNo / max(rings - 1.0, 1.0) + 0.35 * tip + 0.25 * all;
  return emit(g, sdBox(g.local, vec2f(3.3, 3.3), 0.5), ramp(tone), visible * (0.1 + 0.86 * max(sealed, drawing)));
`,
}
