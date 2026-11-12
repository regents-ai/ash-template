import type {ValuePanel} from "../panel"

/** Keyfleet, Notebooks: the cells panel. */
export const notebook: ValuePanel = {
  colours: ["#172554", "#818cf8", "#fef08a"],
  pitch: [8, 8],
  stillAt: 9,
  body: /* wgsl */ `
  let row = g.id.y;
  let slot = floor(row / 5.0);
  let part = row - slot * 5.0;
  let cursor = mix(fract(t * 0.045) * (ceil(g.count.y / 5.0) + 1.5), (1.0 - p.y) * g.count.y / 5.0, p.z);
  let done = step(slot + 0.5, floor(cursor));
  let running = 1.0 - step(0.5, abs(slot - floor(cursor)));
  let gutter = step(g.id.x, 0.5);
  let code = step(part, 2.5);
  let output = 1.0 - step(0.5, abs(part - 3.0));
  let pos = g.id.x - 2.0;
  let word = floor(pos / 4.0);
  let ink = step(0.0, pos) * step(pos, 6.0 + floor(hash(vec2f(row, 3.0)) * (g.count.x - 12.0))) * step(0.5, pos - word * 4.0) * step(0.2, hash(vec2f(word, row)));
  let sweep = step(x, fract(cursor));
  var amount = code * ink * mix(0.34, 0.6, done);
  amount = max(amount, code * ink * running * mix(0.4, 1.0, sweep));
  amount = max(amount, output * done * dith(g.id, 0.7) * 0.9 * step(1.5, g.id.x));
  amount = max(amount, gutter * code * mix(0.3, 1.0, max(done, running)));
  let tone = max(max(code * ink * (0.2 + 0.3 * done + 0.5 * running * sweep), output * done * 0.97), gutter * 0.5);
  return emit(g, sdBox(g.local, vec2f(3.2, 3.0), 0.5), ramp(tone), amount);
`,
}
