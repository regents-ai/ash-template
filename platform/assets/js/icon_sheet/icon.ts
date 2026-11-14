import type {Pen} from "./pen"

/** One icon on the icon sheet: a small scene of marks on the unit grid, and its loop. */
export type Icon = {
  /** Seconds one loop takes. */
  readonly period: number
  /** The phase shown, held still, to a visitor who asked for less motion. */
  readonly still: number
  /** Draws the icon at a phase from 0 to 1 of its loop; 0 and 1 draw the same picture. */
  draw(pen: Pen, p: number): void
}

/** A group of icons by the name the page gives each one. */
export type IconSet = Readonly<Record<string, Icon>>
