import type {ValuePanel} from "../panel"

/** Techtree, Offline verification: the scan panel. */
export const scan: ValuePanel = {
  colours: ["#0a2a4a", "#2ec4e6", "#e3fbff"],
  pitch: [7, 7],
  stillAt: 4.4,
  body: /* wgsl */ `
  let q = g.at * aspect();
  let field = sat(noise(q * 3.2 + vec2f(0.0, t * 0.06)) * 0.75 + noise(q * 8.0 - vec2f(t * 0.05, 0.0)) * 0.3 - 0.05);
  let scan = mix(fract(t * 0.14) * 1.3 - 0.15, p.x, p.z);
  let behind = smoothstep(scan - 0.5, scan, x) * step(x, scan);
  let beam = exp(-sq((x - scan) * g.count.x * 0.8));
  let amount = max(dith(g.id, field) * (0.22 + 0.74 * behind), beam);
  let colour = mix(ramp(0.04 + 0.5 * field + 0.38 * behind), params.c.rgb, beam);
  return emit(g, sdBox(g.local, vec2f(2.7, 2.7), 0.2), colour, amount);
`,
}
