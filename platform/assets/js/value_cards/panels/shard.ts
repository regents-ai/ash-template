import type {ValuePanel} from "../panel"

/** Keyfleet, Shards: the shard panel. */
export const shard: ValuePanel = {
  colours: ["#2a0a4a", "#b388ff", "#e6fff9"],
  pitch: [8, 8],
  stillAt: 3.2,
  body: /* wgsl */ `
  let q = (g.at - vec2f(0.5)) * aspect();
  let n = vec2f(0.8, 0.6);
  let pull = sat(dot((p.xy - vec2f(0.5)) * aspect(), n) * 3.0);
  let away = mix(0.5 - 0.5 * cos(t * 0.5), pull, p.z) * 0.2;
  let body = step(abs(q.x) + abs(q.y), 0.36) * step(dot(q, n), 0.118);
  let qs = q - n * away;
  let piece = step(abs(qs.x) + abs(qs.y), 0.36) * step(0.142, dot(qs, n));
  let facet = 0.5 + 0.5 * sin((q.x - q.y) * 14.0 + t * 0.6);
  let amount = max(body * (0.5 + 0.3 * facet), piece * 0.96);
  return emit(g, sdBox(g.local, vec2f(3.1, 3.1), 0.4), ramp(max(body * (0.15 + 0.4 * facet), piece * (0.7 + 1.5 * away))), amount);
`,
}
