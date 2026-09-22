/**
 * The colours the page ground and the crown are drawn in, and the one place that
 * says which of them is showing right now.
 *
 * One field is drawn twice, so the two canvases have to be handed the same
 * colours in the two forms their pipelines expect. The page canvas writes
 * straight to the screen, so it is given the displayed values. The crown canvas
 * composes in high dynamic range and ends with one tone-mapping and encoding
 * pass, so it is given the values that come out of that pass as the displayed
 * ones. Both sets describe the same picture: the page ground carrying the
 * palette's cream squares.
 *
 * At rest the ground is `--rl-bg`, the palette's Background `#0B0B0B`, and the
 * three lasers are white. Pointing at a product card hands both canvases that
 * product's ground and laser colour instead. The squares keep the palette's own
 * Text cream in every palette.
 */

export type Rgba = readonly [number, number, number, number]
type Rgb = readonly [number, number, number]

/** The palette's Text, `#E5E3D2`, kept as the square colour. */
const SQUARE = [0.898039, 0.890196, 0.823529, 1] as const

export const FIELD_PALETTE = {
  /** Displayed value, for a canvas that presents what the shader writes. */
  displayedSquare: SQUARE,
  /**
   * Pre-tone-mapping value, for the crown scene. It is solved against the ACES
   * curve and sRGB encode in the presentation pass so both canvases present the
   * same colour at a lit amount of 0.118 — the field's own operating point, and
   * the one the two canvases have always been matched at.
   */
  composedSquare: [0.17318, 0.17147, 0.15705, 1],
  /** How far a fully lit cell travels from the ground toward the square colour. */
  intensity: 0.2,
} as const satisfies {
  readonly displayedSquare: Rgba
  readonly composedSquare: Rgba
  readonly intensity: number
}

/** The three highlights a visitor can point at, named as the page names them. */
export type HeroHighlight = "signin" | "account" | "agents"
export type HeroPaletteName = "rest" | HeroHighlight

export interface HeroPalette {
  /** Page ground, for a canvas that presents what the shader writes. */
  readonly displayedGround: Rgba
  /** The same ground, before the crown's tone-mapping and encoding pass. */
  readonly composedGround: Rgba
  /**
   * The three lasers: the white segments take this outright, and the spectral
   * fan is tinted by it. Scaled so its brightest channel is as bright as white.
   */
  readonly beam: Rgb
}

/**
 * The highlight colours, kept in one place so a colour is a one-line change. Each
 * ground is the sRGB value of the stylesheet's `--rl-bg` for that highlight — the
 * highlight's own colour folded 8% into the palette's Background — with the
 * composed value solved back through the crown's ACES curve and sRGB encode.
 */
export const HERO_PALETTES = {
  /** Background #0B0B0B, white lasers: the page at rest carries no highlight colour. */
  rest: {
    displayedGround: [0.043137, 0.043137, 0.043137, 1],
    composedGround: [0.009185, 0.009185, 0.009185, 1],
    beam: [1, 1, 1],
  },
  /** Accent Orange #FF5B19. */
  signin: {
    displayedGround: [0.106287, 0.069634, 0.057801, 1],
    composedGround: [0.020647, 0.013701, 0.011626, 1],
    beam: [1, 0.104616, 0.009721],
  },
  /** Accent Blue #AECACD. */
  account: {
    displayedGround: [0.084286, 0.090331, 0.090966, 1],
    composedGround: [0.016388, 0.017532, 0.017653, 1],
    beam: [0.693318, 0.967442, 1],
  },
  /** Platinum #B9B7A6. */
  agents: {
    displayedGround: [0.086512, 0.086094, 0.082325, 1],
    composedGround: [0.016807, 0.016728, 0.016021, 1],
    beam: [1, 0.976052, 0.785996],
  },
} as const satisfies Record<HeroPaletteName, HeroPalette>

/** The name of the DOM event both canvases take their palette change from. */
export const HERO_PALETTE_EVENT = "regents:hero-palette"

let current: HeroPalette = HERO_PALETTES.rest

/** The palette both canvases are drawing right now. */
export const heroPalette = (): HeroPalette => current

/** Hands both canvases one highlight's colours, or the resting page back. */
export const setHeroPalette = (name: HeroPaletteName): void => {
  current = HERO_PALETTES[name]
}
