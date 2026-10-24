/** The ten wonders at /animations/wonders, by the name each one's markup carries in `data-wonder`. */
import {aurora} from "./aurora"
import {coral} from "./coral"
import {fractal} from "./fractal"
import {horizon} from "./horizon"
import {ink} from "./ink"
import {kaleidoscope} from "./kaleidoscope"
import {ripples} from "./ripples"
import {shatter} from "./shatter"
import {tesseract} from "./tesseract"
import {warp} from "./warp"
import type {Wonder} from "./wonder"

// Each wonder's state is its own; the hook only ever hands a wonder back its own.
export const wonders: Record<string, Wonder<any>> = {
  horizon, warp, fractal, tesseract, coral, ink, shatter, aurora, ripples, kaleidoscope,
}
