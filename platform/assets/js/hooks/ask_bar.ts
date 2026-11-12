import type {Hook} from "../hook_composition"

interface AskBarHook {
  el: HTMLFormElement
  focus?: (event: KeyboardEvent) => void
}

// The ask bar's one shortcut: "/" anywhere on the page, outside a field, puts the
// cursor in the bar, as on most search pages.
export const AskBar: Hook = {
  mounted(this: AskBarHook) {
    const input = this.el.querySelector<HTMLInputElement>("input[name=q]")
    this.focus = event => {
      if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey) return
      if ((event.target as HTMLElement).closest("input, textarea, select, [contenteditable]")) return
      event.preventDefault()
      input?.focus()
      input?.select()
    }
    window.addEventListener("keydown", this.focus)
  },

  destroyed(this: AskBarHook) {
    if (this.focus) window.removeEventListener("keydown", this.focus)
  },
}
