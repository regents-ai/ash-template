import type {ValuePanel} from "../panel"

/** Autolaunch, Claim: the gather panel. */
export const gather: ValuePanel = {
  colours: ["#b34700", "#ffd92e", "#fffbe0"],
  pitch: [11, 11],
  stillAt: 2.2,
  body: /* wgsl */ `
  let home = vec2f(0.5 + 0.07 * sin(t * 0.5), 0.5 + 0.06 * cos(t * 0.41));
  let centre = mix(home, p.xy, p.z);
  let r = length((g.at - centre) * aspect());
  let band = fract(r * 3.4 + t * 0.32);
  let v = smoothstep(0.5, 1.0, band) * (0.25 + 0.75 * (1.0 - sat(r / 0.8)));
  let core = exp(-sq(r * 6.0));
  let value = max(v, core);
  return emit(g, sdDiamond(g.local, mix(1.3, 5.2, value)), ramp(0.06 + 0.94 * value), value);
`,
}
