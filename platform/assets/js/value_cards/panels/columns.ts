import type {ValuePanel} from "../panel"

/** Autolaunch, Revstake: the columns panel. */
export const columns: ValuePanel = {
  colours: ["#35520a", "#c8f25c", "#ffffff"],
  pitch: [8.5, 8.5],
  stillAt: 2.4,
  body: /* wgsl */ `
  let col = g.id.x;
  let alive = step(0.3, hash(vec2f(col, 3.0)));
  let wave = noise(vec2f(col * 0.22, t * 0.7)) * 0.62 + noise(vec2f(col * 0.9 + 9.0, t * 1.6)) * 0.38;
  let lift = exp(-sq((x - p.x) * 6.0)) * p.z * 0.35;
  let height = clamp((0.1 + wave * 0.85) * mix(0.16, 1.0, alive) + lift, 0.04, 0.97);
  let rowH = 1.0 / g.count.y;
  let filled = step(y, height);
  let tip = step(height - rowH * 3.0, y) * filled;
  let after = step(height, y) * step(y, height + rowH * 2.0);
  var colour = mix(mix(ramp(0.82), params.c.rgb, y / height), ramp(0.5), tip);
  colour = mix(colour, ramp(0.3), after);
  return emit(g, sdBox(g.local, vec2f(3.5, 3.5), 0.3), colour, max(filled, after * 0.45));
`,
}
