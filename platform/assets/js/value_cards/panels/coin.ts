import type {ValuePanel} from "../panel"

/** $REGENT, Token: the coin panel. */
export const coin: ValuePanel = {
  colours: ["#6b3a00", "#f2b01e", "#fff4c2"],
  pitch: [8, 8],
  stillAt: 0.5,
  body: /* wgsl */ `
  let q = (g.at - vec2f(0.5)) * aspect();
  let turn = mix(t * 0.7, (p.x - 0.5) * 3.0, p.z);
  let rx = max(abs(cos(turn)) * 0.36, 0.014);
  let e = sqrt(sq(q.x / rx) + sq(q.y / 0.36));
  let inCoin = 1.0 - smoothstep(0.96, 1.04, e);
  let rim = exp(-sq((e - 0.9) * 9.0));
  let inner = exp(-sq((e - 0.52) * 11.0));
  let light = 0.5 + 0.5 * sin(turn * 2.0 + q.y * 3.0);
  let value = sat(inCoin * (0.4 + 0.25 * light + 0.5 * max(rim, inner)));
  return emit(g, length(g.local) - mix(0.9, 3.7, value), ramp(0.1 + 0.9 * value), value);
`,
}
