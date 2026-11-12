import type {ValuePanel} from "../panel"

/** Patchbay, Reports: the glitch panel. */
export const glitch: ValuePanel = {
  colours: ["#2a1a8a", "#ff3fd0", "#ffe3fa"],
  pitch: [12, 7],
  stillAt: 2.3,
  body: /* wgsl */ `
  let row = g.id.y;
  let tear = mix(0.5 + 0.3 * sin(t * 0.37), p.y, p.z);
  let inBand = 1.0 - smoothstep(0.08, 0.13, abs(y - tear));
  let tick = floor(t * 6.0);
  let xs = x + (hash(vec2f(row, tick)) - 0.5) * 0.7 * inBand;
  let v = 0.5 + 0.5 * sin(xs * TAU * 1.5 - t * 0.6);
  let drop = step(0.7, hash(vec2f(floor(xs * g.count.x * 0.5), row + tick * 3.0))) * inBand;
  let spark = step(0.86, hash(vec2f(g.id.x + tick, row))) * inBand;
  let tone = mix(0.04 + 0.5 * v, 0.5 + 0.4 * hash(vec2f(row, tick + 9.0)), inBand);
  return emit(g, sdBox(g.local, vec2f(5.2, 2.3), 0.5), mix(ramp(tone), params.c.rgb, spark), max((0.2 + 0.7 * v) * (1.0 - drop), spark));
`,
}
