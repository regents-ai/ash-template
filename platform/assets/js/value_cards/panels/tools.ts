import type {ValuePanel} from "../panel"

/** WebMCP, Browser tools: the sockets panel. */
export const tools: ValuePanel = {
  colours: ["#003a5c", "#19b5fe", "#eaffff"],
  pitch: [11, 11],
  stillAt: 2,
  body: /* wgsl */ `
  let header = step(1.0 - 2.5 / g.count.y, y);
  let tool = step(0.88, hash(g.id + vec2f(11.0, 5.0))) * (1.0 - header);
  let beat = pow(0.5 + 0.5 * sin(t * 1.3 + hash(g.id) * TAU), 4.0);
  let near = p.z * exp(-sq(length((g.at - p.xy) * aspect()) * 4.0));
  let lit = tool * max(beat, near);
  var d = mix(sdPlus(g.local, 3.0, 0.7), sdDiamond(g.local, 2.8 + 2.4 * lit), tool);
  d = mix(d, sdBox(g.local, vec2f(4.6, 3.4), 0.6), header);
  let amount = mix(mix(0.3 + 0.3 * near, 0.45 + 0.55 * lit, tool), 0.4, header);
  return emit(g, d, ramp(mix(mix(0.2 + 0.3 * near, 0.5 + 0.5 * lit, tool), 0.3, header)), amount);
`,
}
