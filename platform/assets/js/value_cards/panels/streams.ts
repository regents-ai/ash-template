import type {ValuePanel} from "../panel"

/** $REGENT, Revenue: the streams panel. */
export const streams: ValuePanel = {
  colours: ["#5a0f3c", "#ff5fa2", "#ffe9a8"],
  pitch: [9, 9],
  stillAt: 2,
  body: /* wgsl */ `
  let cx = mix(0.5 + 0.1 * sin(t * 0.3), p.x, p.z);
  let spread = 0.1 + 0.9 * smoothstep(0.08, 0.95, y);
  let w = 0.5 + (x - cx) / spread;
  let lane = floor(w * 5.0);
  let on = step(abs(fract(w * 5.0) - 0.5), 0.16 + 0.3 * (1.0 - spread)) * step(0.0, w) * step(w, 1.0);
  let dash = smoothstep(0.35, 0.65, fract(y * 5.0 + t * 0.7 + lane * 0.37));
  let pool = exp(-sq((x - cx) * 7.0)) * (1.0 - smoothstep(0.04, 0.14, y));
  let value = max(on * (0.25 + 0.75 * dash) * (0.45 + 0.55 * (1.0 - y)), pool);
  return emit(g, length(g.local) - mix(0.9, 4.0, value), ramp(0.08 + 0.6 * value + 0.32 * (1.0 - y) * on), value);
`,
}
