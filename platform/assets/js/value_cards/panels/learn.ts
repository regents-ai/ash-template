import type {ValuePanel} from "../panel"

/** Techtree, RL training: the curve panel. */
export const learn: ValuePanel = {
  colours: ["#06324a", "#22c1c3", "#fdbb2d"],
  pitch: [8, 8],
  stillAt: 12,
  body: /* wgsl */ `
  let lap = t * 0.06;
  let shown = step(x, mix(fract(lap) * 1.3, 1.0, p.z));
  let curve = 0.12 + 0.72 * (1.0 - exp(-x * 3.2));
  let sample = curve + (hash(vec2f(g.id.x, floor(lap))) - 0.5) * 0.44 * (1.0 - 0.75 * x);
  let rowH = 1.0 / g.count.y;
  let point = 1.0 - step(rowH * 0.6, abs(y - sample));
  let mean = 1.0 - step(rowH * 0.6, abs(y - curve));
  let under = step(y, curve) * dith(g.id, 0.16 + 0.3 * x);
  let mark = p.z * (1.0 - step(0.6 / g.count.x, abs(x - p.x)));
  let value = max(shown * max(max(point, mean * 0.55), under * 0.3), mark * 0.5);
  let tone = shown * max(point, max(mean * 0.5, under * (0.1 + 0.35 * y / curve)));
  return emit(g, length(g.local) - mix(0.9, 3.6, value), ramp(max(tone, mark * 0.6)), value);
`,
}
