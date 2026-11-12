import type {ValuePanel} from "../panel"

/** Patchbay, Incidents: the sweep panel. */
export const radar: ValuePanel = {
  colours: ["#0b3d1c", "#39e86a", "#eaffe6"],
  pitch: [9, 9],
  stillAt: 3,
  body: /* wgsl */ `
  let q = (g.at - vec2f(0.5)) * aspect();
  let r = length(q);
  let beam = t * 0.9;
  let trail = exp(-fract((beam - atan2(q.y, q.x)) / TAU) * 4.5);
  let inside = 1.0 - smoothstep(0.46, 0.49, r);
  let rings = exp(-sq((fract(r * 6.0 + 0.5) - 0.5) * 7.0));
  var blips = 0.0;
  for (var i = 0; i < 4; i++) {
    let turn = (f32(i) * 1.7 + 0.3) * 2.4;
    let bp = vec2f(cos(turn), sin(turn)) * (0.14 + 0.07 * f32(i));
    blips += exp(-sq(length(q - bp) * 16.0)) * exp(-fract((beam - atan2(bp.y, bp.x)) / TAU) * 2.0);
  }
  let mine = exp(-sq(length((g.at - p.xy) * aspect()) * 12.0)) * p.z;
  let value = sat(inside * (0.12 + 0.7 * trail * (0.3 + 0.7 * r / 0.48) + 0.22 * rings) + blips + mine);
  return emit(g, length(g.local) - mix(0.9, 4.0, value), ramp(0.08 + 0.5 * trail * inside + 0.9 * (blips + mine)), value);
`,
}
