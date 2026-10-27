/**
 * The Verbs view of the grammar page (/showcase/grammar/verbs) plays the two
 * arrivals a live page never plays by itself again: a headline rising in word
 * by word and cards settling into place. Each "Again" button names what it
 * moves in `aria-controls` and the move in `data-replay`. Both moves are the
 * motion kit's own, so the page shows exactly what every Regent page does.
 * With reduced motion asked for, the grammar's one move is a fade, so that is
 * what plays.
 */
import {createScope, splitText, type Scope} from "animejs"
import {GRIDS, HEADLINES} from "./motion/reveals"
import {CLIPPED_WORD, fadeIn, still} from "./motion/shared"
import type {Hook} from "../hook_composition"

type GrammarHook = {el: HTMLElement; scope?: Scope}

const MOVES: Record<string, (el: HTMLElement) => unknown> = {
  // The words are joined back into plain text once they have risen.
  rise: el => {
    const split = splitText(el, {words: CLIPPED_WORD})
    return HEADLINES.rise(split).then(() => split.revert())
  },
  settle: el => GRIDS.cascade([...el.children]),
}

export const GrammarVerbs: Hook = {
  mounted(this: GrammarHook) {
    const scope = createScope({root: this.el})

    this.scope = scope.add(self => {
      self!.add("replay", (move: string, el: HTMLElement) => (still(el) ? fadeIn(el) : MOVES[move](el)))

      const onClick = (event: MouseEvent) => {
        const button = event.target instanceof Element ? event.target.closest<HTMLElement>("[data-replay]") : null
        const target = button && this.el.ownerDocument.getElementById(button.getAttribute("aria-controls") ?? "")
        if (button && target) scope.methods.replay(button.dataset.replay, target)
      }

      this.el.addEventListener("click", onClick)
      return () => this.el.removeEventListener("click", onClick)
    })
  },

  destroyed(this: GrammarHook) {
    this.scope?.revert()
  },
}
