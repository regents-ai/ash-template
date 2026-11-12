import type {ValuePanel} from "../panel"

/** Techtree, Actions: the branch panel. */
export const actions: ValuePanel = {
  colours: ["#1f3d1a", "#8bd450", "#f4ffd9"],
  pitch: [9, 9],
  stillAt: 1.2,
  body: /* wgsl */ `
  let u = x * 4.0;
  let seg = min(floor(u), 3.0);
  let f = smoothstep(0.0, 1.0, u - seg);
  let kids = exp2(seg + 1.0);
  let k0 = floor(y * kids);
  let leaf = select(floor(hash(vec2f(floor(t * 0.45), 9.0)) * 16.0), floor(clamp(p.y, 0.0, 0.999) * 16.0), p.z > 0.5);
  let chosen = floor(leaf / exp2(3.0 - seg));
  var line = 0.0;
  var hot = 0.0;
  for (var i = -1; i <= 1; i++) {
    let k = k0 + f32(i);
    if (k < 0.0 || k >= kids) { continue; }
    let yl = mix((floor(k / 2.0) + 0.5) / (kids * 0.5), (k + 0.5) / kids, f);
    let on = 1.0 - smoothstep(0.5, 1.1, abs(y - yl) * g.count.y);
    line = max(line, on);
    hot = max(hot, on * (1.0 - step(0.5, abs(k - chosen))));
  }
  let run = hot * (0.55 + 0.45 * exp(-sq((x - fract(t * 0.45)) * 5.0)));
  let value = max(line * 0.34, run);
  return emit(g, length(g.local) - mix(0.9, 3.8, value), ramp(0.08 + 0.92 * run + 0.14 * line), value);
`,
}
