import type {ValuePanel} from "../panel"

/** Techtree, Environments: the assemble panel. */
export const assemble: ValuePanel = {
  colours: ["#30343b", "#aeb8c8", "#ffffff"],
  pitch: [11, 11],
  stillAt: 3.6,
  body: /* wgsl */ `
  let front = (1.0 - abs(fract(t * 0.06) * 2.0 - 1.0)) * 0.95 + 0.12;
  let order = x * 0.55 + y * 0.45 + 0.16 * hash(g.id);
  var k = smoothstep(0.0, 0.35, front - order);
  let reach = length((g.at - p.xy) * aspect());
  k = max(k, p.z * (1.0 - smoothstep(0.12, 0.34, reach)));
  let d = mix(sdPlus(g.local, 3.4, 0.7), sdBox(g.local, vec2f(4.3, 4.3), 0.6), k);
  let edge = sin(k * 3.14159);
  return emit(g, d, ramp(0.2 + 0.16 * k + 0.22 * k * hash(g.id + vec2f(3.0)) + 0.55 * edge), 0.4 + 0.3 * k + 0.3 * edge);
`,
}
