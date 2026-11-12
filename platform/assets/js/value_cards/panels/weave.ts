import type {ValuePanel} from "../panel"

/** Keyfleet, Review: the weave panel. */
export const weave: ValuePanel = {
  colours: ["#4a1030", "#ff7ab6", "#ffe9c9"],
  pitch: [10, 10],
  stillAt: 2,
  body: /* wgsl */ `
  let block = floor(g.id / 3.0);
  let odd = (block.x + block.y) - 2.0 * floor((block.x + block.y) / 2.0);
  let s = odd * 2.0 - 1.0;
  let wave = 0.5 + 0.5 * sin((x * s + y) * 9.0 - t * 0.9 * s);
  let near = p.z * exp(-sq(length((g.at - p.xy) * aspect()) * 3.5));
  return emit(g, sdSlash(g.local, 3.8, 1.25, s), ramp(0.08 + 0.55 * wave + 0.4 * near + 0.12 * odd), sat(0.25 + 0.6 * wave + 0.5 * near));
`,
}
