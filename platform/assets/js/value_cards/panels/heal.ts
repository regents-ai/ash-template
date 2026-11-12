import type {ValuePanel} from "../panel"

/** Patchbay, Repairs: the mend panel. */
export const heal: ValuePanel = {
  colours: ["#064a2a", "#00c9ad", "#dcfff8"],
  pitch: [9, 9],
  stillAt: 4.6,
  body: /* wgsl */ `
  let half = vec2f(0.25, 0.21);
  let home = vec2f(0.5 + 0.12 * sin(t * 0.23), 0.5 + 0.1 * cos(t * 0.31));
  let bc = mix(home, clamp(p.xy, half + vec2f(0.06), vec2f(0.94) - half), p.z);
  let rel = (g.at - bc) / half;
  let m = max(abs(rel.x), abs(rel.y));
  let inside = step(m, 1.0);
  let unit = vec2f(1.0) / g.count / half;
  let ring = (1.0 - inside) * step(max((abs(rel.x) - 1.0) / unit.x, (abs(rel.y) - 1.0) / unit.y), 1.0);
  let bracket = ring * step(0.55, abs(rel.x)) * step(0.5, abs(rel.y));
  let ord = (rel.y * 0.5 + 0.5) + (rel.x * 0.5 + 0.5) * 0.12;
  let cycle = fract(t * 0.12) * 1.5;
  let healed = inside * step(ord, cycle);
  let lead = healed * exp(-(cycle - ord) * 7.0);
  let broken = inside * (1.0 - healed);
  let flick = step(0.72, hash(g.id + vec2f(floor(t * 5.0), 0.0)));
  var tone = 0.2;
  var amount = 0.36;
  tone = mix(tone, 0.0, broken);
  amount = mix(amount, 0.04 + 0.3 * flick, broken);
  tone = mix(tone, 0.5 + 0.5 * lead, healed);
  amount = mix(amount, 0.92, healed);
  tone = mix(tone, 1.0, bracket);
  amount = mix(amount, 0.96, bracket);
  return emit(g, sdBox(g.local, vec2f(3.4, 3.4), 1.0), ramp(tone), amount);
`,
}
