/**
 * The night palette the splats page's island is drawn in: thirty-two colours, the
 * four brand colours among them (Tangerine Tango for the fire, Charcoal, Platinum and
 * Powder Blue). Every pixel of the picture is one of these; the painter (painter.ts)
 * picks the nearest by how different two colours look (OKLab), after a small ordered
 * dither, so gradients become pixel patterns rather than bands.
 *
 * This file imports nothing, so the script that draws the page's still picture
 * (`stills.mjs`, beside it) uses the same colours the browser does.
 */
export const NIGHT = [
  // Charcoal, then the sky from its darkest to the haze near the horizon.
  "#161616", "#0a0f1f", "#0f1830", "#152246", "#1c2d5a", "#25396d", "#304883", "#3f5a96",
  // Leaves and grass, from the shade under the crown to the tips the fire lights.
  "#0e2226", "#14332f", "#1b4436", "#24573c", "#2f6b40", "#3f8146", "#58994b", "#7fb356", "#b4cf6c",
  // Earth and bark.
  "#24181a", "#3d2723", "#5c3a2b", "#84532f", "#b06f3a",
  // Stone.
  "#363b4a", "#565f70", "#848d9c",
  // Powder Blue and Platinum: the moon's edge light, the brightest sparks.
  "#AECACD", "#E5E3D2",
  // Fire: embers, Tangerine Tango, amber and the yellow at its heart.
  "#c2341a", "#FF5B19", "#ffa035", "#ffd86a",
  // Flowers.
  "#d0679b",
] as const

const channel = (value: string, at: number) => Number.parseInt(value.slice(at, at + 2), 16) / 255

/** A palette colour as red, green and blue from 0 to 1, as the screen shows them. */
export const rgb = (value: string): [number, number, number] => [channel(value, 1), channel(value, 3), channel(value, 5)]

const linear = (c: number) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4))

/** A colour in OKLab, where equal distances look equally different. */
export function oklab([r, g, b]: readonly [number, number, number]): [number, number, number] {
  const [lr, lg, lb] = [linear(r), linear(g), linear(b)]
  const l = Math.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
  const m = Math.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
  const s = Math.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  ]
}
