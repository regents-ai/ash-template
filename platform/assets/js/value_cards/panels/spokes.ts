import type {ValuePanel} from "../panel"

/** Keyfleet, Daily share: the spokes panel. */
export const spokes: ValuePanel = {
  colours: ["#0d3b2e", "#2ee6a6", "#f2fff0"],
  pitch: [9, 9],
  stillAt: 5.2,
  body: /* wgsl */ `
  let q = (g.at - mix(vec2f(0.5), p.xy, p.z * 0.5)) * aspect();
  let r = length(q);
  let side = abs(fract((atan2(q.y, q.x) / TAU + 0.5) * 12.0) - 0.5) / 12.0 * TAU * r;
  let cycle = fract(t * 0.11);
  let wave = exp(-sq((r - cycle * 0.5) * 14.0));
  let core = exp(-sq(r * 9.0)) * (1.0 - 0.5 * cycle);
  let spoke = (1.0 - smoothstep(0.015, 0.03, side)) * step(r, 0.35) * (0.2 + 0.8 * wave);
  let keys = exp(-sq((r - 0.39) * 22.0)) * (1.0 - smoothstep(0.03, 0.055, side)) * (0.3 + 0.7 * exp(-fract(cycle - 0.78) * 3.0));
  let value = max(max(core, spoke), keys);
  return emit(g, length(g.local) - mix(0.9, 4.0, value), ramp(0.08 + 0.92 * value), value);
`,
}
