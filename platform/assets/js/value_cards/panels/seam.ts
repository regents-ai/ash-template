import type {ValuePanel} from "../panel"

/** Autolaunch, Memestock: the seam panel. */
export const seam: ValuePanel = {
  colours: ["#18b8d6", "#fbf4e6", "#ff4fa3"],
  pitch: [11, 11],
  stillAt: 2,
  body: /* wgsl */ `
  let row = g.id.y;
  var seam = 0.5 + 0.2 * sin(t * 0.8 + row * 0.42) + 0.08 * sin(t * 1.7 - row * 0.9);
  seam = mix(seam, p.x, exp(-sq((y - p.y) * 3.2)) * p.z);
  let side = smoothstep(seam - 0.16, seam + 0.16, x);
  let meet = exp(-sq((x - seam) * 8.0));
  let knot = 1.0 - step(0.55 / g.count.x, abs(x - seam));
  let d = mix(sdSlash(g.local, 3.9, 1.2, sign(x - seam)), sdDiamond(g.local, 4.6), knot);
  let shimmer = 0.5 + 0.5 * sin(t * 1.4 + hash(g.id) * TAU);
  return emit(g, d, ramp(side), 0.44 + 0.46 * meet + 0.12 * shimmer);
`,
}
