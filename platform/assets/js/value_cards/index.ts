/**
 * Every value card's panel, by the name its card carries in `data-value-card`.
 * This list and `panels/` are each site's own; these six are the template's
 * examples, shown at /animations/cards.
 */
import {ballot} from "./panels/ballot"
import {board} from "./panels/board"
import {climb} from "./panels/climb"
import {link} from "./panels/link"
import {ripple} from "./panels/ripple"
import {rooms} from "./panels/rooms"
import type {ValuePanel} from "./panel"

export const panels: Record<string, ValuePanel> = {
  rooms,
  board,
  ballot,
  link,
  climb,
  ripple,
}
