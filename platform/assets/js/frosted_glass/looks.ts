/**
 * The frosted glass's looks. Each one is the same tree, forest and pane in its
 * own colours, surface and light. The page names the look in its address
 * (`?look=`), and the first one needs no name.
 */

export type LookId = "lifelike" | "reeded" | "blocks" | "mist" | "night" | "ember"

type Colour = readonly [number, number, number]

/** The pane's surface: pebbled, ribbed from top to bottom, or laid in thick bricks. */
export const SURFACE = {pebbles: 0, reeds: 1, blocks: 2} as const

export type Look = {
  readonly id: LookId
  readonly surface: (typeof SURFACE)[keyof typeof SURFACE]
  /** Pebbles down the height of the window. */
  readonly pebble: number
  /** How steep the surface is. */
  readonly bump: number
  /** How far the surface bends the view, as a share of the window. */
  readonly bend: number
  /** Blur the glass adds to everything, whatever its distance. */
  readonly frost: number
  /** Squares of wire, ribs or bricks down the height of the window, at its middle. */
  readonly cells: number
  /** How strongly the wire, or the joints between bricks, show. */
  readonly wire: number
  /** Half the width of a wire, as a share of a square. */
  readonly wireWidth: number
  /** Brightness of the wire: above 1 is paler than the glass round it, near 0 is a dark joint. */
  readonly wireTone: number
  /** How far the wire wanders from straight, as a share of the window. */
  readonly wireWander: number
  /** How much the lamp clouds the surface. */
  readonly veil: number
  readonly sparkle: number
  readonly grain: number
  /** Light on the tree away from the lamp. */
  readonly room: number
  /** How far the frost spreads each ray, as a share of the window. */
  readonly scatter: number
  readonly lightHeight: number
  /** The colour the frost and the lamp's veil take. */
  readonly milk: Colour
  /** How thick the fog over the pane is where nobody has wiped it, from 0 to 1. */
  readonly mist: number
  /** How much the glowing wood haloes through the glass. */
  readonly bloom: number
  readonly wind: number
  readonly leafDark: Colour
  readonly leafLight: Colour
  /** A leaf with the sky straight behind it. */
  readonly leafGlow: Colour
  /** The sky behind the trees, and the shade low down among their trunks. */
  readonly sky: Colour
  readonly shade: Colour
  readonly bark: Colour
  /** The light running along the wood, and how much of it there is from 0 to 1. */
  readonly glow: Colour
  readonly glowing: number
}

/** One giant tree in daylight behind pebbled, wired glass. */
const lifelike: Look = {
  id: "lifelike",
  surface: SURFACE.pebbles,
  pebble: 96,
  bump: 0.34,
  bend: 0.009,
  frost: 0.12,
  cells: 42,
  wire: 0.42,
  wireWidth: 0.04,
  wireTone: 1.2,
  wireWander: 0.004,
  veil: 0.44,
  sparkle: 0.4,
  grain: 0.03,
  room: 0.7,
  scatter: 0.005,
  lightHeight: 0.52,
  milk: [0.9, 0.92, 0.88],
  mist: 0,
  bloom: 0,
  wind: 1,
  leafDark: [0.07, 0.24, 0.06],
  leafLight: [0.56, 0.82, 0.26],
  leafGlow: [0.74, 0.9, 0.26],
  sky: [0.84, 0.92, 0.86],
  shade: [0.008, 0.045, 0.02],
  bark: [0.1, 0.075, 0.05],
  glow: [0, 0, 0],
  glowing: 0,
}

/** Ribbed glass: each rib a narrow lens that squeezes its strip of the tree. */
const reeded: Look = {
  ...lifelike,
  id: "reeded",
  surface: SURFACE.reeds,
  pebble: 140,
  bump: 1,
  bend: 0.022,
  frost: 0.06,
  cells: 58,
  wire: 0,
  veil: 0.34,
  sparkle: 0.55,
  scatter: 0.002,
}

/** Thick glass bricks in dark joints, each one showing its own piece of the tree. */
const blocks: Look = {
  ...lifelike,
  id: "blocks",
  surface: SURFACE.blocks,
  pebble: 150,
  bump: 1.1,
  bend: 0.035,
  frost: 0.08,
  cells: 7,
  wire: 0.85,
  wireWidth: 0.03,
  wireTone: 0.32,
  wireWander: 0.0008,
  veil: 0.36,
  sparkle: 0.5,
  scatter: 0.003,
}

/** A fogged pane, wiped clear where the visitor's hand passes, that fogs over again. */
const mist: Look = {
  ...lifelike,
  id: "mist",
  wire: 0,
  frost: 0.08,
  veil: 0.3,
  mist: 1,
  milk: [0.84, 0.88, 0.86],
}

/** The tree at night, its wood running with cyan light. */
const night: Look = {
  ...lifelike,
  id: "night",
  wire: 0.28,
  wireTone: 0.9,
  veil: 0.2,
  sparkle: 0.3,
  room: 0.9,
  milk: [0.34, 0.44, 0.54],
  bloom: 0.4,
  leafDark: [0.006, 0.02, 0.03],
  leafLight: [0.03, 0.1, 0.13],
  leafGlow: [0.12, 0.42, 0.5],
  sky: [0.018, 0.03, 0.055],
  shade: [0.002, 0.004, 0.01],
  bark: [0.015, 0.02, 0.026],
  glow: [0.32, 0.92, 1.0],
  glowing: 1,
}

/** The tree at night, its wood running with amber light. */
const ember: Look = {
  ...night,
  id: "ember",
  milk: [0.54, 0.44, 0.34],
  leafDark: [0.03, 0.015, 0.008],
  leafLight: [0.13, 0.07, 0.03],
  leafGlow: [0.5, 0.28, 0.08],
  sky: [0.05, 0.028, 0.02],
  shade: [0.008, 0.004, 0.002],
  bark: [0.026, 0.018, 0.012],
  glow: [1.0, 0.56, 0.16],
}

export const LOOKS: Readonly<Record<LookId, Look>> = {lifelike, reeded, blocks, mist, night, ember}
