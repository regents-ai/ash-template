import type {ValuePanel} from "../panel"

/** Techtree, Task collections: the freeze panel. */
export const freeze: ValuePanel = {
  colours: ["#0c2d57", "#7cc7ff", "#ffffff"],
  pitch: [8, 8],
  stillAt: 6,
  body: /* wgsl */ `
  let front = (1.0 - abs(fract(t * 0.05) * 2.0 - 1.0)) * 1.5 - 0.2;
  let order = x * 0.6 + (1.0 - y) * 0.4 + 0.08 * hash(g.id);
  let frozen = max(step(order, front), p.z * step(length((g.at - p.xy) * aspect()), 0.22));
  let edge = exp(-sq((front - order) * 9.0)) * step(order, front);
  let loose = step(0.55, hash(g.id + vec2f(floor(t * 7.0), 3.0)));
  let fixed = dith(g.id, 0.25 + 0.6 * noise(g.id * 0.21));
  let amount = max(mix(loose * 0.4, fixed * 0.78, frozen), edge);
  return emit(g, sdBox(g.local, vec2f(3.0, 3.0), 0.5), ramp(mix(0.08, 0.45, frozen) + 0.55 * edge), amount);
`,
}
