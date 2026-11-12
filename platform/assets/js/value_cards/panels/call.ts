import type {ValuePanel} from "../panel"

/** WebMCP, Tool calls: the call panel. */
export const call: ValuePanel = {
  colours: ["#14204a", "#6f8cff", "#9dffcf"],
  pitch: [11, 11],
  stillAt: 2.6,
  body: /* wgsl */ `
  let upper = step(0.5, y);
  let dir = mix(-1.0, 1.0, upper);
  let u = fract(t * 0.22) * 2.0;
  let going = step(u, 1.0);
  let head = mix(mix(2.0 - u, u, going), p.x, p.z);
  let live = mix(mix(1.0 - going, going, upper), 1.0 - abs(upper - step(0.5, p.y)), p.z);
  let behind = (head - x) * dir;
  let sent = upper * (1.0 - going) * (1.0 - p.z) * 0.4 * (2.0 - u);
  let trail = max(step(0.0, behind) * exp(-behind * 2.4) * live, sent);
  let mid = 1.0 - step(0.6 / g.count.y, abs(y - 0.5));
  let d = mix(sdAngle(g.local, 3.2, 1.0, dir), length(g.local) - 1.2, mid);
  return emit(g, d, ramp(mix(0.3, mix(0.98, 0.55, upper), trail)), mix(0.3 + 0.7 * trail, 0.3, mid));
`,
}
