import type {ValuePanel} from "../panel"

/** Keyfleet, Code: the commits panel. */
export const commits: ValuePanel = {
  colours: ["#4a1a08", "#f1502f", "#ffe1c9"],
  pitch: [9, 9],
  stillAt: 2,
  body: /* wgsl */ `
  let c = g.id.y - floor(t * 1.4);
  let lane = clamp(floor(x * 3.0), 0.0, 2.0);
  let onLane = 1.0 - step(0.6 / g.count.x, abs(x - (lane + 0.5) / 3.0));
  let commit = onLane * step(0.7, hash(vec2f(lane, c)));
  let span = mix(step(1.0 / 6.0, x) * step(x, 0.5), step(0.5, x) * step(x, 5.0 / 6.0), step(0.5, hash(vec2f(c, 4.0))));
  let link = step(0.86, hash(vec2f(c, 9.0))) * span * (1.0 - onLane);
  let pick = p.z * (1.0 - step(0.5, abs(lane - min(floor(p.x * 3.0), 2.0))));
  let value = max(max(onLane * (0.3 + 0.4 * pick), commit), link * 0.5);
  let tone = max(commit * (0.55 + 0.45 * hash(vec2f(c, lane + 20.0))), max(link * 0.45, onLane * (0.18 + 0.3 * pick)));
  return emit(g, length(g.local) - mix(mix(1.1, 1.7, link), 4.0, commit), ramp(tone), value);
`,
}
