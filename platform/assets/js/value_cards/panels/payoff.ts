import type {ValuePanel} from "../panel"

/** Autolaunch, Covered calls: the payoff panel. */
export const payoff: ValuePanel = {
  colours: ["#7a1200", "#ff5b19", "#ffe0c7"],
  pitch: [8, 8],
  stillAt: 2.4,
  body: /* wgsl */ `
  let drift = 0.46 + 0.16 * sin(t * 0.55) + 0.05 * sin(t * 1.3 + 1.0);
  let strike = mix(drift, clamp(p.x, 0.15, 0.85), p.z);
  let payoff = min(0.2 + max(x - strike, 0.0) * 1.7, 0.96);
  let filled = step(y, payoff);
  let top = 1.0 - smoothstep(0.0, 0.16, payoff - y);
  let glint = exp(-sq((x - fract(t * 0.18)) * 9.0));
  var colour = ramp(0.08 + 0.4 * y / payoff + 0.42 * top + 0.2 * glint);
  var amount = filled * (0.8 + 0.2 * top);
  let ghost = (1.0 - step(0.6 / g.count.x, abs(x - strike))) * (1.0 - filled) * dith(g.id, 0.5);
  colour = mix(colour, params.c.rgb, ghost);
  amount = max(amount, ghost * 0.6);
  return emit(g, sdBox(g.local, vec2f(3.0, 3.0), 0.7), colour, amount);
`,
}
