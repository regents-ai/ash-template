import type {ValuePanel} from "../panel"

/** Keyfleet, Keys: the seats panel. */
export const seats: ValuePanel = {
  colours: ["#40210f", "#e8a15b", "#fff2dc"],
  pitch: [10, 10],
  stillAt: 9,
  body: /* wgsl */ `
  let seat = step(0.5, (g.id.x + 1.0) % 6.0) * step(0.5, (g.id.y + 1.0) % 4.0);
  let turn = hash(g.id + 3.0);
  let fill = 0.35 + 0.8 * fract(t * 0.04);
  let taken = step(turn, fill) * seat;
  let fresh = taken * exp(-(fill - turn) * 14.0);
  let onCol = 1.0 - step(0.6 / g.count.x, abs(x - p.x));
  let onRow = 1.0 - step(0.6 / g.count.y, abs(y - p.y));
  let here = p.z * onCol * onRow;
  let cross = p.z * max(onCol, onRow);
  let d = mix(length(g.local) - 1.3, sdBox(g.local, vec2f(3.6, 3.6), 1.2), max(taken, here));
  let amount = max(max(mix(0.3, 0.55 + 0.45 * fresh, taken), cross * 0.5), here) * seat;
  return emit(g, d, ramp(max(taken * (0.3 + 0.7 * fresh), max(here, cross * 0.3))), amount);
`,
}
