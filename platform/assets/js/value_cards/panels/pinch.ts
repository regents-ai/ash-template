import type {ValuePanel} from "../panel"

/** Patchbay, Evidence: the pinch panel. */
export const pinch: ValuePanel = {
  colours: ["#8a1616", "#ff4d4d", "#ffe6c7"],
  pitch: [9, 17],
  stillAt: 2,
  body: /* wgsl */ `
  let home = vec2f(0.5 + 0.26 * sin(t * 0.45), 0.5 + 0.2 * cos(t * 0.6));
  let focus = mix(home, p.xy, p.z);
  let dx = x - focus.x;
  let dy = y - focus.y;
  let pinch = exp(-sq(dy * 2.6)) * exp(-sq(dx * 1.9));
  let d = sdBox(g.local, vec2f(3.9, mix(7.5, 0.8, pinch)), 0.4);
  return emit(g, d, ramp(0.2 + abs(dx) * 1.5 + 0.1 * abs(dy)), 0.96 - 0.3 * pinch);
`,
}
