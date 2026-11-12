import type {ValuePanel} from "../panel"

/** Autolaunch, Staking: the rain panel. */
export const rain: ValuePanel = {
  colours: ["#1d1a7a", "#3aa0ff", "#e3f3ff"],
  pitch: [9, 9],
  stillAt: 4,
  body: /* wgsl */ `
  let col = g.id.x;
  let speed = 0.16 + 0.22 * hash(vec2f(col, 1.0));
  let wet = step(0.38, hash(vec2f(col, 5.0)));
  let head = 1.15 - fract(t * speed + hash(vec2f(col, 2.0))) * 1.5;
  let pool = 0.15 + 0.035 * sin(x * 9.0 + t * 1.2) + 0.02 * sin(x * 23.0 - t * 2.0) + 0.26 * exp(-sq((x - p.x) * 4.5)) * p.z;
  let inPool = step(y, pool);
  let streak = (1.0 - sat((y - head) / 0.34)) * step(head, y) * wet * (1.0 - inPool);
  let top = 1.0 - smoothstep(0.0, 0.08, pool - y);
  let value = max(streak, inPool * (0.55 + 0.45 * top));
  let tone = mix(0.15 + 0.8 * streak, 0.3 + 0.7 * top, inPool);
  return emit(g, length(g.local) - mix(1.0, 3.7, value), ramp(tone), value);
`,
}
