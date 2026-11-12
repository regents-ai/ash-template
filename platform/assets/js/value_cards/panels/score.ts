import type {ValuePanel} from "../panel"

/** Techtree, Verifier: the score panel. */
export const score: ValuePanel = {
  colours: ["#4a1055", "#e056fd", "#ffe66d"],
  pitch: [10, 12],
  stillAt: 4,
  body: /* wgsl */ `
  let row = g.id.y;
  let run = t * (0.1 + 0.08 * hash(vec2f(row, 1.0))) + hash(vec2f(row, 2.0));
  let episode = floor(run);
  let head = fract(run) * 1.25;
  let zone = step(1.0 - 3.5 / g.count.x, x);
  let behind = head - x;
  let trail = step(0.0, behind) * exp(-behind * 6.0) * (1.0 - zone);
  let score = mix(hash(vec2f(row, episode + 39.0)), hash(vec2f(row, episode + 40.0)), step(1.0, head));
  let pick = p.z * exp(-sq((y - p.y) * g.count.y * 0.6));
  let amount = max(trail * 0.9 + 0.12 * (1.0 - zone) + 0.3 * pick * (1.0 - zone), zone * (0.3 + 0.7 * score));
  return emit(g, sdBox(g.local, vec2f(3.6, 4.2), 1.0), ramp(mix(0.12 + 0.45 * trail + 0.2 * pick, 0.15 + 0.85 * score, zone)), amount);
`,
}
