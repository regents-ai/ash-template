/**
 * The palettes the splats page's scenes are drawn in, the four brand colours in each
 * (Tangerine Tango, Charcoal, Platinum and Powder Blue). Every pixel of a picture is
 * one of its scene's colours; the painter (painter.ts) picks the nearest by how
 * different two colours look (OKLab), after a small ordered dither, so gradients
 * become pixel patterns rather than bands.
 *
 * This file imports nothing, so the scripts beside it use the colours the browser does.
 */

/** The island at night: thirty-two colours, Tangerine Tango for the fire. */
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

/** The robot factory at dusk: forty-eight colours, Tangerine Tango for its robots, arm and sign. */
export const DUSK = [
  // Charcoal, then the dusk sky from overhead down to the glow on the horizon.
  "#161616", "#120f24", "#1d1a3a", "#2b2752", "#3e3468", "#5a4479", "#80548a", "#b0667f", "#e07b6a", "#f6a36b",
  // Tangerine Tango and a lighter orange, Platinum and Powder Blue.
  "#FF5B19", "#ff8a3d", "#E5E3D2", "#AECACD",
  // Leaves and grass, from deep shade to the tips the low sun lights.
  "#0f2422", "#16362c", "#1f4a33", "#2b5f3a", "#3c7840", "#559146", "#7aab52", "#a8c862",
  // Warm plaster, from its shadow side to the face the sun lights.
  "#5b4650", "#8a6f72", "#b8968a", "#dcbca2", "#f2dcbc",
  // Earth and timber, then brick.
  "#2a1a1c", "#4a2e28", "#734634", "#a0643e", "#b4553a",
  // Solar panels and steel.
  "#1b2440", "#2a3d66", "#43649a", "#7fa3cf", "#3b3a4a", "#5a6074", "#8d93a6",
  // Lamplight, from amber to the white at a bulb's heart.
  "#ffb04a", "#ffd97a", "#fff3c8",
  // Water.
  "#2c5d7c", "#5fa2b8",
  // Flowers and fruit, and the robots' eyes.
  "#e46a9a", "#c43c4c", "#a47be0", "#7ff0e8",
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
