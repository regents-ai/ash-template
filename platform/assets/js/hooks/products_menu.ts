/**
 * The header's Products menu, a `<details>` whose panel is `data-panel="menu"`.
 * A mouse opens it by resting on it and closes it by leaving; a finger or a
 * key opens it with a press, as any `<details>` does. The kit's toggle
 * listener (`motion.ts`) pops the panel open, so this only decides when it
 * opens and plays the short fade when a mouse leaves. Escape, a press
 * outside and focus moving elsewhere close it at once.
 */
import {createScope, type JSAnimation, type Scope} from "animejs"
import {EASE_OUT, FAST, lastInputByPointer, play, still} from "./motion/shared"
import type {Hook} from "../hook_composition"

// Long enough that a mouse passing over the header does not open it, short
// enough that one aimed at it never waits; leaving gets a little longer, so
// a path that cuts a corner on the way into the panel keeps it open.
const OPEN_AFTER = 70
const CLOSE_AFTER = 160

const mouse = (event: PointerEvent) =>
  event.pointerType === "mouse" && matchMedia("(hover: hover) and (pointer: fine)").matches

type ProductsMenuHook = {
  el: HTMLDetailsElement
  scope?: Scope
  timer?: number
  leaving?: JSAnimation
  cleanup?: () => void
}

export const ProductsMenu: Hook = {
  mounted(this: ProductsMenuHook) {
    const menu = this.el
    const summary = menu.querySelector<HTMLElement>(":scope > summary")
    const panel = menu.querySelector<HTMLElement>(":scope > [data-panel='menu']")
    if (summary === null || panel === null) return

    const scope = createScope({root: menu})
    const wait = (ms: number, then: () => void) => {
      window.clearTimeout(this.timer)
      this.timer = window.setTimeout(then, ms)
    }

    // A mouse coming back while the panel fades keeps it open, at rest.
    const stay = () => {
      this.leaving?.revert()
      this.leaving = undefined
    }

    const shut = () => {
      stay()
      menu.open = false
    }

    this.scope = scope.add(() => {
      scope.add("leave", () => {
        if (!menu.open) return
        if (still(menu)) return shut()
        const leaving = play(panel, {opacity: [1, 0], y: [0, -4], duration: FAST, ease: EASE_OUT})
        this.leaving = leaving
        leaving.then(() => { if (this.leaving === leaving) shut() })
      })
    })

    const enter = (event: PointerEvent) => {
      if (!mouse(event)) return
      stay()
      if (!menu.open) wait(OPEN_AFTER, () => { menu.open = true })
      else window.clearTimeout(this.timer)
    }

    const leave = (event: PointerEvent) => {
      if (!mouse(event)) return
      wait(CLOSE_AFTER, () => this.scope?.methods.leave())
    }

    // The mouse already opened it, so its click keeps it open rather than
    // shutting it under the pointer. A key press (no pointer presses) still
    // toggles it, as on every `<details>`.
    const click = (event: MouseEvent) => {
      if (event.detail > 0 && menu.open && matchMedia("(hover: hover) and (pointer: fine)").matches) {
        event.preventDefault()
        stay()
      }
    }

    const outside = (event: PointerEvent) => {
      if (menu.open && !(event.target instanceof Node && menu.contains(event.target))) shut()
    }

    const key = (event: KeyboardEvent) => {
      if (event.key !== "Escape" || !menu.open) return
      shut()
      summary.focus()
    }

    // Tabbing out of the menu closes it. A press on the panel's own padding
    // also takes focus from it, so a pointer's presses are left to `outside`.
    const away = (event: FocusEvent) => {
      if (lastInputByPointer() || !menu.open) return
      if (!(event.relatedTarget instanceof Node && menu.contains(event.relatedTarget))) shut()
    }

    menu.addEventListener("pointerenter", enter)
    menu.addEventListener("pointerleave", leave)
    menu.addEventListener("focusout", away)
    summary.addEventListener("click", click)
    document.addEventListener("pointerdown", outside)
    document.addEventListener("keydown", key)

    this.cleanup = () => {
      window.clearTimeout(this.timer)
      menu.removeEventListener("pointerenter", enter)
      menu.removeEventListener("pointerleave", leave)
      menu.removeEventListener("focusout", away)
      summary.removeEventListener("click", click)
      document.removeEventListener("pointerdown", outside)
      document.removeEventListener("keydown", key)
    }
  },

  destroyed(this: ProductsMenuHook) {
    this.cleanup?.()
    this.scope?.revert()
  },
}
