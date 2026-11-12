import type {ValuePanel} from "../panel"

/** Autolaunch, Agent launch: the chevron panel. */
export const chevron: ValuePanel = {
  colours: ["#3d0f6b", "#ff3355", "#ffd9df"],
  pitch: [10, 10],
  stillAt: 2,
  body: /* wgsl */ `
  let dx = x - mix(0.5 + 0.05 * sin(t * 0.4), p.x, p.z);
  let rise = fract((y + abs(dx) * 0.95) * 2.2 - t * 0.42);
  let value = smoothstep(0.45, 0.92, rise) * (0.35 + 0.65 * y);
  let mid = 1.0 - step(0.55 / g.count.x, abs(dx));
  let d = mix(sdSlash(g.local, 3.7, 1.2, -sign(dx)), sdBox(g.local, vec2f(1.2, 3.9), 1.2), mid);
  return emit(g, d, ramp(0.08 + 0.92 * value), 0.08 + 0.92 * value);
`,
}
